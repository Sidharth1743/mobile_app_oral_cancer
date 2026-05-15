// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Kannada (`kn`).
class AppLocalizationsKn extends AppLocalizations {
  AppLocalizationsKn([String locale = 'kn']) : super(locale);

  @override
  String get appTitle => 'ಬಾಯಿ ಕ್ಯಾನ್ಸರ್';

  @override
  String get chooseLanguageTitle => 'ಭಾಷೆ ಆಯ್ಕೆಮಾಡಿ';

  @override
  String get chooseLanguageSubtitle =>
      'ಅ್ಯಪ್‌ಗೆ ಬಳಸುವ ಭಾಷೆಯನ್ನು ಆಯ್ಕೆಮಾಡಿ. Gemma ಕೂಡ ಸ್ಕ್ರೀನಿಂಗ್ ವಿವರಣೆಯನ್ನು ಇದೇ ಭಾಷೆಯಲ್ಲಿ ನೀಡುತ್ತದೆ.';

  @override
  String get continueButton => 'ಮುಂದುವರಿಸಿ';

  @override
  String get saveButton => 'ಉಳಿಸಿ';

  @override
  String get changeLanguage => 'ಭಾಷೆ ಬದಲಿಸಿ';

  @override
  String get screeningNav => 'ಸ್ಕ್ರೀನಿಂಗ್';

  @override
  String get operationsNav => 'ಕಾರ್ಯಾಚರಣೆಗಳು';

  @override
  String get queueNav => 'ಕ್ಯೂ';

  @override
  String get screeningIntakeTitle => 'ಸ್ಕ್ರೀನಿಂಗ್ ವಿವರಗಳು';

  @override
  String get nameLabel => 'ಹೆಸರು';

  @override
  String get villageLabel => 'ಗ್ರಾಮ / ಪ್ರದೇಶ';

  @override
  String get stateLabel => 'ರಾಜ್ಯ';

  @override
  String get districtLabel => 'ಜಿಲ್ಲೆ';

  @override
  String get dateOfBirthLabel => 'ಜನ್ಮ ದಿನಾಂಕ';

  @override
  String get phoneLabel => 'ಫೋನ್';

  @override
  String get pinCodeLabel => 'ಪಿನ್ ಕೋಡ್';

  @override
  String get ashaPinLabel => 'ಆಶಾ ಪಿನ್';

  @override
  String get genderLabel => 'ಲಿಂಗ';

  @override
  String get femaleLabel => 'ಮಹಿಳೆ';

  @override
  String get maleLabel => 'ಪುರುಷ';

  @override
  String get otherLabel => 'ಇತರೆ';

  @override
  String get tobaccoBrandLabel => 'ತಂಬಾಕು ಬ್ರ್ಯಾಂಡ್';

  @override
  String get chewsPerDayLabel => 'ದಿನಕ್ಕೆ ಚಪ್ಪರಿಸುವ ಸಂಖ್ಯೆ';

  @override
  String get yearsUsedLabel => 'ಬಳಸಿದ ವರ್ಷಗಳು';

  @override
  String get alcoholUseLabel => 'ಮದ್ಯ ಬಳಕೆ';

  @override
  String get savingLabel => 'ಉಳಿಸಲಾಗುತ್ತಿದೆ';

  @override
  String get requiredError => 'ಅಗತ್ಯ';

  @override
  String get numberRequiredError => 'ಸಂಖ್ಯೆ ಅಗತ್ಯ';

  @override
  String locationDataUnavailable(Object error) {
    return 'ಸ್ಥಳದ ಡೇಟಾ ಲಭ್ಯವಿಲ್ಲ: $error';
  }

  @override
  String get captureVideoTitle => 'ಬಾಯಿಯ ಒಳಗಿನ ವೀಡಿಯೊ ಹಿಡಿಯಿರಿ';

  @override
  String get desktopModeInstructions =>
      'ಡೆಸ್ಕ್‌ಟಾಪ್ ಮೋಡ್: ಒಂದು ಇಂಟ್ರಾಓರಲ್ ವೀಡಿಯೊ ಆಯ್ಕೆಮಾಡಿ. ಸ್ಥಳೀಯ ಸ್ಕ್ರೀನಿಂಗ್‌ಗಾಗಿ ಅ್ಯಪ್ ಪ್ರತಿನಿಧಿ ಫ್ರೇಮ್‌ಗಳನ್ನು ಆಯ್ಕೆಮಾಡುತ್ತದೆ.';

  @override
  String get intraoralVideoLabel => 'ಇಂಟ್ರಾಓರಲ್ ವೀಡಿಯೊ';

  @override
  String get recordingLiveVideo => 'ಲೈವ್ ವೀಡಿಯೊ ರೆಕಾರ್ಡ್ ಆಗುತ್ತಿದೆ';

  @override
  String get noVideoSelected => 'ಯಾವುದೇ ವೀಡಿಯೊ ಆಯ್ಕೆಮಾಡಿಲ್ಲ';

  @override
  String selectedVideo(Object fileName) {
    return 'ಆಯ್ಕೆಮಾಡಿದುದು: $fileName';
  }

  @override
  String get stopButton => 'ನಿಲ್ಲಿಸಿ';

  @override
  String get recordLiveButton => 'ಲೈವ್ ರೆಕಾರ್ಡ್';

  @override
  String get uploadVideoButton => 'ವೀಡಿಯೊ ಅಪ್‌ಲೋಡ್';

  @override
  String get changeUploadedVideoButton => 'ಅಪ್‌ಲೋಡ್ ಮಾಡಿದ ವೀಡಿಯೊ ಬದಲಿಸಿ';

  @override
  String get selectVideoButton => 'ವೀಡಿಯೊ ಆಯ್ಕೆಮಾಡಿ';

  @override
  String get fixedModelPathNotice =>
      'LiteRT ಮಾದರಿ ಪಥವನ್ನು ಅ್ಯಪ್ ಸಂರಚನೆಯಿಂದ ನಿಗದಿಪಡಿಸಲಾಗಿದೆ; ಸ್ಕ್ರೀನಿಂಗ್ ಸಮಯದಲ್ಲಿ ಮಾದರಿ ಆಯ್ಕೆ ಅಗತ್ಯವಿಲ್ಲ.';

  @override
  String get analyzeButton => 'ವಿಶ್ಲೇಷಿಸಿ';

  @override
  String get analyzingLabel => 'ವಿಶ್ಲೇಷಿಸಲಾಗುತ್ತಿದೆ';

  @override
  String get preparingVideosProgress => 'ವೀಡಿಯೊ ಸಿದ್ಧಪಡಿಸಲಾಗುತ್ತಿದೆ';

  @override
  String get extractingFramesProgress =>
      'ವೀಡಿಯೊ ಫ್ರೇಮ್‌ಗಳನ್ನು ತೆಗೆದುಕೊಳ್ಳಲಾಗುತ್ತಿದೆ';

  @override
  String get selectingFramesProgress =>
      'ಪ್ರತಿನಿಧಿ ಫ್ರೇಮ್‌ಗಳನ್ನು ಆಯ್ಕೆಮಾಡಲಾಗುತ್ತಿದೆ';

  @override
  String runningTriageProgress(int count) {
    return 'YOLO + Gemma ಟ್ರಯಾಜ್ ನಡೆಯುತ್ತಿದೆ ($count ಫ್ರೇಮ್‌ಗಳು)';
  }

  @override
  String get cameraUnavailableError => 'ಈ ಸಾಧನದಲ್ಲಿ ಕ್ಯಾಮೆರಾ ಲಭ್ಯವಿಲ್ಲ.';

  @override
  String get cameraNotReadyError => 'ಕ್ಯಾಮೆರಾ ಸಿದ್ಧವಾಗಿಲ್ಲ.';

  @override
  String get stopCurrentRecordingError =>
      'ಮೊದಲು ಪ್ರಸ್ತುತ ರೆಕಾರ್ಡಿಂಗ್ ನಿಲ್ಲಿಸಿ.';

  @override
  String videoMissingError(Object path) {
    return 'ವೀಡಿಯೊ ಇಲ್ಲ: $path';
  }

  @override
  String get modelPathRequiredError => 'LiteRT ಮಾದರಿ ಪಥ ಅಗತ್ಯ.';

  @override
  String get yoloPathRequiredError => 'YOLO ಮಾದರಿ ಪಥ ಅಗತ್ಯ.';

  @override
  String get recordOrSelectVideoError =>
      'ಮೊದಲು ಒಂದು ಇಂಟ್ರಾಓರಲ್ ವೀಡಿಯೊ ರೆಕಾರ್ಡ್ ಮಾಡಿ ಅಥವಾ ಆಯ್ಕೆಮಾಡಿ.';

  @override
  String get resultTitle => 'ಫಲಿತಾಂಶ';

  @override
  String get ashaViewButton => 'ಆಶಾ ದೃಶ್ಯ';

  @override
  String get consentSharingButton => 'ಸಮ್ಮತಿ ಮತ್ತು ಹಂಚಿಕೆ';

  @override
  String get translateLocallyButton => 'ಸ್ಥಳೀಯ ಅನುವಾದ';

  @override
  String get treatmentTrackingButton => 'ಚಿಕಿತ್ಸೆ ಟ್ರ್ಯಾಕಿಂಗ್';

  @override
  String get rawModelOutputTitle => 'ಕಚ್ಚಾ ಮಾದರಿ ಔಟ್‌ಪುಟ್';

  @override
  String rawModelOutputSubtitle(int count) {
    return 'ಸ್ಥಳೀಯ LiteRT ನಿಂದ $count ಸೈಟ್ ಪ್ರತಿಕ್ರಿಯೆಗಳು';
  }

  @override
  String get unparsedBadge => 'ಪಾರ್ಸ್ ಆಗಿಲ್ಲ';

  @override
  String get reviewBadge => 'ಪರಿಶೀಲನೆ';

  @override
  String get recaptureBadge => 'ಮತ್ತೆ ಹಿಡಿಯಿರಿ';

  @override
  String get lowRiskBadge => 'ಕಡಿಮೆ ಅಪಾಯ';

  @override
  String get rawLocalModelResponse => 'ಕಚ್ಚಾ ಸ್ಥಳೀಯ ಮಾದರಿ ಪ್ರತಿಕ್ರಿಯೆ';

  @override
  String get ashaSummaryTitle => 'ಆಶಾ ಸಾರಾಂಶ';

  @override
  String rescreenDate(Object date) {
    return 'ಮತ್ತೆ ಸ್ಕ್ರೀನಿಂಗ್ $date';
  }

  @override
  String get progressButton => 'ಪ್ರಗತಿ';

  @override
  String get gemmaLanguageName => 'Kannada';
}
