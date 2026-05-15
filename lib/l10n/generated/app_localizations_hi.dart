// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appTitle => 'मौखिक कैंसर';

  @override
  String get chooseLanguageTitle => 'भाषा चुनें';

  @override
  String get chooseLanguageSubtitle =>
      'ऐप की भाषा चुनें। Gemma स्क्रीनिंग की व्याख्या भी इसी भाषा में देगा।';

  @override
  String get continueButton => 'जारी रखें';

  @override
  String get saveButton => 'सहेजें';

  @override
  String get changeLanguage => 'भाषा बदलें';

  @override
  String get screeningNav => 'स्क्रीनिंग';

  @override
  String get operationsNav => 'संचालन';

  @override
  String get queueNav => 'कतार';

  @override
  String get screeningIntakeTitle => 'स्क्रीनिंग विवरण';

  @override
  String get nameLabel => 'नाम';

  @override
  String get villageLabel => 'गांव / क्षेत्र';

  @override
  String get stateLabel => 'राज्य';

  @override
  String get districtLabel => 'जिला';

  @override
  String get dateOfBirthLabel => 'जन्म तिथि';

  @override
  String get phoneLabel => 'फोन';

  @override
  String get pinCodeLabel => 'पिन कोड';

  @override
  String get ashaPinLabel => 'आशा पिन';

  @override
  String get genderLabel => 'लिंग';

  @override
  String get femaleLabel => 'महिला';

  @override
  String get maleLabel => 'पुरुष';

  @override
  String get otherLabel => 'अन्य';

  @override
  String get tobaccoBrandLabel => 'तंबाकू ब्रांड';

  @override
  String get chewsPerDayLabel => 'प्रतिदिन चबाने की संख्या';

  @override
  String get yearsUsedLabel => 'उपयोग के वर्ष';

  @override
  String get alcoholUseLabel => 'शराब का उपयोग';

  @override
  String get savingLabel => 'सहेजा जा रहा है';

  @override
  String get requiredError => 'आवश्यक';

  @override
  String get numberRequiredError => 'संख्या आवश्यक है';

  @override
  String locationDataUnavailable(Object error) {
    return 'स्थान डेटा उपलब्ध नहीं: $error';
  }

  @override
  String get captureVideoTitle => 'मुंह के अंदर का वीडियो लें';

  @override
  String get desktopModeInstructions =>
      'डेस्कटॉप मोड: एक इंट्राओरल वीडियो चुनें। ऐप स्थानीय स्क्रीनिंग के लिए प्रतिनिधि फ्रेम चुनेगा।';

  @override
  String get intraoralVideoLabel => 'इंट्राओरल वीडियो';

  @override
  String get recordingLiveVideo => 'लाइव वीडियो रिकॉर्ड हो रहा है';

  @override
  String get noVideoSelected => 'कोई वीडियो चयनित नहीं';

  @override
  String selectedVideo(Object fileName) {
    return 'चयनित: $fileName';
  }

  @override
  String get stopButton => 'रोकें';

  @override
  String get recordLiveButton => 'लाइव रिकॉर्ड करें';

  @override
  String get uploadVideoButton => 'वीडियो अपलोड करें';

  @override
  String get changeUploadedVideoButton => 'अपलोड किया वीडियो बदलें';

  @override
  String get selectVideoButton => 'वीडियो चुनें';

  @override
  String get fixedModelPathNotice =>
      'LiteRT मॉडल पथ ऐप कॉन्फ़िगरेशन से तय है; स्क्रीनिंग के दौरान मॉडल चुनने की आवश्यकता नहीं है।';

  @override
  String get analyzeButton => 'विश्लेषण करें';

  @override
  String get analyzingLabel => 'विश्लेषण हो रहा है';

  @override
  String get preparingVideosProgress => 'वीडियो तैयार हो रहा है';

  @override
  String get extractingFramesProgress => 'वीडियो फ्रेम निकाले जा रहे हैं';

  @override
  String get selectingFramesProgress => 'प्रतिनिधि फ्रेम चुने जा रहे हैं';

  @override
  String runningTriageProgress(int count) {
    return 'YOLO + Gemma ट्रायेज चल रहा है ($count फ्रेम)';
  }

  @override
  String get cameraUnavailableError => 'इस डिवाइस पर कैमरा उपलब्ध नहीं है।';

  @override
  String get cameraNotReadyError => 'कैमरा तैयार नहीं है।';

  @override
  String get stopCurrentRecordingError => 'पहले वर्तमान रिकॉर्डिंग रोकें।';

  @override
  String videoMissingError(Object path) {
    return 'वीडियो मौजूद नहीं है: $path';
  }

  @override
  String get modelPathRequiredError => 'LiteRT मॉडल पथ आवश्यक है।';

  @override
  String get yoloPathRequiredError => 'YOLO मॉडल पथ आवश्यक है।';

  @override
  String get recordOrSelectVideoError =>
      'पहले एक इंट्राओरल वीडियो रिकॉर्ड या चुनें।';

  @override
  String get resultTitle => 'परिणाम';

  @override
  String get ashaViewButton => 'आशा दृश्य';

  @override
  String get consentSharingButton => 'सहमति और साझा करना';

  @override
  String get translateLocallyButton => 'स्थानीय अनुवाद';

  @override
  String get treatmentTrackingButton => 'उपचार ट्रैकिंग';

  @override
  String get rawModelOutputTitle => 'कच्चा मॉडल आउटपुट';

  @override
  String rawModelOutputSubtitle(int count) {
    return 'स्थानीय LiteRT से $count साइट प्रतिक्रियाएं';
  }

  @override
  String get unparsedBadge => 'अनपार्स्ड';

  @override
  String get reviewBadge => 'समीक्षा';

  @override
  String get recaptureBadge => 'फिर से लें';

  @override
  String get lowRiskBadge => 'कम जोखिम';

  @override
  String get rawLocalModelResponse => 'कच्ची स्थानीय मॉडल प्रतिक्रिया';

  @override
  String get ashaSummaryTitle => 'आशा सारांश';

  @override
  String rescreenDate(Object date) {
    return 'फिर स्क्रीनिंग $date';
  }

  @override
  String get progressButton => 'प्रगति';

  @override
  String get gemmaLanguageName => 'Hindi';
}
