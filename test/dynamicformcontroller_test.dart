import 'package:flutter_test/flutter_test.dart';
import 'package:reactiveform/dynamicformcontroller.dart';
import 'test_helpers.dart';

void main() {
  group('DynamicFormController Tests', () {
    late DynamicFormController controller;

    setUp(() {
      controller = DynamicFormController(
        formJson: TestHelpers.sampleFormJson,
        onSubmit: (_, __) {},
      );
    });

    test('initializes form controls correctly', () {
      expect(controller.form.control('test_radio'), isNotNull);
      expect(controller.form.control('test_text'), isNotNull);
      expect(controller.form.control('test_number'), isNotNull);
      expect(controller.form.control('test_dropdown'), isNotNull);
    });

    test('validates required fields correctly', () {
      expect(controller.form.valid, isFalse);
      
      controller.form.control('test_radio').value = 'Yes';
      controller.form.control('test_text').value = 'Test';
      controller.form.control('test_number').value = 50;
      controller.form.control('test_dropdown').value = 'Option 1';
      
      expect(controller.form.valid, isTrue);
    });

    test('validates number field min/max correctly', () {
      final numberControl = controller.form.control('test_number');
      
      numberControl.value = -1;
      expect(numberControl.valid, isFalse);
      
      numberControl.value = 101;
      expect(numberControl.valid, isFalse);
      
      numberControl.value = 50;
      expect(numberControl.valid, isTrue);
    });
  });
} 