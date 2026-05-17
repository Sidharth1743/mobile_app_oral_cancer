import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'capture/frame_extractor.dart';
import 'capture/frame_selector.dart';
import 'debug/raw_model_output_capture.dart';
import 'core/deidentification.dart';
import 'core/pii_vault.dart';
import 'data/local_database.dart';
import 'data/models.dart';
import 'cloud/firebase_bootstrap.dart';
import 'inference/gemma_service_factory.dart';
import 'inference/mobile_model_paths.dart';
import 'inference/screening_frame_categories.dart';
import 'inference/video_triage_pipeline.dart';
import 'inference/yolo_prefilter.dart';
import 'intake/date_of_birth.dart';
import 'intake/intake_extraction_service.dart';
import 'intake/speech_intake_service.dart';
import 'translation/local_translation_service.dart';
import 'l10n/generated/app_localizations.dart';
import 'location/indian_locations.dart';
import 'ui/app_home_screen.dart';
import 'ui/app_theme.dart';
import 'ui/components/status_badge.dart';
import 'ui/screens/consent_screen.dart';
import 'ui/screens/local_translation_screen.dart';
import 'ui/screens/progress_screen.dart';
import 'ui/screens/treatment_tracking_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _configureDatabaseFactory();
  await const FirebaseBootstrap().initialize();
  runApp(const OralCancerApp());
}

void _configureDatabaseFactory() {
  final isDesktop =
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);
  if (!isDesktop) {
    return;
  }
  sqfliteFfiInit();
  sqflite.databaseFactory = databaseFactoryFfi;
  debugPrint('SQLite FFI initialized for desktop runtime.');
}

const _languagePreferenceKey = 'selected_language_code';

class OralCancerApp extends StatefulWidget {
  const OralCancerApp({super.key});

  @override
  State<OralCancerApp> createState() => _OralCancerAppState();
}

class _OralCancerAppState extends State<OralCancerApp> {
  Locale? _locale;
  bool _loaded = false;
  bool _languageConfirmed = false;

  @override
  void initState() {
    super.initState();
    _loadLocale();
  }

  Future<void> _loadLocale() async {
    final preferences = await SharedPreferences.getInstance();
    final code = preferences.getString(_languagePreferenceKey);
    if (!mounted) {
      return;
    }
    setState(() {
      _locale = code == null ? null : Locale(code);
      _loaded = true;
      _languageConfirmed = false;
    });
  }

  Future<void> _setLocale(Locale locale) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_languagePreferenceKey, locale.languageCode);
    if (!mounted) {
      return;
    }
    setState(() {
      _locale = locale;
      _languageConfirmed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Oral Cancer',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: _locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: !_loaded
          ? const _StartupLoadingScreen()
          : !_languageConfirmed
          ? LanguageSelectionScreen(onLocaleSelected: _setLocale)
          : AppHomeScreen(
              screening: const IntakeScreen(),
              onChangeLanguage: () =>
                  setState(() => _languageConfirmed = false),
            ),
    );
  }
}

class _StartupLoadingScreen extends StatelessWidget {
  const _StartupLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class LanguageSelectionScreen extends StatelessWidget {
  const LanguageSelectionScreen({super.key, required this.onLocaleSelected});

  final ValueChanged<Locale> onLocaleSelected;

  static const _options = [
    _LanguageOption(Locale('en'), 'English'),
    _LanguageOption(Locale('hi'), 'हिन्दी'),
    _LanguageOption(Locale('kn'), 'ಕನ್ನಡ'),
    _LanguageOption(Locale('ta'), 'தமிழ்'),
    _LanguageOption(Locale('ml'), 'മലയാളം'),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.chooseLanguageTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              l10n.chooseLanguageSubtitle,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            for (final option in _options)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton(
                  onPressed: () => onLocaleSelected(option.locale),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(option.label),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LanguageOption {
  const _LanguageOption(this.locale, this.label);

  final Locale locale;
  final String label;
}

class IntakeScreen extends StatefulWidget {
  const IntakeScreen({super.key});

  @override
  State<IntakeScreen> createState() => _IntakeScreenState();
}

class _IntakeScreenState extends State<IntakeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController(text: '');
  final _village = TextEditingController(text: '');
  final _dobDisplay = TextEditingController(text: '');
  final _phone = TextEditingController(text: '');
  final _pinCode = TextEditingController(text: '');
  final _ashaPin = TextEditingController(text: '');
  final _brand = TextEditingController(text: '');
  final _chews = TextEditingController(text: '');
  final _years = TextEditingController(text: '');
  final _voiceTranscript = TextEditingController(text: '');
  List<IndiaStateLocation> _locations = const [];
  String? _state;
  String? _district;
  DateTime? _selectedDob;
  String _gender = 'female';
  bool _alcohol = false;
  bool _busy = false;
  bool _voiceBusy = false;
  bool _isListening = false;
  String? _error;
  String? _voiceError;
  ExtractedIntake? _extractedIntake;
  ExtractedIntake? _extractedDraft;
  final _speechIntake = const SpeechIntakeService();
  StreamSubscription<String>? _speechTranscriptSub;
  String _extractedTranslateLanguage = 'English';

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  @override
  void dispose() {
    unawaited(_speechTranscriptSub?.cancel());
    if (_isListening) {
      _speechIntake.cancelListening();
    }
    _name.dispose();
    _village.dispose();
    _dobDisplay.dispose();
    _phone.dispose();
    _pinCode.dispose();
    _ashaPin.dispose();
    _brand.dispose();
    _chews.dispose();
    _years.dispose();
    _voiceTranscript.dispose();
    super.dispose();
  }

  String _defaultModelPath() {
    if (!kIsWeb &&
        (Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
      return const String.fromEnvironment(
        'LITERT_MODEL_PATH',
        defaultValue:
            '/home/sach/gemma/organized_artifacts/models/MAIN_ours_text_ours_vision/model.litertlm',
      );
    }
    return const String.fromEnvironment(
      'LITERT_MODEL_PATH',
      defaultValue:
          '/sdcard/Android/data/com.example.oral_cancer/files/models/gemma-4-E2B-it-final.litertlm',
    );
  }

  Future<void> _loadLocations() async {
    try {
      final catalog = await IndiaLocationCatalog.load();
      if (!mounted) {
        return;
      }
      final states = catalog.states;
      setState(() {
        _locations = states;
        _state = states.isEmpty ? null : states.first.name;
        _district = states.isEmpty || states.first.districts.isEmpty
            ? null
            : states.first.districts.first;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    }
  }

  Future<void> _pickDob() async {
    final today = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDob ?? DateTime.utc(1985),
      firstDate: DateTime.utc(1900),
      lastDate: today,
    );
    if (selected == null) {
      return;
    }
    setState(() {
      _selectedDob = selected;
      _dobDisplay.text = formatDateOfBirth(selected);
    });
    _formKey.currentState?.validate();
  }

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final identity = IdentityRecord(
        fullName: _name.text,
        village: _village.text,
        dateOfBirth: _selectedDob!,
        phone: _phone.text,
        pinCode: _pinCode.text,
        state: _state!,
        district: _district!,
      );
      final preferences = await SharedPreferences.getInstance();
      await PiiVault(
        preferences: preferences,
      ).saveIdentity(identity: identity, ashaPin: _ashaPin.text);
      final clinicalRecord = deIdentifyClinicalRecord(
        id: const Uuid().v4(),
        identity: identity,
        gender: _gender,
        tobaccoBrand: _brand.text,
        chewsPerDay: int.parse(_chews.text),
        yearsUsed: int.parse(_years.text),
        alcoholUse: _alcohol,
        createdAt: DateTime.now().toUtc(),
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CaptureScreen(clinicalRecord: clinicalRecord),
        ),
      );
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<String> _resolveGemmaModelPath() async {
    if (!kIsWeb && Platform.isAndroid) {
      return (await MobileModelPaths.resolveGemmaPath()).trim();
    }
    return _defaultModelPath().trim();
  }

  Future<void> _ensureGemmaModelAvailable(String modelPath) async {
    if (modelPath.isEmpty) {
      throw StateError(AppLocalizations.of(context).modelPathRequiredError);
    }
    if (!kIsWeb && Platform.isAndroid && !await File(modelPath).exists()) {
      throw StateError(
        'Gemma model not found on device. Run ./scripts/push_model_to_phone.sh '
        'after building the APK. Expected under app files/models/.',
      );
    }
  }

  Future<void> _toggleVoiceIntake() async {
    if (_isListening) {
      setState(() {
        _voiceBusy = true;
        _voiceError = null;
      });
      try {
        final speech = await _speechIntake.stopListening();
        await _speechTranscriptSub?.cancel();
        _speechTranscriptSub = null;
        if (!mounted) {
          return;
        }
        setState(() {
          _isListening = false;
          _voiceTranscript.text = speech.text;
        });
      } catch (error) {
        if (mounted) {
          setState(() => _voiceError = error.toString());
        }
      } finally {
        if (mounted) {
          setState(() => _voiceBusy = false);
        }
      }
      return;
    }

    setState(() {
      _voiceError = null;
      _extractedIntake = null;
      _extractedDraft = null;
    });
    final languageTag = _speechLanguageTag(Localizations.localeOf(context));
    try {
      await _speechTranscriptSub?.cancel();
      _speechTranscriptSub = SpeechIntakeService.transcriptUpdates().listen(
        (text) {
          if (!mounted || text.trim().isEmpty) {
            return;
          }
          setState(() => _voiceTranscript.text = text.trim());
        },
      );
      await _speechIntake.startListening(languageTag: languageTag);
      if (!mounted) {
        return;
      }
      setState(() => _isListening = true);
    } catch (error) {
      if (mounted) {
        setState(() => _voiceError = error.toString());
      }
    }
  }

  Future<void> _extractIntakeFromTranscript() async {
    setState(() {
      _voiceBusy = true;
      _voiceError = null;
      _extractedIntake = null;
    });
    try {
      final modelPath = await _resolveGemmaModelPath();
      await _ensureGemmaModelAvailable(modelPath);
      final service = IntakeExtractionService(
        gemmaService: GemmaServiceFactory.create(
          modelPath: modelPath,
          backend: 'cpu',
        ),
      );
      final extracted = await service.extract(_voiceTranscript.text);
      if (!mounted) {
        return;
      }
      setState(() {
        _extractedIntake = extracted;
        _extractedDraft = extracted;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _voiceError = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _voiceBusy = false);
      }
    }
  }

  Future<void> _translateExtractedReview() async {
    final draft = _extractedDraft ?? _extractedIntake;
    if (draft == null) {
      return;
    }
    setState(() {
      _voiceBusy = true;
      _voiceError = null;
    });
    try {
      final modelPath = await _resolveGemmaModelPath();
      await _ensureGemmaModelAvailable(modelPath);
      final service = LocalGemmaTranslationService(
        gemmaService: GemmaServiceFactory.create(
          modelPath: modelPath,
          backend: 'cpu',
        ),
      );
      final translated = await service.translateExtractedIntake(
        intake: draft,
        targetLanguage: _extractedTranslateLanguage,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _extractedIntake = translated;
        _extractedDraft = translated;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _voiceError = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _voiceBusy = false);
      }
    }
  }

  void _applyExtractedIntake() {
    final extracted = _extractedDraft ?? _extractedIntake;
    if (extracted == null) {
      return;
    }
    setState(() {
      if (extracted.patientName != null) {
        _name.text = extracted.patientName!;
      }
      if (extracted.villageOrArea != null) {
        _village.text = extracted.villageOrArea!;
      }
      if (extracted.state != null &&
          _locations.any((location) => location.name == extracted.state)) {
        final matchedState = _locations.firstWhere(
          (location) => location.name == extracted.state,
        );
        _state = matchedState.name;
        if (extracted.district != null &&
            matchedState.districts.contains(extracted.district)) {
          _district = extracted.district;
        } else if (matchedState.districts.isNotEmpty) {
          _district = matchedState.districts.first;
        }
      }
      if (extracted.age != null) {
        _selectedDob = _dateOfBirthFromAge(extracted.age!);
        _dobDisplay.text = formatDateOfBirth(_selectedDob!);
      }
      if (extracted.gender != null) {
        _gender = extracted.gender!;
      }
      if (extracted.tobaccoBrand != null) {
        _brand.text = extracted.tobaccoBrand!;
      } else if (extracted.tobaccoUse == true && _brand.text.trim().isEmpty) {
        _brand.text = 'chewing tobacco';
      }
      if (extracted.chewsPerDay != null) {
        _chews.text = extracted.chewsPerDay!.toString();
      }
      if (extracted.yearsUsed != null) {
        _years.text = extracted.yearsUsed!.toString();
      }
      if (extracted.alcoholUse != null) {
        _alcohol = extracted.alcoholUse!;
      }
    });
    _formKey.currentState?.validate();
  }

  DateTime _dateOfBirthFromAge(int age) {
    final today = DateTime.now();
    return DateTime(today.year - age, today.month, today.day);
  }

  String _speechLanguageTag(Locale locale) {
    return switch (locale.languageCode) {
      'hi' => 'hi-IN',
      'kn' => 'kn-IN',
      'ta' => 'ta-IN',
      'ml' => 'ml-IN',
      _ => 'en-IN',
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String? requiredValidator(String? value) {
      if (value == null || value.trim().isEmpty) {
        return l10n.requiredError;
      }
      return null;
    }

    String? integerValidator(String? value) {
      final required = requiredValidator(value);
      if (required != null) {
        return required;
      }
      if (int.tryParse(value!) == null) {
        return l10n.numberRequiredError;
      }
      return null;
    }

    final selectedStateDistricts = _locations
        .where((location) => location.name == _state)
        .expand((location) => location.districts)
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.screeningIntakeTitle)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _VoiceIntakePanel(
                transcriptController: _voiceTranscript,
                extracted: _extractedDraft ?? _extractedIntake,
                isListening: _isListening,
                busy: _voiceBusy,
                error: _voiceError,
                translateLanguage: _extractedTranslateLanguage,
                onTranslateLanguageChanged: (value) =>
                    setState(() => _extractedTranslateLanguage = value),
                onToggleVoice: _toggleVoiceIntake,
                onExtract: _extractIntakeFromTranscript,
                onTranslateExtracted: _translateExtractedReview,
                onExtractedChanged: (value) =>
                    setState(() => _extractedDraft = value),
                onApply: _applyExtractedIntake,
                onTranscriptChanged: () => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                decoration: InputDecoration(labelText: l10n.nameLabel),
                validator: requiredValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _village,
                decoration: InputDecoration(labelText: l10n.villageLabel),
                validator: requiredValidator,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('state-dropdown'),
                initialValue: _state,
                decoration: InputDecoration(labelText: l10n.stateLabel),
                items: _locations
                    .map(
                      (state) => DropdownMenuItem(
                        value: state.name,
                        child: Text(state.name),
                      ),
                    )
                    .toList(),
                validator: requiredValidator,
                onChanged: (value) {
                  final districts = _locations
                      .where((location) => location.name == value)
                      .expand((location) => location.districts)
                      .toList();
                  setState(() {
                    _state = value;
                    _district = districts.isEmpty ? null : districts.first;
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('district-dropdown'),
                initialValue: _district,
                decoration: InputDecoration(labelText: l10n.districtLabel),
                items: selectedStateDistricts
                    .map(
                      (district) => DropdownMenuItem(
                        value: district,
                        child: Text(district),
                      ),
                    )
                    .toList(),
                validator: requiredValidator,
                onChanged: (value) => setState(() => _district = value),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('dob-field'),
                controller: _dobDisplay,
                decoration: InputDecoration(labelText: l10n.dateOfBirthLabel),
                readOnly: true,
                onTap: _pickDob,
                validator: (_) => validateDateOfBirth(_selectedDob),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                decoration: InputDecoration(labelText: l10n.phoneLabel),
                keyboardType: TextInputType.phone,
                validator: requiredValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pinCode,
                decoration: InputDecoration(labelText: l10n.pinCodeLabel),
                keyboardType: TextInputType.number,
                validator: requiredValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ashaPin,
                decoration: InputDecoration(labelText: l10n.ashaPinLabel),
                keyboardType: TextInputType.number,
                obscureText: true,
                validator: requiredValidator,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _gender,
                decoration: InputDecoration(labelText: l10n.genderLabel),
                items: [
                  DropdownMenuItem(
                    value: 'female',
                    child: Text(l10n.femaleLabel),
                  ),
                  DropdownMenuItem(value: 'male', child: Text(l10n.maleLabel)),
                  DropdownMenuItem(
                    value: 'other',
                    child: Text(l10n.otherLabel),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _gender = value ?? _gender),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _brand,
                decoration: InputDecoration(labelText: l10n.tobaccoBrandLabel),
                validator: requiredValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _chews,
                decoration: InputDecoration(labelText: l10n.chewsPerDayLabel),
                keyboardType: TextInputType.number,
                validator: integerValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _years,
                decoration: InputDecoration(labelText: l10n.yearsUsedLabel),
                keyboardType: TextInputType.number,
                validator: integerValidator,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.alcoholUseLabel),
                value: _alcohol,
                onChanged: (value) => setState(() => _alcohol = value),
              ),
              if (_error != null) ErrorText(_error!),
              FilledButton(
                onPressed: _busy ? null : _continue,
                child: Text(_busy ? l10n.savingLabel : l10n.continueButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceIntakePanel extends StatelessWidget {
  const _VoiceIntakePanel({
    required this.transcriptController,
    required this.extracted,
    required this.isListening,
    required this.busy,
    required this.error,
    required this.translateLanguage,
    required this.onTranslateLanguageChanged,
    required this.onToggleVoice,
    required this.onExtract,
    required this.onTranslateExtracted,
    required this.onExtractedChanged,
    required this.onApply,
    required this.onTranscriptChanged,
  });

  final TextEditingController transcriptController;
  final ExtractedIntake? extracted;
  final bool isListening;
  final bool busy;
  final String? error;
  final String translateLanguage;
  final ValueChanged<String> onTranslateLanguageChanged;
  final VoidCallback onToggleVoice;
  final VoidCallback onExtract;
  final VoidCallback onTranslateExtracted;
  final ValueChanged<ExtractedIntake> onExtractedChanged;
  final VoidCallback onApply;
  final VoidCallback onTranscriptChanged;

  @override
  Widget build(BuildContext context) {
    final canExtract =
        transcriptController.text.trim().isNotEmpty && !busy && !isListening;
    final canStop = isListening && !busy;
    final voiceLabel = isListening
        ? 'Tap to stop speaking'
        : busy
        ? 'Processing...'
        : 'Tap to start speaking';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Voice intake with Gemma',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              isListening
                  ? 'Listening… speak in phrases. Text appears below as it is recognized. '
                      'Tap stop when finished.'
                  : 'Tap once to start speaking, tap again when finished. '
                      'Gemma extracts fields for you to edit, translate, and apply.',
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (busy && !canStop) ? null : onToggleVoice,
                style: isListening
                    ? FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                      )
                    : null,
                icon: busy && !isListening
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(isListening ? Icons.stop : Icons.mic),
                label: Text(voiceLabel),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: canExtract ? onExtract : null,
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('Extract with Gemma'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: transcriptController,
              decoration: const InputDecoration(
                labelText: 'Transcript',
                hintText:
                    'Patient is a 45-year-old male, uses chewing tobacco daily...',
              ),
              minLines: 2,
              maxLines: 4,
              onChanged: (_) => onTranscriptChanged(),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              ErrorText(error!),
            ],
            if (extracted != null) ...[
              const SizedBox(height: 12),
              _EditableExtractedIntakeReview(
                key: ObjectKey(extracted),
                extracted: extracted!,
                translateLanguage: translateLanguage,
                onTranslateLanguageChanged: onTranslateLanguageChanged,
                busy: busy,
                onChanged: onExtractedChanged,
                onTranslate: onTranslateExtracted,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: extracted!.hasAnyPrefill && !busy ? onApply : null,
                icon: const Icon(Icons.playlist_add_check),
                label: const Text('Apply extracted fields'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EditableExtractedIntakeReview extends StatefulWidget {
  const _EditableExtractedIntakeReview({
    super.key,
    required this.extracted,
    required this.translateLanguage,
    required this.onTranslateLanguageChanged,
    required this.busy,
    required this.onChanged,
    required this.onTranslate,
  });

  final ExtractedIntake extracted;
  final String translateLanguage;
  final ValueChanged<String> onTranslateLanguageChanged;
  final bool busy;
  final ValueChanged<ExtractedIntake> onChanged;
  final VoidCallback onTranslate;

  @override
  State<_EditableExtractedIntakeReview> createState() =>
      _EditableExtractedIntakeReviewState();
}

class _EditableExtractedIntakeReviewState
    extends State<_EditableExtractedIntakeReview> {
  late final TextEditingController _name;
  late final TextEditingController _village;
  late final TextEditingController _state;
  late final TextEditingController _district;
  late final TextEditingController _age;
  late final TextEditingController _gender;
  late final TextEditingController _tobaccoBrand;
  late final TextEditingController _chews;
  late final TextEditingController _years;
  late final TextEditingController _symptoms;
  late final TextEditingController _symptomDuration;
  bool? _tobaccoUse;
  bool? _alcoholUse;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _village = TextEditingController();
    _state = TextEditingController();
    _district = TextEditingController();
    _age = TextEditingController();
    _gender = TextEditingController();
    _tobaccoBrand = TextEditingController();
    _chews = TextEditingController();
    _years = TextEditingController();
    _symptoms = TextEditingController();
    _symptomDuration = TextEditingController();
    _syncFrom(widget.extracted);
  }

  @override
  void didUpdateWidget(covariant _EditableExtractedIntakeReview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.extracted != widget.extracted) {
      _syncFrom(widget.extracted);
    }
  }

  void _syncFrom(ExtractedIntake extracted) {
    _name.text = extracted.patientName ?? '';
    _village.text = extracted.villageOrArea ?? '';
    _state.text = extracted.state ?? '';
    _district.text = extracted.district ?? '';
    _age.text = extracted.age?.toString() ?? '';
    _gender.text = extracted.gender ?? '';
    _tobaccoBrand.text = extracted.tobaccoBrand ?? '';
    _chews.text = extracted.chewsPerDay?.toString() ?? '';
    _years.text = extracted.yearsUsed?.toString() ?? '';
    _symptoms.text = extracted.symptoms.join(', ');
    _symptomDuration.text = extracted.symptomDuration ?? '';
    _tobaccoUse = extracted.tobaccoUse;
    _alcoholUse = extracted.alcoholUse;
  }

  @override
  void dispose() {
    _name.dispose();
    _village.dispose();
    _state.dispose();
    _district.dispose();
    _age.dispose();
    _gender.dispose();
    _tobaccoBrand.dispose();
    _chews.dispose();
    _years.dispose();
    _symptoms.dispose();
    _symptomDuration.dispose();
    super.dispose();
  }

  void _notifyChanged() {
    widget.onChanged(
      widget.extracted.copyWith(
        patientName: _optionalText(_name.text),
        villageOrArea: _optionalText(_village.text),
        state: _optionalText(_state.text),
        district: _optionalText(_district.text),
        age: int.tryParse(_age.text.trim()),
        gender: _optionalText(_gender.text)?.toLowerCase(),
        tobaccoUse: _tobaccoUse,
        tobaccoBrand: _optionalText(_tobaccoBrand.text),
        chewsPerDay: int.tryParse(_chews.text.trim()),
        yearsUsed: int.tryParse(_years.text.trim()),
        alcoholUse: _alcoholUse,
        symptoms: _symptoms.text
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(),
        symptomDuration: _optionalText(_symptomDuration.text),
        clearPatientName: _name.text.trim().isEmpty,
        clearVillageOrArea: _village.text.trim().isEmpty,
        clearState: _state.text.trim().isEmpty,
        clearDistrict: _district.text.trim().isEmpty,
        clearAge: _age.text.trim().isEmpty,
        clearGender: _gender.text.trim().isEmpty,
        clearTobaccoBrand: _tobaccoBrand.text.trim().isEmpty,
        clearSymptomDuration: _symptomDuration.text.trim().isEmpty,
      ),
    );
  }

  String? _optionalText(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Review extracted fields',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            const Text('Edit any value before applying or translating.'),
            const SizedBox(height: 8),
            _editableField('Name', _name),
            _editableField('Village/area', _village),
            _editableField('State', _state),
            _editableField('District', _district),
            _editableField('Age', _age, keyboardType: TextInputType.number),
            _editableField('Gender', _gender),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tobacco use'),
              value: _tobaccoUse ?? false,
              onChanged: (value) {
                setState(() => _tobaccoUse = value);
                _notifyChanged();
              },
            ),
            _editableField('Tobacco brand', _tobaccoBrand),
            _editableField('Chews/day', _chews, keyboardType: TextInputType.number),
            _editableField('Years used', _years, keyboardType: TextInputType.number),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Alcohol use'),
              value: _alcoholUse ?? false,
              onChanged: (value) {
                setState(() => _alcoholUse = value);
                _notifyChanged();
              },
            ),
            _editableField('Symptoms (comma-separated)', _symptoms, maxLines: 2),
            _editableField('Symptom duration', _symptomDuration),
            if (widget.extracted.missingFields.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Still missing: ${widget.extracted.missingFields.join(', ')}',
                ),
              ),
            Text(
              'Confidence: ${(widget.extracted.confidence * 100).round()}%',
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: widget.translateLanguage,
              decoration: const InputDecoration(labelText: 'Translate to'),
              items: const [
                DropdownMenuItem(value: 'English', child: Text('English')),
                DropdownMenuItem(value: 'Hindi', child: Text('Hindi')),
                DropdownMenuItem(value: 'Tamil', child: Text('Tamil')),
                DropdownMenuItem(value: 'Kannada', child: Text('Kannada')),
                DropdownMenuItem(value: 'Malayalam', child: Text('Malayalam')),
                DropdownMenuItem(value: 'Marathi', child: Text('Marathi')),
                DropdownMenuItem(value: 'Telugu', child: Text('Telugu')),
              ],
              onChanged: widget.busy
                  ? null
                  : (value) {
                      if (value != null) {
                        widget.onTranslateLanguageChanged(value);
                      }
                    },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: widget.busy ? null : widget.onTranslate,
              icon: const Icon(Icons.translate),
              label: const Text('Translate fields with Gemma'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _editableField(
    String label,
    TextEditingController controller, {
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label, isDense: true),
        keyboardType: keyboardType,
        maxLines: maxLines,
        onChanged: (_) => _notifyChanged(),
      ),
    );
  }
}

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key, required this.clinicalRecord});

  final ClinicalRecord clinicalRecord;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  CameraController? _cameraController;
  Future<void>? _cameraInit;
  String? _videoPath;
  bool _recording = false;
  bool _busy = false;
  String? _error;
  String? _progress;

  bool get _isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  @override
  void initState() {
    super.initState();
    if (_isDesktop) {
      _cameraInit = Future.value();
    } else {
      _cameraInit = _initializeCamera();
    }
  }

  String _defaultModelPath() {
    if (_isDesktop) {
      return const String.fromEnvironment(
        'LITERT_MODEL_PATH',
        defaultValue:
            '/home/sach/gemma/organized_artifacts/models/MAIN_ours_text_ours_vision/model.litertlm',
      );
    }
    return const String.fromEnvironment(
      'LITERT_MODEL_PATH',
      defaultValue:
          '/sdcard/Android/data/com.example.oral_cancer/files/models/gemma-4-E2B-it-final.litertlm',
    );
  }

  String _defaultYoloModelPath() {
    if (_isDesktop) {
      return const String.fromEnvironment(
        'YOLO_MODEL_PATH',
        defaultValue:
            '/home/sach/gemma/organized_artifacts/yolo_prefilter/YOLO11n_lesion_cropper_best_mobile_exports/yolo11n_lesion_best_640_int8.tflite',
      );
    }
    return const String.fromEnvironment(
      'YOLO_MODEL_PATH',
      defaultValue:
          '/sdcard/Android/data/com.example.oral_cancer/files/models/yolo11n_lesion_best_640_int8.tflite',
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    if (_isDesktop) {
      return;
    }
    final existing = _cameraController;
    if (existing != null && existing.value.isInitialized) {
      return;
    }
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw StateError('No camera is available on this device.');
    }
    final controller = CameraController(
      cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _cameraController = controller);
  }

  Future<void> _releaseCamera() async {
    final controller = _cameraController;
    if (controller == null) {
      return;
    }
    _cameraController = null;
    _cameraInit = Future.value();
    if (mounted) {
      setState(() {});
    }
    await controller.dispose();
    debugPrint('[OralCancerPipeline] camera_released');
  }

  Future<void> _toggleRecording() async {
    final l10n = AppLocalizations.of(context);
    if (!_isDesktop &&
        (_cameraController == null ||
            !_cameraController!.value.isInitialized)) {
      setState(() {
        _busy = true;
        _error = null;
        _progress = null;
        _cameraInit = _initializeCamera();
      });
      try {
        await _cameraInit;
      } catch (error) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = error.toString();
          });
        }
        return;
      }
      if (mounted) {
        setState(() => _busy = false);
      }
    }

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      setState(() => _error = l10n.cameraNotReadyError);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _progress = null;
    });
    try {
      if (_recording && controller.value.isRecordingVideo) {
        debugPrint('[OralCancerPipeline] record_stop_requested');
        final file = await controller.stopVideoRecording();
        debugPrint('[OralCancerPipeline] record_stop_done path=${file.path}');
        setState(() {
          _videoPath = file.path;
          _recording = false;
        });
        await _releaseCamera();
      } else {
        if (controller.value.isRecordingVideo) {
          throw StateError(l10n.stopCurrentRecordingError);
        }
        debugPrint('[OralCancerPipeline] record_start_requested');
        await controller.startVideoRecording();
        debugPrint('[OralCancerPipeline] record_start_done');
        setState(() => _recording = true);
      }
    } catch (error) {
      debugPrint('[OralCancerPipeline] record_error error=$error');
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _pickDesktopVideo() async {
    debugPrint('[OralCancerPipeline] upload_video_picker_open');
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'videos',
          extensions: ['mp4', 'mov', 'm4v', 'webm', 'mkv', 'avi'],
        ),
      ],
      confirmButtonText: AppLocalizations.of(context).selectVideoButton,
    );
    if (file == null) {
      debugPrint('[OralCancerPipeline] upload_video_picker_cancelled');
      return;
    }
    if (!File(file.path).existsSync()) {
      setState(
        () =>
            _error = AppLocalizations.of(context).videoMissingError(file.path),
      );
      return;
    }
    debugPrint('[OralCancerPipeline] upload_video_selected path=${file.path}');
    setState(() {
      _videoPath = file.path;
      _error = null;
    });
  }

  Future<void> _analyze() async {
    final analyzeStarted = DateTime.now();
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
      _progress = l10n.preparingVideosProgress;
    });
    try {
      final modelPath = !kIsWeb && Platform.isAndroid
          ? (await MobileModelPaths.resolveGemmaPath()).trim()
          : _defaultModelPath().trim();
      final yoloModelPath = !kIsWeb && Platform.isAndroid
          ? (await MobileModelPaths.resolveYoloPath()).trim()
          : _defaultYoloModelPath().trim();
      if (modelPath.isEmpty) {
        throw StateError(l10n.modelPathRequiredError);
      }
      if (yoloModelPath.isEmpty) {
        throw StateError(l10n.yoloPathRequiredError);
      }
      final videoPath = _videoPath;
      if (videoPath == null) {
        throw StateError(l10n.recordOrSelectVideoError);
      }
      await _releaseCamera();
      debugPrint(
        '[OralCancerPipeline] analyze_button_start video=$videoPath '
        'model=$modelPath yolo=$yoloModelPath',
      );
      const maxGemmaImages = 5;
      const gemmaBackend = 'cpu';
      debugPrint(
        '[OralCancerPipeline] runtime_config maxGemmaImages=$maxGemmaImages '
        'gemmaBackend=$gemmaBackend platform=${Platform.operatingSystem}',
      );
      final visitId = const Uuid().v4();
      const extractor = FrameExtractor();
      const selector = FrameSelector();
      debugPrint('[OralCancerPipeline] extract_start video=$videoPath');
      setState(() => _progress = l10n.extractingFramesProgress);
      final frames = await extractor.extractFrames(
        videoPath: videoPath,
        visitId: visitId,
        siteId: 'visit_video',
        framesPerSecond: 1,
        deleteSourceVideo: false,
      );
      debugPrint('[OralCancerPipeline] extract_done frames=${frames.length}');
      setState(() => _progress = l10n.selectingFramesProgress);
      final selected = selector.selectBestFrames(frames, count: maxGemmaImages);
      debugPrint(
        '[OralCancerPipeline] select_done selected=${selected.length} '
        'paths=${selected.join('|')}',
      );
      final database = LocalDatabase();
      setState(() => _progress = l10n.runningTriageProgress(maxGemmaImages));
      final pipeline = VideoTriagePipeline(
        gemmaService: GemmaServiceFactory.create(
          modelPath: modelPath,
          backend: gemmaBackend,
        ),
        database: database,
        yoloPrefilter: YoloPrefilter(modelPath: yoloModelPath),
      );
      final assessment = await pipeline.analyze(
        clinicalRecord: widget.clinicalRecord,
        framePaths: selected,
        maxGemmaImages: maxGemmaImages,
        outputLanguage: l10n.gemmaLanguageName,
        onProgress: (message) {
          if (mounted) {
            setState(() => _progress = message);
          }
        },
      );
      debugPrint(
        '[OralCancerPipeline] analyze_button_done action=${assessment.carePlan.action} '
        'elapsedMs=${DateTime.now().difference(analyzeStarted).inMilliseconds}',
      );
      await RawModelOutputCapture.recordAssessmentBundle(
        visitId: assessment.visitId,
        rawModelOutputs: assessment.rawModelOutputs,
        carePlanAction: assessment.carePlan.action,
      );
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              PatientOutputScreen(assessment: assessment, database: database),
        ),
      );
      if (mounted && !_isDesktop) {
        setState(() {
          _cameraInit = _initializeCamera();
        });
      }
    } catch (error) {
      debugPrint(
        '[OralCancerPipeline] analyze_button_error elapsedMs=${DateTime.now().difference(analyzeStarted).inMilliseconds} '
        'error=$error',
      );
      setState(() => _error = error.toString());
      if (!_isDesktop && mounted) {
        setState(() {
          _cameraInit = _initializeCamera();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final complete = _videoPath != null && !_recording;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.captureVideoTitle)),
      body: FutureBuilder<void>(
        future: _cameraInit,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: ErrorText(snapshot.error.toString()),
            );
          }
          final controller = _cameraController;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!_isDesktop &&
                  controller != null &&
                  controller.value.isInitialized)
                AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: CameraPreview(controller),
                ),
              if (_isDesktop)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(l10n.desktopModeInstructions),
                ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.intraoralVideoLabel),
                      const SizedBox(height: 4),
                      Text(
                        _recording
                            ? l10n.recordingLiveVideo
                            : _videoPath == null
                            ? l10n.noVideoSelected
                            : l10n.selectedVideo(
                                File(_videoPath!).uri.pathSegments.last,
                              ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          if (!_isDesktop)
                            FilledButton.icon(
                              onPressed: _busy ? null : _toggleRecording,
                              icon: Icon(
                                _recording ? Icons.stop : Icons.videocam,
                              ),
                              label: Text(
                                _recording
                                    ? l10n.stopButton
                                    : l10n.recordLiveButton,
                              ),
                            ),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _pickDesktopVideo,
                            icon: const Icon(Icons.upload_file),
                            label: Text(
                              _videoPath == null
                                  ? l10n.uploadVideoButton
                                  : l10n.changeUploadedVideoButton,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(l10n.fixedModelPathNotice),
              ),
              if (_error != null) ErrorText(_error!),
              if (_progress != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_progress!),
                ),
              FilledButton(
                onPressed: complete && !_busy ? _analyze : null,
                child: Text(_busy ? l10n.analyzingLabel : l10n.analyzeButton),
              ),
            ],
          );
        },
      ),
    );
  }
}

class PatientOutputScreen extends StatefulWidget {
  const PatientOutputScreen({
    super.key,
    required this.assessment,
    required this.database,
  });

  final FullAssessment assessment;
  final LocalDatabase database;

  @override
  State<PatientOutputScreen> createState() => _PatientOutputScreenState();
}

class _PatientOutputScreenState extends State<PatientOutputScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final action = widget.assessment.carePlan.action;
    final color = action == 'urgent_referral' || action == 'see_doctor_free'
        ? Colors.red
        : Colors.teal;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.resultTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.assessment.carePlan.patientMessage,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (widget.assessment.rawModelOutputs.isNotEmpty) ...[
            const SizedBox(height: 16),
            RawModelOutputPanel(outputs: widget.assessment.rawModelOutputs),
          ],
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      AshaOutputScreen(assessment: widget.assessment),
                ),
              );
            },
            child: Text(l10n.ashaViewButton),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ConsentScreen(
                    assessment: widget.assessment,
                    database: widget.database,
                  ),
                ),
              );
            },
            child: Text(l10n.consentSharingButton),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LocalTranslationScreen(
                    initialText: widget.assessment.carePlan.patientMessage,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.translate),
            label: Text(l10n.translateLocallyButton),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TreatmentTrackingScreen(
                    assessment: widget.assessment,
                    database: widget.database,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(l10n.treatmentTrackingButton),
          ),
        ],
      ),
    );
  }
}

class RawModelOutputPanel extends StatelessWidget {
  const RawModelOutputPanel({super.key, required this.outputs});

  final List<String> outputs;

  @override
  Widget build(BuildContext context) {
    final entries = outputs.map(_RawModelOutputEntry.parse).toList();
    final aggregation = ScreeningFrameAggregation.fromParsedMaps(
      entries.map((entry) => entry.toLegacyMap()).toList(),
    );
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        title: Text(l10n.rawModelOutputTitle),
        subtitle: Text(l10n.rawModelOutputSubtitle(entries.length)),
        children: [
          _FrameCategorySummaryCard(aggregation: aggregation),
          const SizedBox(height: 12),
          for (var index = 0; index < entries.length; index++) ...[
            _RawModelOutputTile(entry: entries[index]),
            if (index != entries.length - 1)
              Divider(height: 16, color: theme.colorScheme.outlineVariant),
          ],
        ],
      ),
    );
  }
}

class _FrameCategorySummaryCard extends StatelessWidget {
  const _FrameCategorySummaryCard({required this.aggregation});

  final ScreeningFrameAggregation aggregation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final majority = aggregation.majorityCategory;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Majority category',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              majority.isEmpty
                  ? 'No category parsed'
                  : '${formatCategoryLabel(majority)} (${aggregation.categoryCounts[majority] ?? 0} of ${aggregation.frames.length} frames)',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Per frame',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            for (var i = 0; i < aggregation.frames.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Frame ${i + 1}: ',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        formatCategoryLabel(aggregation.frames[i].category),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            if (aggregation.categoryCounts.length > 1) ...[
              const SizedBox(height: 8),
              Text(
                'Counts: ${aggregation.categoryCounts.entries.map((e) => '${formatCategoryLabel(e.key)} ${e.value}').join(' · ')}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RawModelOutputTile extends StatelessWidget {
  const _RawModelOutputTile({required this.entry});

  final _RawModelOutputEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final categoryLabel = formatCategoryLabel(entry.category);
    final isReview =
        entry.category.contains('refer') ||
        entry.recommendation.contains('refer');
    final isRecapture =
        entry.category == 'recapture_required' ||
        entry.recommendation == 'recapture_required';
    final badgeColor = entry.category.isEmpty
        ? theme.colorScheme.outline
        : isReview
        ? Colors.red
        : isRecapture
        ? Colors.orange
        : theme.colorScheme.primary;
    final badgeLabel = entry.category.isEmpty ? l10n.unparsedBadge : categoryLabel;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      title: Row(
        children: [
          Expanded(
            child: Text(
              entry.siteLabel,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          StatusBadge(label: badgeLabel, color: badgeColor),
        ],
      ),
      subtitle: entry.reason.isEmpty
          ? Text(l10n.rawLocalModelResponse)
          : Text(entry.reason, maxLines: 2, overflow: TextOverflow.ellipsis),
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 8, bottom: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            entry.cleanedRaw,
            style: const TextStyle(
              color: Color(0xFFE5E7EB),
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _RawModelOutputEntry {
  const _RawModelOutputEntry({
    required this.siteId,
    required this.category,
    required this.recommendation,
    required this.reason,
    required this.cleanedRaw,
  });

  final String siteId;
  final String category;
  final String recommendation;
  final String reason;
  final String cleanedRaw;

  Map<String, Object?> toLegacyMap() => {
    'category': category,
    'recommendation': recommendation,
    'brief_reason': reason,
    'disclaimer': '',
  };

  String get siteLabel => siteId
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');

  static _RawModelOutputEntry parse(String source) {
    final siteMatch = RegExp(r'^\[site:([^\]]+)\]\s*').firstMatch(source);
    final siteId = siteMatch?.group(1) ?? 'site';
    final withoutPrefix = source.replaceFirst(
      RegExp(r'^\[site:[^\]]+\]\s*'),
      '',
    );
    final parsed = parseScreeningClassifierOutput(withoutPrefix);
    final category = (parsed['category'] as String? ?? '').toLowerCase();
    final recommendation = parsed['recommendation'] as String? ?? '';
    final reason = (parsed['brief_reason'] as String? ?? '').trim().isNotEmpty
        ? parsed['brief_reason'] as String
        : recommendation;
    return _RawModelOutputEntry(
      siteId: siteId,
      category: category,
      recommendation: recommendation,
      reason: reason,
      cleanedRaw: _stripFence(withoutPrefix),
    );
  }

  static String _stripFence(String source) {
    var text = source.trim();
    text = text.replaceFirst(RegExp(r'^```json\s*', caseSensitive: false), '');
    text = text.replaceFirst(RegExp(r'^```\s*'), '');
    text = text.replaceFirst(RegExp(r'\s*```$'), '');
    return text.trim();
  }
}

class AshaOutputScreen extends StatelessWidget {
  const AshaOutputScreen({super.key, required this.assessment});

  final FullAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.ashaSummaryTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(assessment.carePlan.ashaMessage),
          const SizedBox(height: 16),
          for (final hypothesis in assessment.hypotheses)
            ListTile(
              title: Text(hypothesis.label),
              subtitle: LinearProgressIndicator(
                value: hypothesis.probability.clamp(0, 1),
              ),
              trailing: Text('${(hypothesis.probability * 100).round()}%'),
            ),
          const Divider(),
          Text(assessment.delta.summary),
          const SizedBox(height: 12),
          Text(
            l10n.rescreenDate(
              assessment.carePlan.rescreenDate
                  .toIso8601String()
                  .split('T')
                  .first,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProgressScreen(assessment: assessment),
                ),
              );
            },
            icon: const Icon(Icons.timeline),
            label: Text(l10n.progressButton),
          ),
        ],
      ),
    );
  }
}

class ErrorText extends StatelessWidget {
  const ErrorText(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}
