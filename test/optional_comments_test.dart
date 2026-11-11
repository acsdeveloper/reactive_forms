import 'package:flutter_test/flutter_test.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:reactiveform/dynamicformcontroller.dart';

/// Unit tests for comment visibility / optional / mandatory rules.
/// Every case prints one line "CASE|id|description|input|expected|actual|PASS/FAIL"
/// so the results can be copied into the test report.
final List<String> _log = [];

void check(String id, String description, String input, Object? expected,
    Object? actual) {
  final ok = expected.toString() == actual.toString();
  final line =
      'CASE|$id|$description|$input|$expected|$actual|${ok ? 'PASS' : 'FAIL'}';
  // ignore: avoid_print
  print(line);
  _log.add(line);
  expect(actual, expected, reason: '$id $description ($input)');
}

Map<String, dynamic> radio(String name, Map<String, dynamic> extra) => {
      'name': name,
      'type': 'radio',
      'label': name,
      'options': ['Yes', 'No'],
      'required': true,
      'hasAttachments': false,
      'requireAttachmentsOn': [],
      'disableAttachmentsOn': [],
      ...extra,
    };

DynamicFormController build(List<Map<String, dynamic>> json) =>
    DynamicFormController(
      formJson: json,
      onSubmit: (a, b, c, d) {},
      isManageToCheckPress: false,
    );

Future<void> answer(DynamicFormController c, String name, dynamic v) async {
  c.form.control(name).value = v;
  await Future<void>.delayed(Duration.zero); // let valueChanges listeners run
}

void main() {
  late DynamicFormController c;
  late Map<String, dynamic> legacy, optBoth, mixed, both, disabled, optOnlyYes,
      sheetStyle, noLists, noComments, optYesStr;

  setUp(() {
    legacy = radio('legacy', {
      'hasComments': true,
      'requireCommentsOn': ['No'],
    });
    optBoth = radio('optBoth', {
      'hasComments': true,
      'requireCommentsOn': [],
      'optionalCommentsOn': ['Yes', 'No'],
    });
    mixed = radio('mixed', {
      'hasComments': true,
      'requireCommentsOn': ['No'],
      'optionalCommentsOn': ['Yes'],
    });
    both = radio('both', {
      'hasComments': true,
      'requireCommentsOn': ['No'],
      'optionalCommentsOn': ['Yes', 'No'],
    });
    disabled = radio('disabled', {
      'hasComments': true,
      'optionalCommentsOn': ['Yes'],
      'disableCommentsOn': ['No'],
    });
    optOnlyYes = radio('optOnlyYes', {
      'hasComments': true,
      'requireCommentsOn': [],
      'optionalCommentsOn': ['Yes'],
    });
    // Booking app passes blank sheet cells as [''] and cells as comma strings
    sheetStyle = radio('sheetStyle', {
      'hasComments': true,
      'requireCommentsOn': [''],
      'disableCommentsOn': [''],
      'optionalCommentsOn': ['Yes', 'No'],
    });
    noLists = radio('noLists', {'hasComments': true});
    noComments = radio('noComments', {'hasComments': false});
    optYesStr = radio('optYesStr', {
      'hasComments': true,
      'optionalCommentsOn': ' Yes , ',
    });
    c = build([
      legacy,
      optBoth,
      mixed,
      both,
      disabled,
      optOnlyYes,
      sheetStyle,
      noLists,
      noComments,
      optYesStr,
    ]);
  });

  group('Existing behaviour (no optionalCommentsOn) is unchanged', () {
    test('E1 legacy requireCommentsOn=[No]: visibility', () {
      check('E1a', 'show comment on No', 'requireCommentsOn=[No], answer=No',
          true, c.shouldShowCommentsBasedOnFieldValue(legacy, 'No'));
      check('E1b', 'hide comment on Yes', 'requireCommentsOn=[No], answer=Yes',
          false, c.shouldShowCommentsBasedOnFieldValue(legacy, 'Yes'));
    });

    test('E2 legacy comment is mandatory', () async {
      await answer(c, 'legacy', 'No');
      check('E2a', 'empty comment invalid', 'answer=No, comment=""', false,
          c.form.control('legacy_comment').valid);
      c.form.control('legacy_comment').value = 'ok';
      check('E2b', 'filled comment valid', 'answer=No, comment="ok"', true,
          c.form.control('legacy_comment').valid);
      check('E2c', 'not optional', 'answer=No', false,
          c.isCommentOptionalForValue(legacy, 'No'));
      check('E2d', 'no optional config', 'legacy field', false,
          c.hasOptionalCommentsConfig(legacy));
    });

    test('E3 hasComments=true with no lists shows for every answer', () {
      check('E3a', 'show on Yes', 'no lists, answer=Yes', true,
          c.shouldShowCommentsBasedOnFieldValue(noLists, 'Yes'));
      check('E3b', 'show on No', 'no lists, answer=No', true,
          c.shouldShowCommentsBasedOnFieldValue(noLists, 'No'));
      check('E3c', 'comment control is mandatory', 'no lists, empty comment',
          false, c.form.control('noLists_comment').valid);
    });

    test('E4 hasComments=false creates no comment control', () {
      check('E4', 'no _comment control', 'hasComments=false', false,
          c.form.contains('noComments_comment'));
    });

    test('E5 disableCommentsOn hides the comment', () {
      final f = radio('x', {
        'hasComments': true,
        'disableCommentsOn': ['No'],
      });
      check('E5a', 'hidden on disabled answer', 'disableCommentsOn=[No], No',
          false, c.shouldShowCommentsBasedOnFieldValue(f, 'No'));
      check('E5b', 'shown on other answer', 'disableCommentsOn=[No], Yes',
          true, c.shouldShowCommentsBasedOnFieldValue(f, 'Yes'));
    });
  });

  group('New: optionalCommentsOn', () {
    test('N1 optional on both answers', () async {
      check('N1a', 'shown on Yes', 'optionalCommentsOn=[Yes,No], Yes', true,
          c.shouldShowCommentsBasedOnFieldValue(optBoth, 'Yes'));
      check('N1b', 'shown on No', 'optionalCommentsOn=[Yes,No], No', true,
          c.shouldShowCommentsBasedOnFieldValue(optBoth, 'No'));
      await answer(c, 'optBoth', 'Yes');
      check('N1c', 'empty comment is valid on Yes', 'answer=Yes, comment=""',
          true, c.form.control('optBoth_comment').valid);
      await answer(c, 'optBoth', 'No');
      check('N1d', 'empty comment is valid on No', 'answer=No, comment=""',
          true, c.form.control('optBoth_comment').valid);
      check('N1e', 'isCommentOptional on Yes', 'Yes', true,
          c.isCommentOptionalForValue(optBoth, 'Yes'));
      check('N1f', 'validateFieldCommentsIfRequired passes when empty',
          'answer=No, comment=""', true,
          c.validateFieldCommentsIfRequired(optBoth));
    });

    test('N2 mandatory on No, optional on Yes', () async {
      await answer(c, 'mixed', 'Yes');
      check('N2a', 'Yes: shown', 'require=[No], optional=[Yes], Yes', true,
          c.shouldShowCommentsBasedOnFieldValue(mixed, 'Yes'));
      check('N2b', 'Yes: empty comment valid', 'answer=Yes, comment=""', true,
          c.form.control('mixed_comment').valid);
      await answer(c, 'mixed', 'No');
      check('N2c', 'No: shown', 'require=[No], optional=[Yes], No', true,
          c.shouldShowCommentsBasedOnFieldValue(mixed, 'No'));
      check('N2d', 'No: empty comment invalid', 'answer=No, comment=""', false,
          c.form.control('mixed_comment').valid);
      check('N2e', 'No: validateFieldCommentsIfRequired fails',
          'answer=No, comment=""', false,
          c.validateFieldCommentsIfRequired(mixed));
      c.form.control('mixed_comment').value = 'reason';
      check('N2f', 'No: filled comment valid', 'answer=No, comment="reason"',
          true, c.form.control('mixed_comment').valid);
    });

    test('N3 answer changes re-validate the comment', () async {
      await answer(c, 'mixed', 'No');
      final afterNo = c.form.control('mixed_comment').valid;
      await answer(c, 'mixed', 'Yes');
      final afterYes = c.form.control('mixed_comment').valid;
      await answer(c, 'mixed', 'No');
      final backToNo = c.form.control('mixed_comment').valid;
      check('N3', 'valid state follows answer (No->Yes->No), empty comment',
          'No, Yes, No', 'false,true,false', '$afterNo,$afterYes,$backToNo');
    });

    test('N4 answer in both lists: mandatory wins', () async {
      check('N4a', 'not optional', 'require=[No], optional=[Yes,No], No',
          false, c.isCommentOptionalForValue(both, 'No'));
      await answer(c, 'both', 'No');
      check('N4b', 'empty comment invalid', 'answer=No, comment=""', false,
          c.form.control('both_comment').valid);
      check('N4c', 'Yes still optional', 'answer=Yes', true,
          c.isCommentOptionalForValue(both, 'Yes'));
    });

    test('N5 disableCommentsOn beats optionalCommentsOn', () async {
      check('N5a', 'hidden on No', 'optional=[Yes], disable=[No], No', false,
          c.shouldShowCommentsBasedOnFieldValue(disabled, 'No'));
      check('N5b', 'shown on Yes', 'optional=[Yes], disable=[No], Yes', true,
          c.shouldShowCommentsBasedOnFieldValue(disabled, 'Yes'));
      await answer(c, 'disabled', 'Yes');
      check('N5c', 'Yes: empty comment valid', 'answer=Yes, comment=""', true,
          c.form.control('disabled_comment').valid);
    });

    test('N6 optional only on Yes: No gets no comment box', () {
      check('N6a', 'shown on Yes', 'optional=[Yes], require=[], Yes', true,
          c.shouldShowCommentsBasedOnFieldValue(optOnlyYes, 'Yes'));
      check('N6b', 'hidden on No (no fallback)', 'optional=[Yes], require=[], No',
          false, c.shouldShowCommentsBasedOnFieldValue(optOnlyYes, 'No'));
    });

    test('N7 booking-app style lists ([""] blanks, comma strings)', () async {
      check('N7a', 'shown on Yes', "require=[''], optional=[Yes,No], Yes", true,
          c.shouldShowCommentsBasedOnFieldValue(sheetStyle, 'Yes'));
      check('N7b', 'blank entry never matches', "require=[''], answer=''",
          false, c.isCommentOptionalForValue(sheetStyle, ''));
      await answer(c, 'sheetStyle', 'No');
      check('N7c', 'empty comment valid on No', 'answer=No, comment=""', true,
          c.form.control('sheetStyle_comment').valid);
      check('N7d', 'comma string " Yes , " is trimmed', 'optional=" Yes , ", Yes',
          true, c.isCommentOptionalForValue(optYesStr, 'Yes'));
      check('N7e', 'comma string: No not optional', 'optional=" Yes , ", No',
          false, c.isCommentOptionalForValue(optYesStr, 'No'));
    });

    test('N8 multiselect value (list of answers)', () {
      check('N8a', 'optional if a selected answer is optional',
          'optional=[Yes], value=[Yes,No]', true,
          c.isCommentOptionalForValue(optOnlyYes, ['Yes', 'No']));
      check('N8b', 'not optional if none selected is optional',
          'optional=[Yes], value=[No]', false,
          c.isCommentOptionalForValue(optOnlyYes, ['No']));
    });

    test('N9 null / unanswered value', () {
      check('N9a', 'null answer is not optional', 'value=null', false,
          c.isCommentOptionalForValue(optBoth, null));
      check('N9b', 'empty answer is not optional', "value=''", false,
          c.isCommentOptionalForValue(optBoth, ''));
    });
  });

  tearDown(() => c.dispose());

  tearDownAll(() {
    // ignore: avoid_print
    print('TOTAL CASES LOGGED: ${_log.length}');
  });
}
