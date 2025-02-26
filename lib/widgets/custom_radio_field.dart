import 'package:flutter/material.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:reactiveform/constants/colors.dart';
import 'package:reactiveform/widgets/form_field_wrapper.dart';

class CustomRadioField extends StatelessWidget {
  final Map<String, dynamic> field;
  final String fieldName;
  final TextStyle fontFamily;
  final Color primaryColor;
  final Function(String?) onChanged;

  const CustomRadioField({
    Key? key,
    required this.field,
    required this.fieldName,
    required this.fontFamily,
    required this.primaryColor,
    required this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FormFieldWrapper(
      label: field['label'] ?? '',
      isRequired: field['required'] == true,
      labelStyle: fontFamily,
      description: field['description'],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: (field['options'] as List<dynamic>).map<Widget>((option) {
              return Container(
                padding: EdgeInsets.zero,
                margin: const EdgeInsets.symmetric(vertical: 4.0),
                child: Transform.translate(
                  offset: const Offset(-12, 0),
                  child: ReactiveRadioListTile<String>(
                    formControlName: fieldName,
                    value: option.toString(),
                    title: Text(
                      option.toString(),
                      style: fontFamily,
                    ),
                    activeColor: primaryColor,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
} 