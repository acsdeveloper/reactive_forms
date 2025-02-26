import 'package:flutter/material.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:reactiveform/constants/colors.dart';
import 'package:reactiveform/string_constants.dart';
import 'package:reactiveform/widgets/form_field_wrapper.dart';

class CustomDropdownField extends StatelessWidget {
  final Map<String, dynamic> field;
  final String fieldName;
  final TextStyle fontFamily;
  final Color primaryColor;
  final Function(String?) onChanged;

  const CustomDropdownField({
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
      child: ReactiveValueListenableBuilder<String>(
        formControlName: fieldName,
        builder: (context, control, child) {
          return InkWell(
            onTap: () => _showDropdownSheet(context, control),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(4),
              ),
              child: ListTile(
                title: Text(
                  control.value ?? StringConstants.selectOption,
                  style: fontFamily,
                ),
                trailing: Icon(Icons.arrow_drop_down, color: Colors.grey.shade600),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                visualDensity: VisualDensity.compact,
              ),
            ),
          );
        },
      ),
    );
  }

  void _showDropdownSheet(BuildContext context, AbstractControl<String> control) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => ListView.builder(
          controller: scrollController,
          itemCount: (field['options'] as List).length,
          itemBuilder: (context, index) {
            final option = field['options'][index];
            return ListTile(
              title: Text(option.toString(), style: fontFamily),
              onTap: () {
                control.value = option.toString();
                Navigator.pop(context);
                onChanged(option.toString());
              },
              trailing: control.value == option.toString()
                ? Icon(Icons.check, color: primaryColor)
                : null,
            );
          },
        ),
      ),
    );
  }
} 