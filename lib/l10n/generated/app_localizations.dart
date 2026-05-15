import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_kn.dart';
import 'app_localizations_ml.dart';
import 'app_localizations_ta.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hi'),
    Locale('kn'),
    Locale('ml'),
    Locale('ta'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Oral Cancer'**
  String get appTitle;

  /// No description provided for @chooseLanguageTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose language'**
  String get chooseLanguageTitle;

  /// No description provided for @chooseLanguageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select the language used for the app. Gemma will also return the screening explanation in this language.'**
  String get chooseLanguageSubtitle;

  /// No description provided for @continueButton.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueButton;

  /// No description provided for @saveButton.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveButton;

  /// No description provided for @changeLanguage.
  ///
  /// In en, this message translates to:
  /// **'Change language'**
  String get changeLanguage;

  /// No description provided for @screeningNav.
  ///
  /// In en, this message translates to:
  /// **'Screening'**
  String get screeningNav;

  /// No description provided for @operationsNav.
  ///
  /// In en, this message translates to:
  /// **'Operations'**
  String get operationsNav;

  /// No description provided for @queueNav.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get queueNav;

  /// No description provided for @screeningIntakeTitle.
  ///
  /// In en, this message translates to:
  /// **'Screening intake'**
  String get screeningIntakeTitle;

  /// No description provided for @nameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get nameLabel;

  /// No description provided for @villageLabel.
  ///
  /// In en, this message translates to:
  /// **'Village / area'**
  String get villageLabel;

  /// No description provided for @stateLabel.
  ///
  /// In en, this message translates to:
  /// **'State'**
  String get stateLabel;

  /// No description provided for @districtLabel.
  ///
  /// In en, this message translates to:
  /// **'District'**
  String get districtLabel;

  /// No description provided for @dateOfBirthLabel.
  ///
  /// In en, this message translates to:
  /// **'Date of birth'**
  String get dateOfBirthLabel;

  /// No description provided for @phoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phoneLabel;

  /// No description provided for @pinCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'PIN code'**
  String get pinCodeLabel;

  /// No description provided for @ashaPinLabel.
  ///
  /// In en, this message translates to:
  /// **'ASHA PIN'**
  String get ashaPinLabel;

  /// No description provided for @genderLabel.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get genderLabel;

  /// No description provided for @femaleLabel.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get femaleLabel;

  /// No description provided for @maleLabel.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get maleLabel;

  /// No description provided for @otherLabel.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get otherLabel;

  /// No description provided for @tobaccoBrandLabel.
  ///
  /// In en, this message translates to:
  /// **'Tobacco brand'**
  String get tobaccoBrandLabel;

  /// No description provided for @chewsPerDayLabel.
  ///
  /// In en, this message translates to:
  /// **'Chews per day'**
  String get chewsPerDayLabel;

  /// No description provided for @yearsUsedLabel.
  ///
  /// In en, this message translates to:
  /// **'Years used'**
  String get yearsUsedLabel;

  /// No description provided for @alcoholUseLabel.
  ///
  /// In en, this message translates to:
  /// **'Alcohol use'**
  String get alcoholUseLabel;

  /// No description provided for @savingLabel.
  ///
  /// In en, this message translates to:
  /// **'Saving'**
  String get savingLabel;

  /// No description provided for @requiredError.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get requiredError;

  /// No description provided for @numberRequiredError.
  ///
  /// In en, this message translates to:
  /// **'Number required'**
  String get numberRequiredError;

  /// No description provided for @locationDataUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Location data unavailable: {error}'**
  String locationDataUnavailable(Object error);

  /// No description provided for @captureVideoTitle.
  ///
  /// In en, this message translates to:
  /// **'Capture intraoral video'**
  String get captureVideoTitle;

  /// No description provided for @desktopModeInstructions.
  ///
  /// In en, this message translates to:
  /// **'Desktop mode: select one intraoral video. The app will sample representative frames for local screening.'**
  String get desktopModeInstructions;

  /// No description provided for @intraoralVideoLabel.
  ///
  /// In en, this message translates to:
  /// **'Intraoral video'**
  String get intraoralVideoLabel;

  /// No description provided for @recordingLiveVideo.
  ///
  /// In en, this message translates to:
  /// **'Recording live video'**
  String get recordingLiveVideo;

  /// No description provided for @noVideoSelected.
  ///
  /// In en, this message translates to:
  /// **'No video selected'**
  String get noVideoSelected;

  /// No description provided for @selectedVideo.
  ///
  /// In en, this message translates to:
  /// **'Selected: {fileName}'**
  String selectedVideo(Object fileName);

  /// No description provided for @stopButton.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stopButton;

  /// No description provided for @recordLiveButton.
  ///
  /// In en, this message translates to:
  /// **'Record live'**
  String get recordLiveButton;

  /// No description provided for @uploadVideoButton.
  ///
  /// In en, this message translates to:
  /// **'Upload video'**
  String get uploadVideoButton;

  /// No description provided for @changeUploadedVideoButton.
  ///
  /// In en, this message translates to:
  /// **'Change uploaded video'**
  String get changeUploadedVideoButton;

  /// No description provided for @selectVideoButton.
  ///
  /// In en, this message translates to:
  /// **'Select video'**
  String get selectVideoButton;

  /// No description provided for @fixedModelPathNotice.
  ///
  /// In en, this message translates to:
  /// **'The LiteRT model path is fixed by app configuration; no model selection is required during screening.'**
  String get fixedModelPathNotice;

  /// No description provided for @analyzeButton.
  ///
  /// In en, this message translates to:
  /// **'Analyze'**
  String get analyzeButton;

  /// No description provided for @analyzingLabel.
  ///
  /// In en, this message translates to:
  /// **'Analyzing'**
  String get analyzingLabel;

  /// No description provided for @preparingVideosProgress.
  ///
  /// In en, this message translates to:
  /// **'Preparing videos'**
  String get preparingVideosProgress;

  /// No description provided for @extractingFramesProgress.
  ///
  /// In en, this message translates to:
  /// **'Extracting video frames'**
  String get extractingFramesProgress;

  /// No description provided for @selectingFramesProgress.
  ///
  /// In en, this message translates to:
  /// **'Selecting representative frames'**
  String get selectingFramesProgress;

  /// No description provided for @runningTriageProgress.
  ///
  /// In en, this message translates to:
  /// **'Running YOLO + Gemma triage ({count, plural, =1{1 frame} other{{count} frames}})'**
  String runningTriageProgress(int count);

  /// No description provided for @cameraUnavailableError.
  ///
  /// In en, this message translates to:
  /// **'No camera is available on this device.'**
  String get cameraUnavailableError;

  /// No description provided for @cameraNotReadyError.
  ///
  /// In en, this message translates to:
  /// **'Camera is not ready.'**
  String get cameraNotReadyError;

  /// No description provided for @stopCurrentRecordingError.
  ///
  /// In en, this message translates to:
  /// **'Stop the current recording first.'**
  String get stopCurrentRecordingError;

  /// No description provided for @videoMissingError.
  ///
  /// In en, this message translates to:
  /// **'Video does not exist: {path}'**
  String videoMissingError(Object path);

  /// No description provided for @modelPathRequiredError.
  ///
  /// In en, this message translates to:
  /// **'LiteRT model path is required.'**
  String get modelPathRequiredError;

  /// No description provided for @yoloPathRequiredError.
  ///
  /// In en, this message translates to:
  /// **'YOLO model path is required.'**
  String get yoloPathRequiredError;

  /// No description provided for @recordOrSelectVideoError.
  ///
  /// In en, this message translates to:
  /// **'Record or select one intraoral video first.'**
  String get recordOrSelectVideoError;

  /// No description provided for @resultTitle.
  ///
  /// In en, this message translates to:
  /// **'Result'**
  String get resultTitle;

  /// No description provided for @ashaViewButton.
  ///
  /// In en, this message translates to:
  /// **'ASHA view'**
  String get ashaViewButton;

  /// No description provided for @consentSharingButton.
  ///
  /// In en, this message translates to:
  /// **'Consent and sharing'**
  String get consentSharingButton;

  /// No description provided for @translateLocallyButton.
  ///
  /// In en, this message translates to:
  /// **'Translate locally'**
  String get translateLocallyButton;

  /// No description provided for @treatmentTrackingButton.
  ///
  /// In en, this message translates to:
  /// **'Treatment tracking'**
  String get treatmentTrackingButton;

  /// No description provided for @rawModelOutputTitle.
  ///
  /// In en, this message translates to:
  /// **'Raw model output'**
  String get rawModelOutputTitle;

  /// No description provided for @rawModelOutputSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 site response from local LiteRT} other{{count} site responses from local LiteRT}}'**
  String rawModelOutputSubtitle(int count);

  /// No description provided for @unparsedBadge.
  ///
  /// In en, this message translates to:
  /// **'Unparsed'**
  String get unparsedBadge;

  /// No description provided for @reviewBadge.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get reviewBadge;

  /// No description provided for @recaptureBadge.
  ///
  /// In en, this message translates to:
  /// **'Recapture'**
  String get recaptureBadge;

  /// No description provided for @lowRiskBadge.
  ///
  /// In en, this message translates to:
  /// **'Low risk'**
  String get lowRiskBadge;

  /// No description provided for @rawLocalModelResponse.
  ///
  /// In en, this message translates to:
  /// **'Raw local model response'**
  String get rawLocalModelResponse;

  /// No description provided for @ashaSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'ASHA summary'**
  String get ashaSummaryTitle;

  /// No description provided for @rescreenDate.
  ///
  /// In en, this message translates to:
  /// **'Rescreen {date}'**
  String rescreenDate(Object date);

  /// No description provided for @progressButton.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get progressButton;

  /// No description provided for @gemmaLanguageName.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get gemmaLanguageName;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hi', 'kn', 'ml', 'ta'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
    case 'kn':
      return AppLocalizationsKn();
    case 'ml':
      return AppLocalizationsMl();
    case 'ta':
      return AppLocalizationsTa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
