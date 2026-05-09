import os
import json
import random
import argparse
import gc
import inspect
import re
import shutil
from datetime import datetime
from pathlib import Path
from collections import Counter

os.environ["UNSLOTH_COMPILE_DISABLE"] = "1"
os.environ["PYTORCH_ALLOC_CONF"] = "expandable_segments:True"

import torch
from PIL import Image

from unsloth import FastVisionModel, get_chat_template
from unsloth.trainer import UnslothVisionDataCollator
from transformers import EarlyStoppingCallback, TrainerCallback
from trl import SFTTrainer, SFTConfig


BASE_DIR = Path(__file__).resolve().parent
LEGACY_IMAGE_ROOT_NAME = "oral_lesion_crops_224_all"
DEFAULT_MODEL_DIR = BASE_DIR / "model" / "gemma-unsloth-e2b"
DATA_DIR = BASE_DIR / "data"
if not DATA_DIR.exists():
    DATA_DIR = BASE_DIR.parent / "oral_finetune" / "data"

HUB_MODEL_NAME = "unsloth/gemma-4-E2B-it"

OUTPUT_ROOT = BASE_DIR / "outputs"
CATEGORIES = ("low_risk_or_variation", "refer_for_clinical_review")

SEED = 42

FINETUNE_VISION_LAYERS = True

LORA_R = 32
LORA_ALPHA = 64
LORA_DROPOUT = 0.0

NUM_EPOCHS = 20
LR = 2e-4

BATCH_SIZE = 6
GRAD_ACCUM = 1

MAX_LENGTH = 2048
EVAL_STEPS = 25
SAVE_STEPS = 25
EARLY_STOPPING_PATIENCE = 4
EARLY_STOPPING_THRESHOLD = 0.01
CLINICAL_EVAL_STEPS = 50
CLINICAL_EVAL_MAX_SAMPLES = 55
CLINICAL_MIN_MACRO_F1 = 0.45
CLINICAL_MAX_NEW_TOKENS = 96

WANDB_PROJECT = "oral-gemma4-e2b-finetune"
WANDB_LOG_MODEL = "false"
WANDB_WATCH = "gradients"


random.seed(SEED)
torch.manual_seed(SEED)
torch.cuda.manual_seed_all(SEED)


def load_jsonl(path):
    rows = []
    with Path(path).open("r", encoding="utf-8") as f:
        for line in f:
            rows.append(json.loads(line))
    return rows


def parse_args():
    parser = argparse.ArgumentParser(
        description="Fine-tune Gemma 4 E2B Vision with Unsloth QLoRA on the oral screening dataset."
    )
    parser.add_argument(
        "--model-dir",
        type=Path,
        default=DEFAULT_MODEL_DIR,
        help="Local Hugging Face/Transformers checkpoint directory. Defaults to ./model/gemma-unsloth-e2b.",
    )
    parser.add_argument(
        "--hub-model",
        default=HUB_MODEL_NAME,
        help="Hub model id to use when --allow-hub-fallback is set.",
    )
    parser.add_argument(
        "--allow-hub-fallback",
        action="store_true",
        help="Use --hub-model if --model-dir is missing or is not a Transformers checkpoint.",
    )
    parser.add_argument(
        "--data-dir",
        type=Path,
        default=DATA_DIR,
        help="Directory containing train.jsonl, val.jsonl, and test.jsonl.",
    )
    parser.add_argument("--epochs", type=float, default=NUM_EPOCHS)
    parser.add_argument("--lr", type=float, default=LR)
    parser.add_argument("--batch-size", type=int, default=BATCH_SIZE)
    parser.add_argument("--grad-accum", type=int, default=GRAD_ACCUM)
    parser.add_argument("--max-length", type=int, default=MAX_LENGTH)
    parser.add_argument("--eval-steps", type=int, default=EVAL_STEPS)
    parser.add_argument("--save-steps", type=int, default=SAVE_STEPS)
    parser.add_argument(
        "--no-clinical-eval",
        action="store_true",
        help="Disable generation-based clinical validation metrics during training.",
    )
    parser.add_argument(
        "--clinical-eval-steps",
        type=int,
        default=CLINICAL_EVAL_STEPS,
        help="Run generation-based validation metrics every N optimizer steps.",
    )
    parser.add_argument(
        "--clinical-eval-max-samples",
        type=int,
        default=CLINICAL_EVAL_MAX_SAMPLES,
        help="Maximum validation rows used for generation-based clinical metrics.",
    )
    parser.add_argument(
        "--clinical-min-macro-f1",
        type=float,
        default=CLINICAL_MIN_MACRO_F1,
        help="Minimum macro-F1 required before a higher refer recall can replace the best clinical adapter.",
    )
    parser.add_argument(
        "--clinical-max-new-tokens",
        type=int,
        default=CLINICAL_MAX_NEW_TOKENS,
        help="Maximum generated tokens per validation example for clinical metrics.",
    )
    parser.add_argument(
        "--no-load-best-model",
        action="store_true",
        help="Do not reload the best eval-loss checkpoint at the end.",
    )
    parser.add_argument(
        "--no-early-stopping",
        action="store_true",
        help="Disable early stopping on validation loss.",
    )
    parser.add_argument(
        "--early-stopping-patience",
        type=int,
        default=EARLY_STOPPING_PATIENCE,
        help="Stop after this many eval rounds without enough eval_loss improvement.",
    )
    parser.add_argument(
        "--early-stopping-threshold",
        type=float,
        default=EARLY_STOPPING_THRESHOLD,
        help="Minimum eval_loss improvement required to reset early stopping patience.",
    )
    parser.add_argument(
        "--chat-template",
        default="gemma-4",
        choices=("gemma-4", "gemma-4-thinking"),
        help="Gemma 4 chat template. Use gemma-4 for E2B/E4B unless you intentionally train thinking traces.",
    )
    parser.add_argument(
        "--max-steps",
        type=int,
        default=None,
        help="Optional debug/quick-run limit. Leave unset for epoch-based training.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=None,
        help="Output directory. Defaults to a fresh timestamped directory under ./outputs.",
    )
    parser.add_argument(
        "--overwrite-output-dir",
        action="store_true",
        help="Allow Trainer to write into a non-empty output directory.",
    )
    parser.add_argument(
        "--no-wandb",
        action="store_true",
        help="Disable Weights & Biases logging.",
    )
    parser.add_argument(
        "--wandb-project",
        default=WANDB_PROJECT,
        help="Weights & Biases project name.",
    )
    parser.add_argument(
        "--wandb-entity",
        default=None,
        help="Optional Weights & Biases entity/team.",
    )
    parser.add_argument(
        "--wandb-run-name",
        default=None,
        help="Optional Weights & Biases run name.",
    )
    parser.add_argument(
        "--wandb-mode",
        default="online",
        choices=("online", "offline", "disabled"),
        help="Weights & Biases mode.",
    )
    parser.add_argument(
        "--wandb-watch",
        default=WANDB_WATCH,
        choices=("false", "gradients", "all"),
        help="Log gradient histograms, or gradients plus parameter histograms, to W&B.",
    )
    parser.add_argument(
        "--wandb-log-model",
        default=WANDB_LOG_MODEL,
        choices=("false", "checkpoint", "end"),
        help="Whether W&B should upload model checkpoints as artifacts.",
    )
    parser.add_argument(
        "--wandb-tags",
        default="gemma4,e2b,vision,lora,oral-screening",
        help="Comma-separated W&B run tags.",
    )
    parser.add_argument(
        "--finetune-vision-layers",
        action=argparse.BooleanOptionalAction,
        default=FINETUNE_VISION_LAYERS,
        help="Whether LoRA adapters should be added to vision layers.",
    )
    args = parser.parse_args()
    if args.wandb_run_name is None:
        args.wandb_run_name = f"{default_run_name(args)}-{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    if args.output_dir is None:
        args.output_dir = OUTPUT_ROOT / sanitize_run_name(args.wandb_run_name)
    return args


def is_transformers_checkpoint(path):
    return (path / "config.json").exists()


def resolve_model_name(model_dir, hub_model, allow_hub_fallback):
    model_dir = model_dir.expanduser().resolve()

    if is_transformers_checkpoint(model_dir):
        return str(model_dir)

    lite_rt_files = sorted(model_dir.glob("*.litertlm")) if model_dir.exists() else []
    if lite_rt_files:
        message = (
            f"{model_dir} contains LiteRT-LM deployment file(s), not a Hugging Face "
            "Transformers checkpoint: "
            + ", ".join(path.name for path in lite_rt_files)
            + "\n\nUnsloth fine-tuning needs a trainable Transformers checkpoint directory "
            "with files such as config.json, tokenizer files, and model weight shards. "
            "Pass --model-dir pointing at a Hugging Face/Transformers checkpoint, or pass "
            "--allow-hub-fallback to download/use the hub model instead."
        )
    else:
        message = (
            f"{model_dir} is not a usable Transformers checkpoint because config.json "
            "was not found."
        )

    if allow_hub_fallback:
        print("\nWARNING:", message)
        print("Falling back to hub model:", hub_model)
        return hub_model

    raise RuntimeError(message)


def resolve_image_path(raw_path):
    img_path = Path(raw_path)
    if img_path.is_absolute() and img_path.exists():
        return img_path

    package_relative = BASE_DIR / img_path
    if package_relative.exists():
        return package_relative

    parts = img_path.parts
    if LEGACY_IMAGE_ROOT_NAME in parts:
        idx = parts.index(LEGACY_IMAGE_ROOT_NAME)
        candidate = BASE_DIR.joinpath(*parts[idx + 1:])
        if candidate.exists():
            return candidate

    return img_path


def extract_text_content(content):
    if isinstance(content, str):
        return content

    if isinstance(content, list):
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text":
                return item["text"]

    raise TypeError(f"Unsupported content format: {type(content).__name__}")


def parse_category(text):
    start = text.find("{")
    end = text.rfind("}")
    if start != -1 and end != -1 and end > start:
        try:
            parsed = json.loads(text[start:end + 1])
            category = parsed.get("category")
            if category in CATEGORIES:
                return category
        except json.JSONDecodeError:
            pass

    match = re.search(r'"?category"?\s*[:=]\s*"?([a-z_]+)"?', text)
    if match and match.group(1) in CATEGORIES:
        return match.group(1)

    for category in CATEGORIES:
        if category in text:
            return category

    return None


def safe_divide(numerator, denominator):
    return numerator / denominator if denominator else 0.0


def compute_category_metrics(gold_labels, predicted_labels):
    total = len(gold_labels)
    correct = sum(gold == pred for gold, pred in zip(gold_labels, predicted_labels))
    metrics = {
        "accuracy": safe_divide(correct, total),
        "unparsed": sum(pred is None for pred in predicted_labels),
        "macro_f1": 0.0,
        "refer_recall": 0.0,
        "low_risk_recall": 0.0,
    }

    f1_values = []
    for category in CATEGORIES:
        tp = sum(gold == category and pred == category for gold, pred in zip(gold_labels, predicted_labels))
        fp = sum(gold != category and pred == category for gold, pred in zip(gold_labels, predicted_labels))
        fn = sum(gold == category and pred != category for gold, pred in zip(gold_labels, predicted_labels))
        precision = safe_divide(tp, tp + fp)
        recall = safe_divide(tp, tp + fn)
        f1 = safe_divide(2 * precision * recall, precision + recall)
        f1_values.append(f1)
        prefix = "refer" if category == "refer_for_clinical_review" else "low_risk"
        metrics[f"{prefix}_precision"] = precision
        metrics[f"{prefix}_recall"] = recall
        metrics[f"{prefix}_f1"] = f1
        metrics[f"{prefix}_support"] = sum(gold == category for gold in gold_labels)

    metrics["macro_f1"] = sum(f1_values) / len(f1_values)
    metrics["low_to_refer"] = sum(
        gold == "low_risk_or_variation" and pred == "refer_for_clinical_review"
        for gold, pred in zip(gold_labels, predicted_labels)
    )
    metrics["refer_to_low"] = sum(
        gold == "refer_for_clinical_review" and pred == "low_risk_or_variation"
        for gold, pred in zip(gold_labels, predicted_labels)
    )
    return metrics


def validate_rows(rows, name):
    missing = []
    bad = []
    cats = Counter()

    for row in rows:
        img_path = resolve_image_path(row["image"])
        cats[row["metadata"]["binary_category"]] += 1

        if not img_path.exists():
            missing.append(str(img_path))
            continue

        try:
            Image.open(img_path).convert("RGB")
        except Exception as e:
            bad.append((str(img_path), str(e)))

    print(f"\n{name}: {len(rows)} rows")
    print("Categories:", cats)
    print("Missing images:", len(missing))
    print("Bad images:", len(bad))

    if missing:
        print("First missing:", missing[:5])
        raise FileNotFoundError("Some image files are missing.")

    if bad:
        print("First bad:", bad[:5])
        raise RuntimeError("Some images cannot be opened.")

    return cats


def convert_to_conversation(row):
    image_path = resolve_image_path(row["image"])
    image = Image.open(image_path).convert("RGB")

    user_text = extract_text_content(row["messages"][0]["content"])
    assistant_answer = extract_text_content(row["messages"][1]["content"])

    conversation = [
        {
            "role": "user",
            "content": [
                {"type": "image", "image": image},
                {"type": "text", "text": user_text},
            ],
        },
        {
            "role": "assistant",
            "content": [
                {"type": "text", "text": assistant_answer}
            ],
        },
    ]

    return {"messages": conversation}


def make_generation_inputs(processor, row):
    image_path = resolve_image_path(row["image"])
    image = Image.open(image_path).convert("RGB")
    instruction = extract_text_content(row["messages"][0]["content"])
    messages = [
        {
            "role": "user",
            "content": [
                {"type": "image"},
                {"type": "text", "text": instruction},
            ],
        }
    ]
    input_text = processor.apply_chat_template(messages, add_generation_prompt=True)
    return image, input_text


def is_wandb_enabled(args):
    return not args.no_wandb and args.wandb_mode != "disabled"


def sanitize_run_name(name):
    safe_chars = []
    for char in str(name):
        if char.isalnum() or char in ("-", "_", "."):
            safe_chars.append(char)
        else:
            safe_chars.append("-")

    sanitized = "".join(safe_chars).strip("-")
    while "--" in sanitized:
        sanitized = sanitized.replace("--", "-")
    return sanitized or "gemma4-e2b-run"


def default_run_name(args):
    model_name = Path(str(args.model_dir)).name or "gemma4-e2b"
    epochs = int(args.epochs) if float(args.epochs).is_integer() else args.epochs
    return (
        f"{model_name}-r{LORA_R}-a{LORA_ALPHA}-"
        f"bs{args.batch_size}x{args.grad_accum}-ep{epochs}"
    )


def count_parameters(model):
    trainable = 0
    total = 0
    for parameter in model.parameters():
        count = parameter.numel()
        total += count
        if parameter.requires_grad:
            trainable += count

    percent = 100 * trainable / total if total else 0
    return trainable, total, percent


def should_load_best_model(args):
    if args.no_load_best_model:
        return False

    if args.save_steps % args.eval_steps != 0:
        return False

    return args.max_steps is None or args.max_steps >= args.eval_steps


def is_early_stopping_enabled(args):
    return (
        not args.no_early_stopping
        and args.early_stopping_patience > 0
        and should_load_best_model(args)
    )


def is_clinical_eval_enabled(args):
    return (
        not args.no_clinical_eval
        and args.clinical_eval_steps > 0
        and args.clinical_eval_max_samples != 0
    )


def validate_output_dir(args):
    args.output_dir.mkdir(parents=True, exist_ok=True)
    existing_items = [item for item in args.output_dir.iterdir()]
    if existing_items and not args.overwrite_output_dir:
        raise FileExistsError(
            f"Output directory is not empty: {args.output_dir}\n"
            "Use a new --wandb-run-name, pass a different --output-dir, or add "
            "--overwrite-output-dir if you intentionally want to reuse it."
        )


def split_paths(data_dir):
    data_dir = Path(data_dir)
    return {
        "train": data_dir / "train.jsonl",
        "val": data_dir / "val.jsonl",
        "test": data_dir / "test.jsonl",
    }


def validate_data_dir(data_dir):
    paths = split_paths(data_dir)
    missing = [str(path) for path in paths.values() if not path.exists()]
    if missing:
        raise FileNotFoundError(
            "Dataset directory must contain train.jsonl, val.jsonl, and test.jsonl. "
            f"Missing: {missing}"
        )
    return paths


def setup_wandb(args, model_name, split_sizes, category_counts):
    if not is_wandb_enabled(args):
        os.environ["WANDB_DISABLED"] = "true"
        return None

    os.environ.pop("WANDB_DISABLED", None)
    os.environ["WANDB_PROJECT"] = args.wandb_project
    os.environ["WANDB_LOG_MODEL"] = args.wandb_log_model
    os.environ["WANDB_WATCH"] = args.wandb_watch
    os.environ["WANDB_MODE"] = args.wandb_mode

    try:
        import wandb
    except ImportError as exc:
        raise ImportError(
            "Weights & Biases logging is enabled, but wandb is not installed. "
            "Install it with `pip install wandb` or rerun with --no-wandb."
        ) from exc

    run = wandb.init(
        project=args.wandb_project,
        entity=args.wandb_entity,
        name=args.wandb_run_name or default_run_name(args),
        tags=[tag.strip() for tag in args.wandb_tags.split(",") if tag.strip()],
        config={
            "model_name": model_name,
            "model_dir": str(args.model_dir),
            "data_dir": str(args.data_dir),
            "output_dir": str(args.output_dir),
            "chat_template": args.chat_template,
            "train_rows": split_sizes["train"],
            "val_rows": split_sizes["val"],
            "test_rows": split_sizes["test"],
            "train_category_counts": dict(category_counts["train"]),
            "val_category_counts": dict(category_counts["val"]),
            "test_category_counts": dict(category_counts["test"]),
            "lora_r": LORA_R,
            "lora_alpha": LORA_ALPHA,
            "lora_dropout": LORA_DROPOUT,
            "finetune_vision_layers": args.finetune_vision_layers,
            "finetune_language_layers": True,
            "finetune_attention_modules": True,
            "finetune_mlp_modules": True,
            "target_modules": "all-linear",
            "epochs": args.epochs,
            "max_steps": args.max_steps,
            "learning_rate": args.lr,
            "batch_size": args.batch_size,
            "gradient_accumulation_steps": args.grad_accum,
            "effective_batch_size": args.batch_size * args.grad_accum,
            "max_length": args.max_length,
            "eval_steps": args.eval_steps,
            "save_steps": args.save_steps,
            "load_best_model_at_end": should_load_best_model(args),
            "early_stopping_enabled": is_early_stopping_enabled(args),
            "early_stopping_patience": args.early_stopping_patience,
            "early_stopping_threshold": args.early_stopping_threshold,
            "clinical_eval_enabled": is_clinical_eval_enabled(args),
            "clinical_eval_steps": args.clinical_eval_steps,
            "clinical_eval_max_samples": args.clinical_eval_max_samples,
            "clinical_min_macro_f1": args.clinical_min_macro_f1,
            "clinical_max_new_tokens": args.clinical_max_new_tokens,
            "optimizer": "adamw_8bit",
            "lr_scheduler": "cosine",
            "warmup_ratio": 0.03,
            "max_grad_norm": 0.3,
            "seed": SEED,
        },
    )
    return run


def log_wandb_summary(run, metrics):
    if run is None:
        return

    for key, value in metrics.items():
        run.summary[key] = value


class GpuMemoryCallback(TrainerCallback):
    def on_log(self, args, state, control, logs=None, **kwargs):
        if not torch.cuda.is_available() or logs is None:
            return

        logs["gpu/allocated_gb"] = torch.cuda.memory_allocated() / 1024**3
        logs["gpu/reserved_gb"] = torch.cuda.memory_reserved() / 1024**3
        logs["gpu/max_reserved_gb"] = torch.cuda.max_memory_reserved() / 1024**3


class ClinicalValidationCallback(TrainerCallback):
    def __init__(
        self,
        processor,
        rows,
        output_dir,
        eval_steps,
        max_samples,
        max_new_tokens,
        min_macro_f1,
        wandb_run=None,
    ):
        self.processor = processor
        self.rows = rows if max_samples is None or max_samples < 0 else rows[:max_samples]
        self.best_dir = Path(output_dir) / "best_clinical"
        self.eval_steps = eval_steps
        self.max_new_tokens = max_new_tokens
        self.min_macro_f1 = min_macro_f1
        self.wandb_run = wandb_run
        self.best_refer_recall = -1.0
        self.best_macro_f1 = -1.0
        self.best_step = None

    def should_replace_best(self, metrics):
        refer_recall = metrics["refer_recall"]
        macro_f1 = metrics["macro_f1"]

        if macro_f1 < self.min_macro_f1:
            return False

        if refer_recall > self.best_refer_recall:
            return True

        if refer_recall == self.best_refer_recall and macro_f1 > self.best_macro_f1:
            return True

        return False

    def on_step_end(self, args, state, control, model=None, **kwargs):
        if state.global_step == 0 or state.global_step % self.eval_steps != 0:
            return

        if model is None:
            return

        if torch.cuda.is_available():
            torch.cuda.empty_cache()

        was_training = model.training
        model.eval()
        gold_labels = []
        predicted_labels = []

        with torch.inference_mode():
            for row in self.rows:
                image, input_text = make_generation_inputs(self.processor, row)
                inputs = self.processor(
                    image,
                    input_text,
                    add_special_tokens=False,
                    return_tensors="pt",
                ).to("cuda")
                generated = model.generate(
                    **inputs,
                    max_new_tokens=self.max_new_tokens,
                    use_cache=True,
                    do_sample=False,
                )
                prompt_length = inputs["input_ids"].shape[-1]
                output_ids = generated[0][prompt_length:]
                generated_text = self.processor.tokenizer.decode(
                    output_ids,
                    skip_special_tokens=True,
                ).strip()
                gold_labels.append(row["metadata"]["binary_category"])
                predicted_labels.append(parse_category(generated_text))
                del image, input_text, inputs, generated, output_ids

        if was_training:
            model.train()

        gc.collect()
        if torch.cuda.is_available():
            torch.cuda.empty_cache()

        metrics = compute_category_metrics(gold_labels, predicted_labels)
        clinical_logs = {
            f"clinical_val/{key}": value
            for key, value in metrics.items()
        }
        clinical_logs["clinical_val/global_step"] = state.global_step

        print("\nClinical validation metrics:")
        print(json.dumps(clinical_logs, indent=2))

        if self.wandb_run is not None:
            self.wandb_run.log(clinical_logs, step=state.global_step)

        if self.should_replace_best(metrics):
            self.best_refer_recall = metrics["refer_recall"]
            self.best_macro_f1 = metrics["macro_f1"]
            self.best_step = state.global_step
            if self.best_dir.exists():
                shutil.rmtree(self.best_dir)
            self.best_dir.mkdir(parents=True, exist_ok=True)
            model.save_pretrained(self.best_dir)
            self.processor.save_pretrained(self.best_dir)
            metadata = {
                "global_step": state.global_step,
                "selection_rule": "maximize refer_recall, tie-break macro_f1, require min_macro_f1",
                "min_macro_f1": self.min_macro_f1,
                "metrics": metrics,
            }
            (self.best_dir / "clinical_metrics.json").write_text(
                json.dumps(metadata, indent=2),
                encoding="utf-8",
            )
            print("Saved best clinical adapter to:", self.best_dir)
            if self.wandb_run is not None:
                self.wandb_run.summary["clinical_best/global_step"] = state.global_step
                self.wandb_run.summary["clinical_best/refer_recall"] = metrics["refer_recall"]
                self.wandb_run.summary["clinical_best/macro_f1"] = metrics["macro_f1"]
                self.wandb_run.summary["clinical_best/adapter_dir"] = str(self.best_dir)

        gc.collect()
        if torch.cuda.is_available():
            torch.cuda.empty_cache()


def make_sft_config(args):
    kwargs = {
        "output_dir": args.output_dir,
        "per_device_train_batch_size": args.batch_size,
        "gradient_accumulation_steps": args.grad_accum,
        "learning_rate": args.lr,
        "warmup_ratio": 0.03,
        "max_grad_norm": 0.3,
        "logging_steps": 1,
        "save_strategy": "steps",
        "save_steps": args.save_steps,
        "save_total_limit": 2,
        "optim": "adamw_8bit",
        "weight_decay": 0.001,
        "lr_scheduler_type": "cosine",
        "seed": SEED,
        "report_to": "wandb" if is_wandb_enabled(args) else "none",
        "run_name": args.wandb_run_name or default_run_name(args),
        "remove_unused_columns": False,
        "dataset_text_field": "",
        "dataset_kwargs": {"skip_prepare_dataset": True},
        "eval_steps": args.eval_steps,
    }

    parameters = inspect.signature(SFTConfig).parameters
    if args.max_steps is not None:
        kwargs["max_steps"] = args.max_steps
    else:
        kwargs["num_train_epochs"] = args.epochs

    if "max_length" in parameters:
        kwargs["max_length"] = args.max_length
    elif "max_seq_length" in parameters:
        kwargs["max_seq_length"] = args.max_length

    if "eval_strategy" in parameters:
        kwargs["eval_strategy"] = "steps"
    elif "evaluation_strategy" in parameters:
        kwargs["evaluation_strategy"] = "steps"

    if should_load_best_model(args):
        kwargs["load_best_model_at_end"] = True
        kwargs["metric_for_best_model"] = "eval_loss"
        kwargs["greater_is_better"] = False

    return SFTConfig(**kwargs)


def main():
    args = parse_args()
    model_name = resolve_model_name(args.model_dir, args.hub_model, args.allow_hub_fallback)
    paths = validate_data_dir(args.data_dir)
    validate_output_dir(args)

    print("=" * 80)
    print("Gemma 4 E2B Vision QLoRA Fine-tuning")
    print("Task: oral lesion crop -> safe binary screening JSON")
    print("=" * 80)

    print("Working directory:", Path.cwd())
    print("Package directory:", BASE_DIR)
    print("Model:", model_name)
    print("Chat template:", args.chat_template)
    print("Data directory:", args.data_dir)
    print("Output directory:", args.output_dir)
    print("Effective batch size:", args.batch_size * args.grad_accum)
    print("W&B enabled:", is_wandb_enabled(args))
    if is_wandb_enabled(args):
        print("W&B project:", args.wandb_project)
        print("W&B run name:", args.wandb_run_name or default_run_name(args))
        print("W&B watch:", args.wandb_watch)
        print("W&B log model:", args.wandb_log_model)
    print("Load best eval-loss checkpoint:", should_load_best_model(args))
    print("Early stopping enabled:", is_early_stopping_enabled(args))
    if is_early_stopping_enabled(args):
        print("Early stopping patience:", args.early_stopping_patience)
        print("Early stopping threshold:", args.early_stopping_threshold)
    print("Clinical validation enabled:", is_clinical_eval_enabled(args))
    if is_clinical_eval_enabled(args):
        print("Clinical validation steps:", args.clinical_eval_steps)
        print("Clinical validation max samples:", args.clinical_eval_max_samples)
        print("Clinical minimum macro-F1:", args.clinical_min_macro_f1)
    print("CUDA available:", torch.cuda.is_available())
    if torch.cuda.is_available():
        print("GPU count:", torch.cuda.device_count())
        print("GPU:", torch.cuda.get_device_name(0))

    train_rows = load_jsonl(paths["train"])
    val_rows = load_jsonl(paths["val"])
    test_rows = load_jsonl(paths["test"])

    train_counts = validate_rows(train_rows, "TRAIN")
    val_counts = validate_rows(val_rows, "VAL")
    test_counts = validate_rows(test_rows, "TEST")

    wandb_run = setup_wandb(
        args,
        model_name,
        split_sizes={
            "train": len(train_rows),
            "val": len(val_rows),
            "test": len(test_rows),
        },
        category_counts={
            "train": train_counts,
            "val": val_counts,
            "test": test_counts,
        },
    )

    print("\nConverting to Unsloth vision conversation format...")
    converted_train_dataset = [convert_to_conversation(row) for row in train_rows]
    converted_val_dataset = [convert_to_conversation(row) for row in val_rows]
    print("Converted train:", len(converted_train_dataset))
    print("Converted val:", len(converted_val_dataset))

    print("\nLoading Gemma 4 E2B Vision...")
    model, processor = FastVisionModel.from_pretrained(
        model_name,
        load_in_4bit=True,
        use_gradient_checkpointing="unsloth",
    )

    print("\nAdding QLoRA adapters...")
    model = FastVisionModel.get_peft_model(
        model,
        finetune_vision_layers=args.finetune_vision_layers,
        finetune_language_layers=True,
        finetune_attention_modules=True,
        finetune_mlp_modules=True,
        r=LORA_R,
        lora_alpha=LORA_ALPHA,
        lora_dropout=LORA_DROPOUT,
        bias="none",
        random_state=SEED,
        use_rslora=False,
        loftq_config=None,
        target_modules="all-linear",
    )
    trainable_params, total_params, trainable_percent = count_parameters(model)
    print(
        f"Trainable parameters: {trainable_params:,} of {total_params:,} "
        f"({trainable_percent:.2f}% trained)"
    )
    log_wandb_summary(
        wandb_run,
        {
            "parameters/trainable": trainable_params,
            "parameters/total": total_params,
            "parameters/trainable_percent": trainable_percent,
        },
    )

    print("\nApplying Gemma 4 chat template...")
    processor = get_chat_template(
        processor,
        args.chat_template,
    )

    if hasattr(processor, "image_processor"):
        if hasattr(processor.image_processor, "size"):
            processor.image_processor.size = {"height": 224, "width": 224}
        if hasattr(processor.image_processor, "crop_size"):
            processor.image_processor.crop_size = {"height": 224, "width": 224}

    print("Image processor:", getattr(processor, "image_processor", None))

    args.output_dir.mkdir(parents=True, exist_ok=True)

    if torch.cuda.is_available():
        torch.cuda.reset_peak_memory_stats()
        print("\nGPU memory before trainer:")
        print(f"Allocated: {torch.cuda.memory_allocated() / 1024**3:.2f} GB")
        print(f"Reserved:  {torch.cuda.memory_reserved() / 1024**3:.2f} GB")

    print("\nCreating SFTTrainer...")
    trainer = SFTTrainer(
        model=model,
        train_dataset=converted_train_dataset,
        eval_dataset=converted_val_dataset,
        processing_class=processor.tokenizer,
        data_collator=UnslothVisionDataCollator(model, processor),
        args=make_sft_config(args),
    )
    trainer.add_callback(GpuMemoryCallback())
    if is_early_stopping_enabled(args):
        trainer.add_callback(
            EarlyStoppingCallback(
                early_stopping_patience=args.early_stopping_patience,
                early_stopping_threshold=args.early_stopping_threshold,
            )
        )
    if is_clinical_eval_enabled(args):
        trainer.add_callback(
            ClinicalValidationCallback(
                processor=processor,
                rows=val_rows,
                output_dir=args.output_dir,
                eval_steps=args.clinical_eval_steps,
                max_samples=args.clinical_eval_max_samples,
                max_new_tokens=args.clinical_max_new_tokens,
                min_macro_f1=args.clinical_min_macro_f1,
                wandb_run=wandb_run,
            )
        )

    print("\nStarting training...")
    trainer_stats = trainer.train()

    print("\nTraining finished.")
    print(trainer_stats)
    if hasattr(trainer_stats, "metrics"):
        log_wandb_summary(
            wandb_run,
            {f"final/{key}": value for key, value in trainer_stats.metrics.items()},
        )

    print("\nSaving LoRA adapter and processor...")
    model.save_pretrained(args.output_dir)
    processor.save_pretrained(args.output_dir)

    print("Saved LoRA adapter to:", args.output_dir)

    if torch.cuda.is_available():
        peak_reserved_gb = torch.cuda.max_memory_reserved() / 1024**3
        allocated_gb = torch.cuda.memory_allocated() / 1024**3
        reserved_gb = torch.cuda.memory_reserved() / 1024**3
        print("\nGPU memory after training:")
        print(f"Peak reserved: {peak_reserved_gb:.2f} GB")
        print(f"Allocated:     {allocated_gb:.2f} GB")
        print(f"Reserved:      {reserved_gb:.2f} GB")
        log_wandb_summary(
            wandb_run,
            {
                "gpu/final_peak_reserved_gb": peak_reserved_gb,
                "gpu/final_allocated_gb": allocated_gb,
                "gpu/final_reserved_gb": reserved_gb,
            },
        )

    if wandb_run is not None:
        wandb_run.finish()

    print("\nDONE.")


if __name__ == "__main__":
    main()
