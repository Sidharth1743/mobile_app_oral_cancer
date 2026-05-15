import json
import os
import platform
from dataclasses import dataclass
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_ADAPTER_DIR = (
    REPO_ROOT / "oral_gemma_finetune_package" / "outputs" / "no-vision-lora-15ep"
)
DEFAULT_BASE_MODEL_DIR = (
    REPO_ROOT / "oral_gemma_finetune_package" / "model" / "gemma-unsloth-e2b"
)
MAX_UPLOAD_BYTES = 8 * 1024 * 1024
DEFAULT_MAX_NEW_TOKENS = 256

CATEGORIES = {"low_risk_or_variation", "refer_for_clinical_review"}
REQUIRED_FIELDS = ("category", "recommendation", "brief_reason", "disclaimer")

SYSTEM_INSTRUCTION = (
    "You are an oral screening assistant. Analyze this cropped oral mucosal image. "
    "Return JSON with: category, recommendation, brief_reason, disclaimer. "
    "Categories: low_risk_or_variation or refer_for_clinical_review. "
    "Do not diagnose."
)


@dataclass(frozen=True)
class BackendConfig:
    adapter_dir: Path
    base_model_dir: Path
    max_upload_bytes: int
    max_new_tokens: int

    @classmethod
    def from_env(cls) -> "BackendConfig":
        return cls(
            adapter_dir=Path(os.environ.get("ORAL_GEMMA_MODEL_DIR", DEFAULT_ADAPTER_DIR)),
            base_model_dir=Path(
                os.environ.get("ORAL_GEMMA_BASE_MODEL_DIR", DEFAULT_BASE_MODEL_DIR)
            ),
            max_upload_bytes=int(
                os.environ.get("ORAL_GEMMA_MAX_UPLOAD_BYTES", str(MAX_UPLOAD_BYTES))
            ),
            max_new_tokens=int(
                os.environ.get("ORAL_GEMMA_MAX_NEW_TOKENS", str(DEFAULT_MAX_NEW_TOKENS))
            ),
        )


def _find_weights_file(model_dir: Path) -> Path:
    """Return the weights path for a model dir — handles sharded safetensors."""
    single = model_dir / "model.safetensors"
    if single.exists():
        return single
    shards = sorted(model_dir.glob("model-*-of-*.safetensors"))
    if shards:
        return shards[0]
    return single  # non-existent path so the exists check fails informatively


def adapter_config_path(adapter_dir: Path) -> Path:
    return adapter_dir / "adapter_config.json"


def load_adapter_config(adapter_dir: Path) -> dict[str, Any]:
    path = adapter_config_path(adapter_dir)
    if not path.exists():
        raise FileNotFoundError(f"LoRA adapter_config.json not found in: {adapter_dir}")
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def is_lora_adapter_dir(model_dir: Path) -> bool:
    return adapter_config_path(model_dir).exists()


def resolve_base_model_dir(config: BackendConfig) -> Path:
    if not is_lora_adapter_dir(config.adapter_dir):
        return config.adapter_dir
    adapter_config = load_adapter_config(config.adapter_dir)
    raw_path = adapter_config.get("base_model_name_or_path")
    if isinstance(raw_path, str) and raw_path.strip():
        configured = Path(raw_path)
        if configured.exists():
            return configured
    return config.base_model_dir


def inspect_model_files(config: BackendConfig) -> dict[str, Any]:
    model_dir = config.adapter_dir
    base_model_dir = resolve_base_model_dir(config)
    mode = "lora_adapter" if is_lora_adapter_dir(model_dir) else "merged_or_base_model"
    if mode == "lora_adapter":
        files = {
            "adapter_config": adapter_config_path(model_dir),
            "adapter_model": model_dir / "adapter_model.safetensors",
            "adapter_tokenizer": model_dir / "tokenizer.json",
            "base_config": base_model_dir / "config.json",
            "base_model": _find_weights_file(base_model_dir),
            "base_tokenizer": base_model_dir / "tokenizer.json",
        }
    else:
        files = {
            "model_config": model_dir / "config.json",
            "model_weights": _find_weights_file(model_dir),
            "model_tokenizer": model_dir / "tokenizer.json",
        }
    return {
        "model_dir": str(model_dir),
        "mode": mode,
        "base_model_dir": str(base_model_dir),
        "files": {
            name: {
                "path": str(path),
                "exists": path.exists(),
                "size_bytes": path.stat().st_size if path.exists() else None,
            }
            for name, path in files.items()
        },
    }


def model_files_ready(config: BackendConfig) -> bool:
    inspected = inspect_model_files(config)
    return all(item["exists"] for item in inspected["files"].values())


def validate_upload(content_type: str | None, size_bytes: int, max_bytes: int) -> None:
    # Relaxed for local development and various clients (e.g. Flutter desktop)
    # that might send generic content types.
    is_image = content_type and content_type.startswith("image/")
    is_generic = content_type in (None, "application/octet-stream", "application/binary")

    if not (is_image or is_generic):
        raise ValueError(f"Upload must be an image file (got {content_type}).")
    if size_bytes <= 0:
        raise ValueError("Upload is empty.")
    if size_bytes > max_bytes:
        raise ValueError(f"Image is larger than the {max_bytes} byte limit.")


def parse_model_json(raw_text: str) -> dict[str, str]:
    start = raw_text.find("{")
    end = raw_text.rfind("}")
    if start == -1 or end == -1 or end <= start:
        raise ValueError(f"Model output did not contain a JSON object. Raw output: {raw_text}")

    parsed = json.loads(raw_text[start : end + 1])
    if not isinstance(parsed, dict):
        raise ValueError(f"Model output JSON is not an object. Raw output: {raw_text}")

    missing = [field for field in REQUIRED_FIELDS if field not in parsed]
    if missing:
        raise ValueError(f"Model output missing required field(s): {missing}. Raw output: {raw_text}")

    category = parsed["category"]
    if category not in CATEGORIES:
        raise ValueError(f"Unknown category '{category}'. Raw output: {raw_text}")

    return {field: str(parsed[field]) for field in REQUIRED_FIELDS}


def python_runtime_info() -> dict[str, Any]:
    return {
        "python": platform.python_version(),
        "platform": platform.platform(),
    }
