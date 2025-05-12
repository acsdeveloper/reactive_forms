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
| `more` | String | References another question to display in the same card |
| `showWhen` | Object | Defines conditions for when this question should be displayed |
| `groupWith` | String | Groups this question with another question (legacy approach) |
| `hasAttachments` | Boolean | Whether file attachments are allowed |
| `hasComments` | Boolean | Whether comments are allowed |
| `min` / `max` | Number | For number inputs: minimum and maximum values |

## The "more" Field

The `more` field is a powerful feature that allows questions to be displayed together within the same card. It creates a visual and logical grouping in the form.

### How it works:

1. When question A references question B using the `more` field, both questions appear in the same card
2. Question B will not be displayed separately in the form flow
3. Question B can reference question C with its own `more` field, creating a chain of related questions
4. All validation for these questions occurs together

### Example:

```json
{
  "name": "invoice_details",
  "type": "text",
  "label": "Invoice Number",
  "required": true,
  "more": "invoice_date"
},
{
  "name": "invoice_date",
  "type": "text",
  "label": "Invoice Date",
  "required": true
}
```

In this example, both "Invoice Number" and "Invoice Date" will appear in the same card, and "Invoice Date" won't be shown separately.

## Conditional Logic with showWhen

The `showWhen` property controls when a question is visible based on answers to other questions.

### Structure:

```json
"showWhen": {
  "questionName": ["value1", "value2"]
}
```

This means "show this question when the question named 'questionName' has a value of either 'value1' or 'value2'".

### Interaction with "more":

- If question A has `showWhen` conditions and also references question B with `more`, question B will only appear when question A is shown
- If question A references question B with `more`, and question B has its own `showWhen` conditions, question B will always appear with question A regardless of its `showWhen` conditions

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
2. It identifies questions referenced by `more` fields and tracks them
3. The `DynamicForm` widget renders the form, checking if each question:
   - Is referenced by another question's `more` field (if so, it skips rendering it separately)
   - Has conditions in `showWhen` that determine its visibility
   - References other questions via `more` that should be displayed with it

### Validation Flow

1. When validating a question that uses the `more` field:
   - The main question is validated
   - All referenced questions are also validated
   - File attachments and comments are checked for all questions in the group
2. Error messages display with the question label to clarify which question has issues
3. Navigation only proceeds if all questions in the current card are valid

## Best Practices

1. **Question Naming**: Use clear, descriptive names for questions to make references easy to understand
2. **Logical Grouping**: Use the `more` field to group closely related questions
3. **Avoid Circular References**: Don't create circular references with the `more` field
4. **Clear Labels**: Provide clear labels and descriptions for all questions
5. **Mind the Card Size**: Don't put too many questions in one card using `more` references

## Example Use Cases

1. **Address Information**: Group street address, city, state, zip code
2. **Contact Details**: Group name, email, phone number
3. **Conditional Follow-ups**: Show follow-up questions in the same card as the main question
4. **Multi-part Questions**: Split complex questions into related parts while keeping them visually connected 