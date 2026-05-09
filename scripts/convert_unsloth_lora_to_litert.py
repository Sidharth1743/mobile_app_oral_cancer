#!/usr/bin/env python3
"""Merge an Unsloth LoRA adapter and prepare LiteRT conversion artifacts.

This helper intentionally splits the process into explicit steps:
1) Merge LoRA adapter -> full Hugging Face model directory.
2) Optionally convert merged model -> LiteRT TFLite.
3) Optionally bundle TFLite + tokenizer -> MediaPipe `.task`.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


def list_litert_builders() -> tuple[str, list[str]]:
    import pkgutil

    import litert_torch
    import litert_torch.generative.examples as examples

    version = getattr(litert_torch, "__version__", "unknown")
    modules = [module.name for module in pkgutil.iter_modules(examples.__path__)]
    return version, modules


def merge_lora(args: argparse.Namespace) -> Path:
    from unsloth import FastVisionModel, get_chat_template

    source_dir = Path(args.model_dir).expanduser().resolve()
    merged_dir = Path(args.merged_dir).expanduser().resolve()
    merged_dir.mkdir(parents=True, exist_ok=True)

    print(f"[merge] Loading Unsloth model from: {source_dir}")
    model, processor = FastVisionModel.from_pretrained(
        model_name=str(source_dir),
        load_in_4bit=False,
        use_gradient_checkpointing="unsloth",
    )
    # Keep the same chat template expected by project inference.
    processor = get_chat_template(processor, "gemma-4")

    if not hasattr(model, "save_pretrained_merged"):
        raise RuntimeError(
            "This Unsloth version does not expose save_pretrained_merged(). "
            "Please upgrade unsloth first."
        )

    print(f"[merge] Saving merged 16-bit model to: {merged_dir}")
    model.save_pretrained_merged(
        str(merged_dir),
        processor,
        save_method="merged_16bit",
    )
    print("[merge] Done.")
    return merged_dir


def _run_export_hf(args: argparse.Namespace, merged_dir: Path, out_dir: Path) -> bool:
    if args.export_vision_encoder:
        _check_vision_export_support(merged_dir)

    command = [
        sys.executable,
        "-m",
        "litert_torch.generative.export_hf",
        str(merged_dir),
        str(out_dir),
        f"--task={args.export_task}",
        f"--prefill_lengths=[{args.prefill_seq_len}]",
        f"--cache_length={args.kv_cache_max_len}",
        f"--quantization_recipe={args.quantize}",
        "--bundle_litert_lm=True",
    ]
    if args.export_vision_encoder:
        command.append("--export_vision_encoder=True")
        command.append(
            f"--vision_encoder_quantization_recipe={args.vision_quantize}"
        )
    if args.externalize_embedder:
        command.append("--externalize_embedder=True")
    if args.use_jinja_template:
        command.append("--use_jinja_template=True")
    if args.single_token_embedder:
        command.append("--single_token_embedder=True")
    if args.experimental_lightweight_conversion:
        command.append("--experimental_lightweight_conversion=True")
    if args.jinja_chat_template_override:
        command.extend(
            [
                "--jinja_chat_template_override",
                args.jinja_chat_template_override,
            ]
        )

    print("[convert] Using litert_torch.generative.export_hf")
    print(f"[convert] Output directory: {out_dir}")
    env = os.environ.copy()
    env.setdefault("OMP_NUM_THREADS", str(args.export_threads))
    env.setdefault("MKL_NUM_THREADS", str(args.export_threads))
    env.setdefault("NUMEXPR_NUM_THREADS", str(args.export_threads))
    env.setdefault("TOKENIZERS_PARALLELISM", "false")
    try:
        subprocess.run(command, check=True, env=env)
        return True
    except ModuleNotFoundError:
        return False
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(
            "LiteRT export_hf failed. Check convert.log for the exact exporter "
            "stage. If this is a Gemma 4 vision export, current public "
            "litert-torch builds may support Gemma 4 text export but not Gemma 4 "
            "vision exportables."
        ) from exc


def _check_vision_export_support(merged_dir: Path) -> None:
    """Fail before heavy export if the installed litert-torch lacks vision support."""
    try:
        from transformers import AutoConfig
        from litert_torch.generative.export_hf.model_ext import exportables
    except Exception:
        return

    config = AutoConfig.from_pretrained(str(merged_dir))
    try:
        exportables.get_vision_exportables(config)
    except ValueError as exc:
        raise RuntimeError(
            "This installed litert-torch build cannot export the vision encoder "
            f"for model_type={config.model_type!r}. It can still export Gemma 4 "
            "text components, but image_text_to_text export needs a Gemma 4 "
            "vision_exportable implementation or an official/prebuilt "
            "vision-compatible LiteRT-LM bundle."
        ) from exc


def convert_to_tflite(args: argparse.Namespace) -> Path:
    """Convert merged HF model directory to LiteRT-LM artifacts.

    Current Google docs provide explicit examples for Gemma3 builders.
    Current Gemma4 deployment material uses the export_hf CLI/module path
    that emits LiteRT-LM artifacts, so prefer it before older example builders.
    """

    merged_dir = Path(args.merged_dir).expanduser().resolve()
    out_dir = Path(args.tflite_out_dir).expanduser().resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    # Avoid accidentally testing a stale bundle after an export failure.
    stale_outputs = [out_dir / "model.litertlm"]
    stale_outputs.extend(out_dir.glob("model.litertlm.*xnnpack_cache_*"))
    for stale_output in stale_outputs:
        if stale_output.exists() and stale_output.is_file():
            stale_output.unlink()

    if _run_export_hf(args, merged_dir, out_dir):
        capture_exported_model(args, out_dir)
        print("[convert] Done.")
        return out_dir

    try:
        from litert_torch.generative.utilities import converter
        from litert_torch.generative.utilities.export_config import ExportConfig
        from litert_torch.generative.layers import kv_cache
    except Exception as exc:
        raise RuntimeError(
            "litert-torch is required for conversion. Install with "
            '`pip install "litert-torch>=0.8.0"`'
        ) from exc

    version = "unknown"
    available_modules: list[str] = []
    try:
        version, available_modules = list_litert_builders()
    except Exception:
        pass

    builder = None
    builder_name = None

    try:
        from litert_torch.generative.examples.gemma4 import gemma4  # type: ignore

        if hasattr(gemma4, "build_model_e2b"):
            builder = gemma4.build_model_e2b
            builder_name = "gemma4.build_model_e2b"
        elif hasattr(gemma4, "build_model"):
            builder = gemma4.build_model
            builder_name = "gemma4.build_model"
    except Exception:
        pass

    if builder is None:
        raise RuntimeError(
            "Could not find a Gemma4 builder in litert-torch. "
            "Please use a litert-torch build that supports Gemma4 conversion, "
            "or update this helper with the correct builder for your version. "
            f"Detected litert-torch version: {version}. "
            f"Available example modules: {available_modules}"
        )

    print(f"[convert] Using builder: {builder_name}")
    pytorch_model = builder(str(merged_dir))

    export_config = ExportConfig()
    export_config.kvcache_layout = kv_cache.KV_LAYOUT_TRANSPOSED
    export_config.mask_as_input = True

    print(f"[convert] Exporting TFLite to: {out_dir}")
    converter.convert_to_tflite(
        pytorch_model,
        output_path=str(out_dir),
        output_name_prefix=args.output_name_prefix,
        prefill_seq_len=args.prefill_seq_len,
        kv_cache_max_len=args.kv_cache_max_len,
        quantize=args.quantize,
        export_config=export_config,
    )
    print("[convert] Done.")

    # The converter writes files into output_path with prefix naming.
    return out_dir


def capture_exported_model(args: argparse.Namespace, out_dir: Path) -> None:
    exported_model = out_dir / "model.litertlm"
    if not exported_model.exists():
        raise FileNotFoundError(
            f"LiteRT export finished but {exported_model} was not created."
        )

    stat = exported_model.stat()
    manifest_path = out_dir / "latest_export.json"
    manifest = {
        "model_path": str(exported_model),
        "size_bytes": stat.st_size,
        "modified_unix": int(stat.st_mtime),
        "export_task": args.export_task,
        "prefill_seq_len": args.prefill_seq_len,
        "kv_cache_max_len": args.kv_cache_max_len,
        "quantize": args.quantize,
        "export_vision_encoder": args.export_vision_encoder,
        "vision_quantize": args.vision_quantize,
    }
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"[capture] latest_export_manifest={manifest_path}")

    if args.capture_model_path:
        capture_path = Path(args.capture_model_path).expanduser().resolve()
        capture_path.parent.mkdir(parents=True, exist_ok=True)
        for stale_cache in capture_path.parent.glob(
            f"{capture_path.name}.*xnnpack_cache_*"
        ):
            if stale_cache.is_file():
                stale_cache.unlink()
        shutil.copy2(exported_model, capture_path)
        print(f"[capture] copied_model={capture_path}")


def bundle_task(args: argparse.Namespace) -> Path:
    try:
        from mediapipe.tasks.python.genai import bundler
    except Exception as exc:
        raise RuntimeError(
            "mediapipe is required for task bundling. Install with `pip install mediapipe`."
        ) from exc

    tflite_path = Path(args.tflite_model).expanduser().resolve()
    tokenizer_model = Path(args.tokenizer_model).expanduser().resolve()
    task_path = Path(args.task_out).expanduser().resolve()
    task_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"[bundle] Bundling task file: {task_path}")
    config = bundler.BundleConfig(
        tflite_model=str(tflite_path),
        tokenizer_model=str(tokenizer_model),
        start_token="<bos>",
        stop_tokens=["<eos>", "<end_of_turn>"],
        output_filename=str(task_path),
        prompt_prefix="<start_of_turn>user\n",
        prompt_suffix="<end_of_turn>\n<start_of_turn>model\n",
    )
    bundler.create_bundle(config)
    print("[bundle] Done.")
    return task_path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Merge Unsloth LoRA and prepare LiteRT artifacts."
    )
    parser.add_argument(
        "--model-dir",
        default="oral_gemma_finetune_package/outputs/no-vision-lora-15ep",
        help="Path to LoRA adapter dir (or existing Unsloth model dir).",
    )
    parser.add_argument(
        "--merged-dir",
        default="oral_gemma_finetune_package/outputs/no-vision-lora-15ep-merged",
        help="Output dir for merged HF model.",
    )
    parser.add_argument(
        "--tflite-out-dir",
        default="oral_gemma_finetune_package/outputs/no-vision-lora-15ep-litert",
        help="Output dir for LiteRT TFLite conversion.",
    )
    parser.add_argument(
        "--output-name-prefix",
        default="gemma4-oc",
        help="Prefix for exported LiteRT files.",
    )
    parser.add_argument(
        "--prefill-seq-len",
        type=int,
        default=256,
        help="Prefill length for LiteRT conversion. Increase only on a machine with enough RAM.",
    )
    parser.add_argument(
        "--kv-cache-max-len",
        type=int,
        default=1024,
        help="KV cache length for LiteRT conversion. Increase for longer prompts if export memory allows.",
    )
    parser.add_argument(
        "--quantize",
        default="dynamic_wi4_afp32",
        choices=[
            "none",
            "fp16",
            "dynamic_int8",
            "weight_only_int8",
            "dynamic_wi4_afp32",
        ],
        help="Quantization mode.",
    )
    parser.add_argument(
        "--export-task",
        default="text_generation",
        choices=["text_generation", "image_text_to_text"],
        help="LiteRT export task. Use image_text_to_text for vision-compatible Gemma 4.",
    )
    parser.add_argument(
        "--export-vision-encoder",
        action=argparse.BooleanOptionalAction,
        default=False,
        help="Export Gemma 4 vision encoder for multimodal image+text inference.",
    )
    parser.add_argument(
        "--vision-quantize",
        default="none",
        help="Vision encoder quantization recipe. Use none to keep vision FP32 and avoid current Gemma 4 quantization issues.",
    )
    parser.add_argument(
        "--externalize-embedder",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Externalize embedder weights when export_hf supports it.",
    )
    parser.add_argument(
        "--use-jinja-template",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Ask export_hf to preserve/use tokenizer Jinja chat template.",
    )
    parser.add_argument(
        "--single-token-embedder",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Export a single token embedder and skip the heavier per-layer embedder path when supported.",
    )
    parser.add_argument(
        "--jinja-chat-template-override",
        default="",
        help="Optional HF repo or local path used as export_hf Jinja template override.",
    )
    parser.add_argument(
        "--experimental-lightweight-conversion",
        action=argparse.BooleanOptionalAction,
        default=False,
        help="Enable LiteRT export_hf lightweight conversion to reduce peak memory when supported.",
    )
    parser.add_argument(
        "--export-threads",
        type=int,
        default=2,
        help="Thread count exported to OMP/MKL/NUMEXPR during conversion.",
    )
    parser.add_argument(
        "--skip-convert",
        action="store_true",
        help="Only perform LoRA merge, skip LiteRT conversion.",
    )
    parser.add_argument(
        "--skip-merge",
        action="store_true",
        help="Use an existing merged HF model dir and only run LiteRT conversion.",
    )
    parser.add_argument(
        "--bundle-task",
        action="store_true",
        help="Create a MediaPipe task bundle after conversion.",
    )
    parser.add_argument(
        "--capture-model-path",
        default="",
        help="Optional path where the freshly exported model.litertlm is copied after a successful export.",
    )
    parser.add_argument(
        "--tflite-model",
        default="",
        help="Path to exported .tflite for --bundle-task.",
    )
    parser.add_argument(
        "--tokenizer-model",
        default="",
        help="Path to tokenizer.model for --bundle-task.",
    )
    parser.add_argument(
        "--task-out",
        default="oral_gemma_finetune_package/outputs/no-vision-lora-15ep-litert/gemma4-oc.task",
        help="Output path for bundled .task file.",
    )
    parser.add_argument(
        "--list-litert-builders",
        action="store_true",
        help="Print installed litert-torch example modules and exit.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    if args.list_litert_builders:
        version, modules = list_litert_builders()
        print(f"litert_torch_version={version}")
        print(f"litert_example_modules={modules}")
        return

    if args.skip_merge:
        merged_dir = Path(args.merged_dir).expanduser().resolve()
        if not (merged_dir / "config.json").exists():
            raise FileNotFoundError(
                f"--skip-merge was set but no merged model config exists at {merged_dir}"
            )
        print(f"[merge] Skipped. Using existing merged model: {merged_dir}")
    else:
        merged_dir = merge_lora(args)
    print(f"[done] merged_dir={merged_dir}")

    if not args.skip_convert:
        convert_dir = convert_to_tflite(args)
        print(f"[done] tflite_output_dir={convert_dir}")

    if args.bundle_task:
        if not args.tflite_model:
            raise ValueError("--tflite-model is required when --bundle-task is set.")
        if not args.tokenizer_model:
            raise ValueError("--tokenizer-model is required when --bundle-task is set.")
        task_path = bundle_task(args)
        print(f"[done] task_file={task_path}")


if __name__ == "__main__":
    main()
