import argparse
import json
import os
import re
from collections import Counter
from pathlib import Path

os.environ["UNSLOTH_COMPILE_DISABLE"] = "1"
os.environ["PYTORCH_ALLOC_CONF"] = "expandable_segments:True"

import torch
from PIL import Image
from unsloth import FastVisionModel, get_chat_template


BASE_DIR = Path(__file__).resolve().parent
OUTPUT_ROOT = BASE_DIR / "outputs"
DEFAULT_BASE_MODEL_DIR = BASE_DIR / "model" / "gemma-unsloth-e2b"
DEFAULT_DATA_DIR = BASE_DIR / "data"
CATEGORIES = ("low_risk_or_variation", "refer_for_clinical_review")


def parse_args():
    parser = argparse.ArgumentParser(
        description="Benchmark the fine-tuned Gemma 4 E2B LoRA adapter on a JSONL split."
    )
    parser.add_argument(
        "--adapter-dir",
        type=Path,
        default=None,
        help="LoRA adapter directory. Defaults to the newest adapter under ./outputs unless --base-model is set.",
    )
    parser.add_argument(
        "--base-model",
        action="store_true",
        help="Benchmark the non-fine-tuned base model instead of a LoRA adapter.",
    )
    parser.add_argument(
        "--base-model-dir",
        type=Path,
        default=DEFAULT_BASE_MODEL_DIR,
        help="Local non-fine-tuned model directory for --base-model.",
    )
    parser.add_argument(
        "--data-dir",
        type=Path,
        default=DEFAULT_DATA_DIR,
        help="Directory containing train.jsonl, val.jsonl, and test.jsonl.",
    )
    parser.add_argument(
        "--split",
        action="append",
        choices=("train", "val", "test"),
        help="Dataset split to benchmark. Can be passed multiple times. Defaults to test.",
    )
    parser.add_argument(
        "--all-splits",
        action="store_true",
        help="Benchmark train, val, and test.",
    )
    parser.add_argument(
        "--split-path",
        type=Path,
        default=None,
        help="Custom JSONL split path. Cannot be combined with --split or --all-splits.",
    )
    parser.add_argument(
        "--predictions-path",
        type=Path,
        default=None,
        help="Where to write predictions. Defaults to outputs/predictions/<adapter-name>_<split>.jsonl.",
    )
    parser.add_argument("--chat-template", default="gemma-4", choices=("gemma-4", "gemma-4-thinking"))
    parser.add_argument("--max-new-tokens", type=int, default=256)
    parser.add_argument("--limit", type=int, default=None, help="Optional quick benchmark row limit.")
    return parser.parse_args()


def load_jsonl(path):
    with Path(path).open("r", encoding="utf-8") as f:
        return [json.loads(line) for line in f]


def find_latest_adapter_dir():
    if not OUTPUT_ROOT.exists():
        raise FileNotFoundError(
            "outputs/ does not exist yet. Train first or pass --adapter-dir explicitly."
        )

    candidates = [
        path.parent
        for path in OUTPUT_ROOT.rglob("adapter_config.json")
        if path.is_file()
    ]
    if not candidates:
        raise FileNotFoundError(
            "No LoRA adapter directory found under outputs/. Pass --adapter-dir explicitly."
        )
    return max(candidates, key=lambda path: (path / "adapter_config.json").stat().st_mtime)


def default_predictions_path(adapter_dir, split_name):
    adapter_name = adapter_dir.name
    if adapter_dir == DEFAULT_BASE_MODEL_DIR:
        adapter_name = "base_model"
    elif adapter_name.startswith("checkpoint-") and adapter_dir.parent != OUTPUT_ROOT:
        adapter_name = f"{adapter_dir.parent.name}_{adapter_name}"

    return OUTPUT_ROOT / "predictions" / f"{adapter_name}_{split_name}_predictions.jsonl"


def resolve_image_path(raw_path):
    img_path = Path(raw_path)
    if img_path.is_absolute() and img_path.exists():
        return img_path

    package_relative = BASE_DIR / img_path
    if package_relative.exists():
        return package_relative

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


def generate_prediction(model, processor, row, max_new_tokens):
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
    inputs = processor(
        image,
        input_text,
        add_special_tokens=False,
        return_tensors="pt",
    ).to("cuda")

    with torch.inference_mode():
        generated = model.generate(
            **inputs,
            max_new_tokens=max_new_tokens,
            use_cache=True,
            do_sample=False,
        )

    prompt_length = inputs["input_ids"].shape[-1]
    output_ids = generated[0][prompt_length:]
    return processor.tokenizer.decode(output_ids, skip_special_tokens=True).strip()


def safe_divide(numerator, denominator):
    return numerator / denominator if denominator else 0.0


def compute_metrics(gold_labels, predicted_labels):
    total = len(gold_labels)
    correct = sum(gold == pred for gold, pred in zip(gold_labels, predicted_labels))
    metrics = {
        "total": total,
        "accuracy": safe_divide(correct, total),
        "unparsed": sum(pred is None for pred in predicted_labels),
        "per_class": {},
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
        metrics["per_class"][category] = {
            "precision": precision,
            "recall": recall,
            "f1": f1,
            "support": sum(gold == category for gold in gold_labels),
        }

    metrics["macro_f1"] = sum(f1_values) / len(f1_values)
    metrics["confusion"] = {
        gold: {pred: 0 for pred in (*CATEGORIES, "unparsed")}
        for gold in CATEGORIES
    }
    for gold, pred in zip(gold_labels, predicted_labels):
        metrics["confusion"][gold][pred or "unparsed"] += 1

    return metrics


def resolve_splits(args):
    if args.split_path is not None and (args.split or args.all_splits):
        raise ValueError("--split-path cannot be combined with --split or --all-splits.")

    if args.split_path is not None:
        return [(args.split_path.stem, args.split_path)]

    if args.all_splits:
        split_names = ("train", "val", "test")
    else:
        split_names = args.split or ["test"]

    paths = {
        "train": args.data_dir / "train.jsonl",
        "val": args.data_dir / "val.jsonl",
        "test": args.data_dir / "test.jsonl",
    }
    missing = [str(paths[split_name]) for split_name in split_names if not paths[split_name].exists()]
    if missing:
        raise FileNotFoundError(f"Missing split file(s): {missing}")

    return [(split_name, paths[split_name]) for split_name in split_names]


def benchmark_split(model, processor, args, split_name, split_path, model_dir, model_label, split_count):
    predictions_path = args.predictions_path
    if predictions_path is None:
        predictions_path = default_predictions_path(model_dir, split_name)
    elif split_count > 1:
        predictions_path = predictions_path.with_name(
            f"{predictions_path.stem}_{split_name}{predictions_path.suffix}"
        )

    rows = load_jsonl(split_path)
    if args.limit is not None:
        rows = rows[:args.limit]

    print("\n" + "=" * 80)
    print(f"{model_label}:", model_dir)
    print("Split:", split_name, split_path)
    print("Rows:", len(rows))
    print("Gold distribution:", Counter(row["metadata"]["binary_category"] for row in rows))

    predictions_path.parent.mkdir(parents=True, exist_ok=True)
    gold_labels = []
    predicted_labels = []

    with predictions_path.open("w", encoding="utf-8") as f:
        for index, row in enumerate(rows, start=1):
            gold = row["metadata"]["binary_category"]
            generated_text = generate_prediction(model, processor, row, args.max_new_tokens)
            predicted = parse_category(generated_text)

            gold_labels.append(gold)
            predicted_labels.append(predicted)

            record = {
                "split": split_name,
                "index": index,
                "image": row["image"],
                "gold": gold,
                "predicted": predicted,
                "generated_text": generated_text,
            }
            f.write(json.dumps(record, ensure_ascii=False) + "\n")

            print(f"[{index}/{len(rows)}] gold={gold} predicted={predicted}")

    metrics = compute_metrics(gold_labels, predicted_labels)
    print(f"\nBenchmark metrics ({split_name})")
    print(json.dumps(metrics, indent=2))
    print("\nPredictions saved to:", predictions_path)
    return split_name, metrics


def main():
    args = parse_args()

    if args.base_model:
        model_dir = args.base_model_dir
        model_label = "Base model"
    elif args.adapter_dir is None:
        args.adapter_dir = find_latest_adapter_dir()
        model_dir = args.adapter_dir
        model_label = "Adapter"
    else:
        model_dir = args.adapter_dir
        model_label = "Adapter"

    splits = resolve_splits(args)

    model, processor = FastVisionModel.from_pretrained(
        model_name=str(model_dir),
        load_in_4bit=True,
        use_gradient_checkpointing="unsloth",
    )
    processor = get_chat_template(processor, args.chat_template)
    FastVisionModel.for_inference(model)

    all_metrics = {}
    for split_name, split_path in splits:
        split_name, metrics = benchmark_split(
            model,
            processor,
            args,
            split_name,
            split_path,
            model_dir,
            model_label,
            len(splits),
        )
        all_metrics[split_name] = metrics

    if len(all_metrics) > 1:
        print("\n" + "=" * 80)
        print("Benchmark summary")
        print(json.dumps(all_metrics, indent=2))


if __name__ == "__main__":
    main()
