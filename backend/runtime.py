import threading
from dataclasses import dataclass
from typing import Any

from .core import BackendConfig, SYSTEM_INSTRUCTION, inspect_model_files


@dataclass
class ModelBundle:
    model: Any
    processor: Any
    torch: Any


class OralGemmaRuntime:
    def __init__(self, config: BackendConfig) -> None:
        self.config = config
        self._bundle: ModelBundle | None = None
        self._lock = threading.Lock()

    @property
    def loaded(self) -> bool:
        return self._bundle is not None

    def status(self) -> dict[str, Any]:
        runtime = {
            "torch_available": False,
            "cuda_available": False,
            "device": None,
        }
        try:
            import torch

            runtime["torch_available"] = True
            runtime["cuda_available"] = torch.cuda.is_available()
            runtime["device"] = (
                torch.cuda.get_device_name(0) if torch.cuda.is_available() else None
            )
        except Exception as error:
            runtime["torch_error"] = str(error)

        inspected = inspect_model_files(self.config)
        inspected["runtime"] = runtime
        inspected["model_loaded"] = self.loaded
        inspected["ready"] = all(item["exists"] for item in inspected["files"].values())
        return inspected

    def bundle(self) -> ModelBundle:
        if self._bundle is not None:
            return self._bundle

        with self._lock:
            if self._bundle is not None:
                return self._bundle

            status = self.status()
            missing = [
                name for name, item in status["files"].items() if item["exists"] is False
            ]
            if missing:
                raise FileNotFoundError(f"Required model file(s) missing: {missing}")

            import torch
            from unsloth import FastVisionModel, get_chat_template

            if not torch.cuda.is_available():
                raise RuntimeError(
                    "CUDA is required for local Gemma inference, but no CUDA device is available."
                )

            model, processor = FastVisionModel.from_pretrained(
                model_name=str(self.config.adapter_dir),
                load_in_4bit=True,
                use_gradient_checkpointing="unsloth",
            )
            processor = get_chat_template(processor, "gemma-4")
            FastVisionModel.for_inference(model)

            self._bundle = ModelBundle(model=model, processor=processor, torch=torch)
            return self._bundle

    def generate(self, image: Any, prompt: str | None = None) -> str:
        bundle = self.bundle()
        messages = [
            {
                "role": "user",
                "content": [
                    {"type": "image"},
                    {"type": "text", "text": prompt or SYSTEM_INSTRUCTION},
                ],
            }
        ]
        input_text = bundle.processor.apply_chat_template(
            messages,
            add_generation_prompt=True,
            tokenize=False,
        )
        inputs = bundle.processor(
            images=image,
            text=input_text,
            add_special_tokens=False,
            return_tensors="pt",
        ).to("cuda")

        with bundle.torch.inference_mode():
            generated = bundle.model.generate(
                **inputs,
                max_new_tokens=self.config.max_new_tokens,
                use_cache=True,
                do_sample=False,
            )

        prompt_length = inputs["input_ids"].shape[-1]
        output_ids = generated[0][prompt_length:]
        return bundle.processor.tokenizer.decode(
            output_ids,
            skip_special_tokens=True,
        ).strip()
