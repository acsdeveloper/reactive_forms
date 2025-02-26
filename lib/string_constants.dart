
import 'constants/localization.dart';

class StringConstants {
  static final Map<String, String> _strings = AppLocalizations.en;

  // Form Messages
  static String get requiredFieldError => _strings['requiredFieldError']!;
  static String get checkRequiredFields => _strings['checkRequiredFields']!;
  static String get fillRequiredFields => _strings['fillRequiredFields']!;
  static String get question => _strings['question']!;

  // File Upload
  static String get uploadFiles => _strings['uploadFiles']!;
  static String get chooseFile => _strings['chooseFile']!;
  static String get chooseFromGallery => _strings['chooseFromGallery']!;
  static String get takePhoto => _strings['takePhoto']!;
  static const String processingFile = 'Processing file...';
  static const String unnamedFile = 'Unnamed file';
  static const String filePreview = 'File Preview';
  static const String cannotPreviewFile = 'This file type cannot be previewed';
  static const String errorLoadingImage = 'Error loading image';
  static const String errorViewingFile = 'Error viewing file. Please try again.';
  static const String errorSelectingFile = 'Error selecting file. Please try again.';
  static const String errorSelectingImage = 'Error selecting image. Please try again.';
  static const String errorTakingPhoto = 'Error taking photo. Please try again.';
  static const String fileSizeError = 'File size must be less than 5MB';

  // Form Fields
  static const String search = 'Search...';
  static const String selectOption = 'Select an option';
  static const String enterNumber = 'Enter a number';
  static const String min = 'min';
  static const String max = 'max';
  static const String comments = 'Comments';
  static const String enterComments = 'Enter your comments here';

  // Buttons
  static const String submit = 'Submit';

  // Error Messages
  static const String errorLoadingFile = 'Error loading file';
  static const String errorProcessingFile = 'Error processing file';
  static const String fileNotSupported = 'File type not supported';
  static const String invalidFileFormat = 'Invalid file format';
  
  // Progress Messages
  static const String loading = 'Loading...';
  static const String uploading = 'Uploading...';
  static const String processing = 'Processing...';

  // Navigation
  static const String back = 'Back';
  static const String next = 'Next';
  static const String cancel = 'Cancel';
  
  // Validation Messages
  static const String invalidInput = 'Invalid input';
  static const String requiredField = 'This field is required';
  static const String invalidFormat = 'Invalid format';
  static const String fillAllFields = 'Please fill in all fields';
  static const String uploadRequiredFiles = 'Please upload required files';
  static const String pleaseAnswerAllRequiredSubQuestions = 'Please answer all required sub-questions';
  static const String pleaseSelectAnOption = 'Please select an option';
  static const String pleaseAnswerThisQuestion = 'Please answer this question';
  static const String questionNumber = 'Question';
  static const String valueMustBeAtLeast = 'Value must be at least';
  static const String valueMustBeLessThan = 'Value must be less than';
  static const String valueMustBeLessThanOrEqualTo = 'Value must be less than or equal to';
  static const String valueMustBeGreaterThan = 'Value must be greater than';
  static const String valueMustBeGreaterThanOrEqualTo = 'Value must be greater than or equal to';
  static const String valueMustBeBetween = 'Value must be between';
  static const String valueMustBeEqual = 'Value must be equal to';
  static const String enterCommentsHere = 'Enter your comments here';
  static const String thisFileTypeCannotBePreviewed = 'This file type cannot be previewed';
  static const String file = 'File';
  static const String errorViewingFilePleaseTryAgain = 'Error viewing file. Please try again.';
  static const String pleaseCheckAllRequiredFields = 'Please check all required fields';
  static const String pleaseFillInAllRequiredFields = 'Please fill in all required fields';
  static const String processingFilePleaseWait = 'Processing file...';
  static const String fileSizeMustBeLessThan5MB = 'File size must be less than 5MB';
  static const String errorSelectingFilePleaseTryAgain = 'Error selecting file. Please try again.';
  static const String errorSelectingImagePleaseTryAgain = 'Error selecting image. Please try again.';
  static const String errorTakingPhotoPleaseTryAgain = 'Error taking photo. Please try again.';
  static const String enterANumber = 'Enter a number';
  static const String form ="form_"; 
  static const String pdf = 'pdf';
  static const String doc = 'doc';
  static const String pleaseUploadRequiredFiles = 'Please upload required files';
  static const String isRequired = 'is required';
  static const String fileIsRequired = 'File is required';
} 