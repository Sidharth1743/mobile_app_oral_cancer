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
import 'capture/oral_sites.dart';
import 'core/deidentification.dart';
import 'core/pii_vault.dart';
import 'data/local_database.dart';
import 'data/models.dart';
import 'cloud/firebase_bootstrap.dart';
import 'inference/lesion_analyzer.dart';
import 'inference/gemma_service_factory.dart';
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
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pinCode,
                decoration: const InputDecoration(labelText: 'PIN code'),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ashaPin,
                decoration: const InputDecoration(labelText: 'ASHA PIN'),
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
  final Map<String, String> _capturePaths = {};
  late final TextEditingController _modelPathController;
  String? _recordingSiteId;
  bool _busy = false;
  String? _error;
  String? _progress;

  bool get _isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  @override
  void initState() {
    super.initState();
    _modelPathController = TextEditingController(text: _defaultModelPath());
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
        defaultValue: 'model/gemma-4-E2B-it-final.litertlm',
      );
    }
    return const String.fromEnvironment(
      'LITERT_MODEL_PATH',
      defaultValue:
          '/sdcard/Android/data/com.example.oral_cancer/files/models/gemma-4-E2B-it-final.litertlm',
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _modelPathController.dispose();
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

  Future<void> _toggleRecording(OralSite site) async {
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
      if (_recordingSiteId == site.id && controller.value.isRecordingVideo) {
        final file = await controller.stopVideoRecording();
        setState(() {
          _capturePaths[site.id] = file.path;
          _recordingSiteId = null;
        });
      } else {
        if (controller.value.isRecordingVideo) {
          throw StateError('Stop the current site recording first.');
        }
        await controller.startVideoRecording();
        setState(() => _recordingSiteId = site.id);
      }
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _pickDesktopImage(OralSite site) async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'images',
          extensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp'],
        ),
      ],
      confirmButtonText: 'Select image',
    );
    if (file == null) {
      debugPrint('Desktop image selection cancelled for ${site.id}');
      return;
    }
    if (!File(file.path).existsSync()) {
      setState(() => _error = 'Image does not exist: ${file.path}');
      return;
    }
    debugPrint('Desktop image selected for ${site.id}: ${file.path}');
    setState(() {
      _capturePaths[site.id] = file.path;
      _error = null;
    });
  }

  Future<void> _analyze() async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Preparing videos';
    });
    try {
      final modelPath = _modelPathController.text.trim();
      if (modelPath.isEmpty && !_isDesktop) {
        throw StateError('LiteRT model path is required.');
      }
      final visitId = const Uuid().v4();
      const extractor = FrameExtractor();
      const selector = FrameSelector();
      final selectedSites = <CapturedSiteFrames>[];
      if (_isDesktop) {
        if (_capturePaths.isEmpty) {
          throw StateError('Select at least one image for desktop analysis.');
        }
        final fallbackPath = _capturePaths.values.first;
        for (final site in oralSites) {
          final imagePath = _capturePaths[site.id] ?? fallbackPath;
          selectedSites.add(
            CapturedSiteFrames(
              siteId: site.id,
              siteLabel: site.label,
              framePaths: [imagePath],
              roiPath: imagePath,
              createdAt: DateTime.now().toUtc(),
            ),
          );
        }
      } else {
        final capturedSites = oralSites.map((site) {
          final videoPath = _capturePaths[site.id];
          if (videoPath == null) {
            throw StateError('Missing video capture for ${site.label}.');
          }
          return MapEntry(site, videoPath);
        }).toList();
        for (final entry in capturedSites) {
          debugPrint(
            'Extracting frames for ${entry.key.id} from ${entry.value}',
          );
          setState(() => _progress = 'Extracting ${entry.key.label}');
          final frames = await extractor.extractFrames(
            videoPath: entry.value,
            visitId: visitId,
            siteId: entry.key.id,
            framesPerSecond: 1,
          );
          debugPrint(
            'Selecting frames for ${entry.key.id}: ${frames.length} extracted',
          );
          setState(() => _progress = 'Selecting ${entry.key.label}');
          final selected = selector.selectBestFrames(frames, count: 3);
          selectedSites.add(
            CapturedSiteFrames(
              siteId: entry.key.id,
              siteLabel: entry.key.label,
              framePaths: selected,
              roiPath: selected.first,
              createdAt: DateTime.now().toUtc(),
            ),
          );
        }
      }
      final database = LocalDatabase();
      setState(() => _progress = 'Running LiteRT assessment');
      final analyzer = LesionAnalyzer(
        gemmaService: GemmaServiceFactory.create(modelPath: modelPath),
        database: database,
      );
      final assessment = await analyzer.analyze(
        clinicalRecord: widget.clinicalRecord,
        capturedSites: selectedSites,
        previousMeasurements: const [],
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
    final complete = _isDesktop
        ? _capturePaths.isNotEmpty
        : _capturePaths.length == oralSites.length && _recordingSiteId == null;
    return Scaffold(
      appBar: AppBar(title: Text(_isDesktop ? 'Desktop capture' : 'Capture')),
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
                    'Desktop mode: select one or more oral images. '
                    'If some sites are missing, the first selected image is reused for those sites.',
                  ),
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _modelPathController,
                decoration: const InputDecoration(
                  labelText: 'LiteRT model path',
                  hintText: '/sdcard/Download/model.litertlm',
                ),
              ),
              const SizedBox(height: 12),
              for (final site in oralSites)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(site.label),
                  subtitle: Text(
                    _recordingSiteId == site.id
                        ? 'Recording'
                        : _capturePaths.containsKey(site.id)
                        ? _isDesktop
                              ? 'Image selected'
                              : 'Video saved'
                        : 'Pending',
                  ),
                  trailing: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _isDesktop
                              ? _pickDesktopImage(site)
                              : _toggleRecording(site),
                    child: Text(
                      _isDesktop
                          ? (_capturePaths.containsKey(site.id)
                                ? 'Change'
                                : 'Select')
                          : _recordingSiteId == site.id
                          ? 'Stop'
                          : 'Record',
                    ),
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
    final badgeColor = entry.category.isEmpty
        ? theme.colorScheme.outline
        : isReview
        ? Colors.red
        : Colors.teal;
    final badgeLabel = entry.category.isEmpty
        ? 'Unparsed'
        : isReview
        ? 'Review'
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
