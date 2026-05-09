import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'inference/litert_gemma_service.dart';
import 'intake/date_of_birth.dart';
import 'location/indian_locations.dart';
import 'ui/app_home_screen.dart';
import 'ui/app_theme.dart';
import 'ui/screens/consent_screen.dart';
import 'ui/screens/local_translation_screen.dart';
import 'ui/screens/progress_screen.dart';
import 'ui/screens/treatment_tracking_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await const FirebaseBootstrap().initialize();
  runApp(const OralCancerApp());
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
  final Map<String, String> _videoPaths = {};
  final _modelPathController = TextEditingController(
    text: const String.fromEnvironment(
      'LITERT_MODEL_PATH',
      defaultValue:
          '/sdcard/Android/data/com.example.oral_cancer/files/models/gemma-4-E2B-it.litertlm',
    ),
  );
  String? _recordingSiteId;
  bool _busy = false;
  String? _error;
  String? _progress;

  @override
  void initState() {
    super.initState();
    _cameraInit = _initializeCamera();
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
          _videoPaths[site.id] = file.path;
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

  Future<void> _analyze() async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Preparing videos';
    });
    try {
      final modelPath = _modelPathController.text.trim();
      if (modelPath.isEmpty) {
        throw StateError('LiteRT model path is required.');
      }
      final visitId = const Uuid().v4();
      const extractor = FrameExtractor();
      const selector = FrameSelector();
      final capturedSites = oralSites.map((site) {
        final videoPath = _videoPaths[site.id];
        if (videoPath == null) {
          throw StateError('Missing video capture for ${site.label}.');
        }
        return MapEntry(site, videoPath);
      }).toList();
      final selectedSites = <CapturedSiteFrames>[];
      for (final entry in capturedSites) {
        debugPrint('Extracting frames for ${entry.key.id} from ${entry.value}');
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
      final database = LocalDatabase();
      setState(() => _progress = 'Running LiteRT assessment');
      final analyzer = LesionAnalyzer(
        gemmaService: LiteRtGemmaService(modelPath: modelPath),
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
    final complete =
        _videoPaths.length == oralSites.length && _recordingSiteId == null;
    return Scaffold(
      appBar: AppBar(title: const Text('Capture')),
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
              if (controller != null && controller.value.isInitialized)
                AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: CameraPreview(controller),
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
                        : _videoPaths.containsKey(site.id)
                        ? 'Video saved'
                        : 'Pending',
                  ),
                  trailing: OutlinedButton(
                    onPressed: _busy ? null : () => _toggleRecording(site),
                    child: Text(
                      _recordingSiteId == site.id ? 'Stop' : 'Record',
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
