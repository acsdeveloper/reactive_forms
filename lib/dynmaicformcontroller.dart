import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:reactiveform/string_constants.dart';


class DynamicFormController {
  final List<Map<String, dynamic>> formJson;
  final void Function(Map<String, dynamic>, Map<String, List<Map<String, dynamic>>> uploadedFiles) onSubmit;
  
  late FormGroup form;
  Map<String, List<Map<String, dynamic>>> uploadedFiles = {};
  int currentQuestionIndex = 0;

  DynamicFormController({
    required this.formJson,
    required this.onSubmit,
  }) {
    _initializeForm();
  }

  void _initializeForm() {
    Map<String, AbstractControl<dynamic>> controls = {};
    
    // Initialize form controls and uploadedFiles
    for (var field in formJson) {
      final fieldName = field['name'];
      
      // Initialize file upload fields
      if (field['type'] == 'file') {
        uploadedFiles[fieldName] = []; // Initialize empty list for file uploads
        controls[fieldName] = FormControl<String>(value: '');
      } else if (field['type'] == 'number') {
        // Special handling for number fields
        controls[fieldName] = FormControl<num>(
          value: null,
          validators: _getValidators(field['validators'], field),
        );
      } else {
        // Initialize form controls for non-file fields
        controls[fieldName] = FormControl<String>(
          value: '',
          validators: _getValidators(field['validators'], field),
        );
        
        if (field['hasComments'] == true) {
          controls['${fieldName}_comment'] = FormControl<String>();
        }
        
        if (field['subQuestions'] != null) {
          (field['subQuestions'] as Map<String, dynamic>).forEach((answer, subQuestions) {
            if (subQuestions is List) {
              for (var subField in subQuestions) {
                if (subField is Map<String, dynamic>) {
                  controls[subField['name']] = FormControl<String>(
                    validators: _getValidators(subField['validators'], subField),
                  );
                }
              }
            }
          });
        }
      }
    }
    
    form = FormGroup(controls);
  }

  List<Validator<dynamic>> _getValidators(List<dynamic>? validators, Map<String, dynamic>? field) {
    List<Validator<dynamic>> validatorsList = [];
    
    if (validators == null) return validatorsList;

    // Add required validator if present
    if (validators.contains('required')) {
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

  void submitForm(BuildContext context) {
    bool isValid = true;
    
    // Check each field's validation
    for (var field in formJson) {
      final fieldName = field['name'];
      final control = form.control(fieldName);
      
      // If field is file type, check uploaded files
      if (field['type'] == 'file') {
        if (field['validators']?.contains('required') == true) {
          isValid = isValid && (uploadedFiles[fieldName]?.isNotEmpty ?? false);
        }
        continue; // Skip further validation for file fields
      }
      
      // For non-file fields, check form control validity
      if (!control.valid && field['validators']?.contains('required') == true) {
        isValid = false;
        break;
      }
    }

    if (isValid) {
      onSubmit(form.value, uploadedFiles);
    } else {
      form.markAllAsTouched();
      _handleFormErrors(context);
    }
  }

  void _handleFormErrors(BuildContext context) {
    int errorIndex = formJson.indexWhere((field) {
      final control = form.control(field['name']);
      return field['validators']?.contains('required') == true && 
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
    
    // Special handling for file type fields
    if (field['type'] == 'file') {
      // Check if file upload is required and no files are uploaded
      if (field['validators']?.contains('required') == true && 
          (uploadedFiles[currentFieldName]?.isEmpty ?? true)) {
        _showErrorSnackBar(context, StringConstants.uploadRequiredFiles);
        return false;
      }
      // If file is not required or files are uploaded, proceed
      currentQuestionIndex++;
      return true;
    }

    // For non-file fields, use existing validation
    final currentControl = form.control(currentFieldName);
    if (_hasValidationError(field, currentControl, currentFieldName)) {
      String errorMessage = _getErrorMessage(field, currentControl);
      _showErrorSnackBar(context, errorMessage);
      return false;
    }

    currentQuestionIndex++;
    return true;
  }

  bool _hasValidationError(Map<String, dynamic> field, AbstractControl currentControl, String fieldName) {
    // Required field validation
    if (field['validators']?.contains('required') == true && 
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
        if (subField['validators']?.contains('required') == true && 
            (subControl.value == null || subControl.value.toString().isEmpty)) {
          return true;
        }
      }
    }

    return false;
  }

  String _getErrorMessage(Map<String, dynamic> field, AbstractControl control) {
    if (field['validators']?.contains('required') == true && 
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
        content: Text(message),
        duration: Duration(seconds: 2),
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


void dispose() {
    form.dispose(); // Dispose the ReactiveForm
    // Dispose of any other resources held by the controller
    if (kDebugMode) {
      print('DynamicFormController disposed');
    }
  }
}