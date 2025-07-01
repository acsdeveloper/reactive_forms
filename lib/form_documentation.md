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

# Dynamic Form - URL-Based File Attachment Feature

## Overview

The DynamicForm now supports automatically fetching file metadata from URLs during form initialization. This allows you to display previously uploaded files (stored in S3 or other cloud storage) in the form for editing purposes.

## How It Works

### 1. Initial Values Structure

When you pass `initialValues` to the `DynamicForm`, you can include file attachments with URLs:

```dart
Map<String, dynamic> initialValues = {
  'question_6': 'Yes', // Regular field value
  'question_6_attachments': [
    {
      'file_url': 'https://s3.amazonaws.com/yourbucket/file1.jpg',
      'fileName': 'issue_photo.png', // Optional, will be fetched if not provided
      'fileType': 'image', // Optional, will be determined if not provided
      'question_name': 'question_6',
      'question_label': 'If an issue was found, describe the problem.'
    }
  ],
};
```

### 2. Automatic Metadata Fetching

The `DynamicFormController` automatically:

1. **Detects URL-based attachments** in `initialValues`
2. **Fetches file metadata** using HTTP HEAD requests
3. **Extracts filename** from Content-Disposition headers or URL path
4. **Determines file type** from extension or Content-Type header
5. **Populates the `uploadedFiles` map** with complete file information

### 3. File Display

The `FileUploadWidget` now handles both:
- **Local files** (with file bytes) - for new uploads
- **URL-based files** (with file_url) - for existing files

#### For Images:
- Shows a preview thumbnail
- Click to view full-screen
- Download option available

#### For Other Files:
- Shows file icon, name, and size
- Download button to open in browser/new tab
- Delete button to remove from form

## Implementation Details

### Controller Changes

The `DynamicFormController` includes new methods:

```dart
// Fetches metadata from URL
Future<Map<String, dynamic>> _fetchFileMetadataFromUrl(
  String url, 
  String questionName, 
  String questionLabel,
)

// Extracts filename from URL or headers
String _extractFileNameFromUrl(String url, Map<String, String> headers)

// Determines file type from extension or content type
String _determineFileType(String fileName, String? contentType)
```

### Widget Changes

The `FileUploadWidget` includes new methods:

```dart
// Builds appropriate display for URL vs local files
Widget _buildFileDisplay(Map<String, dynamic> fileData)

// Downloads URL-based files
void _downloadUrlFile(String url, String? fileName)

// Previews URL-based files
void _previewUrlFile(BuildContext context, Map<String, dynamic> fileData)
```

## Usage Example

```dart
// When editing an existing form entry
DynamicForm(
  formJson: formFields,
  onSubmit: (values, files, isManageToCheck) {
    // Handle form submission
  },
  initialValues: {
    'question_6': 'Yes',
    'question_6_attachments': [
      {
        'file_url': 'https://your-s3-bucket.s3.amazonaws.com/uploads/photo.jpg',
        'question_name': 'question_6',
        'question_label': 'Upload photo of the issue'
      }
    ],
  },
  // ... other parameters
)
```

## File Structure Created

For each URL-based file, the system creates a structure like:

```dart
{
  'question_name': 'question_6',
  'question_label': 'Upload photo of the issue',
  'fileName': 'photo.jpg', // Extracted from URL or headers
  'fileType': 'image', // Determined from extension or content type
  'file_url': 'https://your-s3-bucket.s3.amazonaws.com/uploads/photo.jpg',
  'fileSize': 1024000, // If available from Content-Length header
  'mimeType': 'image/jpeg', // From Content-Type header
  'file': null, // No file bytes for URL-based files
}
```

## Benefits

1. **Seamless Edit Experience**: Users can see and manage previously uploaded files
2. **Automatic Metadata**: No need to store filename, type, size separately
3. **Fallback Handling**: Gracefully handles network errors or missing metadata
4. **Consistent UI**: Same interface for new uploads and existing files
5. **Download Support**: Users can download/view existing files

## Dependencies Added

- `http: ^1.1.0` - For fetching file metadata
- `path: ^1.8.3` - For file path operations

## Error Handling

The system includes robust error handling:

1. **Network failures**: Falls back to URL-based filename extraction
2. **Missing headers**: Uses URL path or query parameters
3. **Invalid URLs**: Generates fallback filenames
4. **Content-Type mismatches**: Uses file extension as backup

## Security Considerations

- Only HEAD requests are made (no file content downloaded)
- URLs are validated before processing
- Error messages don't expose sensitive information
- File size limits are respected for new uploads 