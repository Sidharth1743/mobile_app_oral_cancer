import 'package:flutter/material.dart';

import '../../inference/gemma_service_factory.dart';
import '../../translation/local_translation_service.dart';
import '../components/section_panel.dart';

class LocalTranslationScreen extends StatefulWidget {
  const LocalTranslationScreen({super.key, required this.initialText});

  final String initialText;

  @override
  State<LocalTranslationScreen> createState() => _LocalTranslationScreenState();
}

class _LocalTranslationScreenState extends State<LocalTranslationScreen> {
  final _modelPath = TextEditingController(
    text: const String.fromEnvironment(
      'LITERT_MODEL_PATH',
      defaultValue:
          '/sdcard/Android/data/com.example.oral_cancer/files/models/gemma-4-E2B-it.litertlm',
    ),
  );
  final _text = TextEditingController();
  String _language = 'Tamil';
  bool _busy = false;
  String? _error;
  TranslationResult? _result;

  @override
  void initState() {
    super.initState();
    _text.text = widget.initialText;
  }

  @override
  void dispose() {
    _modelPath.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _translate() async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final modelPath = _modelPath.text.trim();
      if (modelPath.isEmpty) {
        throw StateError('LiteRT model path is required.');
      }
      final service = LocalGemmaTranslationService(
        gemmaService: GemmaServiceFactory.create(modelPath: modelPath),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Local translation')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionPanel(
            title: 'Translate on device',
            subtitle: 'Runs through the local LiteRT Gemma service.',
            children: [
              TextFormField(
                controller: _modelPath,
                decoration: const InputDecoration(
                  labelText: 'LiteRT model path',
                ),
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
                  onPressed: _busy ? null : _translate,
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
