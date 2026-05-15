import 'dart:io';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'capture/frame_extractor.dart';
import 'capture/frame_selector.dart';
import 'core/deidentification.dart';
import 'core/pii_vault.dart';
import 'data/local_database.dart';
import 'data/models.dart';
import 'cloud/firebase_bootstrap.dart';
import 'inference/gemma_service_factory.dart';
import 'inference/video_triage_pipeline.dart';
import 'inference/yolo_prefilter.dart';
import 'intake/date_of_birth.dart';
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

class OralCancerApp extends StatelessWidget {
  const OralCancerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Oral Cancer',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const AppHomeScreen(screening: IntakeScreen()),
    );
  }
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
  List<IndiaStateLocation> _locations = const [];
  String? _state;
  String? _district;
  DateTime? _selectedDob;
  String _gender = 'female';
  bool _alcohol = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  @override
  void dispose() {
    _name.dispose();
    _village.dispose();
    _dobDisplay.dispose();
    _phone.dispose();
    _pinCode.dispose();
    _ashaPin.dispose();
    _brand.dispose();
    _chews.dispose();
    _years.dispose();
    super.dispose();
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
        setState(() => _error = 'Location data unavailable: $error');
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

  @override
  Widget build(BuildContext context) {
    final selectedStateDistricts = _locations
        .where((location) => location.name == _state)
        .expand((location) => location.districts)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Screening intake')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _village,
                decoration: const InputDecoration(labelText: 'Village / area'),
                validator: _required,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('state-dropdown'),
                initialValue: _state,
                decoration: const InputDecoration(labelText: 'State'),
                items: _locations
                    .map(
                      (state) => DropdownMenuItem(
                        value: state.name,
                        child: Text(state.name),
                      ),
                    )
                    .toList(),
                validator: _required,
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
                decoration: const InputDecoration(labelText: 'District'),
                items: selectedStateDistricts
                    .map(
                      (district) => DropdownMenuItem(
                        value: district,
                        child: Text(district),
                      ),
                    )
                    .toList(),
                validator: _required,
                onChanged: (value) => setState(() => _district = value),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('dob-field'),
                controller: _dobDisplay,
                decoration: const InputDecoration(labelText: 'Date of birth'),
                readOnly: true,
                onTap: _pickDob,
                validator: (_) => validateDateOfBirth(_selectedDob),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'Phone'),
                keyboardType: TextInputType.phone,
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pinCode,
                decoration: const InputDecoration(labelText: 'PIN code'),
                keyboardType: TextInputType.number,
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ashaPin,
                decoration: const InputDecoration(labelText: 'ASHA PIN'),
                keyboardType: TextInputType.number,
                obscureText: true,
                validator: _required,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _gender,
                decoration: const InputDecoration(labelText: 'Gender'),
                items: const [
                  DropdownMenuItem(value: 'female', child: Text('Female')),
                  DropdownMenuItem(value: 'male', child: Text('Male')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (value) =>
                    setState(() => _gender = value ?? _gender),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _brand,
                decoration: const InputDecoration(labelText: 'Tobacco brand'),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _chews,
                decoration: const InputDecoration(labelText: 'Chews per day'),
                keyboardType: TextInputType.number,
                validator: _integer,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _years,
                decoration: const InputDecoration(labelText: 'Years used'),
                keyboardType: TextInputType.number,
                validator: _integer,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Alcohol use'),
                value: _alcohol,
                onChanged: (value) => setState(() => _alcohol = value),
              ),
              if (_error != null) ErrorText(_error!),
              FilledButton(
                onPressed: _busy ? null : _continue,
                child: Text(_busy ? 'Saving' : 'Continue'),
              ),
            ],
          ),
        ),
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

  Future<void> _toggleRecording() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      setState(() => _error = 'Camera is not ready.');
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
      } else {
        if (controller.value.isRecordingVideo) {
          throw StateError('Stop the current recording first.');
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
      confirmButtonText: 'Select video',
    );
    if (file == null) {
      debugPrint('[OralCancerPipeline] upload_video_picker_cancelled');
      return;
    }
    if (!File(file.path).existsSync()) {
      setState(() => _error = 'Video does not exist: ${file.path}');
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
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Preparing videos';
    });
    try {
      final modelPath = _defaultModelPath().trim();
      final yoloModelPath = _defaultYoloModelPath().trim();
      if (modelPath.isEmpty) {
        throw StateError('LiteRT model path is required.');
      }
      if (yoloModelPath.isEmpty) {
        throw StateError('YOLO model path is required.');
      }
      final videoPath = _videoPath;
      if (videoPath == null) {
        throw StateError('Record or select one intraoral video first.');
      }
      debugPrint(
        '[OralCancerPipeline] analyze_button_start video=$videoPath '
        'model=$modelPath yolo=$yoloModelPath',
      );
      final maxGemmaImages = !kIsWeb && Platform.isAndroid ? 1 : 5;
      const gemmaBackend = 'cpu';
      debugPrint(
        '[OralCancerPipeline] runtime_config maxGemmaImages=$maxGemmaImages '
        'gemmaBackend=$gemmaBackend platform=${Platform.operatingSystem}',
      );
      final visitId = const Uuid().v4();
      const extractor = FrameExtractor();
      const selector = FrameSelector();
      debugPrint('[OralCancerPipeline] extract_start video=$videoPath');
      setState(() => _progress = 'Extracting video frames');
      final frames = await extractor.extractFrames(
        videoPath: videoPath,
        visitId: visitId,
        siteId: 'visit_video',
        framesPerSecond: 1,
        deleteSourceVideo: false,
      );
      debugPrint('[OralCancerPipeline] extract_done frames=${frames.length}');
      setState(() => _progress = 'Selecting representative frames');
      final selected = selector.selectBestFrames(frames, count: maxGemmaImages);
      debugPrint(
        '[OralCancerPipeline] select_done selected=${selected.length} '
        'paths=${selected.join('|')}',
      );
      final database = LocalDatabase();
      setState(
        () => _progress =
            'Running YOLO + Gemma triage '
            '($maxGemmaImages frame${maxGemmaImages == 1 ? '' : 's'})',
      );
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
      if (!mounted) {
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              PatientOutputScreen(assessment: assessment, database: database),
        ),
      );
    } catch (error) {
      debugPrint(
        '[OralCancerPipeline] analyze_button_error elapsedMs=${DateTime.now().difference(analyzeStarted).inMilliseconds} '
        'error=$error',
      );
      setState(() => _error = error.toString());
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
    final complete = _videoPath != null && !_recording;
    return Scaffold(
      appBar: AppBar(title: const Text('Capture intraoral video')),
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
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Desktop mode: select one intraoral video. The app will '
                    'sample representative frames for local screening.',
                  ),
                ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Intraoral video'),
                      const SizedBox(height: 4),
                      Text(
                        _recording
                            ? 'Recording live video'
                            : _videoPath == null
                            ? 'No video selected'
                            : 'Selected: ${File(_videoPath!).uri.pathSegments.last}',
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
                              label: Text(_recording ? 'Stop' : 'Record live'),
                            ),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _pickDesktopVideo,
                            icon: const Icon(Icons.upload_file),
                            label: Text(
                              _videoPath == null
                                  ? 'Upload video'
                                  : 'Change uploaded video',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'The LiteRT model path is fixed by app configuration; no '
                  'model selection is required during screening.',
                ),
              ),
              if (_error != null) ErrorText(_error!),
              if (_progress != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_progress!),
                ),
              FilledButton(
                onPressed: complete && !_busy ? _analyze : null,
                child: Text(_busy ? 'Analyzing' : 'Analyze'),
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
    final action = widget.assessment.carePlan.action;
    final color = action == 'urgent_referral' || action == 'see_doctor_free'
        ? Colors.red
        : Colors.teal;
    return Scaffold(
      appBar: AppBar(title: const Text('Result')),
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
            child: const Text('ASHA view'),
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
            child: const Text('Consent and sharing'),
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
            label: const Text('Translate locally'),
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
            label: const Text('Treatment tracking'),
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
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        title: const Text('Raw model output'),
        subtitle: Text('${entries.length} site responses from local LiteRT'),
        children: [
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

class _RawModelOutputTile extends StatelessWidget {
  const _RawModelOutputTile({required this.entry});

  final _RawModelOutputEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isReview = entry.category == 'refer_for_clinical_review';
    final isRecapture = entry.category == 'recapture_required';
    final badgeColor = entry.category.isEmpty
        ? theme.colorScheme.outline
        : isReview
        ? Colors.red
        : isRecapture
        ? Colors.orange
        : Colors.teal;
    final badgeLabel = entry.category.isEmpty
        ? 'Unparsed'
        : isReview
        ? 'Review'
        : isRecapture
        ? 'Recapture'
        : 'Low risk';
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
          ? const Text('Raw local model response')
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
    required this.reason,
    required this.cleanedRaw,
  });

  final String siteId;
  final String category;
  final String reason;
  final String cleanedRaw;

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
    final cleaned = _stripFence(withoutPrefix);
    final category = _field(cleaned, 'category').toLowerCase();
    final recommendation = _field(cleaned, 'recommendation');
    final reason = _field(cleaned, 'brief_reason').isNotEmpty
        ? _field(cleaned, 'brief_reason')
        : recommendation;
    return _RawModelOutputEntry(
      siteId: siteId,
      category: category,
      reason: reason,
      cleanedRaw: cleaned,
    );
  }

  static String _stripFence(String source) {
    var text = source.trim();
    text = text.replaceFirst(RegExp(r'^```json\s*', caseSensitive: false), '');
    text = text.replaceFirst(RegExp(r'^```\s*'), '');
    text = text.replaceFirst(RegExp(r'\s*```$'), '');
    return text.trim();
  }

  static String _field(String source, String field) {
    final pattern = RegExp(
      '"${RegExp.escape(field)}"\\s*:\\s*"([^"\\\\]*(?:\\\\.[^"\\\\]*)*)"',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(source);
    return match?.group(1)?.replaceAll(r'\"', '"').trim() ?? '';
  }
}

class AshaOutputScreen extends StatelessWidget {
  const AshaOutputScreen({super.key, required this.assessment});

  final FullAssessment assessment;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ASHA summary')),
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
            'Rescreen ${assessment.carePlan.rescreenDate.toIso8601String().split('T').first}',
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
            label: const Text('Progress'),
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

String? _required(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Required';
  }
  return null;
}

String? _integer(String? value) {
  final required = _required(value);
  if (required != null) {
    return required;
  }
  if (int.tryParse(value!) == null) {
    return 'Number required';
  }
  return null;
}
