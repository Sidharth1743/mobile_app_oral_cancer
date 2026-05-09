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
"""Metadata builder for Gemma4 multimodal LiteRT-LM bundles."""

from litert_torch.generative.export_hf.core import export_lib
from litert_torch.generative.export_hf.core import exportable_module

from ai_edge_litert.internal import llm_metadata_pb2
from ai_edge_litert.internal import llm_model_type_pb2


def build_llm_metadata(
    source_model_artifacts: export_lib.SourceModelArtifacts,
    export_config: exportable_module.ExportableModuleConfig,
    exported_model_artifacts: export_lib.ExportedModelArtifacts,
    llm_metadata: llm_metadata_pb2.LlmMetadata,
) -> llm_metadata_pb2.LlmMetadata:
  """Builds Gemma4 LLM metadata."""
  if export_config.task != 'image_text_to_text':
    return llm_metadata
  if not export_config.export_vision_encoder:
    return llm_metadata
  if not exported_model_artifacts.vision_encoder_model_path:
    return llm_metadata

  tokenizer = source_model_artifacts.tokenizer
  model_config = source_model_artifacts.model_config
  token_map = tokenizer.special_tokens_map

  llm_metadata.llm_model_type.CopyFrom(
      llm_model_type_pb2.LlmModelType(gemma4=llm_model_type_pb2.Gemma4())
  )
  gemma4 = llm_metadata.llm_model_type.gemma4
  gemma4.start_of_image_token.token_str = token_map.get('boi_token', '<|image>')
  gemma4.end_of_image_token.token_str = token_map.get('eoi_token', '<image|>')
  gemma4.patch_width = model_config.vision_config.patch_size
  gemma4.patch_height = model_config.vision_config.patch_size
  gemma4.pooling_kernel_size = model_config.vision_config.pooling_kernel_size
  # The runtime uses this value to choose the resize target and then writes the
  # actual patch count into the fixed-capacity 2520-patch encoder buffers.
  gemma4.max_num_patches = 2520
  if token_map.get('boa_token'):
    gemma4.start_of_audio_token.token_str = token_map['boa_token']
  if token_map.get('eoa_token'):
    gemma4.end_of_audio_token.token_str = token_map['eoa_token']
  return llm_metadata
