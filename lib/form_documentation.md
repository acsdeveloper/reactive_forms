# Dynamic Form System Documentation

## Overview

The dynamic form system allows for creating complex, interactive forms with conditional logic and nested question relationships. The form structure is defined using JSON, which is processed by the `DynamicFormController` and rendered by the `DynamicForm` widget.

## JSON Structure

Each question in the form is represented as a JSON object with various properties that control its behavior and appearance.

### Basic Question Properties

| Property | Type | Description |
|----------|------|-------------|
| `name` | String | A unique identifier for the question |
| `type` | String | The type of input (text, radio, number, multiselect, etc.) |
| `label` | String | The display label for the question |
| `required` | Boolean | Whether the question requires an answer |
| `description` | String | Additional explanatory text for the question |
| `options` | Array | For radio and multiselect: the available options |

### Special Properties

| Property | Type | Description |
|----------|------|-------------|
| `showWhen` | Object | Defines conditions for when this question should be displayed |
| `groupWith` | String | Groups this question with another question |
| `hasAttachments` | Boolean | Whether file attachments are allowed |
| `hasComments` | Boolean | Whether comments are allowed |
| `min` / `max` | Number | For number inputs: minimum and maximum values |

## Conditional Logic with showWhen

The `showWhen` property controls when a question is visible based on answers to other questions.

### Structure:

```json
"showWhen": {
  "questionName": ["value1", "value2"]
}
```

This means "show this question when the question named 'questionName' has a value of either 'value1' or 'value2'".

## File Attachments

Questions can allow or require file attachments using these properties:

| Property | Type | Description |
|----------|------|-------------|
| `hasAttachments` | Boolean | Whether file uploads are allowed |
| `requireAttachmentsOn` | Array | Values that trigger mandatory file uploads |
| `disableAttachmentsOn` | Array | Values that disable file uploads |

For text fields, setting `hasAttachments: true` will make file uploads mandatory.

## Implementation Details

### How the Form Renders

1. The `DynamicFormController` processes the JSON structure and creates form controls
2. The `DynamicForm` widget renders the form, checking if each question:
   - Has conditions in `showWhen` that determine its visibility
   - Is grouped with other questions via `groupWith`

### Validation Flow

1. When validating a question:
   - The main question is validated
   - All related questions in the same group are also validated
   - File attachments and comments are checked for all questions in the group
2. Error messages display with the question label to clarify which question has issues
3. Navigation only proceeds if all questions in the current card are valid

## Best Practices

1. **Question Naming**: Use clear, descriptive names for questions to make references easy to understand
2. **Logical Grouping**: Use the `groupWith` field to group closely related questions
3. **Clear Labels**: Provide clear labels and descriptions for all questions
4. **Mind the Card Size**: Don't put too many questions in one card using grouping

## Example Use Cases

1. **Address Information**: Group street address, city, state, zip code
2. **Contact Details**: Group name, email, phone number
3. **Conditional Follow-ups**: Show follow-up questions in the same card as the main question
4. **Multi-part Questions**: Split complex questions into related parts while keeping them visually connected 