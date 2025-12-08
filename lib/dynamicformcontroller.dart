import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:reactiveform/components/app_snackbar.dart';
import 'package:reactiveform/string_constants.dart';
import 'package:reactiveform/models/form_field_model.dart';

class DynamicFormController extends ChangeNotifier {
  final List<Map<String, dynamic>> formJson;
  final void Function(
          Map<String, dynamic>, Map<String, List<Map<String, dynamic>>>, bool?, bool?)
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
  List<String> _parseInitialToList(dynamic initial, List<dynamic>? options) {
    if (initial == null) return <String>[];

    if (initial is List) {
      return initial
          .map((e) => e.toString().trim())
          .where(
              (e) => e.isNotEmpty && (options == null || options.contains(e)))
          .toList();
    }
    if (initial is String) {
      final s = initial.trim();
      try {
        final decoded = jsonDecode(s);
        if (decoded is List) {
          return decoded
              .map((e) => e.toString().trim())
              .where((e) =>
                  e.isNotEmpty && (options == null || options.contains(e)))
              .toList();
        }
      } catch (_) {}
      var cleaned = s;
      if (cleaned.startsWith('[') && cleaned.endsWith(']')) {
        cleaned = cleaned.substring(1, cleaned.length - 1);
      }
      if (cleaned.isEmpty) return <String>[];
      return cleaned
          .split(',')
          .map((e) => e.trim())
          .where(
              (e) => e.isNotEmpty && (options == null || options.contains(e)))
          .toList();
    }
    return initial
        .toString()
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && (options == null || options.contains(e)))
        .toList();
  }
  Map<String, dynamic>? requiredListValidator(
      AbstractControl<dynamic> control) {
    final value = control.value;
    if (value is List && value.isNotEmpty) return null;
    return {'required': true};
  }

// --- initialization building FormGroup dynamically ---
  void _initializeForm() {
    final Map<String, AbstractControl<dynamic>> controls = {};

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
          final List<String> initialValue = _parseInitialToList(
            initial,
            field['options'] as List<dynamic>?,
          );

          controls[fieldName] = FormControl<List<String>>(
            value: initialValue,
            // <- wrap the function with Validators.delegate
            validators: field['required'] == true
                ? [Validators.delegate(requiredListValidator)]
                : [],
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
          continue;
        } else if (field['type'] == 'file') {
          // Only initialize uploadedFiles if not already set by hasAttachments logic above
          if (!uploadedFiles.containsKey(fieldName)) {
            uploadedFiles[fieldName] = [];
          }
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
            value: double.tryParse(initial?.toString() ?? '') ?? 0.0,
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
          // Handle other field types, including comma-separated types like "text, file"
          // For combo types, we need to check if hasAttachments should be true
          final String typeStr = (field['type'] ?? '').toString();
          final bool isComboWithFile = typeStr.contains(',') && typeStr.contains('file');

          // Set hasAttachments for combo fields with file type
          if (isComboWithFile && field['hasAttachments'] != true) {
            field['hasAttachments'] = true;
          }

          // Initialize uploaded files for file-containing combo types
          if (isComboWithFile) {
            final dynamic attachments = initialValues?['${fieldName}_attachments'];
            if (attachments is List) {
              uploadedFiles[fieldName] = attachments.whereType<Map<String, dynamic>>().toList();
            } else {
              uploadedFiles[fieldName] = [];
            }
          }

          controls[fieldName] = FormControl<String>(
            value: initial != null ? initial.toString() : (field['defaultValue'] ?? ''),
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
  }

  List<Validator> _getValidators(
      bool isRequired, Map<String, dynamic>? field) {
    List<Validator> validatorsList = [];

    if (isRequired) {
      // For composite types like "text, file" we enforce an either-or rule at submit time,
      // so we should not add a hard required validator to the text control here.
      final String typeStr = (field?['type'] ?? '').toString();
      final bool isCompositeTextFile =
          typeStr.contains(',') && typeStr.contains('text') && typeStr.contains('file');

      // Also, for text fields that separately require attachments, we validate at submit time.
      final bool isTextWithAttachments =
          (field != null && field['type'] == 'text' && field['hasAttachments'] == true);

      if (!(isCompositeTextFile || isTextWithAttachments)) {
        validatorsList.add(Validators.required);
      }
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

    if (kDebugMode) {
      print("=== SUBMIT FORM VALIDATION ===");
    }

    // Get all form controls and validate only visible ones
    for (var controlName in form.controls.keys) {
      final control = form.control(controlName);
      
      // Skip comment fields for now
      if (controlName.endsWith('_comment')) continue;
      
      
      // Check if this field should be visible
      bool shouldValidate = shouldValidateField(controlName);
      
      if (!shouldValidate) {
        continue;
      }
      
      // Find the field definition for additional rules
      final field = findFieldDefinition(controlName);

      // Composite rule: for required fields with type containing both text and file,
      // accept if either text is provided or a file is uploaded.
      if (field != null && field['required'] == true) {
        final String typeStr = (field['type'] ?? '').toString();
        final bool isCompositeTextFile =
            typeStr.contains(',') && typeStr.contains('text') && typeStr.contains('file');

        if (isCompositeTextFile) {
          final dynamic value = control.value;
          final bool textEmpty = value == null ||
              value.toString().isEmpty ||
              value.toString() == 'null' ||
              (value is List && value.isEmpty);
          final bool filesEmpty =
              (uploadedFiles[controlName]?.isEmpty ?? true);

          if (textEmpty && filesEmpty) {
            isValid = false;
            break;
          }
        } else {
          // Fallback to existing control validity for non-composite fields
          if (!control.valid) {
            isValid = false;
            break;
          }
        }
      } else {
        // Non-required fields: still ensure other validators
        if (!control.valid) {
          isValid = false;
          break;
        }
      }
    }


    if (isValid) {
      final formValue = Map<String, dynamic>.from(form.value);
      final nestedFormValue = createNestedStructure(formValue);
      onSubmit(nestedFormValue, uploadedFiles, false, isManageToCheckPress);
    } else {
      form.markAllAsTouched();
      _handleFormErrors(context);
    }
  }

  /// Creates a nested JSON structure for grouped fields
  Map<String, dynamic> createNestedStructure(Map<String, dynamic> formValue) {
    final Map<String, dynamic> nestedData = {};
    final Map<String, Map<String, dynamic>> groups = {};
    final Map<String, dynamic> standaloneFields = {};

    // First, identify which fields have groupId (are parent fields)
    final Set<String> parentFields = {};
    // Also identify which fields are children (appear in groupId of other fields)
    final Set<String> childFields = {};
    
    for (var field in formJson) {
      if (field['groupId'] != null && field['groupId'].toString().isNotEmpty) {
        parentFields.add(field['name']);
        // Parse the groupId to identify child fields
        final groupId = field['groupId'].toString();
        final childNames = groupId.split(',').map((s) => s.trim()).toList();
        childFields.addAll(childNames);
      }
    }

    // Group fields by their parent (only for fields that have groupId)
    formValue.forEach((fieldName, value) {
      // Skip comment fields that belong to grouped fields
      if (fieldName.endsWith('_comment') && fieldName.contains('_question_')) {
        // This is a comment field for a grouped field, skip it
        return;
      }
      
      // Check if this is a grouped field (has pattern: originalName_parentName)
      if (fieldName.contains('_question_')) {
        final parts = fieldName.split('_question_');
        if (parts.length == 2) {
          final originalName = parts[0];
          final parentName = 'question_${parts[1]}';
          
          // Only create groups for fields that have groupId
          if (parentFields.contains(parentName)) {
            // Check if this field should be visible based on showWhen conditions
            if (_shouldIncludeFieldInOutput(fieldName, originalName, parentName)) {
              // Initialize group if it doesn't exist
              if (!groups.containsKey(parentName)) {
                groups[parentName] = {};
              }
              
              // Add the field to the group with the required structure
              groups[parentName]![originalName] = {
                'answer': value?.toString() ?? '',
                'comment': formValue['${fieldName}_comment']?.toString() ?? '',
                'imageUrls': formValue['${fieldName}_images'] ?? [],
                'question': _getFieldLabel(originalName),
                'questionId': originalName,
                'groupId': parentName, // Add groupId to identify grouped fields
              };
            }
          } else {
            // This is a standalone field that happens to have underscore in name
            standaloneFields[fieldName] = {
              'answer': value?.toString() ?? '',
              'comment': formValue['${fieldName}_comment']?.toString() ?? '',
              'imageUrls': formValue['${fieldName}_images'] ?? [],
              'question': _getFieldLabel(fieldName),
              'questionId': fieldName,
            };
          }
        }
      } else {
        // This is a standalone field or parent field
        // Exclude child fields and comment fields from root level
        bool isCommentField = fieldName.endsWith('_comment');
        bool isChildField = childFields.contains(fieldName);
        bool isParentField = parentFields.contains(fieldName);
        
        
        if (!isParentField && !isChildField && !isCommentField) {
          // Check if this field should be visible based on showWhen conditions
          if (_shouldIncludeFieldInOutput(fieldName, fieldName, '')) {
            standaloneFields[fieldName] = {
              'answer': value?.toString() ?? '',
              'comment': formValue['${fieldName}_comment']?.toString() ?? '',
              'imageUrls': formValue['${fieldName}_images'] ?? [],
              'question': _getFieldLabel(fieldName),
              'questionId': fieldName,
            };
          }
        }
      }
    });

    // Add groups to nested data (only for fields with groupId)
    groups.forEach((parentName, groupData) {
      // Find the parent field to get its label and value
      final parentField = formJson.firstWhere(
        (field) => field['name'] == parentName,
        orElse: () => <String, dynamic>{},
      );
      
      final String groupLabel = parentField['label']?.toString() ?? parentName;
      final String groupName = formValue[parentName]?.toString() ?? parentName;
      
      nestedData[parentName] = {
        'name': groupName,
        'label': groupLabel,
        'data': groupData,
      };
    });

    // Add standalone fields (fields that don't have groupId)
    standaloneFields.forEach((fieldName, value) {
      nestedData[fieldName] = value;
    });

    return nestedData;
  }

  /// Get the field label for a given field name
  String _getFieldLabel(String fieldName) {
    final field = formJson.firstWhere(
      (field) => field['name'] == fieldName,
      orElse: () => <String, dynamic>{},
    );
    return field['label']?.toString() ?? fieldName;
  }

  /// Check if a field should be included in the output based on showWhen conditions
  bool _shouldIncludeFieldInOutput(String fieldName, String originalName, String parentName) {
    // Find the original field definition
    final originalField = formJson.firstWhere(
      (field) => field['name'] == originalName,
      orElse: () => <String, dynamic>{},
    );

    if (originalField.isEmpty) return true;

    // If no showWhen condition, include the field
    if (originalField['showWhen'] == null) return true;

    final conditions = originalField['showWhen'] as Map<String, dynamic>;
    bool shouldShow = true;

    conditions.forEach((dependentField, expectedValue) {
      // For grouped fields, we need to check the transformed field name
      String actualDependentField = dependentField;
      
      // If the dependent field is also a child field, it might be transformed
      // Check if there's a transformed version with the same parent
      // The pattern is: question_X_question_Y
      if (form.contains('${dependentField}_${parentName}')) {
        actualDependentField = '${dependentField}_${parentName}';
      }
      
      // Check if the dependent field exists in the form
      if (!form.contains(actualDependentField)) {
        shouldShow = false;
        return;
      }

      // Get the value of the dependent field
      final fieldValue = form.control(actualDependentField).value;
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

  /// Check if a field should be validated based on showWhen conditions
  bool shouldValidateField(String controlName) {
    // Find the field definition for this control
    final field = findFieldDefinition(controlName);
    if (field == null) {
      if (kDebugMode) {
        print("_shouldValidateField: Field definition not found for $controlName");
      }
      return true;
    }

    // If no showWhen condition, validate the field
    if (field['showWhen'] == null) {
      if (kDebugMode) {
        print("_shouldValidateField: No showWhen condition for $controlName - validating");
      }
      return true;
    }

    final conditions = field['showWhen'] as Map<String, dynamic>;
    bool shouldShow = true;

    if (kDebugMode) {
      print("_shouldValidateField: Checking $controlName with conditions: $conditions");
    }

    conditions.forEach((dependentField, expectedValue) {
      // For grouped fields, we need to find the correct transformed field name
      String actualDependentField = _findTransformedFieldName(controlName, dependentField);
      
      if (kDebugMode) {
        print("_shouldValidateField: $controlName depends on $actualDependentField = $expectedValue");
      }
      
      // Check if the dependent field exists in the form
      if (!form.contains(actualDependentField)) {
        if (kDebugMode) {
          print("_shouldValidateField: Dependent field $actualDependentField not found in form");
        }
        shouldShow = false;
        return;
      }

      // Get the value of the dependent field
      final fieldValue = form.control(actualDependentField).value;
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

      if (kDebugMode) {
        print("_shouldValidateField: $controlName - $actualDependentField = $fieldValue, expected = $expectedValue, matches = $fieldMatches");
      }

      shouldShow = shouldShow && fieldMatches;
    });

    if (kDebugMode) {
      print("_shouldValidateField: $controlName should validate = $shouldShow");
    }

    return shouldShow;
  }

  /// Find the transformed field name for showWhen conditions
  String _findTransformedFieldName(String currentFieldName, String dependentField) {
    // If current field is grouped (has pattern: originalName_parentName)
    if (currentFieldName.contains('_question_')) {
      final parts = currentFieldName.split('_question_');
      if (parts.length == 2) {
        final parentName = 'question_${parts[1]}';
        // Return the transformed dependent field name
        return '${dependentField}_${parentName}';
      }
    }
    
    // If current field is not grouped, return the original dependent field name
    return dependentField;
  }

  /// Find the field definition for a control name
  Map<String, dynamic>? findFieldDefinition(String controlName) {
    
    // Check if it's a grouped field (has pattern: originalName_parentName)
    if (controlName.contains('_question_')) {
      final parts = controlName.split('_question_');
      if (parts.length == 2) {
        final originalName = parts[0];
        final field = formJson.firstWhere(
          (field) => field['name'] == originalName,
          orElse: () => <String, dynamic>{},
        );
        return field.isNotEmpty ? field : null;
      }
    }
    
    // Check if it's a direct field
    final field = formJson.firstWhere(
      (field) => field['name'] == controlName,
      orElse: () => <String, dynamic>{},
    );
    return field.isNotEmpty ? field : null;
  }

  /// Creates a clean group key from the fridge label
  String _createGroupKey(String label) {
    // Extract fridge name from label (e.g., "Fridge name/number: Walk in Fridge 1" -> "walk_in_fridge_1")
    final fridgeName = label.split(':').last.trim().toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll('-', '_');
    return fridgeName;
  }

  void _handleFormErrors(BuildContext context) {
    // Find the first invalid field that should be visible
    String? firstInvalidField;
    
    for (var controlName in form.controls.keys) {
      if (controlName.endsWith('_comment')) continue;
      
      final control = form.control(controlName);
      if (!control.valid && shouldValidateField(controlName)) {
        final field = findFieldDefinition(controlName);
        if (field != null && field['required'] == true) {
          firstInvalidField = controlName;
          break;
        }
      }
    }

    if (firstInvalidField != null) {
      // Find the index of the field in formJson for navigation
      int errorIndex = formJson.indexWhere((field) => field['name'] == firstInvalidField);
      if (errorIndex == -1) {
        // If it's a grouped field, find the parent field
        if (firstInvalidField.contains('_question_')) {
          final parts = firstInvalidField.split('_question_');
          if (parts.length == 2) {
            final parentName = 'question_${parts[1]}';
            errorIndex = formJson.indexWhere((field) => field['name'] == parentName);
          }
        }
      }

    if (errorIndex != -1) {
      _currentQuestionIndex = errorIndex;
      }

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

        // If hasAttachments is true and both requireAttachmentsOn and disableAttachmentsOn are empty arrays,
        // default to requiring a file unless there is text entered (either-or rule)
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

        // Either-or: if there is text, do not require file
        final bool hasText = currentControl.value != null &&
            currentControl.value.toString().trim().isNotEmpty;
        if (hasText) {
          fileRequired = false;
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

    // Helper function to check if controlValue matches any disabled option
    bool isValueInDisabledOptions() {
      if (disabledOptions.isEmpty) return false;

      // For multiselect (List values), check if any selected value is in disabled options
      if (controlValue is List) {
        return controlValue.any((val) => disabledOptions.contains(val));
      }

      // For single values (dropdown, radio, date, etc.)
      return disabledOptions.contains(controlValue);
    }

    // If control value is in disabled options, don't show comments
    if (isValueInDisabledOptions()) {
      return false;
    }

    bool shouldShowComments = false;

    // Helper function to check if controlValue matches any option in a list
    bool isValueInOptions(List<dynamic> options) {
      if (options.isEmpty) return false;

      // For multiselect (List values), check if any selected value is in the options
      if (controlValue is List) {
        return controlValue.any((val) => options.contains(val));
      }

      // For single values
      return options.contains(controlValue);
    }

    // Check if field has comments and if the value is not in disabled options
    if (field['hasComments'] == true &&
        disabledOptions.isNotEmpty &&
        !isValueInDisabledOptions()) {
      shouldShowComments = true;
    } else {
      // Check requireCommentsOn
      if (field['requireCommentsOn'] != null) {
        List<dynamic> requiredOptions = field['requireCommentsOn'] is List
            ? field['requireCommentsOn']
            : [field['requireCommentsOn']];

        if (isValueInOptions(requiredOptions)) {
          shouldShowComments = true;
        }
      }

      // Check for legacy Comments Required property
      if (!shouldShowComments && field['enableCommentsOn'] != null) {
        List<dynamic> enabledOptions = field['enableCommentsOn'] is List
            ? field['enableCommentsOn']
            : [field['enableCommentsOn']];

        if (isValueInOptions(enabledOptions)) {
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
      // Either-or for text with attachments: if files exist, don't flag as error
      if (field['type'] == 'text' && field['hasAttachments'] == true) {
        final bool hasFiles = uploadedFiles[fieldName]?.isNotEmpty ?? false;
        if (!hasFiles) {
          return true;
        }
      } else {
        return true;
      }
    }

    if (field['hasAttachments'] != false) {
      final selectedValue = currentControl.value;

      final bool isMultiselect = field['type'] == 'multiselect';

      

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

        // If hasAttachments is true and both requireAttachmentsOn and disableAttachmentsOn are empty arrays,
        // default to requiring a file unless there is text entered (either-or rule)
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
        // Either-or: if there is text, do not require file
        final bool hasText = currentControl.value != null &&
            currentControl.value.toString().trim().isNotEmpty;
        if (hasText) {
          fileRequired = false;
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
      // Either-or for text with attachments: if files exist, don't show empty error
      if (field['type'] == 'text' && field['hasAttachments'] == true) {
        final String fieldName = field['name']?.toString() ?? '';
        final bool hasFiles = uploadedFiles[fieldName]?.isNotEmpty ?? false;
        if (!hasFiles) {
          if (field['type'] == "radio") {
            return StringConstants.pleaseSelectAnOption;
          } else if (field['type'] == 'text' || field['type'] == 'number') {
            return StringConstants.requiredField;
          } else {
            return StringConstants.pleaseAnswerThisQuestion;
          }
        }
      } else {
        if (field['type'] == "radio") {
          return StringConstants.pleaseSelectAnOption;
        } else if (field['type'] == 'text' || field['type'] == 'number') {
          return StringConstants.requiredField;
        } else {
          return StringConstants.pleaseAnswerThisQuestion;
        }
      }
    }

    if (field['hasAttachments'] != false) {
      bool fileRequired = false;
      final selectedValue = control.value;

      final bool isMultiselect = field['type'] == 'multiselect';

      

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

        // If hasAttachments is true and both requireAttachmentsOn and disableAttachmentsOn are empty arrays,
        // default to requiring a file unless there is text entered (either-or rule)
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
        // Either-or: if there is text, do not require file
        final bool hasText = control.value != null &&
            control.value.toString().trim().isNotEmpty;
        if (hasText) {
          fileRequired = false;
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
          // Only initialize uploadedFiles if not already set
          if (!uploadedFiles.containsKey(n)) {
            uploadedFiles[n] = [];
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
              value: initial != null ? double.tryParse(initial.toString()) : 0.0, 
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
    if (conditions.isEmpty) return true;
    bool shouldShow = true;
    conditions.forEach((dependentField, expectedValue) {
      String actualDependentField = _findTransformedFieldNameForVisibility(field, dependentField);
      if (!form.contains(actualDependentField)) {
        if (form.contains(dependentField)) {
          actualDependentField = dependentField;
        } else {
          shouldShow = false;
          return;
        }
      }
      final currentValue = form.control(actualDependentField).value;
      final bool matches = _valuesMatch(expectedValue, currentValue);
      shouldShow = shouldShow && matches;
    });
    return shouldShow;
  }

  // Normalize and compare expected vs current values with leniency for strings
  bool _valuesMatch(dynamic expected, dynamic current) {
    if (expected is List) {
      // If expected is a list, match if any element equals current (normalized)
      return expected.any((e) => _valuesMatch(e, current));
    }
    if (current is List) {
      // If current is a list, match if any element equals expected (normalized)
      return current.any((c) => _valuesMatch(expected, c));
    }
    if (expected is String && current is String) {
      return expected.trim().toLowerCase() == current.trim().toLowerCase();
    }
    return current == expected;
  }

  /// Find the transformed field name for showWhen conditions in shouldFieldBeVisible
  String _findTransformedFieldNameForVisibility(Map<String, dynamic> currentField, String dependentField) {
    // Check if current field is grouped (has groupWith property)
    if (currentField['groupWith'] != null) {
      final parentName = currentField['groupWith'].toString();
      
      // Check if the dependent field is also a child field that should be transformed
      // Look for the dependent field in the original formJson to see if it's a child field
      final dependentFieldDef = formJson.firstWhere(
        (field) => field['name'] == dependentField,
        orElse: () => <String, dynamic>{},
      );
      
      if (dependentFieldDef.isNotEmpty && dependentFieldDef['groupWith'] != null) {
        // The dependent field is also a child field, so it should be transformed
        final transformedName = '${dependentField}_${parentName}';
        
        
        return transformedName;
      } else {
        // The dependent field is not a child field, return as is
        return dependentField;
      }
    }
    
    
    // If current field is not grouped, return the original dependent field name
    return dependentField;
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
    String actualFieldName = fieldName;
    for (String controlName in form.controls.keys) {
      if (controlName.startsWith(fieldName) &&
          controlName.contains('_question_')) {
        actualFieldName = controlName;
        break;
      }
    }

    // Get current value from the form (if control exists)
    dynamic currentValue = form.contains(actualFieldName)
        ? form.control(actualFieldName).value
        : null;
    final String typeStr = (field['type'] ?? '').toString();
    final bool isCompositeTextFile =
        typeStr.contains('text') && typeStr.contains('file');
    if (isCompositeTextFile) {
      if (field['required'] == true) {
        final bool textIsEmpty = currentValue == null ||
            (currentValue is String && currentValue.trim().isEmpty) ||
            (currentValue is List && currentValue.isEmpty);
        final bool hasFiles =
            uploadedFiles[actualFieldName]?.isNotEmpty ?? false;
        return !textIsEmpty || hasFiles;
      } else {
        return true;
      }
    }

    bool requiresAttachments = false;

    // If type is exactly 'file' and required true => attachments required
    if (typeStr == 'file' && field['required'] == true) {
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

    // If attachments are required, ensure there is at least one uploaded file
    final uploads = uploadedFiles[actualFieldName];
    return uploads != null && uploads.isNotEmpty;
  }

  /// Separate commenter validation - enforce comment presence when hasComments == true
  bool validateFieldCommentIfRequired(Map<String, dynamic> field) {
    if (field['hasComments'] != true) return true;

    final String fieldName = field['name']?.toString() ?? '';

    // --- Find actual/control name for grouped fields (same approach) ---
    String actualFieldName = fieldName;
    for (String controlName in form.controls.keys) {
      if (controlName.startsWith(fieldName) &&
          controlName.contains('_question_')) {
        actualFieldName = controlName;
        break;
      }
    }

    final String commentControlName = '${actualFieldName}_comment';
    if (!form.contains(commentControlName))
      return false; // comment control missing -> fail
    final dynamic commentValue = form.control(commentControlName).value;

    if (commentValue == null) return false;
    if (commentValue is String && commentValue.trim().isEmpty) return false;
    if (commentValue is List && commentValue.isEmpty) return false;

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
      
      // Check if this is a grouped field by looking for the transformed name
      String actualFieldControlName = fieldControlName;
      String actualCommentControlName = commentControlName;
      
      // Look for grouped field names in the form controls
      for (String controlName in form.controls.keys) {
        if (controlName.startsWith(fieldControlName) && controlName.contains('_question_')) {
          actualFieldControlName = controlName;
          actualCommentControlName = '${controlName}_comment';
          break;
        }
      }
      
      if (form.contains(actualCommentControlName) &&
          form.contains(actualFieldControlName)) {
        final fieldControl = form.control(actualFieldControlName);
        final commentControl = form.control(actualCommentControlName);
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
