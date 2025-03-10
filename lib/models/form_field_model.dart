enum FormFieldType {
  text,
  number,
  date,
  dropdown,
  multiselect,
  // ... existing types ...
}

class FormFieldModel {
  final String name;
  final String type;
  final String label;
  final List<String>? options;
  final bool required;
  final bool? hasAttachments;
  final dynamic requireAttachmentsOn;
  final dynamic showAttachmentsOn;
  final dynamic disableAttachmentsOn;
  final bool? hasComments;
  final String? requiredCommentsOn;
  final Map<String, dynamic>? branching;
  final int? min;
  final int? max;

  FormFieldModel({
    required this.name,
    required this.type,
    required this.label,
    this.options,
    this.required = false,
    this.hasAttachments,
    this.requireAttachmentsOn,
    this.showAttachmentsOn,
    this.disableAttachmentsOn,
    this.hasComments,
    this.requiredCommentsOn,
    this.branching,
    this.min,
    this.max,
  });

  factory FormFieldModel.fromJson(Map<String, dynamic> json) {
    try {
      print('Parsing field: ${json['name']}');

      bool parseRequired(dynamic value) {
        if (value == null) return false;
        if (value is bool) return value;
        if (value is List) return value.isNotEmpty;
        if (value is String) return value.toLowerCase() == 'true';
        return false;
      }

      // Helper method to safely parse dynamic values to boolean
      bool? parseBooleanField(dynamic value) {
        if (value == null) return null;
        if (value is bool) return value;
        if (value is List) return value.isNotEmpty;
        if (value is String) return value.toLowerCase() == 'true';
        return null;
      }

      // Helper method to safely parse options
      List<String>? parseOptions(dynamic value, String type) {
        if (value == null) {
          return type == 'radio' ? ['Yes', 'No'] : null;
        }
        if (value is List) {
          return value.map((e) => e.toString()).toList();
        }
        return null;
      }

      return FormFieldModel(
        name: json['name']?.toString() ?? '',
        type: json['type']?.toString() ?? 'text',
        label: json['label']?.toString() ?? 'Untitled Question',
        options: parseOptions(json['options'], json['type']?.toString() ?? ''),
        required: parseRequired(json['required']),
        hasAttachments: parseBooleanField(json['hasAttachments']),
        requireAttachmentsOn: json['requireAttachmentsOn'],
        showAttachmentsOn: json['showAttachmentsOn'],
        disableAttachmentsOn: json['disableAttachmentsOn'],
        hasComments: parseBooleanField(json['hasComments']),
        requiredCommentsOn: json['requiredCommentsOn']?.toString(),
        branching: json['branching'] as Map<String, dynamic>?,
        min: json['min'] != null ? int.tryParse(json['min'].toString()) : null,
        max: json['max'] != null ? int.tryParse(json['max'].toString()) : null,
      );
    } catch (e) {
      print('Error parsing field ${json['name']}: $e');
      print('JSON data: $json');
      rethrow;
    }
  }

  @override
  String toString() {
    return 'FormFieldModel(name: $name, type: $type, label: $label, required: $required)';
  }

  dynamic parseValue(dynamic value) {
    switch (type) {
      case 'multiselect':
        if (value is List) return value;
        return [];
      default:
        return value;
    }
  }
} 