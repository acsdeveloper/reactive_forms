# Unit Test Report - Optional Comments (optionalCommentsOn)

Date: 2026-11-11  |  Branch: feature/optional-comments-on (reactive_forms, from development)

Method: `flutter test` was run; every row below was copied from the test run output (not hand-written). Input = question config / answer / comment typed. Expected = what the test asserted. Received = what the code actually returned.

## A. Renderer rules (reactive_forms) - `test/optional_comments_test.dart`

| ID | Case | Input | Expected | Received | Result |
|---|---|---|---|---|---|
| E1a | show comment on No | requireCommentsOn=[No], answer=No | true | true | PASS |
| E1b | hide comment on Yes | requireCommentsOn=[No], answer=Yes | false | false | PASS |
| E2a | empty comment invalid | answer=No, comment="" | false | false | PASS |
| E2b | filled comment valid | answer=No, comment="ok" | true | true | PASS |
| E2c | not optional | answer=No | false | false | PASS |
| E2d | no optional config | legacy field | false | false | PASS |
| E3a | show on Yes | no lists, answer=Yes | true | true | PASS |
| E3b | show on No | no lists, answer=No | true | true | PASS |
| E3c | comment control is mandatory | no lists, empty comment | false | false | PASS |
| E4 | no _comment control | hasComments=false | false | false | PASS |
| E5a | hidden on disabled answer | disableCommentsOn=[No], No | false | false | PASS |
| E5b | shown on other answer | disableCommentsOn=[No], Yes | true | true | PASS |
| N1a | shown on Yes | optionalCommentsOn=[Yes,No], Yes | true | true | PASS |
| N1b | shown on No | optionalCommentsOn=[Yes,No], No | true | true | PASS |
| N1c | empty comment is valid on Yes | answer=Yes, comment="" | true | true | PASS |
| N1d | empty comment is valid on No | answer=No, comment="" | true | true | PASS |
| N1e | isCommentOptional on Yes | Yes | true | true | PASS |
| N1f | validateFieldCommentsIfRequired passes when empty | answer=No, comment="" | true | true | PASS |
| N2a | Yes: shown | require=[No], optional=[Yes], Yes | true | true | PASS |
| N2b | Yes: empty comment valid | answer=Yes, comment="" | true | true | PASS |
| N2c | No: shown | require=[No], optional=[Yes], No | true | true | PASS |
| N2d | No: empty comment invalid | answer=No, comment="" | false | false | PASS |
| N2e | No: validateFieldCommentsIfRequired fails | answer=No, comment="" | false | false | PASS |
| N2f | No: filled comment valid | answer=No, comment="reason" | true | true | PASS |
| N3 | valid state follows answer (No->Yes->No), empty comment | No, Yes, No | false,true,false | false,true,false | PASS |
| N4a | not optional | require=[No], optional=[Yes,No], No | false | false | PASS |
| N4b | empty comment invalid | answer=No, comment="" | false | false | PASS |
| N4c | Yes still optional | answer=Yes | true | true | PASS |
| N5a | hidden on No | optional=[Yes], disable=[No], No | false | false | PASS |
| N5b | shown on Yes | optional=[Yes], disable=[No], Yes | true | true | PASS |
| N5c | Yes: empty comment valid | answer=Yes, comment="" | true | true | PASS |
| N6a | shown on Yes | optional=[Yes], require=[], Yes | true | true | PASS |
| N6b | hidden on No (no fallback) | optional=[Yes], require=[], No | false | false | PASS |
| N7a | shown on Yes | require=[''], optional=[Yes,No], Yes | true | true | PASS |
| N7b | blank entry never matches | require=[''], answer='' | false | false | PASS |
| N7c | empty comment valid on No | answer=No, comment="" | true | true | PASS |
| N7d | comma string " Yes , " is trimmed | optional=" Yes , ", Yes | true | true | PASS |
| N7e | comma string: No not optional | optional=" Yes , ", No | false | false | PASS |
| N8a | optional if a selected answer is optional | optional=[Yes], value=[Yes,No] | true | true | PASS |
| N8b | not optional if none selected is optional | optional=[Yes], value=[No] | false | false | PASS |
| N9a | null answer is not optional | value=null | false | false | PASS |
| N9b | empty answer is not optional | value='' | false | false | PASS |

## B. Booking app parsing - `booking_app_frontend/test/checklist_optional_comments_test.dart`

| ID | Case | Input | Expected | Received | Result |
|---|---|---|---|---|---|
| B1 | comma list parsed | optionalCommentsOn='Yes,No' | [Yes, No] | [Yes, No] | PASS |
| B2 | spaces trimmed | optionalCommentsOn=' Yes , No ' | [Yes, No] | [Yes, No] | PASS |
| B3 | blank string gives empty list | optionalCommentsOn='' | [] | [] | PASS |
| B4 | missing key gives empty list | key absent | [] | [] | PASS |
| B5 | requireCommentsOn unchanged | requireCommentsOn='No' | [No] | [No] | PASS |
| B6 | toJson carries optionalCommentsOn | optionalCommentsOn='Yes' | [Yes] | [Yes] | PASS |

## Summary

- 48 cases run (42 renderer + 6 booking app), 48 passed, 0 failed.

## Not covered by these tests (needs a manual run on a device)

- Red `*` showing/hiding next to the comment label as the answer changes.
- "Next" / "Submit" being blocked or allowed in the real UI (`validateAndProceed`, `validateCurrentSection`); only `validateFieldCommentsIfRequired` is covered here.
- Hidden-comment text being dropped from the submitted data.
- Grouped questions, multiselect/number/temp/file question types with comments, and duplicated (add-another) question sets.
- Reading the new `optionalCommentsOn` column end-to-end from the Google Sheet through the backend into the app.
- Not run: the repo's pre-existing tests.
