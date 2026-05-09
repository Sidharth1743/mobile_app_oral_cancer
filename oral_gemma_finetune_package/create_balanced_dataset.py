import argparse
import json
import random
from collections import Counter
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent
SEED = 42
TARGET_CATEGORY = "refer_for_clinical_review"
OTHER_CATEGORY = "low_risk_or_variation"


def parse_args():
    parser = argparse.ArgumentParser(
        description="Create a balanced mixed oral Gemma training dataset from v1 and v2 JSONL files."
    )
    parser.add_argument("--v1-dir", type=Path, default=BASE_DIR / "data")
    parser.add_argument("--v2-dir", type=Path, default=BASE_DIR / "data_v2_describe")
    parser.add_argument("--output-dir", type=Path, default=BASE_DIR / "data_balanced_mix")
    parser.add_argument("--seed", type=int, default=SEED)
    parser.add_argument(
        "--val-source",
        choices=("v1", "v2"),
        default="v2",
        help="Which dataset version to use for validation split.",
    )
    parser.add_argument(
        "--test-source",
        choices=("v1", "v2"),
        default="v2",
        help="Which dataset version to use for test split.",
    )
    parser.add_argument(
        "--low-risk-ratio",
        type=float,
        default=1.0,
        help="Low-risk rows per referral row in train. 1.0 creates a balanced train split.",
    )
    return parser.parse_args()


def load_jsonl(path):
    with Path(path).open("r", encoding="utf-8") as f:
        return [json.loads(line) for line in f]


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with Path(path).open("w", encoding="utf-8") as f:
        for row in rows:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")


def category(row):
    return row["metadata"]["binary_category"]


def add_source_tag(rows, source):
    tagged = []
    for row in rows:
        row = dict(row)
        metadata = dict(row["metadata"])
        metadata["dataset_version"] = source
        row["metadata"] = metadata
        tagged.append(row)
    return tagged


def build_balanced_train(v1_dir, v2_dir, low_risk_ratio, seed):
    rng = random.Random(seed)
    v1_rows = add_source_tag(load_jsonl(v1_dir / "train.jsonl"), "v1")
    v2_rows = add_source_tag(load_jsonl(v2_dir / "train.jsonl"), "v2_describe")
    rows = v1_rows + v2_rows

    refer_rows = [row for row in rows if category(row) == TARGET_CATEGORY]
    low_rows = [row for row in rows if category(row) == OTHER_CATEGORY]

    target_low_count = round(len(refer_rows) * low_risk_ratio)
    if target_low_count <= len(low_rows):
        selected_low_rows = rng.sample(low_rows, target_low_count)
    else:
        selected_low_rows = [rng.choice(low_rows) for _ in range(target_low_count)]

    train_rows = refer_rows + selected_low_rows
    rng.shuffle(train_rows)
    return train_rows


def copy_split(source_dir, split, source_name):
    return add_source_tag(load_jsonl(source_dir / f"{split}.jsonl"), source_name)


def summarize(name, rows):
    print(name, len(rows), Counter(category(row) for row in rows), Counter(row["metadata"].get("dataset_version") for row in rows))


def main():
    args = parse_args()
    source_dirs = {
        "v1": args.v1_dir,
        "v2": args.v2_dir,
    }

    train_rows = build_balanced_train(args.v1_dir, args.v2_dir, args.low_risk_ratio, args.seed)
    val_rows = copy_split(source_dirs[args.val_source], "val", args.val_source)
    test_rows = copy_split(source_dirs[args.test_source], "test", args.test_source)

    write_jsonl(args.output_dir / "train.jsonl", train_rows)
    write_jsonl(args.output_dir / "val.jsonl", val_rows)
    write_jsonl(args.output_dir / "test.jsonl", test_rows)

    summarize("train", train_rows)
    summarize("val", val_rows)
    summarize("test", test_rows)
    print("Wrote:", args.output_dir)


if __name__ == "__main__":
    main()
