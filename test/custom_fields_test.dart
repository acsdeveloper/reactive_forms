import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reactiveform/widgets/custom_radio_field.dart';
import 'package:reactiveform/widgets/custom_text_field.dart';
import 'package:reactiveform/widgets/custom_number_field.dart';
import 'package:reactiveform/widgets/custom_dropdown_field.dart';
import 'test_helpers.dart';

void main() {
  group('Custom Fields Widget Tests', () {
    testWidgets('CustomRadioField renders correctly', (WidgetTester tester) async {
      final field = TestHelpers.sampleFormJson[0];
      
      await tester.pumpWidget(
        TestHelpers.makeTestableWidget(
          child: CustomRadioField(
            field: field,
            fieldName: field['name'],
            fontFamily: const TextStyle(),
            primaryColor: Colors.blue,
            onChanged: (_) {},
          ),
        ),
      );

      expect(find.text('Test Radio'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);
      expect(find.text('No'), findsOneWidget);
    });

    testWidgets('CustomTextField renders correctly', (WidgetTester tester) async {
      final field = TestHelpers.sampleFormJson[1];
      
      await tester.pumpWidget(
        TestHelpers.makeTestableWidget(
          child: CustomTextField(
            field: field,
            fieldName: field['name'],
            fontFamily: const TextStyle(),
          ),
        ),
      );

      expect(find.text('Test Text'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('CustomNumberField renders correctly', (WidgetTester tester) async {
      final field = TestHelpers.sampleFormJson[2];
      
      await tester.pumpWidget(
        TestHelpers.makeTestableWidget(
          child: CustomNumberField(
            field: field,
            fieldName: field['name'],
            fontFamily: const TextStyle(),
          ),
        ),
      );

      expect(find.text('Test Number'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('CustomDropdownField renders correctly', (WidgetTester tester) async {
      final field = TestHelpers.sampleFormJson[3];
      
      await tester.pumpWidget(
        TestHelpers.makeTestableWidget(
          child: CustomDropdownField(
            field: field,
            fieldName: field['name'],
            fontFamily: const TextStyle(),
            primaryColor: Colors.blue,
            onChanged: (_) {},
          ),
        ),
      );

      expect(find.text('Test Dropdown'), findsOneWidget);
      
      // Tap to open dropdown
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();
      
      expect(find.text('Option 1'), findsOneWidget);
      expect(find.text('Option 2'), findsOneWidget);
      expect(find.text('Option 3'), findsOneWidget);
    });
  });
} 