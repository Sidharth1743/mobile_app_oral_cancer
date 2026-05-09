# Patch snippet used by scripts/patch_litert_gemma4_vision_export.py.

OLD = """def maybe_quantize_model(
    model_path: str,
    quantization_recipe: str | None = None,
):
  \"\"\"Quantizes model if recipe is provided.\"\"\"
  if not quantization_recipe:
    return model_path
  return quantize_model(model_path, quantization_recipe)
"""

NEW = """def maybe_quantize_model(
    model_path: str,
    quantization_recipe: str | None = None,
):
  \"\"\"Quantizes model if recipe is provided.\"\"\"
  if not quantization_recipe:
    return model_path
  if isinstance(quantization_recipe, str) and quantization_recipe.lower() in (
      'none',
      'no_quant',
      'no_quantization',
  ):
    return model_path
  return quantize_model(model_path, quantization_recipe)
"""
