#!/usr/bin/env python3
"""Local LiteRT helper for Flutter desktop development.

Dependency-light implementation using the stdlib HTTP server so it can run in
environments where FastAPI/Pydantic versions are pinned for other workflows.
"""

from __future__ import annotations

import json
import logging
import os
import shlex
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path
from threading import Lock
from typing import Any

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

try:
    import litert_lm
except Exception as exc:  # pragma: no cover - import failure surfaced at startup
    raise RuntimeError(
        "litert_lm is required. Install with `pip install litert-lm-api-nightly`."
    ) from exc

logging.basicConfig(
    level=getattr(logging, os.environ.get("PC_LITERT_LOG_LEVEL", "INFO").upper(), logging.INFO),
    format="%(asctime)s %(levelname)s %(name)s - %(message)s",
)
logger = logging.getLogger("pc_litert_helper")


class _EngineCache:
    def __init__(self) -> None:
        self._engine: Any | None = None
        self._key: tuple[str, str] | None = None
        self._lock = Lock()

    def _backend(self, backend_name: str) -> Any:
        if backend_name.lower() == "gpu":
            return litert_lm.Backend.GPU
        return litert_lm.Backend.CPU

    def get_engine(self, model_path: str, backend_name: str) -> Any:
        key = (model_path, backend_name.lower())
        with self._lock:
            if self._engine is not None and self._key == key:
                logger.info("Reusing cached engine model=%s backend=%s", model_path, backend_name)
                return self._engine
            if self._engine is not None:
                logger.info("Closing cached engine for key=%s", self._key)
                self._engine.close()
                self._engine = None
            logger.info("Initializing LiteRT engine model=%s backend=%s", model_path, backend_name)
            self._engine = litert_lm.Engine(
                model_path,
                backend=self._backend(backend_name),
            )
            self._key = key
            return self._engine

    def close(self) -> None:
        with self._lock:
            if self._engine is not None:
                logger.info("Closing engine on shutdown key=%s", self._key)
                self._engine.close()
                self._engine = None
            self._key = None


cache = _EngineCache()
default_model = os.environ.get("PC_LITERT_DEFAULT_MODEL", "")
default_backend = os.environ.get("PC_LITERT_DEFAULT_BACKEND", "cpu")
infer_mode = os.environ.get("PC_LITERT_INFER_MODE", "cli").strip().lower()
cli_bin = os.environ.get("PC_LITERT_CLI_BIN", "litert-lm").strip() or "litert-lm"
cli_timeout_sec = int(os.environ.get("PC_LITERT_TIMEOUT_SEC", "180"))
safe_vision_max_tokens = int(os.environ.get("PC_LITERT_SAFE_VISION_MAX_TOKENS", "256"))
safe_text_max_tokens = int(os.environ.get("PC_LITERT_SAFE_TEXT_MAX_TOKENS", "512"))
safe_max_temperature = float(os.environ.get("PC_LITERT_SAFE_MAX_TEMPERATURE", "0"))
trace_log_dir = Path(os.environ.get("PC_LITERT_TRACE_DIR", "logs")).expanduser()
trace_log_path = Path(
    os.environ.get(
        "PC_LITERT_TRACE_FILE",
        str(trace_log_dir / f"pc_litert_infer_trace-{datetime.now().strftime('%Y%m%d-%H%M%S')}.jsonl"),
    )
).expanduser()
trace_log_lock = Lock()


def _json_response(handler: BaseHTTPRequestHandler, status: int, payload: dict[str, Any]) -> None:
    body = json.dumps(payload).encode("utf-8")
    handler.send_response(status)
    handler.send_header("content-type", "application/json")
    handler.send_header("content-length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def _append_trace(event: dict[str, Any]) -> None:
    record = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        **event,
    }
    trace_log_path.parent.mkdir(parents=True, exist_ok=True)
    with trace_log_lock:
        with trace_log_path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")


def _infer_via_cli(
    model_path: Path,
    prompt: str,
    backend: str,
    image_paths: list[str],
    max_tokens: int,
    temperature: float,
) -> dict[str, str]:
    started = time.time()
    command: list[str] = [
        cli_bin,
        "run",
        str(model_path),
        "--prompt",
        prompt,
        "--backend",
        backend if backend else "cpu",
        "--vision-backend",
        "cpu",
        "--enable-speculative-decoding",
        "false",
        "--max-num-tokens",
        str(max_tokens),
        "--temperature",
        str(temperature),
    ]
    for image_path in image_paths:
        command.extend(["--attachment", image_path])
    logger.info("CLI inference command=%s", " ".join(shlex.quote(part) for part in command))
    completed = subprocess.run(
        command,
        capture_output=True,
        text=True,
        timeout=cli_timeout_sec,
        check=False,
    )
    if completed.returncode != 0:
        logger.error("CLI inference failed exit=%d stderr=%s", completed.returncode, completed.stderr)
        _append_trace(
            {
                "mode": "cli",
                "ok": False,
                "model_path": str(model_path),
                "backend": backend if backend else "cpu",
                "image_paths": image_paths,
                "max_tokens": max_tokens,
                "temperature": temperature,
                "command": command,
                "return_code": completed.returncode,
                "stderr": completed.stderr,
                "stdout": completed.stdout,
            }
        )
        raise RuntimeError(
            "LiteRT CLI failed "
            f"(exit={completed.returncode}): {completed.stderr.strip() or completed.stdout.strip()}"
        )
    text = completed.stdout.strip()
    if not text or text == "An error occurred":
        error = (
            "LiteRT CLI returned no usable model text."
            if not text
            else "LiteRT CLI reported an internal error."
        )
        _append_trace(
            {
                "mode": "cli",
                "ok": False,
                "model_path": str(model_path),
                "backend": backend if backend else "cpu",
                "image_paths": image_paths,
                "max_tokens": max_tokens,
                "temperature": temperature,
                "command": command,
                "return_code": completed.returncode,
                "stderr": completed.stderr,
                "stdout": completed.stdout,
                "error": error,
            }
        )
        detail = completed.stderr.strip() or completed.stdout.strip()
        raise RuntimeError(f"{error} {detail}".strip())
    _append_trace(
        {
            "mode": "cli",
            "ok": True,
            "model_path": str(model_path),
            "backend": backend if backend else "cpu",
            "image_paths": image_paths,
            "max_tokens": max_tokens,
            "temperature": temperature,
            "command": command,
            "return_code": completed.returncode,
            "stderr": completed.stderr,
            "stdout": completed.stdout,
            "elapsed_ms": int((time.time() - started) * 1000),
        }
    )
    logger.info(
        "CLI inference success model=%s elapsed_ms=%d response_chars=%d",
        model_path.name,
        int((time.time() - started) * 1000),
        len(text),
    )
    return {"text": text, "modelName": model_path.name}


def _normalize_generation_settings(
    *,
    image_count: int,
    requested_max_tokens: int,
    requested_temperature: float,
) -> tuple[int, float]:
    token_limit = safe_vision_max_tokens if image_count > 0 else safe_text_max_tokens
    normalized_max_tokens = max(32, min(requested_max_tokens, token_limit))
    normalized_temperature = max(0.0, min(requested_temperature, safe_max_temperature))
    return normalized_max_tokens, normalized_temperature


def _is_abort_like_exit(code: int) -> bool:
    # litert-lm process crashes often surface as SIGABRT/SIGSEGV negative exits.
    return code in {-6, -11, 134, 139}


def _infer(payload: dict[str, Any]) -> dict[str, str]:
    started = time.time()
    model_path = Path(str(payload.get("modelPath") or default_model)).expanduser().resolve()
    prompt = str(payload.get("prompt") or "").strip()
    if not prompt:
        # Fallback for oral cancer screening if prompt is missing
        prompt = (
            "Analyze this cropped oral mucosal image. "
            "Return JSON with: category, recommendation, brief_reason, disclaimer. "
            "Categories: low_risk_or_variation or refer_for_clinical_review."
        )
        logger.warning("Prompt missing in request, using fallback: %s", prompt)

    backend = str(payload.get("backend") or default_backend).strip()
    image_paths = [str(path) for path in payload.get("imagePaths", [])]
    requested_max_tokens = int(payload.get("maxTokens") or 256)
    requested_temperature = float(payload.get("temperature") or 0)
    max_tokens, temperature = _normalize_generation_settings(
        image_count=len(image_paths),
        requested_max_tokens=requested_max_tokens,
        requested_temperature=requested_temperature,
    )
    if not model_path.exists():
        raise ValueError(f"Model file does not exist: {model_path}")
    missing_images = [path for path in image_paths if not Path(path).expanduser().resolve().exists()]
    if missing_images:
        raise ValueError(f"Missing image file(s): {missing_images}")

    try:
        logger.info(
            "Inference request mode=%s model=%s backend=%s image_count=%d prompt_chars=%d requested_max_tokens=%d normalized_max_tokens=%d requested_temperature=%.3f normalized_temperature=%.3f",
            infer_mode,
            model_path,
            backend,
            len(image_paths),
            len(prompt),
            requested_max_tokens,
            max_tokens,
            requested_temperature,
            temperature,
        )
        if infer_mode == "cli":
            try:
                return _infer_via_cli(
                    model_path=model_path,
                    prompt=prompt,
                    backend=backend,
                    image_paths=image_paths,
                    max_tokens=max_tokens,
                    temperature=temperature,
                )
            except RuntimeError as exc:
                message = str(exc)
                if "exit=" not in message:
                    raise
                retry_max_tokens = 128 if image_paths else 256
                retry_temperature = 0.0
                should_retry = any(
                    _is_abort_like_exit(code)
                    for code in (-6, -11, 134, 139)
                    if f"exit={code}" in message
                )
                if not should_retry:
                    raise
                logger.warning(
                    "Retrying after abort-like LiteRT CLI failure with safer settings max_tokens=%d temperature=%.1f",
                    retry_max_tokens,
                    retry_temperature,
                )
                return _infer_via_cli(
                    model_path=model_path,
                    prompt=prompt,
                    backend=backend,
                    image_paths=image_paths,
                    max_tokens=retry_max_tokens,
                    temperature=retry_temperature,
                )
        engine = cache.get_engine(str(model_path), backend)
        with engine.create_conversation() as conversation:
            content = [{"type": "text", "text": prompt}]
            for image_path in image_paths:
                content.insert(0, {"type": "image", "path": image_path})
            message = {"role": "user", "content": content}
            response = conversation.send_message(message)
            text_parts = [
                item.get("text", "")
                for item in response.get("content", [])
                if item.get("type") == "text"
            ]
            text = "".join(text_parts).strip()
            if not text:
                raise RuntimeError("LiteRT helper returned empty text.")
            _append_trace(
                {
                    "mode": "engine",
                    "ok": True,
                    "model_path": str(model_path),
                    "backend": backend,
                    "image_paths": image_paths,
                    "max_tokens": max_tokens,
                    "temperature": temperature,
                    "response_text": text,
                    "elapsed_ms": int((time.time() - started) * 1000),
                }
            )
            logger.info(
                "Inference success model=%s elapsed_ms=%d response_chars=%d",
                model_path.name,
                int((time.time() - started) * 1000),
                len(text),
            )
            return {"text": text, "modelName": model_path.name}
    except Exception as exc:
        _append_trace(
            {
                "mode": infer_mode,
                "ok": False,
                "model_path": str(model_path),
                "backend": backend,
                "image_paths": image_paths,
                "max_tokens": max_tokens,
                "temperature": temperature,
                "error": str(exc),
            }
        )
        logger.exception("Inference failed: %s", exc)
        raise


class _Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/health":
            _json_response(self, 200, {"status": "ok"})
            return
        _json_response(self, 404, {"error": "not_found"})

    def do_POST(self) -> None:  # noqa: N802
        if self.path != "/api/infer":
            _json_response(self, 404, {"error": "not_found"})
            return
        try:
            content_type = self.headers.get("content-type", "")
            length = int(self.headers.get("content-length", "0"))
            logger.info("POST /api/infer content_type=%s length=%d", content_type, length)

            if "multipart/form-data" in content_type:
                import cgi
                import tempfile

                # Ensure environment variables are set for cgi.FieldStorage
                environ = {
                    "REQUEST_METHOD": "POST",
                    "CONTENT_TYPE": content_type,
                    "CONTENT_LENGTH": str(length),
                }
                form = cgi.FieldStorage(
                    fp=self.rfile,
                    headers=self.headers,
                    environ=environ,
                )

                logger.info("Received multipart form fields: %s", form.keys())

                payload = {
                    "prompt": form.getfirst("prompt") or form.getfirst("fields[prompt]") or "",
                    "modelPath": form.getfirst("modelPath") or form.getfirst("fields[modelPath]") or "",
                    "backend": form.getfirst("backend") or "cpu",
                    "maxTokens": form.getfirst("maxTokens") or "256",
                    "temperature": form.getfirst("temperature") or "0",
                }
                # Handle uploaded file
                if "file" in form:
                    file_item = form["file"]
                    if file_item.filename:
                        suffix = Path(file_item.filename).suffix
                        with tempfile.NamedTemporaryFile(
                            delete=False, suffix=suffix
                        ) as tmp:
                            tmp.write(file_item.file.read())
                            payload["imagePaths"] = [tmp.name]
                elif "imagePaths" in form:
                    payload["imagePaths"] = form.getlist("imagePaths")
            else:
                raw = self.rfile.read(length).decode("utf-8")
                payload = json.loads(raw) if raw else {}

            result = _infer(payload)
            _json_response(self, 200, result)
        except ValueError as exc:
            _json_response(self, 400, {"error": str(exc)})
        except json.JSONDecodeError as exc:
            _json_response(self, 400, {"error": f"Invalid JSON: {exc}"})
        except Exception as exc:  # pragma: no cover
            logger.exception("Internal error in POST handler")
            _json_response(self, 500, {"error": str(exc)})

    def log_message(self, _format: str, *_args: Any) -> None:
        return


def main() -> None:
    host = os.environ.get("PC_LITERT_HOST", "127.0.0.1")
    port = int(os.environ.get("PC_LITERT_PORT", "8010"))
    server = ThreadingHTTPServer((host, port), _Handler)
    logger.info("PC LiteRT helper listening on http://%s:%d", host, port)
    logger.info("Default model=%s backend=%s", default_model or "<none>", default_backend)
    logger.info("Inference mode=%s cli_bin=%s timeout_sec=%d", infer_mode, cli_bin, cli_timeout_sec)
    logger.info(
        "Safety limits vision_max_tokens=%d text_max_tokens=%d max_temperature=%.3f",
        safe_vision_max_tokens,
        safe_text_max_tokens,
        safe_max_temperature,
    )
    logger.info("Trace log path=%s", trace_log_path)
    try:
        server.serve_forever()
    finally:
        cache.close()
        server.server_close()


if __name__ == "__main__":
    main()
