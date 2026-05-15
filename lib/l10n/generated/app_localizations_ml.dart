// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Malayalam (`ml`).
class AppLocalizationsMl extends AppLocalizations {
  AppLocalizationsMl([String locale = 'ml']) : super(locale);

  @override
  String get appTitle => 'വായിലെ കാൻസർ';

  @override
  String get chooseLanguageTitle => 'ഭാഷ തിരഞ്ഞെടുക്കുക';

  @override
  String get chooseLanguageSubtitle =>
      'ആപ്പിൽ ഉപയോഗിക്കേണ്ട ഭാഷ തിരഞ്ഞെടുക്കുക. Gemma സ്ക്രീനിംഗ് വിശദീകരണവും ഇതേ ഭാഷയിൽ നൽകും.';

  @override
  String get continueButton => 'തുടരുക';

  @override
  String get saveButton => 'സേവ് ചെയ്യുക';

  @override
  String get changeLanguage => 'ഭാഷ മാറ്റുക';

  @override
  String get screeningNav => 'സ്ക്രീനിംഗ്';

  @override
  String get operationsNav => 'ഓപ്പറേഷനുകൾ';

  @override
  String get queueNav => 'ക്യൂ';

  @override
  String get screeningIntakeTitle => 'സ്ക്രീനിംഗ് വിവരങ്ങൾ';

  @override
  String get nameLabel => 'പേര്';

  @override
  String get villageLabel => 'ഗ്രാമം / പ്രദേശം';

  @override
  String get stateLabel => 'സംസ്ഥാനം';

  @override
  String get districtLabel => 'ജില്ല';

  @override
  String get dateOfBirthLabel => 'ജനന തീയതി';

  @override
  String get phoneLabel => 'ഫോൺ';

  @override
  String get pinCodeLabel => 'പിൻ കോഡ്';

  @override
  String get ashaPinLabel => 'ആശ പിൻ';

  @override
  String get genderLabel => 'ലിംഗം';

  @override
  String get femaleLabel => 'സ്ത്രീ';

  @override
  String get maleLabel => 'പുരുഷൻ';

  @override
  String get otherLabel => 'മറ്റുള്ളവ';

  @override
  String get tobaccoBrandLabel => 'തമ്പാകു ബ്രാൻഡ്';

  @override
  String get chewsPerDayLabel => 'ദിവസേന ചവയ്ക്കുന്ന എണ്ണം';

  @override
  String get yearsUsedLabel => 'ഉപയോഗിച്ച വർഷങ്ങൾ';

  @override
  String get alcoholUseLabel => 'മദ്യ ഉപയോഗം';

  @override
  String get savingLabel => 'സേവ് ചെയ്യുന്നു';

  @override
  String get requiredError => 'ആവശ്യമാണ്';

  @override
  String get numberRequiredError => 'നമ്പർ ആവശ്യമാണ്';

  @override
  String locationDataUnavailable(Object error) {
    return 'സ്ഥല വിവരങ്ങൾ ലഭ്യമല്ല: $error';
  }

  @override
  String get captureVideoTitle => 'വായ്ക്കുള്ളിലെ വീഡിയോ എടുക്കുക';

  @override
  String get desktopModeInstructions =>
      'ഡെസ്ക്ടോപ്പ് മോഡ്: ഒരു ഇൻട്രാഓറൽ വീഡിയോ തിരഞ്ഞെടുക്കുക. പ്രാദേശിക സ്ക്രീനിംഗിനായി ആപ്പ് പ്രതിനിധി ഫ്രെയിമുകൾ തിരഞ്ഞെടുക്കും.';

  @override
  String get intraoralVideoLabel => 'ഇൻട്രാഓറൽ വീഡിയോ';

  @override
  String get recordingLiveVideo => 'ലൈവ് വീഡിയോ റെക്കോർഡ് ചെയ്യുന്നു';

  @override
  String get noVideoSelected => 'വീഡിയോ തിരഞ്ഞെടുത്തിട്ടില്ല';

  @override
  String selectedVideo(Object fileName) {
    return 'തിരഞ്ഞെടുത്തത്: $fileName';
  }

  @override
  String get stopButton => 'നിർത്തുക';

  @override
  String get recordLiveButton => 'ലൈവ് റെക്കോർഡ്';

  @override
  String get uploadVideoButton => 'വീഡിയോ അപ്‌ലോഡ്';

  @override
  String get changeUploadedVideoButton => 'അപ്‌ലോഡ് ചെയ്ത വീഡിയോ മാറ്റുക';

  @override
  String get selectVideoButton => 'വീഡിയോ തിരഞ്ഞെടുക്കുക';

  @override
  String get fixedModelPathNotice =>
      'LiteRT മോഡൽ പാത ആപ്പ് കോൺഫിഗറേഷനിൽ നിശ്ചയിച്ചിരിക്കുന്നു; സ്ക്രീനിംഗിനിടെ മോഡൽ തിരഞ്ഞെടുക്കേണ്ടതില്ല.';

  @override
  String get analyzeButton => 'വിശകലനം ചെയ്യുക';

  @override
  String get analyzingLabel => 'വിശകലനം ചെയ്യുന്നു';

  @override
  String get preparingVideosProgress => 'വീഡിയോ തയ്യാറാക്കുന്നു';

  @override
  String get extractingFramesProgress => 'വീഡിയോ ഫ്രെയിമുകൾ എടുക്കുന്നു';

  @override
  String get selectingFramesProgress =>
      'പ്രതിനിധി ഫ്രെയിമുകൾ തിരഞ്ഞെടുക്കുന്നു';

  @override
  String runningTriageProgress(int count) {
    return 'YOLO + Gemma ട്രയാജ് നടക്കുന്നു ($count ഫ്രെയിമുകൾ)';
  }

  @override
  String get cameraUnavailableError => 'ഈ ഉപകരണത്തിൽ ക്യാമറ ലഭ്യമല്ല.';

  @override
  String get cameraNotReadyError => 'ക്യാമറ തയ്യാറല്ല.';

  @override
  String get stopCurrentRecordingError =>
      'ആദ്യം നിലവിലുള്ള റെക്കോർഡിംഗ് നിർത്തുക.';

  @override
  String videoMissingError(Object path) {
    return 'വീഡിയോ ഇല്ല: $path';
  }

  @override
  String get modelPathRequiredError => 'LiteRT മോഡൽ പാത ആവശ്യമാണ്.';

  @override
  String get yoloPathRequiredError => 'YOLO മോഡൽ പാത ആവശ്യമാണ്.';

  @override
  String get recordOrSelectVideoError =>
      'ആദ്യം ഒരു ഇൻട്രാഓറൽ വീഡിയോ റെക്കോർഡ് ചെയ്യുകയോ തിരഞ്ഞെടുക്കുകയോ ചെയ്യുക.';

  @override
  String get resultTitle => 'ഫലം';

  @override
  String get ashaViewButton => 'ആശ കാഴ്ച';

  @override
  String get consentSharingButton => 'സമ്മതവും പങ്കിടലും';

  @override
  String get translateLocallyButton => 'പ്രാദേശിക വിവർത്തനം';

  @override
  String get treatmentTrackingButton => 'ചികിത്സ ട്രാക്കിംഗ്';

  @override
  String get rawModelOutputTitle => 'റോ മോഡൽ ഔട്ട്പുട്ട്';

  @override
  String rawModelOutputSubtitle(int count) {
    return 'പ്രാദേശിക LiteRT-ൽ നിന്ന് $count സൈറ്റ് പ്രതികരണങ്ങൾ';
  }

  @override
  String get unparsedBadge => 'പാർസ് ചെയ്തില്ല';

  @override
  String get reviewBadge => 'റിവ്യൂ';

  @override
  String get recaptureBadge => 'വീണ്ടും എടുക്കുക';

  @override
  String get lowRiskBadge => 'കുറഞ്ഞ അപകടം';

  @override
  String get rawLocalModelResponse => 'റോ പ്രാദേശിക മോഡൽ പ്രതികരണം';

  @override
  String get ashaSummaryTitle => 'ആശ സംഗ്രഹം';

  @override
  String rescreenDate(Object date) {
    return 'വീണ്ടും സ്ക്രീനിംഗ് $date';
  }

  @override
  String get progressButton => 'പുരോഗതി';

  @override
  String get gemmaLanguageName => 'Malayalam';
}
