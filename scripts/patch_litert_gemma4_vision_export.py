#!/usr/bin/env python3
"""Apply a local Gemma4 vision export patch to the active litert-torch install."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import shutil


ROOT = Path(__file__).resolve().parents[1]
PATCH_DIR = ROOT / "scripts" / "litert_gemma4_vision_patch"


def package_root() -> Path:
    spec = importlib.util.find_spec("litert_torch")
    if spec is None or spec.origin is None:
        raise RuntimeError("litert_torch is not installed in this Python environment.")
    return Path(spec.origin).resolve().parent


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if new in text:
        return
    if old not in text:
        raise RuntimeError(f"Could not find expected text in {path}")
    path.write_text(text.replace(old, new, 1))


def main() -> None:
    root = package_root()
    model_ext = root / "generative" / "export_hf" / "model_ext"
    core = root / "generative" / "export_hf" / "core"
    site_packages = root.parent
    gemma4_dir = model_ext / "gemma4"

    shutil.copyfile(
        PATCH_DIR / "vision_exportable.py",
        gemma4_dir / "vision_exportable.py",
    )
    shutil.copyfile(
        PATCH_DIR / "metadata_builder.py",
        gemma4_dir / "metadata_builder.py",
    )

    exportables = model_ext / "exportables.py"
    replace_once(
        exportables,
        "from litert_torch.generative.export_hf.model_ext.gemma4 import exportable_module as gemma4_exportable\n",
        "from litert_torch.generative.export_hf.model_ext.gemma4 import exportable_module as gemma4_exportable\n"
        "from litert_torch.generative.export_hf.model_ext.gemma4 import vision_exportable as gemma4_vision_exportable\n",
    )
    replace_once(
        exportables,
        "  elif model_config.model_type == 'gemma3n':\n"
        "    return (\n"
        "        gemma3n_vision_exportable.LiteRTExportableModuleForGemma3nVisionEncoder,\n"
        "        gemma3n_vision_exportable.LiteRTExportableModuleForGemma3nVisionAdapter,\n"
        "    )\n"
        "  else:\n"
        "    raise ValueError(f'Unsupported model type: {model_config.model_type}')\n",
        "  elif model_config.model_type == 'gemma3n':\n"
        "    return (\n"
        "        gemma3n_vision_exportable.LiteRTExportableModuleForGemma3nVisionEncoder,\n"
        "        gemma3n_vision_exportable.LiteRTExportableModuleForGemma3nVisionAdapter,\n"
        "    )\n"
        "  elif model_config.model_type == 'gemma4':\n"
        "    return (\n"
        "        gemma4_vision_exportable.LiteRTExportableModuleForGemma4VisionEncoder,\n"
        "        gemma4_vision_exportable.LiteRTExportableModuleForGemma4VisionAdapter,\n"
        "    )\n"
        "  else:\n"
        "    raise ValueError(f'Unsupported model type: {model_config.model_type}')\n",
    )

    metadata = model_ext / "metadata_builder.py"
    replace_once(
        metadata,
        "from litert_torch.generative.export_hf.model_ext.gemma3 import metadata_builder as gemma3_metadata_builder\n",
        "from litert_torch.generative.export_hf.model_ext.gemma3 import metadata_builder as gemma3_metadata_builder\n"
        "from litert_torch.generative.export_hf.model_ext.gemma4 import metadata_builder as gemma4_metadata_builder\n",
    )
    replace_once(
        metadata,
        "  elif model_config.model_type == 'gemma4':\n"
        "    # TODO(weiyiw): Update Gemma4 metadata builder once builder is updated.\n"
        "    return gemma3_metadata_builder.build_llm_metadata\n",
        "  elif model_config.model_type == 'gemma4':\n"
        "    return gemma4_metadata_builder.build_llm_metadata\n",
    )

    export_lib = core / "export_lib.py"
    snippet_ns: dict[str, str] = {}
    exec((PATCH_DIR / "export_lib_none_quantization.py").read_text(), snippet_ns)
    replace_once(export_lib, snippet_ns["OLD"], snippet_ns["NEW"])
    replace_once(
        export_lib,
        "  sample_inputs = encode_module.get_sample_inputs(\n"
        "      model_config, image_processor=image_processor\n"
        "  )\n"
        "  for signature_name, (sample_inputs, _) in sample_inputs.items():\n"
        "    converter.add_signature(\n"
        "        signature_name,\n"
        "        encode_module.eval(),\n"
        "        sample_kwargs=sample_inputs,\n"
        "    )\n",
        "  sample_inputs = encode_module.get_sample_inputs(\n"
        "      model_config, image_processor=image_processor\n"
        "  )\n"
        "  for signature_name, (sample_inputs, dynamic_shapes) in sample_inputs.items():\n"
        "    if dynamic_shapes:\n"
        "      encoder_ep = torch.export.export(\n"
        "          encode_module.eval(),\n"
        "          args=(),\n"
        "          kwargs=sample_inputs,\n"
        "          dynamic_shapes=dynamic_shapes,\n"
        "      )\n"
        "      encoder_ep = fx_infra.safe_run_decompositions(\n"
        "          encoder_ep, fx_infra.decomp.pre_lower_decomp()\n"
        "      )\n"
        "      encoder_ep = encoder_ep.run_decompositions(torch_tfl.decomps)\n"
        "      converter.add_signature(\n"
        "          signature_name,\n"
        "          encoder_ep.module(),\n"
        "          sample_kwargs=sample_inputs,\n"
        "          dynamic_shapes=dynamic_shapes,\n"
        "      )\n"
        "    else:\n"
        "      converter.add_signature(\n"
        "          signature_name,\n"
        "          encode_module.eval(),\n"
        "          sample_kwargs=sample_inputs,\n"
        "      )\n",
    )
    replace_once(
        export_lib,
        "  sample_inputs = adapter_module.get_sample_inputs(\n"
        "      model_config, image_processor=image_processor\n"
        "  )\n"
        "  for signature_name, (sample_inputs, _) in sample_inputs.items():\n"
        "    converter.add_signature(\n"
        "        signature_name,\n"
        "        adapter_module.eval(),\n"
        "        sample_kwargs=sample_inputs,\n"
        "    )\n",
        "  sample_inputs = adapter_module.get_sample_inputs(\n"
        "      model_config, image_processor=image_processor\n"
        "  )\n"
        "  for signature_name, (sample_inputs, dynamic_shapes) in sample_inputs.items():\n"
        "    if dynamic_shapes:\n"
        "      adapter_ep = torch.export.export(\n"
        "          adapter_module.eval(),\n"
        "          args=(),\n"
        "          kwargs=sample_inputs,\n"
        "          dynamic_shapes=dynamic_shapes,\n"
        "      )\n"
        "      adapter_ep = fx_infra.safe_run_decompositions(\n"
        "          adapter_ep, fx_infra.decomp.pre_lower_decomp()\n"
        "      )\n"
        "      adapter_ep = adapter_ep.run_decompositions(torch_tfl.decomps)\n"
        "      converter.add_signature(\n"
        "          signature_name,\n"
        "          adapter_ep.module(),\n"
        "          sample_kwargs=sample_inputs,\n"
        "          dynamic_shapes=dynamic_shapes,\n"
        "      )\n"
        "    else:\n"
        "      converter.add_signature(\n"
        "          signature_name,\n"
        "          adapter_module.eval(),\n"
        "          sample_kwargs=sample_inputs,\n"
        "      )\n",
    )

    transformers_gemma4 = (
        site_packages
        / "transformers"
        / "models"
        / "gemma4"
        / "modeling_gemma4.py"
    )
    if transformers_gemma4.exists():
        replace_once(
            transformers_gemma4,
            "    if n_rep == 1:\n"
            "        return hidden_states\n",
            "    if n_rep == 1:\n"
            "        return hidden_states.clone()\n",
        )
        replace_once(
            transformers_gemma4,
            "        query_states = self.q_proj(hidden_states).view(hidden_shape)\n",
            "        query_states = self.q_proj(hidden_states).view(hidden_shape).clone()\n",
        )
        replace_once(
            transformers_gemma4,
            "        key_states = self.k_proj(hidden_states).view(hidden_shape)\n",
            "        key_states = self.k_proj(hidden_states).view(hidden_shape).clone()\n",
        )
        replace_once(
            transformers_gemma4,
            "        value_states = self.v_proj(hidden_states).view(hidden_shape)\n",
            "        value_states = self.v_proj(hidden_states).view(hidden_shape).clone()\n",
        )

    print(f"Patched litert_torch at {root}")


if __name__ == "__main__":
    main()
