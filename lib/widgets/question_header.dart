import 'package:flutter/material.dart';

class QuestionHeader extends StatelessWidget {
  final Map<String, dynamic> field;
  final TextStyle fontFamily;
  final Color primaryColor;

  const QuestionHeader({
    Key? key,
    required this.field,
    required this.fontFamily,
    required this.primaryColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  field['label'] ?? '',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
              ),
              if (field['required'] == true)
                const Text(
                  ' *',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 16,
                  ),
                ),
            ],
          ),
        ),
        if (field['description'] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Text(
              field['description'],
              style: fontFamily,
            ),
          ),
      ],
    );
  }
} 