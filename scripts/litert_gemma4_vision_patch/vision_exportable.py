# Copyright 2026 The LiteRT Torch Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ==============================================================================
"""Exportable modules for Gemma4 vision encoder and adapter.

This is an experimental local patch for public litert-torch builds that export
Gemma4 text components but do not yet register Gemma4 vision exportables.
"""

from litert_torch.generative.export_hf.core import exportable_module as exportable_module_base
import torch


class LiteRTExportableModuleForGemma4VisionEncoder(
    exportable_module_base.ExportableModuleBase
):
  """Exportable module for Gemma4 vision encoder."""

  def __init__(self, model: torch.nn.Module, export_config):
    super().__init__(export_config)
    self.model = model
    self.soft_tokens_per_image = 256

  def forward(
      self,
      images,
    positions_xy,
  ):
    vision_tower = self.model.model.vision_tower
    padding_positions = positions_xy[..., 0] < 0
    inputs_embeds = vision_tower.patch_embedder(
        images,
        positions_xy,
        padding_positions,
    )
    encoder_output = vision_tower.encoder(
        inputs_embeds=inputs_embeds,
        attention_mask=~padding_positions,
        pixel_position_ids=positions_xy,
    )
    output_length = images.shape[1] // (
        vision_tower.config.pooling_kernel_size
        * vision_tower.config.pooling_kernel_size
    )
    hidden_states, pooler_mask = vision_tower.pooler(
        hidden_states=encoder_output.last_hidden_state,
        pixel_position_ids=positions_xy,
        padding_positions=padding_positions,
        output_length=output_length,
    )
    return {
        'features': hidden_states[:, : self.soft_tokens_per_image, :].clone(),
        'mask': pooler_mask[:, : self.soft_tokens_per_image].clone(),
    }

  def get_sample_inputs(
      self, model_config, **kwargs
  ) -> dict[str, tuple[dict[str, torch.Tensor], dict[str, torch.export.Dim]]]:
    """Returns sample inputs for the model."""
    image_processor = kwargs.get('image_processor', None)
    if image_processor is None:
      raise ValueError(
          'Image processor is required for exporting Gemma4 vision encoder.'
      )
    max_soft_tokens = getattr(
        image_processor,
        'max_soft_tokens',
        model_config.vision_config.default_output_length,
    )
    del max_soft_tokens
    max_patches = 2520
    self.soft_tokens_per_image = (
        max_patches // model_config.vision_config.pooling_kernel_size**2
    )
    inputs = {
        'images': torch.zeros(
            (
                1,
                max_patches,
                model_config.vision_config.patch_size
                * model_config.vision_config.patch_size
                * 3,
            ),
            dtype=torch.float32,
        ),
        'positions_xy': torch.zeros((1, max_patches, 2), dtype=torch.int64),
    }
    return {f'vision_{max_patches}': (inputs, {})}


class LiteRTExportableModuleForGemma4VisionAdapter(
    exportable_module_base.ExportableModuleBase
):
  """Exportable module for Gemma4 vision adapter."""

  def __init__(self, model: torch.nn.Module, export_config, tokenizer):
    super().__init__(export_config)
    self.model = model
    self.tokenizer = tokenizer

  def forward(
      self,
      features,
  ):
    image_features = self.model.model.embed_vision(inputs_embeds=features)
    eoi = self.tokenizer.encode(
        self.tokenizer.special_tokens_map['eoi_token'],
        add_special_tokens=False,
    )
    eoi_emb = self.model.get_input_embeddings()(torch.tensor(eoi)[None, :])
    return {'mm_embedding': torch.concat([image_features, eoi_emb], axis=1)}

  def get_sample_inputs(
      self, model_config, **kwargs
  ) -> dict[str, tuple[dict[str, torch.Tensor], dict[str, torch.export.Dim]]]:
    """Returns sample inputs for the model."""
    image_processor = kwargs.get('image_processor', None)
    if image_processor is None:
      raise ValueError(
          'Image processor is required for exporting Gemma4 vision adapter.'
      )
    del image_processor
    soft_tokens_per_image = (
        2520 // model_config.vision_config.pooling_kernel_size**2
    )
    inputs = {
        'features': torch.zeros(
            (
                1,
                soft_tokens_per_image,
                model_config.vision_config.hidden_size,
            ),
            dtype=torch.float32,
        )
    }
    return {'vision_adapter': (inputs, {})}
