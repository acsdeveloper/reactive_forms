import 'package:flutter/material.dart';
import 'package:reactive_forms/reactive_forms.dart';


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
    final controls = <String, AbstractControl>{};
    
    void addFieldControls(Map<String, dynamic> field) {
      controls[field['name']] = FormControl<String>(
        validators: _getValidators(field['validators']),
      );
      
      if (field['hasComments'] == true) {
        controls['${field['name']}_comment'] = FormControl<String>();
      }
      
      if (field['subQuestions'] != null) {
        (field['subQuestions'] as Map<String, dynamic>).forEach((answer, subQuestions) {
          if (subQuestions is List) {
            for (var subField in subQuestions) {
              if (subField is Map<String, dynamic>) {
                addFieldControls(subField);
              }
            }
          }
        });
      }
      
      uploadedFiles[field['name']] = [];
    }

    for (var field in formJson) {
      addFieldControls(field);
    }

    form = FormGroup(controls);
  }

  List<Validator<dynamic>> _getValidators(List<dynamic>? validators) {
    if (validators == null) return [];
    return validators.where((v) => v == 'required')
        .map((v) => Validators.required)
        .toList();
  }

  void submitForm(BuildContext context) {
    if (form.valid) {
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
        SnackBar(
          content: Text('Please fill in all required fields'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  bool validateAndProceed(BuildContext context) {
    final field = formJson[currentQuestionIndex];
    final currentFieldName = field['name'];
    final currentControl = form.control(currentFieldName);
    final type = field['type'];
    if (type != 'file') {
    if (_hasValidationError(field, currentControl, currentFieldName)) {
      String errorMessage = _getErrorMessage(field, currentControl);
      _showErrorSnackBar(context, errorMessage);
      return false;
    }
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
          ? 'Please select an option'
          : 'Please answer this question';
    }
    
    if (field['requireAttachmentsOn'] == control.value) {
      return 'Please upload required files';
    }
    
    return 'Please answer all required sub-questions';
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
              field['label'] ?? 'Select an option',
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
}