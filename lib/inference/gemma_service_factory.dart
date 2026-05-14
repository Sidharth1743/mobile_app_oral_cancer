import 'dart:io';

import 'package:flutter/foundation.dart';

import 'gemma_service.dart';
import 'litert_gemma_service.dart';
import 'pc_litert_helper_service.dart';

class GemmaServiceFactory {
  const GemmaServiceFactory._();

  static const _desktopHelperUrl = String.fromEnvironment(
    'PC_LITERT_HELPER_URL',
    defaultValue: 'http://127.0.0.1:8010',
  );

  static GemmaService create({
    required String modelPath,
    String backend = 'gpu',
  }) {
    if (!kIsWeb && Platform.isAndroid) {
      return LiteRtGemmaService(modelPath: modelPath, backend: backend);
    }
    return PcLiteRtHelperService(
      modelPath: modelPath,
      backend: backend == 'gpu' ? 'cpu' : backend,
      baseUrl: _desktopHelperUrl,
    );
  }
}
