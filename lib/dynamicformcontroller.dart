import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:reactiveform/components/app_snackbar.dart';
import 'package:reactiveform/string_constants.dart';
import 'package:reactiveform/models/form_field_model.dart';

class DynamicFormController extends ChangeNotifier {
  final List<Map<String, dynamic>> formJson;
  final void Function(Map<String, dynamic>,
      Map<String, List<Map<String, dynamic>>> uploadedFiles) onSubmit;

  late FormGroup form;
  Map<String, List<Map<String, dynamic>>> uploadedFiles = {};
  int _currentQuestionIndex = 0;
  Map<String, dynamic> _values = {};
  final List<FormFieldModel> _fields;

  DynamicFormController({
    required this.formJson,
    required this.onSubmit,
  }) : _fields =
            formJson.map((json) => FormFieldModel.fromJson(json)).toList() {
    _initializeForm();
  }

  void _initializeForm() {
    Map<String, AbstractControl<dynamic>> controls = {};

    // Initialize form controls and uploadedFiles
    for (var field in formJson) {
      final fieldName = field['name'];

      if (field['type'] == 'multiselect') {
        // Create a properly typed FormControl for multiselect
        List<String> initialValue = [];
        if (field['defaultValue'] != null) {
          if (field['defaultValue'] is List) {
            initialValue = (field['defaultValue'] as List)
                .map((item) => item.toString())
                .toList();
          }
        }

        // Debug print
        print(
            'Initializing multiselect field: $fieldName with initial value: $initialValue');

        controls[fieldName] = FormControl<List<String>>(
          value: initialValue,
          validators: field['required'] == true ? [Validators.required] : [],
        );
      } else if (field['type'] == 'file') {
        uploadedFiles[fieldName] = []; // Initialize empty list for file uploads
        controls[fieldName] = FormControl<String>(value: '');
      } else if (field['type'] == 'number') {
        // Special handling for number fields
        controls[fieldName] = FormControl<num>(
          value: null,
          validators: _getValidators(field['required'], field),
        );
      } else if (field['type'] == 'radio') {
        // Set default Yes/No options for radio type if no options provided
        if (field['options'] == null || (field['options'] as List).isEmpty) {
          field['options'] = ['Yes', 'No'];
        }
        controls[fieldName] = FormControl<String>(
          value: field['defaultValue'] ??
              '', // Initialize with default value if provided
          validators: _getValidators(field['required'], field),
        );

        if (field['hasComments'] == true) {
          // When hasComments is true, make the comment field mandatory
          controls['${fieldName}_comment'] = FormControl<String>(
            value: '',
            validators: [Validators.required],
          );
        }
      } else {
        // Initialize form controls for non-file fields
        controls[fieldName] = FormControl<String>(
          value: field['defaultValue'] ?? '',
          validators: _getValidators(field['required'], field),
        );

        if (field['hasComments'] == true) {
          // When hasComments is true, make the comment field mandatory
          controls['${fieldName}_comment'] = FormControl<String>(
            value: '',
            validators: [Validators.required],
          );
        }

        if (field['subQuestions'] != null) {
          (field['subQuestions'] as Map<String, dynamic>)
              .forEach((answer, subQuestions) {
            if (subQuestions is List) {
              for (var subField in subQuestions) {
                if (subField is Map<String, dynamic>) {
                  controls[subField['name']] = FormControl<String>(
                    validators: _getValidators(subField['required'], subField),
                  );
                }
              }
            }
          });
        }
      }
    }

    form = FormGroup(controls);

    // Debug: Print initial form values
    print('Initial form values: ${form.value}');
  }

  List<Validator<dynamic>> _getValidators(
      bool validators, Map<String, dynamic>? field) {
    List<Validator<dynamic>> validatorsList = [];

    // Add required validator if present
    if (validators == true) {
      validatorsList.add(Validators.required);
    }

    // Add min/max validators for number fields
    if (field?['type'] == 'number') {
      if (field?['min'] != null) {
        validatorsList.add(Validators.min(field!['min']));
      }
      if (field?['max'] != null) {
        validatorsList.add(Validators.max(field!['max']));
      }
    }

    return validatorsList;
  }

  static Map<String, dynamic>? _multiSelectValidator(
      AbstractControl<dynamic> control) {
    final value = control.value as List<String>?;
    if (value == null || value.isEmpty) {
      return {'required': true};
    }
    return null;
  }

  void submitForm(BuildContext context) {
    bool isValid = true;

    // Print the current form value for debugging
    print('Form value at submission: ${form.value}');

    // Check each field's validation
    for (var field in formJson) {
      final fieldName = field['name'];
      final control = form.control(fieldName);

      // Debug info
      print(
          'Field: $fieldName, Value: ${control.value}, Valid: ${control.valid}');

      // If field is file type, check uploaded files
      if (field['type'] == 'file') {
        if (field['required'] == true) {
          isValid = isValid && (uploadedFiles[fieldName]?.isNotEmpty ?? false);
        }
        continue; // Skip further validation for file fields
      }

      // For non-file fields, check form control validity
      if (!control.valid && field['required'] == true) {
        isValid = false;
        break;
      }
    }

    if (isValid) {
      // Make a deep copy of the form value to ensure we get everything
      final formValue = Map<String, dynamic>.from(form.value);
      onSubmit(formValue, uploadedFiles);
    } else {
      form.markAllAsTouched();
      _handleFormErrors(context);
    }
  }

  void _handleFormErrors(BuildContext context) {
    int errorIndex = formJson.indexWhere((field) {
      final control = form.control(field['name']);
      return field['required'] == true &&
          (control.value == null || control.value.toString().isEmpty);
    });

    if (errorIndex != -1) {
      _currentQuestionIndex = errorIndex;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(StringConstants.fillAllFields),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// The function `validateAndProceed` in Dart validates form fields, handles file uploads, and
  /// navigates to the next question based on user input.
  ///
  /// Args:
  ///   context (BuildContext): The `context` parameter in the `validateAndProceed` function is of type
  /// `BuildContext`. It is typically used in Flutter to provide access to the nearest BuildContext
  /// ancestor in the widget tree. This context is necessary for various operations such as showing
  /// dialogs, navigating between screens, accessing theme data, and
  ///
  /// Returns:
  ///   The function `validateAndProceed` returns a boolean value - `true` if the current field is valid
  /// and all necessary conditions are met to proceed to the next question, and `false` if there are
  /// validation errors or requirements that prevent moving to the next question.
  bool validateAndProceed(BuildContext context) {
    final field = formJson[_currentQuestionIndex];
    final currentFieldName = field['name'];
    final currentControl = form.control(currentFieldName);

    // Debug information
    print("Current question: ${currentFieldName}, value: ${field}");

    // Mark the current field as touched to trigger validation
    currentControl.markAsTouched();

    // Check if the current field is valid
    if (!currentControl.valid) {
      String errorMessage = _getErrorMessage(field, currentControl);
      if (!(field["type"] == "text" || field["type"] == "number")) {
        AppSnackBar(context).showErrorSnackBar(errorMessage);
      }
      notifyListeners();
      return false;
    }

    // Check if the field has a required comment and validate it
    if (field['hasComments'] == true) {
      final commentControlName = '${currentFieldName}_comment';
      if (form.contains(commentControlName)) {
        final commentControl = form.control(commentControlName);

        // Mark comment field as touched to trigger validation
        commentControl.markAsTouched();

        // Check if comment field is valid
        if (!commentControl.valid) {
          AppSnackBar(context)
              .showErrorSnackBar(StringConstants.commentsAreRequired);
          notifyListeners();
          return false;
        }
      }
    }

    // Add scenario for 'file' type with 'required' set to true
    if (field['type'] == 'file' && field['required'] == true) {
      // Check if files are uploaded
      if (uploadedFiles[currentFieldName]?.isEmpty ?? true) {
        AppSnackBar(context).showErrorSnackBar(StringConstants.fileIsRequired);
        notifyListeners();
        return false;
      }
    }

    // Check if file upload is required for TEXT fields with requiredAttachmentsOn = true
    if (field['type'] == 'text' && field['requiredAttachmentsOn'] == true) {
      // Check if files are uploaded
      if (uploadedFiles[currentFieldName]?.isEmpty ?? true) {
        AppSnackBar(context)
            .showErrorSnackBar(StringConstants.uploadRequiredFiles);
        notifyListeners();
        return false;
      }
    }

    // Check if file upload is required for RADIO fields with requireAttachmentsOn
    if (field['hasAttachments'] == true &&
        field['requireAttachmentsOn'] != null &&
        field['requireAttachmentsOn'].isNotEmpty) {
      final selectedValue = currentControl.value;
      final requireAttachmentsOn = field['requireAttachmentsOn'] is List
          ? field['requireAttachmentsOn']
          : [field['requireAttachmentsOn']];

      if (requireAttachmentsOn.contains(selectedValue)) {
        // Check if files are uploaded
        if (uploadedFiles[currentFieldName]?.isEmpty ?? true) {
          AppSnackBar(context)
              .showErrorSnackBar(StringConstants.uploadRequiredFiles);
          notifyListeners();
          return false;
        }
      }
    }

    // Special handling for multiselect validation
    if (field['type'] == 'multiselect' && field['required'] == true) {
      if (currentControl.value == null) {
        AppSnackBar(context)
            .showErrorSnackBar(StringConstants.pleaseSelectAtLeastOneOption);
        notifyListeners();
        return false;
      }

      final List<dynamic>? values =
          currentControl.value is List ? currentControl.value : null;
      if (values == null || values.isEmpty) {
        AppSnackBar(context)
            .showErrorSnackBar(StringConstants.pleaseSelectAtLeastOneOption);
        notifyListeners();
        return false;
      }
    }

    // DYNAMIC NAVIGATION LOGIC
    // Find the next question that should be shown based on current answers
    int nextQuestionIndex = findNextVisibleQuestionIndex();

    if (nextQuestionIndex != -1) {
      _currentQuestionIndex = nextQuestionIndex;
      print("Navigation: Moving to question at index $nextQuestionIndex");
    } else if (_currentQuestionIndex < formJson.length - 1) {
      // If no conditional question found but we're not at the end,
      // move to the next sequential question
      _currentQuestionIndex++;
      print(
          "Navigation: No conditional question found, moving to next question ${_currentQuestionIndex}");
    }

    notifyListeners();
    return true;
  }

  // Helper method to find the next question that should be visible
  int findNextVisibleQuestionIndex() {
    print("Finding next visible question after ${_currentQuestionIndex}");

    // Check questions sequentially starting from the next one
    for (int i = _currentQuestionIndex + 1; i < formJson.length; i++) {
      final question = formJson[i];
      final questionName = question['name'];

      // If no conditions, this question should always be shown
      if (question['showWhen'] == null) {
        print("Question $questionName has no conditions - will be shown");
        return i;
      }

      // Check if this question's conditions are met
      final Map<String, dynamic> conditions = question['showWhen'];
      bool shouldShow = true; // Start with true for AND logic between fields

      print("Checking conditions for $questionName: $conditions");

      // Check each condition
      conditions.forEach((dependentField, expectedValues) {
        // Skip if the dependent field doesn't exist in the form
        if (!form.contains(dependentField)) {
          print("Field $dependentField not found in form");
          shouldShow = false;
          return;
        }

        // Get the value of the dependent field
        final dependentControl = form.control(dependentField);
        final fieldValue = dependentControl.value;

        print("Field $dependentField has value: $fieldValue");

        // Check if the field value matches any expected value
        bool fieldMatches = false;

        // Handle different types of field values and expected values
        if (fieldValue is List && expectedValues is List) {
          // If both are lists, check if there's any intersection
          fieldMatches = fieldValue.any((v) => expectedValues.contains(v));
          print(
              "Checking if list $fieldValue intersects with $expectedValues: $fieldMatches");
        } else if (fieldValue is List) {
          // If field value is a list but expected value is single, check if the list contains the expected value
          fieldMatches = fieldValue.contains(expectedValues);
          print(
              "Checking if list $fieldValue contains $expectedValues: $fieldMatches");
        } else if (expectedValues is List) {
          // If expected value is a list but field value is single, check if the expected list contains the field value
          fieldMatches = expectedValues.contains(fieldValue);
          print(
              "Checking if $fieldValue is in list $expectedValues: $fieldMatches");
        } else {
          // Simple equality check for single values
          fieldMatches = (fieldValue == expectedValues);
          print(
              "Checking if $fieldValue equals $expectedValues: $fieldMatches");
        }

        // For this question to show, ALL conditions must be met (AND logic)
        shouldShow = shouldShow && fieldMatches;
      });

      // If this question's conditions are met, it should be shown
      if (shouldShow) {
        print("All conditions met for $questionName, it will be shown");
        return i;
      } else {
        print("Conditions not met for $questionName, checking next question");
      }
    }

    // No more questions should be shown
    return -1;
  }

  bool shouldDisplayQuestion(int questionIndex) {
    if (questionIndex >= formJson.length) {
      return false;
    }

    final question = formJson[questionIndex];

    // If no conditions, always show the question
    if (question['showWhen'] == null) {
      return true;
    }

    final conditions = question['showWhen'] as Map<String, dynamic>;
    bool shouldShow = true;

    conditions.forEach((dependentField, expectedValue) {
      if (!form.contains(dependentField)) {
        shouldShow = false;
        return;
      }

      final fieldValue = form.control(dependentField).value;
      bool fieldMatches = false;

      // Handle different types of field values and expected values
      if (fieldValue is List && expectedValue is List) {
        // If both are lists, check if there's any intersection
        fieldMatches = fieldValue.any((v) => expectedValue.contains(v));
      } else if (fieldValue is List) {
        // If field value is a list but expected value is single, check if the list contains the expected value
        fieldMatches = fieldValue.contains(expectedValue);
      } else if (expectedValue is List) {
        // If expected value is a list but field value is single, check if the expected list contains the field value
        fieldMatches = expectedValue.contains(fieldValue);
      } else {
        // Simple equality check for single values
        fieldMatches = (fieldValue == expectedValue);
      }

      shouldShow = shouldShow && fieldMatches;
    });

    return shouldShow;
  }

  bool _hasValidationError(Map<String, dynamic> field,
      AbstractControl currentControl, String fieldName) {
    // Add multiselect validation
    if (field['type'] == 'multiselect' && field['required'] == true) {
      final List<String>? values = currentControl.value as List<String>?;
      if (values == null || values.isEmpty) {
        return true;
      }
    }

    // Required field validation
    if (field['required'] == true &&
        (currentControl.value == null ||
            currentControl.value.toString().isEmpty)) {
      return true;
    }

    // Attachment validation
    if (field['requireAttachmentsOn'] == currentControl.value &&
        (uploadedFiles[fieldName]?.isEmpty ?? true)) {
      return true;
    }

    // Sub-questions validation
    if (field['subQuestions']?[currentControl.value] != null) {
      for (var subField in field['subQuestions'][currentControl.value]) {
        final subControl = form.control(subField['name']);
        if (subField['required'] == true &&
            (subControl.value == null || subControl.value.toString().isEmpty)) {
          return true;
        }
      }
    }

    return false;
  }

  /// The function `_getErrorMessage` checks for various conditions and returns error messages based on
  /// the field type and control value.
  ///
  /// Args:
  ///   field (Map<String, dynamic>): The `field` parameter is a map containing information about a form
  /// field. It includes properties like `type`, `required`, and `requireAttachmentsOn`.
  ///   control (AbstractControl): The `control` parameter in the `_getErrorMessage` function is an
  /// instance of `AbstractControl`. This parameter is likely used to access the current value of a form
  /// control in an Angular application. The function checks various conditions based on the type of
  /// field and the value of the control to determine the appropriate
  ///
  /// Returns:
  ///   The function `_getErrorMessage` returns an error message based on the conditions specified in
  /// the code. The specific error message returned depends on the type of field, whether it is
  /// required, the control value, and other conditions. The possible error messages that can be
  /// returned are:
  /// - 'Please select at least one option' if a multiselect field is required and no option is
  /// selected.
  /// - 'Please select
  String _getErrorMessage(Map<String, dynamic> field, AbstractControl control) {
    if (field['type'] == 'multiselect') {
      // First check if value is actually a List
      final dynamic rawValue = control.value;
      final List<dynamic>? values = rawValue is List ? rawValue : null;

      if (field['required'] == true && (values == null || values.isEmpty)) {
        return StringConstants.pleaseSelectAtLeastOneOption;
      }
    }

    if (field['required'] == true &&
        (control.value == null || control.value.toString().isEmpty)) {
      if (field['type'] == "radio") {
        return StringConstants.pleaseSelectAnOption;
      } else if (field['type'] == 'text' || field['type'] == 'number') {
        return StringConstants.requiredField;
      } else {
        return StringConstants.pleaseAnswerThisQuestion;
      }
    }

    if (field['requireAttachmentsOn'] == control.value) {
      return StringConstants.uploadRequiredFiles;
    }

    return StringConstants.pleaseAnswerAllRequiredSubQuestions;
  }

  void showDropdownBottomSheet(
      BuildContext context, Map<String, dynamic> field) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              field['label'] ?? StringConstants.selectOption,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            ...List<Widget>.from(
              (field['options'] as List).map(
                (option) => ListTile(
                  title: Text(option['label']),
                  onTap: () {
                    form.control(field['name']).value = option['value'];
                    Navigator.pop(context);
                  },
                  trailing: form.control(field['name']).value == option['value']
                      ? const Icon(Icons.check, color: Colors.blue)
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool shouldShowSubmitButton() {
    if (_currentQuestionIndex >= formJson.length) return false;

    final currentField = formJson[_currentQuestionIndex];
    if (currentField['branching'] == null) return false;

    var branchTo = currentField['branching'];
    if (branchTo is Map<String, dynamic>) {
      String? targetQuestion =
          branchTo[form.control(currentField['name']).value?.toString()];
      return targetQuestion == 'end';
    }

    return false;
  }

  @override
  void dispose() {
    super.dispose();
    form.dispose(); // Dispose the ReactiveForm
    // Dispose of any other resources held by the controller
    if (kDebugMode) {
      print('DynamicFormController disposed');
    }
  }

  void updateFieldValue(String fieldId, dynamic value) {
    FormFieldModel field = _fields.firstWhere((f) => f.name == fieldId);
    if (field.type == 'multiselect') {
      // Ensure the value is always a List<String>
      _values[fieldId] = (value as List).cast<String>();
    } else {
      _values[fieldId] = value;
    }
    notifyListeners();
  }

  dynamic getFieldValue(String fieldId) {
    return _values[fieldId];
  }

  bool isFieldValid(String fieldName) {
    final control = form.control(fieldName);
    final field = formJson.firstWhere((f) => f['name'] == fieldName);

    if (field['type'] == 'multiselect' && field['required'] == true) {
      final List<String>? values = control.value as List<String>?;
      return values != null && values.isNotEmpty;
    }

    return control.valid;
  }

  bool shouldShowField(Map<String, dynamic> field) {
    if (field['showWhen'] == null) return true;

    bool shouldShow = true;
    final conditions = field['showWhen'] as Map<String, dynamic>;

    conditions.forEach((dependentField, expectedValue) {
      if (!form.contains(dependentField)) {
        shouldShow = false;
        return;
      }

      final fieldValue = form.control(dependentField).value;
      bool fieldMatches = false;

      // Handle different types of field values and expected values
      if (fieldValue is List && expectedValue is List) {
        // If both are lists, check if there's any intersection
        fieldMatches = fieldValue.any((v) => expectedValue.contains(v));
      } else if (fieldValue is List) {
        // If field value is a list but expected value is single, check if the list contains the expected value
        fieldMatches = fieldValue.contains(expectedValue);
      } else if (expectedValue is List) {
        // If expected value is a list but field value is single, check if the expected list contains the field value
        fieldMatches = expectedValue.contains(fieldValue);
      } else {
        // Simple equality check for single values
        fieldMatches = (fieldValue == expectedValue);
      }

      shouldShow = shouldShow && fieldMatches;
    });

    return shouldShow;
  }

  // Add this helper method to get properly typed multiselect values
  List<String> getMultiselectValue(String fieldName) {
    final value = form.control(fieldName).value;

    // Convert to List<String> regardless of current type
    if (value == null || value == "") {
      return [];
    } else if (value is List) {
      return List<String>.from(value.map((item) => item.toString()));
    } else {
      // Handle unexpected single value
      return [value.toString()];
    }
  }

  // Modify the updateMultiselectValue method
  void updateMultiselectValue(String fieldName, List<String> selectedValues) {
    print('Updating multiselect: $fieldName with values: $selectedValues');

    // Update value in form using various approaches to ensure it sticks
    form.patchValue({fieldName: selectedValues});

    final control = form.control(fieldName);
    control.updateValue(selectedValues);

    // Verify the update
    print('After update, control value type: ${control.value.runtimeType}');
    print('After update, control value: ${control.value}');
  }

  set currentQuestionIndex(int value) {
    if (_currentQuestionIndex != value) {
      _currentQuestionIndex = value;
      notifyListeners(); // This is crucial to trigger the UI update
    }
  }

  int get currentQuestionIndex => _currentQuestionIndex;
}
