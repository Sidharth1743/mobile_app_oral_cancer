import json
import os
from dataclasses import dataclass
from io import BytesIO
from pathlib import Path
from typing import Any

import torch
from fastapi import FastAPI, File, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from PIL import Image, UnidentifiedImageError


BASE_DIR = Path(__file__).resolve().parent
UI_DIR = BASE_DIR / "ui"
DEFAULT_MODEL_DIR = BASE_DIR / "outputs" / "no-vision-lora-15ep"
MODEL_DIR = Path(os.environ.get("ORAL_GEMMA_MODEL_DIR", DEFAULT_MODEL_DIR))
MAX_UPLOAD_BYTES = 8 * 1024 * 1024
MAX_NEW_TOKENS = int(os.environ.get("ORAL_GEMMA_MAX_NEW_TOKENS", "256"))
CATEGORIES = {"low_risk_or_variation", "refer_for_clinical_review"}
REQUIRED_FIELDS = ("category", "recommendation", "brief_reason", "disclaimer")


SYSTEM_INSTRUCTION = (
    "You are an oral screening assistant. Analyze this cropped oral mucosal image. "
    "Return JSON with: category, recommendation, brief_reason, disclaimer. "
    "Categories: low_risk_or_variation or refer_for_clinical_review. "
    "Do not diagnose."
)


@dataclass
class ModelBundle:
    model: Any
    processor: Any


model_bundle: ModelBundle | None = None

app = FastAPI(title="Oral Gemma Screening UI")
app.mount("/assets", StaticFiles(directory=UI_DIR), name="assets")


@app.exception_handler(FileNotFoundError)
async def file_not_found_handler(request: Request, exc: FileNotFoundError) -> JSONResponse:
    return JSONResponse(
        status_code=500,
        content={"error": "FileNotFoundError", "message": str(exc)},
    )


@app.exception_handler(UnidentifiedImageError)
async def image_error_handler(request: Request, exc: UnidentifiedImageError) -> JSONResponse:
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
    return {
        "model_dir": str(MODEL_DIR),
        "model_loaded": model_bundle is not None,
        "cuda_available": torch.cuda.is_available(),
        "device": torch.cuda.get_device_name(0) if torch.cuda.is_available() else None,
    }


@app.post("/api/analyze")
async def analyze(file: UploadFile = File(...)) -> dict[str, Any]:
    if file.content_type is None or not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="Upload must be an image file.")

    image_bytes = await file.read()
    if len(image_bytes) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="Image is larger than the 8 MB limit.")

    image = Image.open(BytesIO(image_bytes)).convert("RGB")
    bundle = get_model_bundle()
    raw_text = generate_response(bundle.model, bundle.processor, image)
    parsed = parse_model_json(raw_text)

    return {
        "model_dir": str(MODEL_DIR),
        "filename": file.filename,
        "raw_text": raw_text,
        "result": parsed,
    }


def get_model_bundle() -> ModelBundle:
    global model_bundle

    if model_bundle is not None:
        return model_bundle

    if not MODEL_DIR.exists():
        raise FileNotFoundError(f"Model directory does not exist: {MODEL_DIR}")
    if not (MODEL_DIR / "adapter_config.json").exists():
        raise FileNotFoundError(f"LoRA adapter_config.json not found in: {MODEL_DIR}")
    if not torch.cuda.is_available():
        raise RuntimeError("CUDA is required for local Gemma inference, but no CUDA device is available.")

    from unsloth import FastVisionModel, get_chat_template

    model, processor = FastVisionModel.from_pretrained(
        model_name=str(MODEL_DIR),
        load_in_4bit=True,
        use_gradient_checkpointing="unsloth",
    )
    processor = get_chat_template(processor, "gemma-4")
    FastVisionModel.for_inference(model)

    model_bundle = ModelBundle(model=model, processor=processor)
    return model_bundle


def generate_response(model: Any, processor: Any, image: Image.Image) -> str:
    messages = [
        {
            "role": "user",
            "content": [
                {"type": "image"},
                {"type": "text", "text": SYSTEM_INSTRUCTION},
            ],
        }
    ]
    input_text = processor.apply_chat_template(messages, add_generation_prompt=True)
    inputs = processor(
        image,
        input_text,
        add_special_tokens=False,
        return_tensors="pt",
    ).to("cuda")

    with torch.inference_mode():
        generated = model.generate(
            **inputs,
            max_new_tokens=MAX_NEW_TOKENS,
            use_cache=True,
            do_sample=False,
        )

    prompt_length = inputs["input_ids"].shape[-1]
    output_ids = generated[0][prompt_length:]
    return processor.tokenizer.decode(output_ids, skip_special_tokens=True).strip()


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
