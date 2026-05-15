// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Oral Cancer';

  @override
  String get chooseLanguageTitle => 'Choose language';

  @override
  String get chooseLanguageSubtitle =>
      'Select the language used for the app. Gemma will also return the screening explanation in this language.';

  @override
  String get continueButton => 'Continue';

  @override
  String get saveButton => 'Save';

  @override
  String get changeLanguage => 'Change language';

  @override
  String get screeningNav => 'Screening';

  @override
  String get operationsNav => 'Operations';

  @override
  String get queueNav => 'Queue';

  @override
  String get screeningIntakeTitle => 'Screening intake';

  @override
  String get nameLabel => 'Name';

  @override
  String get villageLabel => 'Village / area';

  @override
  String get stateLabel => 'State';

  @override
  String get districtLabel => 'District';

  @override
  String get dateOfBirthLabel => 'Date of birth';

  @override
  String get phoneLabel => 'Phone';

  @override
  String get pinCodeLabel => 'PIN code';

  @override
  String get ashaPinLabel => 'ASHA PIN';

  @override
  String get genderLabel => 'Gender';

  @override
  String get femaleLabel => 'Female';

  @override
  String get maleLabel => 'Male';

  @override
  String get otherLabel => 'Other';

  @override
  String get tobaccoBrandLabel => 'Tobacco brand';

  @override
  String get chewsPerDayLabel => 'Chews per day';

  @override
  String get yearsUsedLabel => 'Years used';

  @override
  String get alcoholUseLabel => 'Alcohol use';

  @override
  String get savingLabel => 'Saving';

  @override
  String get requiredError => 'Required';

  @override
  String get numberRequiredError => 'Number required';

  @override
  String locationDataUnavailable(Object error) {
    return 'Location data unavailable: $error';
  }

  @override
  String get captureVideoTitle => 'Capture intraoral video';

  @override
  String get desktopModeInstructions =>
      'Desktop mode: select one intraoral video. The app will sample representative frames for local screening.';

  @override
  String get intraoralVideoLabel => 'Intraoral video';

  @override
  String get recordingLiveVideo => 'Recording live video';

  @override
  String get noVideoSelected => 'No video selected';

  @override
  String selectedVideo(Object fileName) {
    return 'Selected: $fileName';
  }

  @override
  String get stopButton => 'Stop';

  @override
  String get recordLiveButton => 'Record live';

  @override
  String get uploadVideoButton => 'Upload video';

  @override
  String get changeUploadedVideoButton => 'Change uploaded video';

  @override
  String get selectVideoButton => 'Select video';

  @override
  String get fixedModelPathNotice =>
      'The LiteRT model path is fixed by app configuration; no model selection is required during screening.';

  @override
  String get analyzeButton => 'Analyze';

  @override
  String get analyzingLabel => 'Analyzing';

  @override
  String get preparingVideosProgress => 'Preparing videos';

  @override
  String get extractingFramesProgress => 'Extracting video frames';

  @override
  String get selectingFramesProgress => 'Selecting representative frames';

  @override
  String runningTriageProgress(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count frames',
      one: '1 frame',
    );
    return 'Running YOLO + Gemma triage ($_temp0)';
  }

  @override
  String get cameraUnavailableError => 'No camera is available on this device.';

  @override
  String get cameraNotReadyError => 'Camera is not ready.';

  @override
  String get stopCurrentRecordingError => 'Stop the current recording first.';

  @override
  String videoMissingError(Object path) {
    return 'Video does not exist: $path';
  }

  @override
  String get modelPathRequiredError => 'LiteRT model path is required.';

  @override
  String get yoloPathRequiredError => 'YOLO model path is required.';

  @override
  String get recordOrSelectVideoError =>
      'Record or select one intraoral video first.';

  @override
  String get resultTitle => 'Result';

  @override
  String get ashaViewButton => 'ASHA view';

  @override
  String get consentSharingButton => 'Consent and sharing';

  @override
  String get translateLocallyButton => 'Translate locally';

  @override
  String get treatmentTrackingButton => 'Treatment tracking';

  @override
  String get rawModelOutputTitle => 'Raw model output';

  @override
  String rawModelOutputSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count site responses from local LiteRT',
      one: '1 site response from local LiteRT',
    );
    return '$_temp0';
  }

  @override
  String get unparsedBadge => 'Unparsed';

  @override
  String get reviewBadge => 'Review';

  @override
  String get recaptureBadge => 'Recapture';

  @override
  String get lowRiskBadge => 'Low risk';

  @override
  String get rawLocalModelResponse => 'Raw local model response';

  @override
  String get ashaSummaryTitle => 'ASHA summary';

  @override
  String rescreenDate(Object date) {
    return 'Rescreen $date';
  }

  @override
  String get progressButton => 'Progress';

  @override
  String get gemmaLanguageName => 'English';
}
