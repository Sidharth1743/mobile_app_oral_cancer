import json
import tempfile
import unittest
from pathlib import Path

from backend.core import (
    BackendConfig,
    inspect_model_files,
    model_files_ready,
    parse_model_json,
    validate_upload,
)


class BackendCoreTest(unittest.TestCase):
    def test_parse_model_json_accepts_required_screening_response(self) -> None:
        parsed = parse_model_json(
            'prefix {"category":"refer_for_clinical_review",'
            '"recommendation":"Clinical review advised.",'
            '"brief_reason":"Irregular red-white patch.",'
            '"disclaimer":"Screening support only, not a diagnosis."} suffix'
        )

        self.assertEqual(parsed["category"], "refer_for_clinical_review")
        self.assertEqual(parsed["recommendation"], "Clinical review advised.")

    def test_parse_model_json_rejects_missing_fields(self) -> None:
        with self.assertRaises(ValueError):
            parse_model_json('{"category":"low_risk_or_variation"}')

    def test_parse_model_json_rejects_unknown_category(self) -> None:
        with self.assertRaises(ValueError):
            parse_model_json(
                json.dumps(
                    {
                        "category": "diagnosis",
                        "recommendation": "Bad output.",
                        "brief_reason": "Bad output.",
                        "disclaimer": "Bad output.",
                    }
                )
            )

    def test_validate_upload_rejects_non_image_and_oversized_file(self) -> None:
        with self.assertRaises(ValueError):
            validate_upload("application/pdf", 10, 100)
        with self.assertRaises(ValueError):
            validate_upload("image/jpeg", 101, 100)
        validate_upload("image/jpeg", 99, 100)

    def test_inspect_model_files_checks_adapter_and_base_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            adapter = root / "adapter"
            base = root / "base"
            adapter.mkdir()
            base.mkdir()
            (adapter / "adapter_config.json").write_text(
                json.dumps({"base_model_name_or_path": str(base)}),
                encoding="utf-8",
            )
            (adapter / "adapter_model.safetensors").write_bytes(b"adapter")
            (adapter / "tokenizer.json").write_text("{}", encoding="utf-8")
            (base / "config.json").write_text("{}", encoding="utf-8")
            (base / "model.safetensors").write_bytes(b"base")
            (base / "tokenizer.json").write_text("{}", encoding="utf-8")

            config = BackendConfig(
                adapter_dir=adapter,
                base_model_dir=root / "fallback-base",
                max_upload_bytes=10,
                max_new_tokens=8,
            )

            inspected = inspect_model_files(config)

            self.assertTrue(model_files_ready(config))
            self.assertEqual(inspected["base_model_dir"], str(base))
            self.assertTrue(inspected["files"]["adapter_model"]["exists"])


if __name__ == "__main__":
    unittest.main()
