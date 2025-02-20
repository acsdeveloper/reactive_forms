# Dynamic Form Builder

A flexible and customizable dynamic form builder for Flutter that supports various input types, file uploads, and conditional rendering.

## Features

- Multiple input types (Radio, Dropdown, Text, Number, File Upload)
- Step-by-step form navigation
- File upload support with image/document preview
- Validation support
- Conditional rendering of fields
- Sub-questions support
- Comments support
- Custom styling options

## Installation

Add these dependencies to your `pubspec.yaml`:

yaml
dependencies:
reactive_forms: ^latest_version
file_picker: ^latest_version
image_picker: ^latest_version
permission_handler: ^latest_version


## Usage

### Basic Implementation
dart
import 'package:your_package/dynamicform.dart';
DynamicForm(
context: context,
formJson: yourFormJson,
onSubmit: (formData, attachments) {
// Handle form submission
print(formData);
print(attachments);
},
fontFamily: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
showOneByOne: true,
primaryColor: Colors.black,
)

### Form JSON Structure

The form is configured using a JSON structure. Here's an example:
dart
final List<Map<String, dynamic>> formJson = [
{
'name': 'question_1',
'type': 'radio',
'label': 'Is this a radio question?',
'options': ['Yes', 'No'],
'validators': ['required'],
'hasAttachments': true,
'showAttachmentsOn': 'Yes',
},
{
'name': 'question_2',
'type': 'dropdown',
'label': 'Select an option',
'options': ['Option 1', 'Option 2', 'Option 3'],
validators': ['required'],
},
{
'name': 'question_3',
'type': 'number',
'label': 'Enter a number',
'validators': ['required'],
'min': 0,
'max': 100,
'allowNegatives': false,
'allowedDecimals': 0,
},
];

### Field Types

1. **Radio Button**
dart
{
'name': 'field_name',
'type': 'radio',
'label': 'Question label',
'options': ['Option 1', 'Option 2'],
'validators': ['required'],
'hasAttachments': true,
'showAttachmentsOn': 'Option 1'
}
dart
{
'name': 'field_name',
'type': 'dropdown',
'label': 'Question label',
'options': ['Option 1', 'Option 2'],
'validators': ['required']
}

3. **Number Input**
{
'name': 'field_name',
'type': 'number',
'label': 'Question label',
'validators': ['required'],
'min': 0,
'max': 100,
'allowNegatives': false,
'allowedDecimals': 0
}

4. **Text Input**

{
'name': 'field_name',
'type': 'text',
'label': 'Question label',
'validators': ['required']
}

5. **File Upload**

{
'name': 'field_name',
'type': 'file',
'label': 'Upload files',
'validators': ['required']
}



### Properties

| Property | Type | Description |
|----------|------|-------------|
| formJson | List<Map<String, dynamic>> | Form configuration |
| onSubmit | Function | Callback for form submission |
| context | BuildContext | Build context |
| primaryColor | Color | Primary color theme |
| buttonTextColor | Color | Button text color |
| fieldSpacing | double | Spacing between fields |
| showOneByOne | bool | Show questions one at a time |
| fontFamily | TextStyle | Text style for form |

### Validation

Add validators in the field configuration:
'validators': ['required']

### Sub-Questions

You can add sub-questions that appear based on the parent question's answer:
{
'name': 'parent_question',
'type': 'radio',
'options': ['Yes', 'No'],
'subQuestions': {
'Yes': [
{
'name': 'sub_question',
'type': 'text',
'label': 'Sub question',
'validators': ['required']
}
]
}
}

## License

This project is licensed under the MIT License - see the LICENSE file for details.