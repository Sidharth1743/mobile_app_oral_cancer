import asyncio
from io import BytesIO
from pathlib import Path
from typing import Any

from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from PIL import Image, UnidentifiedImageError
from pydantic import BaseModel

from .core import BackendConfig, parse_model_json, python_runtime_info, validate_upload
from .runtime import OralGemmaRuntime


BASE_DIR = Path(__file__).resolve().parent
UI_DIR = BASE_DIR / "ui"
CONFIG = BackendConfig.from_env()
RUNTIME = OralGemmaRuntime(CONFIG)

app = FastAPI(title="Oral Gemma Local Backend")
app.mount("/assets", StaticFiles(directory=UI_DIR), name="assets")


@app.exception_handler(FileNotFoundError)
async def file_not_found_handler(
    request: Request,
    exc: FileNotFoundError,
) -> JSONResponse:
    return JSONResponse(
        status_code=500,
        content={"error": "FileNotFoundError", "message": str(exc)},
    )


@app.exception_handler(UnidentifiedImageError)
async def image_error_handler(
    request: Request,
    exc: UnidentifiedImageError,
) -> JSONResponse:
    return JSONResponse(
        status_code=400,
        content={"error": "InvalidImage", "message": str(exc)},
    )


@app.exception_handler(ValueError)
async def value_error_handler(request: Request, exc: ValueError) -> JSONResponse:
    return JSONResponse(
        status_code=422,
        content={"error": "ValueError", "message": str(exc)},
    )


@app.exception_handler(RuntimeError)
async def runtime_error_handler(request: Request, exc: RuntimeError) -> JSONResponse:
    return JSONResponse(
        status_code=500,
        content={"error": "RuntimeError", "message": str(exc)},
    )


@app.get("/")
def index() -> FileResponse:
    return FileResponse(UI_DIR / "index.html")


@app.get("/api/status")
def status() -> dict[str, Any]:
    payload = RUNTIME.status()
    payload["python"] = python_runtime_info()
    return payload


@app.post("/api/analyze")
async def analyze(
    file: UploadFile = File(...), prompt: str = Form(None)
) -> dict[str, Any]:
    image_bytes = await file.read()
    try:
        validate_upload(
            content_type=file.content_type,
            size_bytes=len(image_bytes),
            max_bytes=CONFIG.max_upload_bytes,
        )
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error

    image = Image.open(BytesIO(image_bytes)).convert("RGB")
    loop = asyncio.get_event_loop()
    raw_text = await loop.run_in_executor(None, RUNTIME.generate, image, prompt)
    parsed = parse_model_json(raw_text)

    return {
        "adapter_dir": str(CONFIG.adapter_dir),
        "filename": file.filename,
        "raw_text": raw_text,
        "result": parsed,
    }


@app.post("/api/infer")
async def infer(
    file: UploadFile = File(...),
    prompt: str = Form(None),
    modelPath: str = Form(None),
) -> dict[str, Any]:
    if modelPath and modelPath.endswith(".litertlm"):
        raise HTTPException(
            status_code=400,
            detail=(
                "This backend runs Unsloth/HF models. To use a .litertlm file, "
                "run the LiteRT helper instead (./scripts/run_pc_litert_helper.sh) "
                "and ensure it is listening on the port the app is calling."
            ),
        )

    image_bytes = await file.read()

    try:
        validate_upload(
            content_type=file.content_type,
            size_bytes=len(image_bytes),
            max_bytes=CONFIG.max_upload_bytes,
        )
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error

    image = Image.open(BytesIO(image_bytes)).convert("RGB")
    loop = asyncio.get_event_loop()
    raw_text = await loop.run_in_executor(None, RUNTIME.generate, image, prompt)
    parsed = parse_model_json(raw_text)

    return {
        "adapter_dir": str(CONFIG.adapter_dir),
        "filename": file.filename,
        "raw_text": raw_text,
        "result": parsed,
    }
