import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Helper class for testing widgets
class TestHelpers {
  /// Creates a MaterialApp wrapper for testing widgets
  static Widget makeTestableWidget({required Widget child}) {
    return MaterialApp(
      home: Scaffold(
        body: child,
      ),
    );
  }

  /// Sample form JSON for testing
  static final List<Map<String, dynamic>> sampleFormJson = [
    {
      'name': 'test_radio',
      'type': 'radio',
      'label': 'Test Radio',
      'options': ['Yes', 'No'],
      'required': true,
    },
    {
      'name': 'test_text',
      'type': 'text',
      'label': 'Test Text',
      'required': true,
    },
    {
      'name': 'test_number',
      'type': 'number',
      'label': 'Test Number',
      'min': 0,
      'max': 100,
      'required': true,
    },
    {
      'name': 'test_dropdown',
      'type': 'dropdown',
      'label': 'Test Dropdown',
      'options': ['Option 1', 'Option 2', 'Option 3'],
      'required': true,
    },
  ];
} 