import 'package:flutter/material.dart';
import 'package:reactiveform/string_constants.dart';

class FormNavigation extends StatelessWidget {
  final bool showOneByOne;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onSubmit;
  final bool isFirstQuestion;
  final bool isLastQuestion;
  final Color buttonColor;
  final Color buttonTextColor;
  final TextStyle fontFamily;

  const FormNavigation({
    Key? key,
    required this.showOneByOne,
    required this.onPrevious,
    required this.onNext,
    required this.onSubmit,
    required this.isFirstQuestion,
    required this.isLastQuestion,
    required this.buttonColor,
    required this.buttonTextColor,
    required this.fontFamily,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!showOneByOne) {
      return _buildSubmitButton();
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (!isFirstQuestion)
          Expanded(
            flex: 1,
            child: OutlinedButton(
              onPressed: onPrevious,
              style: OutlinedButton.styleFrom(
                foregroundColor: buttonColor,
                side: BorderSide(color: buttonColor),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Icon(Icons.arrow_back),
            ),
          ),
        if (!isFirstQuestion)
          const SizedBox(width: 16),
        Expanded(
          flex: 3,
          child: ElevatedButton(
            onPressed: isLastQuestion ? onSubmit : onNext,
            style: ElevatedButton.styleFrom(
              backgroundColor: buttonColor,
              foregroundColor: buttonTextColor,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text(
              isLastQuestion
                  ? StringConstants.submit
                  : StringConstants.next,
              style: fontFamily.copyWith(
                color: buttonTextColor,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return ElevatedButton(
      onPressed: onSubmit,
      style: ElevatedButton.styleFrom(
        backgroundColor: buttonColor,
        foregroundColor: buttonTextColor,
        minimumSize: const Size(double.infinity, 48),
      ),
      child: Text(
        StringConstants.submit,
        style: fontFamily.copyWith(
          color: buttonTextColor,
          fontSize: 16,
        ),
      ),
    );
  }
} 