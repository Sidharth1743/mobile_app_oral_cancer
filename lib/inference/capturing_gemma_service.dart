import 'package:flutter/foundation.dart';

import '../debug/raw_model_output_capture.dart';
import 'gemma_service.dart';

/// Debug wrapper that persists every Gemma response for adb pull to a dev PC.
class CapturingGemmaService implements GemmaService, ReleasableGemmaService {
  CapturingGemmaService({
    required GemmaService inner,
    this.captureLabel = 'infer',
  }) : _inner = inner;

  final GemmaService _inner;
  final String captureLabel;
  static var _sequence = 0;

  @override
  Future<GemmaRawResponse> infer(GemmaRequest request) async {
    final label = '$captureLabel-${++_sequence}';
    final response = await _inner.infer(request);
    if (kDebugMode) {
      await RawModelOutputCapture.recordInference(
        label: label,
        prompt: request.prompt,
        imagePaths: request.imagePaths,
        rawText: response.text,
        modelName: response.modelName,
        elapsed: response.elapsed,
      );
    }
    return response;
  }

  @override
  Future<void> close() async {
    final inner = _inner;
    if (inner is ReleasableGemmaService) {
      await (inner as ReleasableGemmaService).close();
    }
  }
}
