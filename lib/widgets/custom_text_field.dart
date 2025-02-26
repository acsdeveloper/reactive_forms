import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:reactiveform/string_constants.dart';
import 'package:reactiveform/widgets/form_field_wrapper.dart';

class CustomTextField extends StatelessWidget {
  final Map<String, dynamic> field;
  final String fieldName;
  final TextStyle fontFamily;
  final bool isMultiline;
  final List<TextInputFormatter>? inputFormatters;

  const CustomTextField({
    Key? key,
    required this.field,
    required this.fieldName,
    required this.fontFamily,
    this.isMultiline = false,
    this.inputFormatters,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FormFieldWrapper(
      label: field['label'] ?? '',
      isRequired: field['required'] == true,
      labelStyle: fontFamily,
      description: field['description'],
      child: ReactiveTextField<String>(
        formControlName: fieldName,
        style: fontFamily,
        decoration: InputDecoration(
          hintText: field['hint'] ?? StringConstants.enterText,
          hintStyle: fontFamily.copyWith(color: Colors.grey),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 16,
          ),
        ),
        maxLines: isMultiline ? 3 : 1,
        inputFormatters: inputFormatters,
        validationMessages: {
          ValidationMessage.required: (_) => 
              StringConstants.requiredFieldError,
        },
      ),
    );
  }
} 