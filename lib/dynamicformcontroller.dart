import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:reactiveform/components/app_snackbar.dart';
import 'package:reactiveform/string_constants.dart';
import 'package:reactiveform/models/form_field_model.dart';
import 'package:http/http.dart' as http;

class DynamicFormController extends ChangeNotifier {
  final List<Map<String, dynamic>> formJson;
  final void Function(
          Map<String, dynamic>, Map<String, List<Map<String, dynamic>>>, bool)
      onSubmit;
  final Map<String, dynamic>? initialValues;

  late FormGroup form;
  Map<String, List<Map<String, dynamic>>> uploadedFiles = {};
  int _currentQuestionIndex = 0;
  Map<String, dynamic> _values = {};
  final List<FormFieldModel> _fields;
  final bool isManageToCheckPress;

  DynamicFormController({
    required this.formJson,
    required this.onSubmit,
    required this.isManageToCheckPress,
    this.initialValues,
  }) : _fields =
            formJson.map((json) => FormFieldModel.fromJson(json)).toList() {
    _initializeForm();
    _processInitialFileAttachmentsSync().then((_) {
      notifyListeners(); // Notify after processing completes
    });
  }

  void _initializeForm() {
    Map<String, AbstractControl<dynamic>> controls = {};

    void _addControlsForFields(Iterable<Map<String, dynamic>> fieldList) {
      for (var field in fieldList) {
        final fieldName = field['name'];

        if (controls.containsKey(fieldName)) {
          continue;
        }
        final initial =
            initialValues != null && initialValues!.containsKey(fieldName)
                ? initialValues![fieldName]
                : field['defaultValue'];

        if (field['hasAttachments'] == true) {
          uploadedFiles[fieldName] = initialValues != null &&
                  initialValues!.containsKey('${fieldName}_attachments')
              ? List<Map<String, dynamic>>.from(
                  initialValues!['${fieldName}_attachments'])
              : [];
        }

        if (field['type'] == 'multiselect') {
          List<String> initialValue = [];
          if (initial != null && initial is List<dynamic>) {
            initialValue = initial
                .where((item) => field['options'].contains(item))
                .map((item) => item.toString())
                .toList();
          }

          controls[fieldName] = FormControl<List<String>>(
            value: initialValue.isNotEmpty ? initialValue : null,
            validators: field['required'] == true ? [Validators.required] : [],
          );

          if (field['hasComments'] == true) {
            controls['${fieldName}_comment'] = FormControl<String>(
              value: initialValues != null &&
                      initialValues!.containsKey('${fieldName}_comment')
                  ? initialValues!['${fieldName}_comment']
                  : '',
              validators: [Validators.required],
            );
          }
        } else if (field['type'] == 'file') {
          uploadedFiles[fieldName] = [];
          controls[fieldName] = FormControl<String>(
            value: initial != null ? initial.toString() : '',
            validators: field['required'] == true ? [Validators.required] : [],
          );

          if (field['hasComments'] == true) {
            controls['${fieldName}_comment'] = FormControl<String>(
              value: initialValues != null &&
                      initialValues!.containsKey('${fieldName}_comment')
                  ? initialValues!['${fieldName}_comment']
                  : '',
              validators: [Validators.required],
            );
          }
        } else if (field['type'] == 'text') {
          controls[fieldName] = FormControl<String>(
            value: initial != null ? initial.toString() : '',
            validators: _getValidators(field['required'] == true, field),
          );
          if (field['hasComments'] == true) {
            controls['${fieldName}_comment'] = FormControl<String>(
              value: initialValues != null &&
                      initialValues!.containsKey('${fieldName}_comment')
                  ? initialValues!['${fieldName}_comment']
                  : '',
              validators: [Validators.required],
            );
          }
        } else if (field['type'] == 'number') {
          controls[fieldName] = FormControl<num>(
            value: initial != null ? num.tryParse(initial.toString()) : null,
            validators: _getValidators(field['required'] == true, field),
          );

          if (field['hasComments'] == true) {
            controls['${fieldName}_comment'] = FormControl<String>(
              value: initialValues != null &&
                      initialValues!.containsKey('${fieldName}_comment')
                  ? initialValues!['${fieldName}_comment']
                  : '',
              validators: [Validators.required],
            );
          }
        } else if (field['type'] == 'temp') {
          controls[fieldName] = FormControl<double>(
            value: initial != null ? double.tryParse(initial.toString()) : 20.0,
            validators: _getValidators(field['required'] == true, field),
          );

          if (field['hasComments'] == true) {
            controls['${fieldName}_comment'] = FormControl<String>(
              value: initialValues != null &&
                      initialValues!.containsKey('${fieldName}_comment')
                  ? initialValues!['${fieldName}_comment']
                  : '',
              validators: [Validators.required],
            );
          }
        } else if (field['type'] == 'radio') {
          if (field['options'] == null || (field['options'] as List).isEmpty) {
            field['options'] = ['Yes', 'No'];
          }
          controls[fieldName] = FormControl<String>(
            value: initial != null ? initial.toString() : '',
            validators: _getValidators(field['required'] == true, field),
          );

          if (field['hasComments'] == true) {
            controls['${fieldName}_comment'] = FormControl<String>(
              value: initialValues != null &&
                      initialValues!.containsKey('${fieldName}_comment')
                  ? initialValues!['${fieldName}_comment']
                  : '',
              validators: [Validators.required],
            );
          }
        } else if (field['type'] == 'dropdown') {
          controls[fieldName] = FormControl<String>(
            value: (initial != null && field['options'].contains(initial))
                ? initial.toString()
                : '',
            validators: _getValidators(field['required'] == true, field),
          );
          if (field['hasComments'] == true) {
            controls['${fieldName}_comment'] = FormControl<String>(
              value: initialValues != null &&
                      initialValues!.containsKey('${fieldName}_comment')
                  ? initialValues!['${fieldName}_comment']
                  : '',
              validators: [Validators.required],
            );
          }
        } else {
          controls[fieldName] = FormControl<String>(
            value: field['defaultValue'] ?? '',
            validators: _getValidators(field['required'] == true, field),
          );

          if (field['hasComments'] == true) {
            controls['${fieldName}_comment'] = FormControl<String>(
              value: initialValues != null &&
                      initialValues!.containsKey('${fieldName}_comment')
                  ? initialValues!['${fieldName}_comment']
                  : '',
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
                      validators: _getValidators(
                          subField['required'] == true, subField),
                    );
                  }
                }
              }
            });
          }
        }
      }
    }

    _addControlsForFields(formJson);
    form = FormGroup(controls);
    if (kDebugMode) {
      print('Initial form values: ${form.value}');
      print('Initial uploaded files: $uploadedFiles');
    }
  }

  List<Validator<dynamic>> _getValidators(
      bool isRequired, Map<String, dynamic>? field) {
    List<Validator<dynamic>> validatorsList = [];

    if (isRequired) {
      validatorsList.add(Validators.required);
      if (kDebugMode) {
        print("Adding required validator for field ${field?['name']}");
      }
    }

    if (field?['type'] == 'number' || field?['type'] == 'temp') {
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

    for (var field in formJson) {
      final fieldName = field['name'];
      final control = form.control(fieldName);

      if (!control.valid && field['required'] == true) {
        isValid = false;
        break;
      }
    }

    if (isValid) {
      final formValue = Map<String, dynamic>.from(form.value);
      onSubmit(formValue, uploadedFiles, isManageToCheckPress);
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

  bool validateAndProceed(BuildContext context) {
    final field = formJson[_currentQuestionIndex];
    final currentFieldName = field['name'];
    final currentControl = form.control(currentFieldName);

    currentControl.markAsTouched();

    if (!currentControl.valid) {
      String errorMessage = _getErrorMessage(field, currentControl);
      if (!(field["type"] == "text" || field["type"] == "number")) {
        AppSnackBar(context).showErrorSnackBar(errorMessage);
      }
      notifyListeners();
      return false;
    }

    if (field['hasComments'] == true) {
      final commentControlName = '${currentFieldName}_comment';
      if (form.contains(commentControlName)) {
        final commentControl = form.control(commentControlName);

        commentControl.markAsTouched();

        if (!commentControl.valid) {
          AppSnackBar(context)
              .showErrorSnackBar(StringConstants.commentsAreRequired);
          notifyListeners();
          return false;
        }
      }
    }

    if (field['hasAttachments'] != false) {
      final selectedValue = currentControl.value;

      final bool isMultiselect = field['type'] == 'multiselect';

      bool isTextWithAttachments =
          field['type'] == 'text' && field['hasAttachments'] == true;

      List<dynamic> disabledOptions = field['disableAttachmentsOn'] is List
          ? field['disableAttachmentsOn']
          : field['disableAttachmentsOn'] != null
              ? [field['disableAttachmentsOn']]
              : [];

      bool isAttachmentDisabled = false;

      if (isMultiselect && selectedValue is List) {
        isAttachmentDisabled =
            selectedValue.any((value) => disabledOptions.contains(value));
      } else {
        isAttachmentDisabled = disabledOptions.contains(selectedValue);
      }

      if (!isAttachmentDisabled) {
        bool fileRequired = false;

        if (field['requireAttachmentsOn'] != null) {
          final requireAttachmentsOn = field['requireAttachmentsOn'] is List
              ? field['requireAttachmentsOn']
              : [field['requireAttachmentsOn']];

          if (isMultiselect && selectedValue is List) {
            fileRequired = selectedValue
                .any((value) => requireAttachmentsOn.contains(value));
          } else {
            fileRequired = requireAttachmentsOn.contains(selectedValue);
          }
        }

        // NEW CHECK: If hasAttachments is true and both requireAttachmentsOn and disableAttachmentsOn are empty arrays,
        // require file upload
        if (!fileRequired && field['hasAttachments'] == true) {
          // Check if requireAttachmentsOn is an empty array
          bool isRequireAttachmentsOnEmpty =
              field['requireAttachmentsOn'] is List &&
                  (field['requireAttachmentsOn'] as List).isEmpty;

          // Check if disableAttachmentsOn is an empty array
          bool isDisableAttachmentsOnEmpty =
              field['disableAttachmentsOn'] is List &&
                  (field['disableAttachmentsOn'] as List).isEmpty;

          // If both are empty arrays, require file upload
          if (isRequireAttachmentsOnEmpty && isDisableAttachmentsOnEmpty) {
            if (kDebugMode) {
              print(
                  "File required for ${field['name']} because hasAttachments=true and both requireAttachmentsOn and disableAttachmentsOn are empty arrays");
            }
            fileRequired = true;
          }
        }

        if (!fileRequired && isTextWithAttachments) {
          fileRequired = true;
        }

        if (!fileRequired && field['attachmentsRequired'] == true) {
          print(
              "Legacy property 'attachmentsRequired' detected - treating as requireAttachmentsOn");
          fileRequired = true;
        }

        if (fileRequired &&
            (uploadedFiles[currentFieldName]?.isEmpty ?? true)) {
          AppSnackBar(context)
              .showErrorSnackBar(StringConstants.uploadRequiredFiles);
          notifyListeners();
          return false;
        }
      }
    }

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

    int nextQuestionIndex = findNextVisibleQuestionIndex();

    if (nextQuestionIndex != -1) {
      _currentQuestionIndex = nextQuestionIndex;
      print("Navigation: Moving to question at index $nextQuestionIndex");
    } else if (_currentQuestionIndex < formJson.length - 1) {
      _currentQuestionIndex++;
      print(
          "Navigation: No conditional question found, moving to next question ${_currentQuestionIndex}");
    }

    notifyListeners();
    return true;
  }

  /// Given a field and its control value, determine if comments should be shown.
  ///
  /// 1. If the control value is in the disabled options, don't show comments.
  /// 2. If the field has comments and the value is not in disabled options, show comments.
  /// 3. If the field has requireCommentsOn property, check if the control value is in the required options.
  /// 4. If the field has legacy Comments Required property, check if the control value is in the enabled options.
  /// 5. If none of the above conditions apply, and hasComments is true, show comments if both requireCommentsOn and enableCommentsOn are empty or null.
  ///
  bool shouldShowCommentsBasedOnFieldValue(
      dynamic field, dynamic controlValue) {
    // List of disabled options
    List<dynamic> disabledOptions = field['disableCommentsOn'] is List
        ? field['disableCommentsOn']
        : field['disableCommentsOn'] != null
            ? [field['disableCommentsOn']]
            : [];

    // If control value is in disabled options, don't show comments
    if (disabledOptions.isNotEmpty && disabledOptions.contains(controlValue)) {
      return false;
    }

    bool shouldShowComments = false;

    // Check if field has comments and if the value is not in disabled options
    if (field['hasComments'] == true &&
        disabledOptions.isNotEmpty &&
        !disabledOptions.contains(controlValue)) {
      shouldShowComments = true;
    } else {
      // Check requireCommentsOn
      if (field['requireCommentsOn'] != null) {
        List<dynamic> requiredOptions = field['requireCommentsOn'] is List
            ? field['requireCommentsOn']
            : [field['requireCommentsOn']];

        if (requiredOptions.contains(controlValue)) {
          shouldShowComments = true;
        }
      }

      // Check for legacy Comments Required property
      if (!shouldShowComments && field['enableCommentsOn'] != null) {
        List<dynamic> enabledOptions = field['enableCommentsOn'] is List
            ? field['enableCommentsOn']
            : [field['enableCommentsOn']];

        if (enabledOptions.contains(controlValue)) {
          shouldShowComments = true;
        }
      }

      // Fallback: If hasComments is true and none of the above conditions applied
      if (!shouldShowComments && field['hasComments'] == true) {
        bool isRequireCommentsOnEmpty = field['requireCommentsOn'] == null ||
            (field['requireCommentsOn'] is List &&
                (field['requireCommentsOn'] as List).isEmpty);

        bool isEnableCommentsOnEmpty = field['enableCommentsOn'] == null ||
            (field['enableCommentsOn'] is List &&
                (field['enableCommentsOn'] as List).isEmpty);

        // If both requireCommentsOn and enableCommentsOn are empty or null, show comments
        if (isRequireCommentsOnEmpty && isEnableCommentsOnEmpty) {
          shouldShowComments = true;
        }
      }
    }

    return shouldShowComments;
  }

  int findNextVisibleQuestionIndex() {
    print("Finding next visible question after ${_currentQuestionIndex}");

    for (int i = _currentQuestionIndex + 1; i < formJson.length; i++) {
      final question = formJson[i];
      final questionName = question['name'];

      if (question['showWhen'] == null) {
        print("Question $questionName has no conditions - will be shown");
        return i;
      }

      final Map<String, dynamic> conditions = question['showWhen'];
      bool shouldShow = true;

      conditions.forEach((dependentField, expectedValues) {
        if (!form.contains(dependentField)) {
          print("Field $dependentField not found in form");
          shouldShow = false;
          return;
        }

        final fieldValue = form.control(dependentField).value;
        bool fieldMatches = false;

        if (fieldValue is List && expectedValues is List) {
          fieldMatches = fieldValue.any((v) => expectedValues.contains(v));
          print(
              "Checking if list $fieldValue intersects with $expectedValues: $fieldMatches");
        } else if (fieldValue is List) {
          fieldMatches = fieldValue.contains(expectedValues);
          print(
              "Checking if list $fieldValue contains $expectedValues: $fieldMatches");
        } else if (expectedValues is List) {
          fieldMatches = expectedValues.contains(fieldValue);
          print(
              "Checking if $fieldValue is in list $expectedValues: $fieldMatches");
        } else {
          fieldMatches = (fieldValue == expectedValues);
          print(
              "Checking if $fieldValue equals $expectedValues: $fieldMatches");
        }

        shouldShow = shouldShow && fieldMatches;
      });

      if (shouldShow) {
        print("All conditions met for $questionName, it will be shown");
        return i;
      } else {
        print("Conditions not met for $questionName, checking next question");
      }
    }

    return -1;
  }

  bool shouldDisplayQuestion(int questionIndex) {
    if (questionIndex >= formJson.length) {
      return false;
    }

    final question = formJson[questionIndex];

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

      if (fieldValue is List && expectedValue is List) {
        fieldMatches = fieldValue.any((v) => expectedValue.contains(v));
      } else if (fieldValue is List) {
        fieldMatches = fieldValue.contains(expectedValue);
      } else if (expectedValue is List) {
        fieldMatches = expectedValue.contains(fieldValue);
      } else {
        fieldMatches = (fieldValue == expectedValue);
      }

      shouldShow = shouldShow && fieldMatches;
    });

    return shouldShow;
  }

  bool _hasValidationError(Map<String, dynamic> field,
      AbstractControl currentControl, String fieldName) {
    if (field['type'] == 'multiselect' && field['required'] == true) {
      final List<String>? values = currentControl.value as List<String>?;
      if (values == null || values.isEmpty) {
        return true;
      }
    }

    if (field['required'] == true &&
        (currentControl.value == null ||
            currentControl.value.toString().isEmpty)) {
      return true;
    }

    if (field['hasAttachments'] != false) {
      final selectedValue = currentControl.value;

      final bool isMultiselect = field['type'] == 'multiselect';

      bool isTextWithAttachments =
          field['type'] == 'text' && field['hasAttachments'] == true;

      List<dynamic> disabledOptions = field['disableAttachmentsOn'] is List
          ? field['disableAttachmentsOn']
          : field['disableAttachmentsOn'] != null
              ? [field['disableAttachmentsOn']]
              : [];

      bool isAttachmentDisabled = false;

      if (isMultiselect && selectedValue is List) {
        isAttachmentDisabled =
            selectedValue.any((value) => disabledOptions.contains(value));
      } else {
        isAttachmentDisabled = disabledOptions.contains(selectedValue);
      }

      if (!isAttachmentDisabled) {
        bool fileRequired = false;

        if (field['requireAttachmentsOn'] != null) {
          final requireAttachmentsOn = field['requireAttachmentsOn'] is List
              ? field['requireAttachmentsOn']
              : [field['requireAttachmentsOn']];

          if (isMultiselect && selectedValue is List) {
            fileRequired = selectedValue
                .any((value) => requireAttachmentsOn.contains(value));
          } else {
            fileRequired = requireAttachmentsOn.contains(selectedValue);
          }
        }

        // NEW CHECK: If hasAttachments is true and both requireAttachmentsOn and disableAttachmentsOn are empty arrays,
        // require file upload
        if (!fileRequired && field['hasAttachments'] == true) {
          // Check if requireAttachmentsOn is an empty array
          bool isRequireAttachmentsOnEmpty =
              field['requireAttachmentsOn'] is List &&
                  (field['requireAttachmentsOn'] as List).isEmpty;

          // Check if disableAttachmentsOn is an empty array
          bool isDisableAttachmentsOnEmpty =
              field['disableAttachmentsOn'] is List &&
                  (field['disableAttachmentsOn'] as List).isEmpty;

          // If both are empty arrays, require file upload
          if (isRequireAttachmentsOnEmpty && isDisableAttachmentsOnEmpty) {
            if (kDebugMode) {
              print(
                  "File required for ${field['name']} because hasAttachments=true and both requireAttachmentsOn and disableAttachmentsOn are empty arrays");
            }
            fileRequired = true;
          }
        }

        if (!fileRequired && isTextWithAttachments) {
          fileRequired = true;
        }

        if (!fileRequired && field['attachmentsRequired'] == true) {
          print(
              "Legacy property 'attachmentsRequired' detected - treating as requireAttachmentsOn");
          fileRequired = true;
        }

        if (fileRequired && (uploadedFiles[fieldName]?.isEmpty ?? true)) {
          return true;
        }
      }
    }

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

  String _getErrorMessage(Map<String, dynamic> field, AbstractControl control) {
    if (field['type'] == 'multiselect') {
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

    if (field['hasAttachments'] != false) {
      bool fileRequired = false;
      final selectedValue = control.value;

      final bool isMultiselect = field['type'] == 'multiselect';

      bool isTextWithAttachments =
          field['type'] == 'text' && field['hasAttachments'] == true;

      List<dynamic> disabledOptions = field['disableAttachmentsOn'] is List
          ? field['disableAttachmentsOn']
          : field['disableAttachmentsOn'] != null
              ? [field['disableAttachmentsOn']]
              : [];

      bool isAttachmentDisabled = false;

      if (isMultiselect && selectedValue is List) {
        isAttachmentDisabled =
            selectedValue.any((value) => disabledOptions.contains(value));
      } else {
        isAttachmentDisabled = disabledOptions.contains(selectedValue);
      }

      if (!isAttachmentDisabled) {
        if (field['requireAttachmentsOn'] != null) {
          final requireAttachmentsOn = field['requireAttachmentsOn'] is List
              ? field['requireAttachmentsOn']
              : [field['requireAttachmentsOn']];

          if (isMultiselect && selectedValue is List) {
            fileRequired = selectedValue
                .any((value) => requireAttachmentsOn.contains(value));
          } else {
            fileRequired = requireAttachmentsOn.contains(selectedValue);
          }
        }

        // NEW CHECK: If hasAttachments is true and both requireAttachmentsOn and disableAttachmentsOn are empty arrays,
        // require file upload
        if (!fileRequired && field['hasAttachments'] == true) {
          // Check if requireAttachmentsOn is an empty array
          bool isRequireAttachmentsOnEmpty =
              field['requireAttachmentsOn'] is List &&
                  (field['requireAttachmentsOn'] as List).isEmpty;

          // Check if disableAttachmentsOn is an empty array
          bool isDisableAttachmentsOnEmpty =
              field['disableAttachmentsOn'] is List &&
                  (field['disableAttachmentsOn'] as List).isEmpty;

          // If both are empty arrays, require file upload
          if (isRequireAttachmentsOnEmpty && isDisableAttachmentsOnEmpty) {
            if (kDebugMode) {
              print(
                  "File required for ${field['name']} because hasAttachments=true and both requireAttachmentsOn and disableAttachmentsOn are empty arrays");
            }
            fileRequired = true;
          }
        }

        if (!fileRequired && isTextWithAttachments) {
          fileRequired = true;
        }

        if (!fileRequired && field['attachmentsRequired'] == true) {
          print(
              "Legacy property 'attachmentsRequired' detected - treating as requireAttachmentsOn");
          fileRequired = true;
        }

        if (fileRequired) {
          return StringConstants.uploadRequiredFiles;
        }
      }
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

    // Case 1: Current question has explicit branching to "end"
    if (currentField['branching'] != null) {
      var branchTo = currentField['branching'];
      if (branchTo is Map<String, dynamic>) {
        String? targetQuestion =
            branchTo[form.control(currentField['name']).value?.toString()];
        if (targetQuestion == 'end') return true;
      }
    }

    // Case 2: Check if there are no more visible questions after this one
    bool noMoreVisibleQuestions = findNextVisibleQuestionIndex() == -1;

    // Case 3: We've reached the last question in the form
    bool isLastQuestion = _currentQuestionIndex == formJson.length - 1;

    return noMoreVisibleQuestions || isLastQuestion;
  }

  void addFormControls(List<Map<String, dynamic>> newFields) {
    final Map<String, AbstractControl> newControls = {};
    if (kDebugMode) {
      print("\n=== Adding Form Controls ===");
    }
    void _addControls(Iterable<Map<String, dynamic>> fields) {
      for (var f in fields) {
        final n = f['name'];
        if (form.contains(n)) continue;
        final initial = initialValues != null && initialValues!.containsKey(n)
            ? initialValues![n]
            : f['defaultValue'];
        final bool isRequired = f['required'] == true;
        if (f['type'] == 'multiselect') {
          List<String> initialValue = [];
          if (initial != null && initial is List) {
            initialValue = initial.map((item) => item.toString()).toList();
          } else if (f['defaultValue'] != null && f['defaultValue'] is List) {
            initialValue = (f['defaultValue'] as List)
                .map((item) => item.toString())
                .toList();
          }
          List<Validator> validators = _getValidators(isRequired, f);
          newControls[n] = FormControl<List<String>>(
              value: initialValue, validators: validators);
          if (f['hasComments'] == true) {
            newControls['${n}_comment'] = FormControl<String>(
                value: initialValues != null &&
                        initialValues!.containsKey('${n}_comment')
                    ? initialValues!['${n}_comment']
                    : '',
                validators: [Validators.required]);
          }
        } else if (f['type'] == 'file') {
          uploadedFiles[n] = [];
          List<Validator> validators = _getValidators(isRequired, f);
          newControls[n] = FormControl<String>(
            value: initial != null ? initial : '',
            validators: validators,
          );
          if (f['hasComments'] == true) {
            newControls['${n}_comment'] = FormControl<String>(
                value: initialValues != null &&
                        initialValues!.containsKey('${n}_comment')
                    ? initialValues!['${n}_comment']
                    : '',
                validators: [Validators.required]);
          }
        } else if (f['type'] == 'number') {
          List<Validator> validators = _getValidators(isRequired, f);
          newControls[n] = FormControl<num>(
              value: initial != null ? initial : null, validators: validators);
          if (f['hasComments'] == true) {
            newControls['${n}_comment'] = FormControl<String>(
                value: initialValues != null &&
                        initialValues!.containsKey('${n}_comment')
                    ? initialValues!['${n}_comment']
                    : '',
                validators: [Validators.required]);
          }
        } else if (f['type'] == 'temp') {
          List<Validator> validators = _getValidators(isRequired, f);
          newControls[n] = FormControl<double>(
              value: initial != null ? double.tryParse(initial.toString()) : 20.0, 
              validators: validators);
          if (f['hasComments'] == true) {
            newControls['${n}_comment'] = FormControl<String>(
                value: initialValues != null &&
                        initialValues!.containsKey('${n}_comment')
                    ? initialValues!['${n}_comment']
                    : '',
                validators: [Validators.required]);
          }
        } else if (f['type'] == 'radio') {
          if (f['options'] == null || (f['options'] as List).isEmpty) {
            f['options'] = ['Yes', 'No'];
          }
          List<Validator> validators = _getValidators(isRequired, f);
          newControls[n] = FormControl<String>(
            value: initial != null ? initial : '',
            validators: validators,
          );
          if (f['hasComments'] == true) {
            newControls['${n}_comment'] = FormControl<String>(
                value: initialValues != null &&
                        initialValues!.containsKey('${n}_comment')
                    ? initialValues!['${n}_comment']
                    : '',
                validators: [Validators.required]);
          }
        } else {
          List<Validator> validators = _getValidators(isRequired, f);
          newControls[n] = FormControl<String>(
              value: initial != null ? initial : '', validators: validators);
          if (f['hasComments'] == true) {
            newControls['${n}_comment'] = FormControl<String>(
                value: initialValues != null &&
                        initialValues!.containsKey('${n}_comment')
                    ? initialValues!['${n}_comment']
                    : '',
                validators: [Validators.required]);
          }
        }
      }
    }

    _addControls(newFields);
    form.addAll(newControls);
    if (kDebugMode) {
      print("=== Form Controls After Adding ===");
      newControls.forEach((key, control) {
        final hasRequiredValidator = control.validators
            .any((validator) => validator.toString().contains('required'));
        print("Control: $key, hasRequiredValidator: $hasRequiredValidator");
      });
    }
    notifyListeners();
  }

  /// Removes form controls for deleted fields
  ///
  /// This method is called when question sets are removed from the form
  /// via the delete button. It removes the main control, any associated
  /// comment fields, and cleans up uploaded files.
  void removeFormControls(Iterable<String> names) {
    for (var n in names) {
      // Remove the main control
      if (form.contains(n)) {
        form.removeControl(n);
      }

      // Remove any associated comment control
      final commentField = '${n}_comment';
      if (form.contains(commentField)) {
        form.removeControl(commentField);
      }

      // Remove any uploaded files
      uploadedFiles.remove(n);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
    form.dispose();
    if (kDebugMode) {
      print('DynamicFormController disposed');
    }
  }

  void updateFieldValue(String fieldId, dynamic value) {
    FormFieldModel field = _fields.firstWhere((f) => f.name == fieldId);
    if (field.type == 'multiselect') {
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

      if (fieldValue is List && expectedValue is List) {
        fieldMatches = fieldValue.any((v) => expectedValue.contains(v));
      } else if (fieldValue is List) {
        fieldMatches = fieldValue.contains(expectedValue);
      } else if (expectedValue is List) {
        fieldMatches = expectedValue.contains(fieldValue);
      } else {
        fieldMatches = (fieldValue == expectedValue);
      }

      shouldShow = shouldShow && fieldMatches;
    });

    return shouldShow;
  }

  List<String> getMultiselectValue(String fieldName) {
    final value = form.control(fieldName).value;

    if (value == null || value == "") {
      return [];
    } else if (value is List) {
      return List<String>.from(value.map((item) => item.toString()));
    } else {
      return [value.toString()];
    }
  }

  void updateMultiselectValue(String fieldName, List<String> selectedValues) {
    print('Updating multiselect: $fieldName with values: $selectedValues');

    form.patchValue({fieldName: selectedValues});

    final control = form.control(fieldName);
    control.updateValue(selectedValues);

    print('After update, control value type: ${control.value.runtimeType}');
    print('After update, control value: ${control.value}');
  }

  set currentQuestionIndex(int value) {
    if (_currentQuestionIndex != value) {
      _currentQuestionIndex = value;
      notifyListeners();
    }
  }

  int get currentQuestionIndex => _currentQuestionIndex;

  /// Process initial file attachments by fetching file metadata from URLs
  Future<void> _processInitialFileAttachmentsSync() async {
    if (initialValues == null) return;

    for (var field in formJson) {
      final fieldName = field['name'];

      // Check if this field has attachments and if there are initial values for it
      if (field['hasAttachments'] == true &&
          initialValues!.containsKey('${fieldName}_attachments')) {
        List<Map<String, dynamic>> attachments =
            List<Map<String, dynamic>>.from(
                initialValues!['${fieldName}_attachments']);

        List<Map<String, dynamic>> processedAttachments = [];

        for (var attachment in attachments) {
          if (attachment['file_url'] != null) {
            // Process file metadata synchronously from URL
            Map<String, dynamic> fileData = await _processFileDataFromUrl(
              attachment['file_url'],
              fieldName,
              field['label'] ?? fieldName,
            );

            // Merge with existing attachment data
            fileData.addAll(attachment);
            processedAttachments.add(fileData);
          } else {
            // If no URL, keep the original attachment
            processedAttachments.add(attachment);
          }
        }

        // Update the uploadedFiles map with processed attachments
        uploadedFiles[fieldName] = processedAttachments;
      }
    }

    if (kDebugMode) {
      print('Processed initial file attachments: $uploadedFiles');
    }
  }

  Future<Map<String, dynamic>> _processFileDataFromUrl(
    String url,
    String questionName,
    String questionLabel,
  ) async {
    String fileName = _extractFileNameFromUrl(url, {});
    String fileType = _determineFileType(fileName, null);

    return {
      'question_name': questionName,
      'question_label': questionLabel,
      'fileName': fileName,
      'fileType': ['jpg', 'png', 'jpeg'].contains(fileType)
          ? 'image'
          : fileType == 'pdf'
              ? 'pdf'
              : fileType,
      'file_url': url,
      'mimeType': 'application/octet-stream',
      'file': null,
    };
  }

  /// Extract filename from URL or Content-Disposition header
  String _extractFileNameFromUrl(String url, Map<String, String> headers) {
    // Try to get filename from Content-Disposition header first
    String fileName = url.split('/').last;

    return fileName;
  }

  /// Determine file type from filename extension or content type
  String _determineFileType(String fileName, String? contentType) {
    // First try to determine from file extension
    return fileName.split('.').last;
  }

  /// The function determines whether a field should be visible based on specified conditions.
  ///
  /// Args:
  ///   field (Map<String, dynamic>): The `shouldFieldBeVisible` function takes a `Map<String, dynamic>`
  /// named `field` as a parameter. This map represents a field in a form and contains information about
  /// when the field should be visible based on certain conditions specified in the `showWhen` key of
  /// the map.
  ///
  /// Returns:
  ///   The function `shouldFieldBeVisible` returns a boolean value indicating whether the field should
  /// be visible based on the conditions specified in the `field` parameter.
  bool shouldFieldBeVisible(Map<String, dynamic> field) {
    if (field['showWhen'] == null) return true;
    final conditions = field['showWhen'] as Map<String, dynamic>;
    bool shouldShow = true;
    conditions.forEach((dependentField, expectedValue) {
      if (!form.contains(dependentField)) {
        shouldShow = false;
        return;
      }
      final currentValue = form.control(dependentField).value;
      bool matches;
      if (expectedValue is List) {
        if (currentValue is List) {
          matches = currentValue.any((v) => expectedValue.contains(v));
        } else {
          matches = expectedValue.contains(currentValue);
        }
      } else if (currentValue is List) {
        matches = currentValue.contains(expectedValue);
      } else {
        matches = currentValue == expectedValue;
      }
      shouldShow = shouldShow && matches;
    });
    return shouldShow;
  }

  /// The function `validateFieldAttachmentsIfRequired` checks if field attachments are required based
  /// on specified conditions and returns true if attachments are present, false otherwise.
  ///
  /// Args:
  ///   field (Map<String, dynamic>): The `field` parameter in the `validateFieldAttachmentsIfRequired`
  /// function is a Map that contains information about a specific field in a form. It includes details
  /// such as the field name, type, required status, options for requiring attachments, enabling
  /// attachments, disabling attachments, and whether attachments are currently present
  ///   lastValidationErrorField: The `lastValidationErrorField` parameter in the
  /// `validateFieldAttachmentsIfRequired` function is used to store the last field that failed
  /// validation due to missing attachments. If the field does not have the required attachments, the
  /// function sets `lastValidationErrorField` to that field and returns `false`. This parameter
  ///
  /// Returns:
  ///   The function `validateFieldAttachmentsIfRequired` returns a boolean value. It returns `true` if
  /// the field does not require attachments or if attachments are present, and it returns `false` if
  /// attachments are required but not present for the field.
  bool validateFieldAttachmentsIfRequired(Map<String, dynamic> field) {
    final String fieldName = field['name']?.toString() ?? '';

    // Determine requirement using same rules as _checkIfRequiredFilesUploaded
    dynamic currentValue =
        form.contains(fieldName) ? form.control(fieldName).value : null;

    bool requiresAttachments = false;

    if (field['type'] == 'file' && field['required'] == true) {
      requiresAttachments = true;
    }

    if (field['requireAttachmentsOn'] != null) {
      if (field['requireAttachmentsOn'] == true) {
        requiresAttachments = true;
      } else {
        List<dynamic> requiredOptions = field['requireAttachmentsOn'] is List
            ? field['requireAttachmentsOn']
            : [field['requireAttachmentsOn']];
        if (currentValue is List) {
          requiresAttachments =
              currentValue.any((value) => requiredOptions.contains(value));
        } else {
          requiresAttachments = requiredOptions.contains(currentValue);
        }
      }
    }

    if (field['enableAttachmentsOn'] != null && !requiresAttachments) {
      List<dynamic> enabledOptions = field['enableAttachmentsOn'] is List
          ? field['enableAttachmentsOn']
          : [field['enableAttachmentsOn']];
      if (currentValue is List) {
        requiresAttachments =
            currentValue.any((value) => enabledOptions.contains(value));
      } else {
        requiresAttachments = enabledOptions.contains(currentValue);
      }
    }

    if (field['attachmentsRequired'] == true && !requiresAttachments) {
      requiresAttachments = true;
    }

    if (field['hasAttachments'] == true && !requiresAttachments) {
      bool hasConditionalAttachments = field['requireAttachmentsOn'] != null ||
          field['disableAttachmentsOn'] != null;

      if (!hasConditionalAttachments) {
        requiresAttachments = true;
      } else {
        bool isRequireAttachmentsOnEmpty =
            field['requireAttachmentsOn'] is List &&
                (field['requireAttachmentsOn'] as List).isEmpty;
        bool isDisableAttachmentsOnEmpty =
            field['disableAttachmentsOn'] is List &&
                (field['disableAttachmentsOn'] as List).isEmpty;
        if (isRequireAttachmentsOnEmpty && isDisableAttachmentsOnEmpty) {
          requiresAttachments = true;
        }
      }
    }

    if (field['disableAttachmentsOn'] != null) {
      List<dynamic> disabledOptions = field['disableAttachmentsOn'] is List
          ? field['disableAttachmentsOn']
          : [field['disableAttachmentsOn']];
      if (currentValue is List) {
        if (currentValue.any((v) => disabledOptions.contains(v))) {
          requiresAttachments = false;
        }
      } else if (disabledOptions.contains(currentValue)) {
        requiresAttachments = false;
      }
    }

    if (!requiresAttachments) return true;

    final uploads = uploadedFiles[fieldName];
    if (uploads == null || uploads.isEmpty) {
      return false;
    }
    return true;
  }

  /// This Dart function validates field comments if required based on certain conditions.
  ///
  /// Args:
  ///   field (Map<String, dynamic>): The `validateFieldCommentsIfRequired` function takes a
  /// `Map<String, dynamic>` named `field` as a parameter. This `field` map is expected to have a
  /// key-value pair where the key is `'hasComments'` and the value is a boolean indicating whether
  /// comments are present for the
  ///
  /// Returns:
  ///   The function `validateFieldCommentsIfRequired` returns a boolean value - `true` or `false`.
  bool validateFieldCommentsIfRequired(Map<String, dynamic> field) {
    if (field['hasComments'] == true) {
      final fieldControlName = field['name']?.toString() ?? '';
      final commentControlName = '${fieldControlName}_comment';
      if (form.contains(commentControlName) &&
          form.contains(fieldControlName)) {
        final fieldControl = form.control(fieldControlName);
        final commentControl = form.control(commentControlName);
        final show =
            shouldShowCommentsBasedOnFieldValue(field, fieldControl.value);
        if (show) {
          commentControl.markAsTouched();
          if (!commentControl.valid) return false;
        }
      }
    }
    return true;
  }

// Validate all questions and required attachments in short text mode
  bool validateAllQuestionsAndAttachments(
      groupAnchors, anchorToFieldIndices, internalFields) {
    bool isValid = true;

    // Iterate each anchor (question group)
    for (final anchor in groupAnchors) {
      final List<int> indices = anchorToFieldIndices[anchor] ?? [anchor];
      for (final idx in indices) {
        if (idx < 0 || idx >= internalFields.length) continue;
        final field = internalFields[idx];
        final String fieldName = field['name']?.toString() ?? '';

        // Skip non-visible fields according to showWhen
        if (!shouldFieldBeVisible(field)) continue;

        if (form.contains(fieldName)) {
          final control = form.control(fieldName);
          control.markAsTouched();
          if (!control.valid) {
            isValid = false;
          }
        }

        // Files/comments requirements
        if (!validateFieldAttachmentsIfRequired(field)) {
          isValid = false;
        }

        if (!validateFieldCommentsIfRequired(field)) {
          isValid = false;
        }
      }
    }

    return isValid;
  }

  /// The function `buildInputDecoration` returns an `InputDecoration` object with different border
  /// styles based on the value of the `accordionView` parameter.
  ///
  /// Args:
  ///   accordionView (bool): The `accordionView` parameter is a boolean value that determines whether
  /// the input decoration should be styled for an accordion view. If `accordionView` is true, the
  /// error border and error style will be customized with specific colors and styles for the accordion
  /// view. Otherwise, the default input decoration styles will be
  ///
  /// Returns:
  ///   The function `buildInputDecoration` returns an `InputDecoration` object with different border
  /// configurations based on the value of the `accordionView` parameter. If `accordionView` is true,
  /// it sets the error border color to the theme's error color, error style to transparent, and
  /// focused error border color to red. Otherwise, it sets the error border and style to null. The
  /// enabled border and
  InputDecoration buildInputDecoration(bool accordionView) {
    return InputDecoration(
      errorBorder: accordionView
          ? UnderlineInputBorder(
              borderSide: BorderSide(
                color: Get.theme.colorScheme.onError,
              ),
            )
          : null,
      errorStyle: accordionView
          ? const TextStyle(
              fontSize: 0,
              height: 0,
              color: Colors.transparent,
            )
          : null,
      enabledBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Colors.black),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Colors.black),
      ),
      focusedErrorBorder: accordionView
          ? const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.red, width: 2),
            )
          : null,
    );
  }
}
