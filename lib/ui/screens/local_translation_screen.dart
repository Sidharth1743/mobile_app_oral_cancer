import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../inference/gemma_service_factory.dart';
import '../../inference/mobile_model_paths.dart';
import '../../translation/local_translation_service.dart';
import '../components/section_panel.dart';

class LocalTranslationScreen extends StatefulWidget {
  const LocalTranslationScreen({super.key, required this.initialText});

  final String initialText;

  @override
  State<LocalTranslationScreen> createState() => _LocalTranslationScreenState();
}

class _LocalTranslationScreenState extends State<LocalTranslationScreen> {
  final _text = TextEditingController();
  String _language = 'Tamil';
  String? _modelPath;
  bool _resolvingModel = true;
  bool _busy = false;
  String? _error;
  TranslationResult? _result;

  @override
  void initState() {
    super.initState();
    _text.text = widget.initialText;
    _resolveModelPath();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _resolveModelPath() async {
    try {
      final path = !kIsWeb && Platform.isAndroid
          ? (await MobileModelPaths.resolveGemmaPath()).trim()
          : const String.fromEnvironment(
              'LITERT_MODEL_PATH',
              defaultValue:
                  '/home/sach/gemma/organized_artifacts/models/MAIN_ours_text_ours_vision/model.litertlm',
            );
      if (!mounted) {
        return;
      }
      if (!kIsWeb && Platform.isAndroid && !await File(path).exists()) {
        setState(() {
          _modelPath = path;
          _resolvingModel = false;
          _error =
              'Gemma model not found on device. Run ./scripts/push_model_to_phone.sh.';
        });
        return;
      }
      setState(() {
        _modelPath = path;
        _resolvingModel = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _resolvingModel = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _translate() async {
    final modelPath = _modelPath?.trim() ?? '';
    if (modelPath.isEmpty) {
      setState(() => _error = 'LiteRT model path is not ready yet.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      if (!kIsWeb && Platform.isAndroid && !await File(modelPath).exists()) {
        throw StateError(
          'Gemma model not found on device. Run ./scripts/push_model_to_phone.sh.',
        );
      }
      final service = LocalGemmaTranslationService(
        gemmaService: GemmaServiceFactory.create(
          modelPath: modelPath,
          backend: 'cpu',
        ),
      );
      final result = await service.translate(
        TranslationRequest(text: _text.text, targetLanguage: _language),
      );
      if (!mounted) {
        return;
      }
      setState(() => _result = result);
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = !_resolvingModel && (_modelPath?.isNotEmpty ?? false);
    return Scaffold(
      appBar: AppBar(title: const Text('Local translation')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionPanel(
            title: 'Translate on device',
            subtitle: 'Runs through the local LiteRT Gemma service.',
            children: [
              if (_resolvingModel)
                const LinearProgressIndicator()
              else if (_modelPath != null)
                Text(
                  'Model: ${_modelPath!.split('/').last}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _language,
                decoration: const InputDecoration(labelText: 'Language'),
                items: const [
                  DropdownMenuItem(value: 'Tamil', child: Text('Tamil')),
                  DropdownMenuItem(value: 'Hindi', child: Text('Hindi')),
                  DropdownMenuItem(value: 'Marathi', child: Text('Marathi')),
                  DropdownMenuItem(value: 'Telugu', child: Text('Telugu')),
                  DropdownMenuItem(value: 'English', child: Text('English')),
                  DropdownMenuItem(value: 'Kannada', child: Text('Kannada')),
                  DropdownMenuItem(
                    value: 'Malayalam',
                    child: Text('Malayalam'),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _language = value ?? _language),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _text,
                decoration: const InputDecoration(labelText: 'Text'),
                maxLines: 4,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy || !ready ? null : _translate,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.translate),
                  label: Text(_busy ? 'Translating' : 'Translate'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
          if (_result != null) ...[
            const SizedBox(height: 12),
            SectionPanel(
              title: _result!.targetLanguage,
              subtitle: _result!.modelName,
              children: [SelectableText(_result!.translatedText)],
            ),
          ],
        ],
      ),
    );
  }
}
