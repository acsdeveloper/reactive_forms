import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:reactive_forms/src/validators/validators.dart';
import 'package:reactiveform/string_constants.dart';
import 'package:reactiveform/models/form_field_model.dart';


class DynamicFormController extends ChangeNotifier {
  final List<Map<String, dynamic>> formJson;
  final void Function(Map<String, dynamic>, Map<String, List<Map<String, dynamic>>> uploadedFiles) onSubmit;
  
  late FormGroup form;
  Map<String, List<Map<String, dynamic>>> uploadedFiles = {};
  int currentQuestionIndex = 0;
  Map<String, dynamic> _values = {};
  final List<FormFieldModel> _fields;

  DynamicFormController({
    required this.formJson,
    required this.onSubmit,
  }) : _fields = formJson.map((json) => FormFieldModel.fromJson(json)).toList() {
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
            initialValue = (field['defaultValue'] as List).map((item) => item.toString()).toList();
          }
        }
        
        // Debug print
        print('Initializing multiselect field: $fieldName with initial value: $initialValue');
        
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
          validators: _getValidators(field ['required'], field),
        );
      } else if (field['type'] == 'radio') {
        // Set default Yes/No options for radio type if no options provided
        if (field['options'] == null || (field['options'] as List).isEmpty) {
          field['options'] = ['Yes', 'No'];
        }
        controls[fieldName] = FormControl<String>(
          value: field['defaultValue'] ?? '', // Initialize with default value if provided
          validators: _getValidators(field['required'], field),
        );
        
        if (field['hasComments'] == true) {
          controls['${fieldName}_comment'] = FormControl<String>(value: '');
        }
      } else {
        // Initialize form controls for non-file fields
        controls[fieldName] = FormControl<String>(
          value: field['defaultValue'] ?? '',
          validators: _getValidators(field['required'], field),
        );
        
        if (field['hasComments'] == true) {
          controls['${fieldName}_comment'] = FormControl<String>(value: '');
        }
        
        if (field['subQuestions'] != null) {
          (field['subQuestions'] as Map<String, dynamic>).forEach((answer, subQuestions) {
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

  List<Validator<dynamic>> _getValidators( bool validators, Map<String, dynamic>? field) {
    List<Validator<dynamic>> validatorsList = [];
    


    // Add required validator if present
    if (validators==true) {
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

  static Map<String, dynamic>? _multiSelectValidator(AbstractControl<dynamic> control) {
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
      print('Field: $fieldName, Value: ${control.value}, Valid: ${control.valid}');
      
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
      return field['required']== true && 
             (control.value == null || control.value.toString().isEmpty);
    });
    
    if (errorIndex != -1) {
      currentQuestionIndex = errorIndex;
      
      ScaffoldMessenger.of(context).showSnackBar(
       const SnackBar(
          content: Text(StringConstants.fillAllFields),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  bool validateAndProceed(BuildContext context) {
    final field = formJson[currentQuestionIndex];
    final currentFieldName = field['name'];
    final currentControl = form.control(currentFieldName);

    // Mark the current field as touched to trigger validation
    currentControl.markAsTouched();

    // Special handling for multiselect validation
    if (field['type'] == 'multiselect' && field['required'] == true) {
      if (currentControl.value == null) {
        _showErrorSnackBar(context, 'Please select at least one option');
        notifyListeners();
        return false;
      }
      
      final List<dynamic>? values = currentControl.value is List ? currentControl.value : null;
      if (values == null || values.isEmpty) {
        _showErrorSnackBar(context, 'Please select at least one option');
        notifyListeners();
        return false;
      }
    }

    // Check if the current field is valid
    if (!currentControl.valid) {
      String errorMessage = _getErrorMessage(field, currentControl);
      _showErrorSnackBar(context, errorMessage);
      notifyListeners();
      return false;
    }

    // Handle branching logic
    int nextIndex = _findNextQuestionIndex(currentQuestionIndex, currentControl.value);
    if (nextIndex == -2) {
      return true;
    } else if (nextIndex != -1) {
      currentQuestionIndex = nextIndex;
    } else if (currentQuestionIndex < formJson.length - 1) {
      currentQuestionIndex++;
    }

    notifyListeners();
    return true;
  }

  int _findNextQuestionIndex(int currentIndex, dynamic currentValue) {
    final currentField = formJson[currentIndex];
    
    if (currentField['branching'] != null) {
      var branchTo = currentField['branching'];
      
      if (branchTo is Map<String, dynamic>) {
        // For multiselect, we might want to check if any of the selected values trigger branching
        if (currentField['type'] == 'multiselect' && currentValue is List) {
          for (var value in currentValue) {
            String? targetQuestion = branchTo[value.toString()];
            if (targetQuestion == 'end') {
              return -2;
            }
            if (targetQuestion != null) {
              int targetIndex = formJson.indexWhere((field) => field['name'] == targetQuestion);
              if (targetIndex != -1) {
                return targetIndex;
              }
            }
          }
        } else {
          // Regular single-value branching
          String? targetQuestion = branchTo[currentValue?.toString()];
          if (targetQuestion == 'end') {
            return -2;
          }
          if (targetQuestion != null) {
            int targetIndex = formJson.indexWhere((field) => field['name'] == targetQuestion);
            if (targetIndex != -1) {
              return targetIndex;
            }
          }
        }
      }
    }
    
    return -1;
  }

  bool _hasValidationError(Map<String, dynamic> field, AbstractControl currentControl, String fieldName) {
    // Add multiselect validation
    if (field['type'] == 'multiselect' && field['required'] == true) {
      final List<String>? values = currentControl.value as List<String>?;
      if (values == null || values.isEmpty) {
        return true;
      }
    }

    // Required field validation
    if (field['required'] == true && 
        (currentControl.value == null || currentControl.value.toString().isEmpty)) {
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

  String _getErrorMessage(Map<String, dynamic> field, AbstractControl control) {
    if (field['type'] == 'multiselect') {
      // First check if value is actually a List
      final dynamic rawValue = control.value;
      final List<dynamic>? values = rawValue is List ? rawValue : null;
      
      if (field['required'] == true && (values == null || values.isEmpty)) {
        return 'Please select at least one option';
      }
    }
    
    if (field['required'] == true && 
        (control.value == null || control.value.toString().isEmpty)) {
      return field['type'] == 'radio' 
          ? StringConstants.pleaseSelectAnOption
          : StringConstants.pleaseAnswerThisQuestion;
    }
    
    if (field['requireAttachmentsOn'] == control.value) {
      return StringConstants.uploadRequiredFiles;
    }
    
    return StringConstants.pleaseAnswerAllRequiredSubQuestions;
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void showDropdownBottomSheet(BuildContext context, Map<String, dynamic> field) {
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
              (field['options'] as List).map((option) => 
                ListTile(
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
    if (currentQuestionIndex >= formJson.length) return false;
    
    final currentField = formJson[currentQuestionIndex];
    if (currentField['branching'] == null) return false;
    
    var branchTo = currentField['branching'];
    if (branchTo is Map<String, dynamic>) {
      String? targetQuestion = branchTo[form.control(currentField['name']).value?.toString()];
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
      final dependentControl = form.control(dependentField);
      if (expectedValue is List) {
        shouldShow = shouldShow && expectedValue.contains(dependentControl.value);
      } else {
        shouldShow = shouldShow && dependentControl.value == expectedValue;
      }
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
}