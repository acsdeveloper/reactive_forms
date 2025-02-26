import 'package:flutter/material.dart';
import 'package:reactiveform/string_constants.dart';

class FormProgressIndicator extends StatelessWidget {
  final int currentQuestion;
  final int totalQuestions;
  final TextStyle fontFamily;
  final Color primaryColor;

  const FormProgressIndicator({
    Key? key,
    required this.currentQuestion,
    required this.totalQuestions,
    required this.fontFamily,
    required this.primaryColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${StringConstants.questionNumber} $currentQuestion',
            style: fontFamily.copyWith(fontWeight: FontWeight.bold),
          ),
          SizedBox(
            width: 100,
            height: 6,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: currentQuestion / totalQuestions,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              ),
            ),
          ),
        ],
      ),
    );
  }
} 