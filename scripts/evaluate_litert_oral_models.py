#!/usr/bin/env python3
"""Evaluate LiteRT-LM oral screening models on local image samples."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import subprocess
import sys
from pathlib import Path


PROMPT = (
    "You are an oral screening assistant. Analyze this cropped oral mucosal "
    "image. Return JSON with: category, recommendation, brief_reason, "
    "disclaimer. Categories: low_risk_or_variation or "
    "refer_for_clinical_review. Do not diagnose."
)

PROMPTS = {
    "training": PROMPT,
    "conservative": (
        "You are an oral screening assistant for cancer risk screening. Analyze "
        "this cropped oral mucosal image. If there is any visible ulcer, white "
        "patch, red patch, pigmentation, irregular texture, raised area, or if "
        "the image is uncertain, choose refer_for_clinical_review. Return valid "
        "JSON only with keys category, recommendation, brief_reason, disclaimer. "
        "Categories: low_risk_or_variation or refer_for_clinical_review. Do not "
        "diagnose."
    ),
    "forced_choice": (
        "Look at this cropped oral mucosal image. Choose exactly one category: "
        "refer_for_clinical_review if suspicious or uncertain, otherwise "
        "low_risk_or_variation. Return JSON only: {\"category\":\"...\","
        "\"recommendation\":\"...\",\"brief_reason\":\"...\",\"disclaimer\":\"...\"}."
    ),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--model",
        action="append",
        required=True,
        help="LiteRT-LM model path. Repeat to compare multiple models.",
    )
    parser.add_argument(
        "--image-root",
        default="oral_gemma_finetune_package/images/val",
        help="Directory containing evaluation images.",
    )
    parser.add_argument("--per-class", type=int, default=8)
    parser.add_argument("--max-num-tokens", type=int, default=256)
    parser.add_argument("--timeout-seconds", type=int, default=180)
    parser.add_argument(
        "--prompt-mode",
        choices=sorted(PROMPTS),
        default="training",
        help="Prompt template used for all samples.",
    )
    parser.add_argument(
        "--out-dir",
        default="oral_gemma_finetune_package/outputs/litert_eval",
        help="Output directory. A timestamped subdirectory is always created.",
    )
    parser.add_argument(
        "--litert-lm",
        default=".venv/bin/litert-lm",
        help="Path to litert-lm CLI.",
    )
    return parser.parse_args()


def collect_images(root: Path, per_class: int) -> list[tuple[Path, str]]:
    samples: list[tuple[Path, str]] = []
    for prefix, label in (
        ("opmd_", "refer_for_clinical_review"),
        ("variation_from_normal_", "low_risk_or_variation"),
    ):
        paths = sorted(root.glob(f"{prefix}*.jpg"))[:per_class]
        samples.extend((path, label) for path in paths)
    if not samples:
        raise FileNotFoundError(f"No evaluation images found in {root}")
    return samples


def extract_prediction(text: str) -> str:
    match = re.search(
        r'"category"\s*:\s*"(low_risk_or_variation|refer_for_clinical_review)"',
        text,
    )
    if match:
        return match.group(1)
    for label in ("refer_for_clinical_review", "low_risk_or_variation"):
        if label in text:
            return label
    return "unparsed"


def run_one(
    litert_lm: str,
    model: Path,
    image: Path,
    max_num_tokens: int,
    timeout_seconds: int,
    prompt: str,
) -> tuple[str, str]:
    command = [
        litert_lm,
        "run",
        str(model),
        "--attachment",
        str(image),
        "--prompt",
        prompt,
        "--backend",
        "cpu",
        "--vision-backend",
        "cpu",
        "--enable-speculative-decoding",
        "false",
        "--max-num-tokens",
        str(max_num_tokens),
        "--temperature",
        "0",
    ]
    completed = subprocess.run(
        command,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout_seconds,
    )
    output = completed.stdout.strip()
    if completed.returncode != 0:
        output = (output + "\n" + completed.stderr.strip()).strip()
    return extract_prediction(output), output


def summarize(rows: list[dict[str, str]]) -> dict[str, object]:
    labels = ("refer_for_clinical_review", "low_risk_or_variation")
    summary: dict[str, object] = {"total": len(rows)}
    correct = sum(row["gold"] == row["predicted"] for row in rows)
    summary["accuracy"] = correct / len(rows) if rows else 0.0
    for label in labels:
        class_rows = [row for row in rows if row["gold"] == label]
        true_positive = sum(row["predicted"] == label for row in class_rows)
        summary[f"recall_{label}"] = (
            true_positive / len(class_rows) if class_rows else 0.0
        )
    summary["unparsed"] = sum(row["predicted"] == "unparsed" for row in rows)
    return summary


def main() -> None:
    args = parse_args()
    timestamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    out_dir = Path(args.out_dir) / timestamp
    out_dir.mkdir(parents=True, exist_ok=False)

    samples = collect_images(Path(args.image_root), args.per_class)
    prompt = PROMPTS[args.prompt_mode]
    all_summaries = []

    for model_arg in args.model:
        model = Path(model_arg)
        safe_name = model.name.replace(".litertlm", "")
        rows = []
        print(f"[eval] model={model}")
        for index, (image, gold) in enumerate(samples, start=1):
            predicted, output = run_one(
                args.litert_lm,
                model,
                image,
                args.max_num_tokens,
                args.timeout_seconds,
                prompt,
            )
            row = {
                "index": str(index),
                "model": str(model),
                "image": str(image),
                "gold": gold,
                "predicted": predicted,
                "prompt_mode": args.prompt_mode,
                "output": output,
            }
            rows.append(row)
            print(f"[eval] {index}/{len(samples)} gold={gold} pred={predicted}")

        jsonl_path = out_dir / f"{safe_name}.jsonl"
        with jsonl_path.open("w", encoding="utf-8") as handle:
            for row in rows:
                handle.write(json.dumps(row, ensure_ascii=False) + "\n")

        summary = summarize(rows)
        summary["model"] = str(model)
        summary["rows_path"] = str(jsonl_path)
        all_summaries.append(summary)

    summary_path = out_dir / "summary.json"
    summary_path.write_text(json.dumps(all_summaries, indent=2) + "\n")
    print(f"[done] summary={summary_path}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
