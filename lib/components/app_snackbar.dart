import 'package:flutter/material.dart';

class AppSnackBar {
  final BuildContext context;
  
  // Constructor to initialize context
  AppSnackBar(this.context);

  /// This method displays a styled SnackBar with customizable message, heading,
  /// duration, and background color.
  ///
  /// Args:
  ///   message (String): The message to be displayed in the SnackBar.
  ///   heading (String?): The optional heading to be displayed above the message.
  ///   duration (Duration?): The duration for which the SnackBar will be shown.
  ///   backgroundColor (Color?): The background color of the SnackBar.
  void showErrorSnackBar(
    String message, {
    String? heading,
    Duration? duration,
    Color? backgroundColor,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            // If heading is provided, display it; otherwise, leave it empty
            if (heading != null) 
              Text(
                heading,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white, // Heading color
                ),
              ),
            const SizedBox(width: 8), // Space between heading and content text
            // The content message
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: backgroundColor ?? Colors.red, // Default to red for error
        duration: duration ?? const Duration(seconds: 3), // Default duration 3 seconds
        behavior: SnackBarBehavior.floating, // Makes the SnackBar float
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10), // Rounded edges
        ),
        elevation: 10, // Floating effect with shadow
        margin: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).size.height * 0.08, // Adjust based on bottom navigation height
        ),
      ),
    );
  }
}
