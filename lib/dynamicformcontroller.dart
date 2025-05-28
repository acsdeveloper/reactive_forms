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
  List<int> _navigationHistory = [];
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

    void _addControlsForFields(Iterable<Map<String, dynamic>> fieldList) {
      for (var field in fieldList) {
        final fieldName = field['name'];

        if (controls.containsKey(fieldName)) {
          continue;
        }

        if (field['type'] == 'multiselect') {
          List<String> initialValue = [];
          if (field['defaultValue'] != null && field['defaultValue'] is List) {
            initialValue = (field['defaultValue'] as List)
                .map((item) => item.toString())
                .toList();
          }

          controls[fieldName] = FormControl<List<String>>(
            value: initialValue,
            validators: field['required'] == true ? [Validators.required] : [],
          );

          if (field['hasComments'] == true) {
            controls['${fieldName}_comment'] = FormControl<String>(
              value: '',
              validators: [Validators.required],
            );
          }
        } else if (field['type'] == 'file') {
          uploadedFiles[fieldName] = [];
          controls[fieldName] = FormControl<String>(
            value: '',
            validators: field['required'] == true ? [Validators.required] : [],
          );

          if (field['hasComments'] == true) {
            controls['${fieldName}_comment'] = FormControl<String>(
              value: '',
              validators: [Validators.required],
            );
          }
        } else if (field['type'] == 'number') {
          controls[fieldName] = FormControl<num>(
            value: null,
            validators: _getValidators(field['required'] == true, field),
          );

          if (field['hasComments'] == true) {
            controls['${fieldName}_comment'] = FormControl<String>(
              value: '',
              validators: [Validators.required],
            );
          }
        } else if (field['type'] == 'radio') {
          if (field['options'] == null || (field['options'] as List).isEmpty) {
            field['options'] = ['Yes', 'No'];
          }
          controls[fieldName] = FormControl<String>(
            value: field['defaultValue'] ?? '',
            validators: _getValidators(field['required'] == true, field),
          );

          if (field['hasComments'] == true) {
            controls['${fieldName}_comment'] = FormControl<String>(
              value: '',
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

    // Debug: Print initial form values
    if (kDebugMode) {
      print('Initial form values: ${form.value}');
    }

    // Ensure we start with a visible question
    if (!shouldDisplayQuestion(_currentQuestionIndex)) {
      int nextVisibleIndex = findNextVisibleQuestionIndex();
      if (nextVisibleIndex != -1) {
        _currentQuestionIndex = nextVisibleIndex;
        if (kDebugMode) {
          print(
              'First question not visible, moving to index: $_currentQuestionIndex');
        }
      }
    }
  }

  List<Validator<dynamic>> _getValidators(
      bool isRequired, Map<String, dynamic>? field) {
    List<Validator<dynamic>> validatorsList = [];

    if (isRequired) {
      validatorsList.add(Validators.required);
      // if (kDebugMode) {
      //   print("Adding required validator for field ${field?['name']}");
      // }
    }

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

  bool validateAndProceed(BuildContext context) {
    // Ensure we're not out of bounds
    if (_currentQuestionIndex < 0 || _currentQuestionIndex >= formJson.length) {
      if (kDebugMode) {
        print(
            "Error: Current question index out of bounds: $_currentQuestionIndex");
      }
      return false;
    }

    final field = formJson[_currentQuestionIndex];
    final currentFieldName = field['name'];

    if (kDebugMode) {
      print("Validating field: $currentFieldName");
    }

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

    // Validate comments if required
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

    // Validate file uploads if required
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

        // Check: If hasAttachments is true and both requireAttachmentsOn and disableAttachmentsOn are empty arrays,
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

        if (fileRequired &&
            (uploadedFiles[currentFieldName]?.isEmpty ?? true)) {
          AppSnackBar(context)
              .showErrorSnackBar(StringConstants.uploadRequiredFiles);
          notifyListeners();
          return false;
        }
      }
    }

    // Validate multiselect fields
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

    // Field validation passed, add current question to navigation history before moving
    _navigationHistory.add(_currentQuestionIndex);

    // Check for branching rules first - they take precedence
    if (field['branching'] != null &&
        field['branching'] is Map<String, dynamic>) {
      final Map<String, dynamic> branchingRules = field['branching'];
      final String? selectedValue = currentControl.value?.toString();

      if (selectedValue != null && branchingRules.containsKey(selectedValue)) {
        final dynamic targetQuestion = branchingRules[selectedValue];

        if (targetQuestion == 'end') {
          // This branch leads to the end of the form - show submit button
          if (kDebugMode) {
            print("Navigation: Branching to 'end' - form complete");
          }
          notifyListeners();
          return true;
        } else if (targetQuestion is String) {
          // Find the index of the target question
          int targetIndex = -1;
          for (int i = 0; i < formJson.length; i++) {
            if (formJson[i]['name'] == targetQuestion) {
              targetIndex = i;
              break;
            }
          }

          if (targetIndex != -1) {
            if (shouldDisplayQuestion(targetIndex)) {
              _currentQuestionIndex = targetIndex;
              if (kDebugMode) {
                print(
                    "Navigation: Branching to question '$targetQuestion' at index $targetIndex");
              }
              notifyListeners();
              return true;
            } else {
              if (kDebugMode) {
                print(
                    "Navigation: Branching target '$targetQuestion' is not visible - finding next visible question");
              }
              // The branching target is not visible, find next visible
              int nextVisibleIndex = findNextVisibleQuestionIndex(targetIndex);
              if (nextVisibleIndex != -1) {
                _currentQuestionIndex = nextVisibleIndex;
                if (kDebugMode) {
                  print(
                      "Navigation: Found next visible question at index $nextVisibleIndex");
                }
                notifyListeners();
                return true;
              }
            }
          }
        }
      }
    }

    // No branching or branching target not found/valid, find next visible question
    int nextVisibleIndex = findNextVisibleQuestionIndex();

    if (nextVisibleIndex != -1) {
      _currentQuestionIndex = nextVisibleIndex;
      if (kDebugMode) {
        print(
            "Navigation: Moving to next visible question at index $nextVisibleIndex");
      }
    } else {
      // No more visible questions - we're at the end of the form
      if (kDebugMode) {
        print("Navigation: No more visible questions found - form complete");
      }
    }

    notifyListeners();
    return true;
  }

  int findNextVisibleQuestionIndex([int? startFromIndex]) {
    int startIndex = startFromIndex ?? _currentQuestionIndex;
    if (kDebugMode) {
      print("Finding next visible question after index $startIndex");
    }

    for (int i = startIndex + 1; i < formJson.length; i++) {
      if (shouldDisplayQuestion(i)) {
        if (kDebugMode) {
          print(
              "Found next visible question at index $i (${formJson[i]['name']})");
        }
        return i;
      }
    }

    if (kDebugMode) {
      print("No more visible questions found after index $startIndex");
    }
    return -1;
  }

  bool shouldDisplayQuestion(int questionIndex) {
    if (questionIndex >= formJson.length) {
      return false;
    }

    final question = formJson[questionIndex];

    // NEW: Questions with groupWith should not appear as standalone questions
    // They should only appear as part of their parent question's group
    if (question['groupWith'] != null &&
        question['groupWith'].toString().isNotEmpty) {
      if (kDebugMode) {
        print(
            "Question ${question['name']} has groupWith=${question['groupWith']}, excluding from standalone navigation");
      }
      return false;
    }

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

        // Make sure we correctly determine if field is required
        final bool isRequired = f['required'] == true;

        // Log the field we're adding
        // if (kDebugMode) {
        //   print(
        //       "Adding control for field: $n, type: ${f['type']}, required: $isRequired, isDuplicate: ${f['isDuplicate'] == true}");
        // }

        if (f['type'] == 'multiselect') {
          List<String> initialValue = [];
          if (f['defaultValue'] != null && f['defaultValue'] is List) {
            initialValue = (f['defaultValue'] as List)
                .map((item) => item.toString())
                .toList();
          }

          // Use _getValidators to ensure consistency
          List<Validator> validators = _getValidators(isRequired, f);

          // if (kDebugMode) {
          //   print(
          //       "Adding multiselect field $n with ${validators.length} validators, required=$isRequired");
          // }

          newControls[n] = FormControl<List<String>>(
              value: initialValue, validators: validators);

          if (f['hasComments'] == true) {
            newControls['${n}_comment'] = FormControl<String>(
                value: '', validators: [Validators.required]);
          }
        } else if (f['type'] == 'file') {
          // For file fields, we need to ensure the uploadedFiles entry is initialized
          uploadedFiles[n] = [];

          // Use _getValidators to ensure consistency
          List<Validator> validators = _getValidators(isRequired, f);

          // if (kDebugMode) {
          //   print(
          //       "Adding file field $n with ${validators.length} validators, required=$isRequired");
          // }

          newControls[n] = FormControl<String>(
            value: '',
            validators: validators,
          );

          if (f['hasComments'] == true) {
            newControls['${n}_comment'] = FormControl<String>(
                value: '', validators: [Validators.required]);
          }
        } else if (f['type'] == 'number') {
          // Use the getValidators helper to ensure consistency
          List<Validator> validators = _getValidators(isRequired, f);

          // if (kDebugMode) {
          //   print(
          //       "Adding number field $n with ${validators.length} validators, required=$isRequired");
          // }

          newControls[n] =
              FormControl<num>(value: null, validators: validators);

          if (f['hasComments'] == true) {
            newControls['${n}_comment'] = FormControl<String>(
                value: '', validators: [Validators.required]);
          }
        } else if (f['type'] == 'radio') {
          if (f['options'] == null || (f['options'] as List).isEmpty) {
            f['options'] = ['Yes', 'No'];
          }

          // Use _getValidators to ensure consistency
          List<Validator> validators = _getValidators(isRequired, f);

          // if (kDebugMode) {
          //   print(
          //       "Adding radio field $n with ${validators.length} validators, required=$isRequired");
          // }

          newControls[n] = FormControl<String>(
            value: f['defaultValue'] ?? '',
            validators: validators,
          );

          if (f['hasComments'] == true) {
            newControls['${n}_comment'] = FormControl<String>(
                value: '', validators: [Validators.required]);
          }
        } else {
          // Default case for text and other field types
          List<Validator> validators = _getValidators(isRequired, f);

          // if (kDebugMode) {
          //   print(
          //       "Adding text field $n with ${validators.length} validators, required=$isRequired");
          // }

          newControls[n] = FormControl<String>(
              value: f['defaultValue'] ?? '', validators: validators);

          if (f['hasComments'] == true) {
            newControls['${n}_comment'] = FormControl<String>(
                value: '', validators: [Validators.required]);
          }
        }
      }
    }

    _addControls(newFields);
    form.addAll(newControls);

    // Debug log of all controls after adding
    if (kDebugMode) {
      // print("=== Form Controls After Adding ===");
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

  /// Moves to the previous question that the user actually saw
  /// Returns true if successful, false if there's no previous question
  bool moveToPreviousQuestion() {
    if (kDebugMode) {
      print("moveToPreviousQuestion called");
      print("Current index: $_currentQuestionIndex");
      print("Navigation history: $_navigationHistory");
    }

    // If navigation history is empty, try to find the previous visible question
    if (_navigationHistory.isEmpty) {
      if (kDebugMode) {
        print(
            "Navigation history is empty, looking for previous visible question");
      }

      // Find the previous visible question before the current one
      int previousVisibleIndex = -1;
      for (int i = _currentQuestionIndex - 1; i >= 0; i--) {
        if (shouldDisplayQuestion(i)) {
          previousVisibleIndex = i;
          break;
        }
      }

      if (previousVisibleIndex != -1) {
        _currentQuestionIndex = previousVisibleIndex;
        if (kDebugMode) {
          print(
              "Found previous visible question at index $previousVisibleIndex");
        }
        notifyListeners();
        return true;
      } else {
        if (kDebugMode) {
          print("No previous visible question found");
        }
        return false;
      }
    }

    int previousIndex = _navigationHistory.removeLast();
    if (kDebugMode) {
      print("Trying to navigate back to index $previousIndex");
    }

    // Check if the previous question from history is still visible
    if (shouldDisplayQuestion(previousIndex)) {
      _currentQuestionIndex = previousIndex;
      if (kDebugMode) {
        print(
            "Successfully navigated back to visible question at index $previousIndex");
      }
      notifyListeners();
      return true;
    }

    // If the previous question from history is no longer visible,
    // find the closest previous visible question to our current position
    if (kDebugMode) {
      print(
          "Question at index $previousIndex is no longer visible, finding alternative");
    }

    // Try to find a visible question before the one that's no longer visible
    int alternativeIndex = -1;
    for (int i = previousIndex - 1; i >= 0; i--) {
      if (shouldDisplayQuestion(i)) {
        alternativeIndex = i;
        break;
      }
    }

    // If we found an alternative, use it
    if (alternativeIndex != -1) {
      _currentQuestionIndex = alternativeIndex;
      if (kDebugMode) {
        print("Found alternative previous question at index $alternativeIndex");
      }
      notifyListeners();
      return true;
    }

    // If no alternative found, check if there are more items in navigation history
    while (_navigationHistory.isNotEmpty) {
      previousIndex = _navigationHistory.removeLast();
      if (kDebugMode) {
        print("Checking next item in history: index $previousIndex");
      }

      if (shouldDisplayQuestion(previousIndex)) {
        _currentQuestionIndex = previousIndex;
        if (kDebugMode) {
          print("Found visible question in history at index $previousIndex");
        }
        notifyListeners();
        return true;
      }
    }

    // As a last resort, go to the first visible question
    int firstVisibleIndex = findFirstVisibleQuestionIndex();
    if (firstVisibleIndex != -1) {
      _currentQuestionIndex = firstVisibleIndex;
      if (kDebugMode) {
        print(
            "Falling back to first visible question at index $firstVisibleIndex");
      }
      notifyListeners();
      return true;
    }

    if (kDebugMode) {
      print("No visible questions found, navigation failed");
    }
    return false;
  }

  /// Finds the index of the first visible question in the form
  int findFirstVisibleQuestionIndex() {
    for (int i = 0; i < formJson.length; i++) {
      if (shouldDisplayQuestion(i)) {
        return i;
      }
    }
    return -1;
  }

  /// Calculates the visual question number based on visible questions only
  /// Returns a 1-based index (first question is #1)
  int calculateVisualQuestionNumber(int questionIndex) {
    // Start with the first question being #1
    int visualNumber = 1;

    // Get all visible question indices first to ensure proper sequence
    List<int> visibleIndices = [];
    for (int i = 0; i < formJson.length; i++) {
      if (shouldDisplayQuestion(i)) {
        visibleIndices.add(i);
      }
    }

    // Find the position of the current question in the visible questions list
    int position = visibleIndices.indexOf(questionIndex);

    // If we found the question in our visible list, its number is position + 1
    // Otherwise, default to 1
    if (position != -1) {
      visualNumber = position + 1;
      if (kDebugMode) {
        print(
            "Visual question number for index $questionIndex (${formJson[questionIndex]['name']}): $visualNumber");
        print("Total visible questions: ${visibleIndices.length}");
      }
    } else {
      if (kDebugMode) {
        print(
            "Warning: Question at index $questionIndex is not in visible questions list!");
      }
    }

    return visualNumber;
  }

  /// Adds debugging information about the current navigation state
  void debugNavigationState() {
    if (kDebugMode) {
      print("Current index: $_currentQuestionIndex");
      print("Navigation history: $_navigationHistory");
      print(
          "Is current question visible: ${shouldDisplayQuestion(_currentQuestionIndex)}");
      print("Next visible question index: ${findNextVisibleQuestionIndex()}");
      print("Should show submit button: ${shouldShowSubmitButton()}");
      print(
          "Visual question number: ${calculateVisualQuestionNumber(_currentQuestionIndex)}");
    }
  }
}
