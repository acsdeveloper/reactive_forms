import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:reactiveform/string_constants.dart';
import 'package:reactiveform/widgets/form_field_wrapper.dart';

class CustomNumberField extends StatelessWidget {
  final Map<String, dynamic> field;
  final String fieldName;
  final TextStyle fontFamily;

  const CustomNumberField({
    Key? key,
    required this.field,
    required this.fieldName,
    required this.fontFamily,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final min = field['min'] as num?;
    final max = field['max'] as num?;
    
    return FormFieldWrapper(
      label: field['label'] ?? '',
      isRequired: field['required'] == true,
      labelStyle: fontFamily,
      description: field['description'],
      child: ReactiveTextField<num>(
        formControlName: fieldName,
        style: fontFamily,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          hintText: _buildHintText(min, max),
          hintStyle: fontFamily.copyWith(color: Colors.grey),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 16,
          ),
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.-]')),
        ],
        validationMessages: {
          ValidationMessage.required: (_) => 
              StringConstants.requiredFieldError,
          ValidationMessage.number: (_) => 
              StringConstants.numberRequired,
          ValidationMessage.min: (_) => 
              '${StringConstants.min}: $min',
          ValidationMessage.max: (_) => 
              '${StringConstants.max}: $max',
        },
      ),
    );
  }

  String _buildHintText(num? min, num? max) {
    if (min != null && max != null) {
      return '${StringConstants.enterNumber} ($min-$max)';
    } else if (min != null) {
      return '${StringConstants.enterNumber} (min: $min)';
    } else if (max != null) {
      return '${StringConstants.enterNumber} (max: $max)';
    }
    return StringConstants.enterNumber;
  }
} 