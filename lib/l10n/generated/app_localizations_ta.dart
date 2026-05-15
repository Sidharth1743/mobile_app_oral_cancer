// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Tamil (`ta`).
class AppLocalizationsTa extends AppLocalizations {
  AppLocalizationsTa([String locale = 'ta']) : super(locale);

  @override
  String get appTitle => 'வாய் புற்றுநோய்';

  @override
  String get chooseLanguageTitle => 'மொழியைத் தேர்ந்தெடுக்கவும்';

  @override
  String get chooseLanguageSubtitle =>
      'பயன்பாட்டின் மொழியைத் தேர்ந்தெடுக்கவும். Gemma திரையிடல் விளக்கத்தையும் இதே மொழியில் தரும்.';

  @override
  String get continueButton => 'தொடரவும்';

  @override
  String get saveButton => 'சேமிக்கவும்';

  @override
  String get changeLanguage => 'மொழி மாற்று';

  @override
  String get screeningNav => 'திரையிடல்';

  @override
  String get operationsNav => 'செயல்பாடுகள்';

  @override
  String get queueNav => 'வரிசை';

  @override
  String get screeningIntakeTitle => 'திரையிடல் விவரங்கள்';

  @override
  String get nameLabel => 'பெயர்';

  @override
  String get villageLabel => 'கிராமம் / பகுதி';

  @override
  String get stateLabel => 'மாநிலம்';

  @override
  String get districtLabel => 'மாவட்டம்';

  @override
  String get dateOfBirthLabel => 'பிறந்த தேதி';

  @override
  String get phoneLabel => 'தொலைபேசி';

  @override
  String get pinCodeLabel => 'பின் குறியீடு';

  @override
  String get ashaPinLabel => 'ஆஷா பின்';

  @override
  String get genderLabel => 'பாலினம்';

  @override
  String get femaleLabel => 'பெண்';

  @override
  String get maleLabel => 'ஆண்';

  @override
  String get otherLabel => 'மற்றவை';

  @override
  String get tobaccoBrandLabel => 'புகையிலை பிராண்ட்';

  @override
  String get chewsPerDayLabel => 'ஒரு நாளில் மெல்லும் எண்ணிக்கை';

  @override
  String get yearsUsedLabel => 'பயன்படுத்திய ஆண்டுகள்';

  @override
  String get alcoholUseLabel => 'மது பயன்பாடு';

  @override
  String get savingLabel => 'சேமிக்கிறது';

  @override
  String get requiredError => 'தேவை';

  @override
  String get numberRequiredError => 'எண் தேவை';

  @override
  String locationDataUnavailable(Object error) {
    return 'இடத் தரவு கிடைக்கவில்லை: $error';
  }

  @override
  String get captureVideoTitle => 'வாய் உள்ளக வீடியோ பதிவு';

  @override
  String get desktopModeInstructions =>
      'டெஸ்க்டாப் முறை: ஒரு வாய் உள்ளக வீடியோவைத் தேர்ந்தெடுக்கவும். உள்ளூர் திரையிடலுக்காக பயன்பாடு பிரதிநிதி ஃப்ரேம்களைத் தேர்வு செய்யும்.';

  @override
  String get intraoralVideoLabel => 'வாய் உள்ளக வீடியோ';

  @override
  String get recordingLiveVideo => 'நேரடி வீடியோ பதிவு செய்யப்படுகிறது';

  @override
  String get noVideoSelected => 'வீடியோ தேர்ந்தெடுக்கப்படவில்லை';

  @override
  String selectedVideo(Object fileName) {
    return 'தேர்ந்தெடுக்கப்பட்டது: $fileName';
  }

  @override
  String get stopButton => 'நிறுத்து';

  @override
  String get recordLiveButton => 'நேரடி பதிவு';

  @override
  String get uploadVideoButton => 'வீடியோ பதிவேற்று';

  @override
  String get changeUploadedVideoButton => 'பதிவேற்றிய வீடியோ மாற்று';

  @override
  String get selectVideoButton => 'வீடியோ தேர்வு';

  @override
  String get fixedModelPathNotice =>
      'LiteRT மாதிரி பாதை பயன்பாட்டு அமைப்பில் நிர்ணயிக்கப்பட்டுள்ளது; திரையிடலின் போது மாதிரி தேர்வு தேவையில்லை.';

  @override
  String get analyzeButton => 'ஆய்வு செய்';

  @override
  String get analyzingLabel => 'ஆய்வு செய்கிறது';

  @override
  String get preparingVideosProgress => 'வீடியோ தயாராகிறது';

  @override
  String get extractingFramesProgress => 'வீடியோ ஃப்ரேம்கள் எடுக்கப்படுகின்றன';

  @override
  String get selectingFramesProgress =>
      'பிரதிநிதி ஃப்ரேம்கள் தேர்வு செய்யப்படுகின்றன';

  @override
  String runningTriageProgress(int count) {
    return 'YOLO + Gemma ஆய்வு நடக்கிறது ($count ஃப்ரேம்கள்)';
  }

  @override
  String get cameraUnavailableError => 'இந்த சாதனத்தில் கேமரா இல்லை.';

  @override
  String get cameraNotReadyError => 'கேமரா தயாராக இல்லை.';

  @override
  String get stopCurrentRecordingError => 'முதலில் தற்போதைய பதிவை நிறுத்தவும்.';

  @override
  String videoMissingError(Object path) {
    return 'வீடியோ இல்லை: $path';
  }

  @override
  String get modelPathRequiredError => 'LiteRT மாதிரி பாதை தேவை.';

  @override
  String get yoloPathRequiredError => 'YOLO மாதிரி பாதை தேவை.';

  @override
  String get recordOrSelectVideoError =>
      'முதலில் ஒரு வாய் உள்ளக வீடியோவை பதிவு செய்யவும் அல்லது தேர்வு செய்யவும்.';

  @override
  String get resultTitle => 'முடிவு';

  @override
  String get ashaViewButton => 'ஆஷா காட்சி';

  @override
  String get consentSharingButton => 'ஒப்புதல் மற்றும் பகிர்வு';

  @override
  String get translateLocallyButton => 'உள்ளூர் மொழிபெயர்ப்பு';

  @override
  String get treatmentTrackingButton => 'சிகிச்சை கண்காணிப்பு';

  @override
  String get rawModelOutputTitle => 'மூல மாதிரி வெளியீடு';

  @override
  String rawModelOutputSubtitle(int count) {
    return 'உள்ளூர் LiteRT இலிருந்து $count தள பதில்கள்';
  }

  @override
  String get unparsedBadge => 'பார்ஸ் ஆகவில்லை';

  @override
  String get reviewBadge => 'மதிப்பாய்வு';

  @override
  String get recaptureBadge => 'மீண்டும் பதிவு';

  @override
  String get lowRiskBadge => 'குறைந்த ஆபத்து';

  @override
  String get rawLocalModelResponse => 'மூல உள்ளூர் மாதிரி பதில்';

  @override
  String get ashaSummaryTitle => 'ஆஷா சுருக்கம்';

  @override
  String rescreenDate(Object date) {
    return 'மீண்டும் திரையிடல் $date';
  }

  @override
  String get progressButton => 'முன்னேற்றம்';

  @override
  String get gemmaLanguageName => 'Tamil';
}
