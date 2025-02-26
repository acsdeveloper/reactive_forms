import 'package:flutter/material.dart';

class FormFieldWrapper extends StatelessWidget {
  final String label;
  final bool isRequired;
  final Widget child;
  final TextStyle? labelStyle;
  final String? description;

  const FormFieldWrapper({
    Key? key,
    required this.label,
    required this.child,
    this.isRequired = false,
    this.labelStyle,
    this.description,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: labelStyle ?? Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (isRequired)
              Text(
                ' *',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 16,
                ),
              ),
          ],
        ),
        if (description != null) ...[
          const SizedBox(height: 8),
          Text(
            description!,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 16),
        child,
      ],
    );
  }
} 