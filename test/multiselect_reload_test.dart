import 'package:flutter_test/flutter_test.dart';
import 'package:reactiveform/dynamicformcontroller.dart';

/// Saved multiselect (chip) answers must come back selected when a form is
/// reopened. Submitted answers are stored as text such as "[Sit, Down]".
Map<String, dynamic> chips(String name) => {
      'name': name,
      'type': 'multiselect',
      'label': name,
      'options': ['Sit', 'Down', 'Stay', 'Parkour (elites only)'],
      'required': true,
    };

DynamicFormController build(Map<String, dynamic> initial) =>
    DynamicFormController(
      formJson: [chips('q1')],
      initialValues: initial,
      onSubmit: (a, b, c, d) {},
      isManageToCheckPress: false,
    );

List<String>? valueOf(Map<String, dynamic> initial) =>
    (build(initial).form.control('q1').value as List?)?.cast<String>();

void main() {
  test('bracketed text from a saved answer', () {
    expect(valueOf({'q1': '[Sit, Down]'}), ['Sit', 'Down']);
  });

  test('a list is still accepted', () {
    expect(valueOf({'q1': ['Stay']}), ['Stay']);
  });

  test('JSON array text', () {
    expect(valueOf({'q1': '["Sit","Stay"]'}), ['Sit', 'Stay']);
  });

  test('option with brackets inside keeps working', () {
    expect(valueOf({'q1': '[Parkour (elites only)]'}),
        ['Parkour (elites only)']);
  });

  test('values that are not options are dropped', () {
    expect(valueOf({'q1': '[Sit, Jump]'}), ['Sit']);
  });

  test('empty saved answer stays unselected', () {
    expect(valueOf({'q1': '[]'}), isNull);
    expect(valueOf({}), isNull);
  });

  test('form loaded from saved answer is valid', () {
    expect(build({'q1': '[Sit, Down]'}).form.control('q1').valid, isTrue);
  });
}
