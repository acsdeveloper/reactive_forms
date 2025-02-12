import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:flutter/material.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:universal_html/html.dart' as html;

import 'dynmaicformcontroller.dart';



class DynamicForm extends StatefulWidget {
  final List<Map<String, dynamic>> formJson;
  final void Function(Map<String, dynamic>, Map<String, List<Map<String, dynamic>>> uploadedFiles) onSubmit;
  final Color primaryColor;
  final Color buttonTextColor;
  final double fieldSpacing;
  final bool showOneByOne;

  DynamicForm({
    required this.formJson,
    required this.onSubmit,
    this.primaryColor = const Color(0xFF4BA7D1),
    this.buttonTextColor = Colors.white,
    this.fieldSpacing = 20.0,
    this.showOneByOne = false,
  });

  @override
  _DynamicFormState createState() => _DynamicFormState();
}

class _DynamicFormState extends State<DynamicForm> {
  late DynamicFormController controller;

  @override
  void initState() {
    super.initState();
    controller = DynamicFormController(
      formJson: widget.formJson,
      onSubmit: widget.onSubmit,
    );
  }

  Future<void> _showFilePickerOptions(String questionName, String questionLabel) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!kIsWeb) ...[
                ListTile(
                  leading: Icon(Icons.camera_alt_outlined),
                  title: Text('Camera'),
                  onTap: () {
                    Navigator.pop(context);
                    _captureImage(questionName, questionLabel);
                  },
                ),
                Divider(height: 0.5),
              ],
              ListTile(
                leading: Icon(Icons.photo_outlined),
                title: Text('Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickFile(questionName, questionLabel, type: FileType.image);
                },
              ),
              Divider(height: 0.5),
              ListTile(
                leading: Icon(Icons.file_copy_outlined),
                title: Text('Files'),
                onTap: () {
                  Navigator.pop(context);
                  _pickFile(questionName, questionLabel, type: FileType.any);
                },
              ),
              Divider(height: 0.5),
              ListTile(
                title: Center(child: Text('Cancel')),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickFile(String questionName, String questionLabel, {FileType type = FileType.any, bool allowMultiple = false}) async {
    try {
      if (kIsWeb) {
        // Web-specific file picking
        final input = html.FileUploadInputElement()
          ..multiple = allowMultiple;
        
        // Set accept attribute based on type
        if (type == FileType.image) {
          input.accept = 'image/*';
        }
        
        input.click();

        await input.onChange.first;
        if (input.files!.isNotEmpty) {
          setState(() {
            if (!allowMultiple) {
              controller.uploadedFiles[questionName]!.clear();
            }

            for (var file in input.files!) {
              final reader = html.FileReader();
              reader.readAsArrayBuffer(file);
              reader.onLoadEnd.listen((event) {
                if (reader.result != null) {
                  final bytes = (reader.result as List<int>).cast<int>();
                  setState(() {
                    controller.uploadedFiles[questionName]!.add({
                      'question_name': questionName,
                      'question_label': questionLabel,
                      'file': Uint8List.fromList(bytes),
                      'fileName': file.name,
                      'fileType': _getFileType(file.name),
                      'mimeType': file.type,
                    });
                  });
                }
              });
            }
          });
        }
      } else {
        // Mobile file picking
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          allowMultiple: allowMultiple,
          type: type,
          withData: true,
          allowCompression: true,
        );
        
        if (result != null && result.files.isNotEmpty) {
          setState(() {
            if (!allowMultiple) {
              controller.uploadedFiles[questionName]!.clear();
            }
            
            for (var file in result.files) {
              if (file.bytes != null) {
                controller.uploadedFiles[questionName]!.add({
                  'question_name': questionName,
                  'question_label': questionLabel,
                  'file': file.bytes,
                  'fileName': file.name,
                  'fileType': _getFileType(file.name),
                  'mimeType': file.extension != null ? 'application/${file.extension}' : 'application/octet-stream',
                });
              }
            }
          });
        }
      }
    } catch (e) {
      print('Error in _pickFile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error selecting file. Please try again.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  String _getFileType(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'pdf':
        return 'pdf';
      case 'doc':
      case 'docx':
        return 'document';
      case 'xls':
      case 'xlsx':
        return 'spreadsheet';
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return 'image';
      default:
        return 'jpg';
    }
  }

  Future<void> _captureImage(String questionName, String questionLabel) async {
    if (kIsWeb) {
      await _pickFile(questionName, questionLabel);
      return;
    }

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 50,
        maxWidth: 1200,
        maxHeight: 1200,
      );
      
      if (image != null) {
        try {
          final bytes = await image.readAsBytes();
          
          if (mounted) {
            setState(() {
              controller.uploadedFiles[questionName]!.clear();
              controller.uploadedFiles[questionName]!.add({
                'question_name': questionName,
                'question_label': questionLabel,
                'file': bytes,
                'fileName': image.name,
                'fileType': 'image',
                'mimeType': 'image/jpeg',
              });
            });
          }
        } catch (e) {
          print('Error reading image: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error processing image. Please try again.'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      }
    } catch (e) {
      print('Error in _captureImage: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error capturing image. Please try again.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _submitForm() {
    if (controller.form.valid) {
      controller.onSubmit(controller.form.value, controller.uploadedFiles);
    } else {
      controller.form.markAllAsTouched();
      
      // Find first error and navigate to it
      if (widget.showOneByOne) {
        int errorIndex = widget.formJson.indexWhere((field) {
          final control = controller.form.control(field['name']);
          if (field['validators']?.contains('required') == true && 
              (control.value == null || control.value.toString().isEmpty)) {
            return true;
          }
          return false;
        });
        if (errorIndex != -1) {
          controller.form.focus(widget.formJson[errorIndex]['name']);
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Please fill in all required fields'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  void _viewFile(BuildContext context, Map<String, dynamic> file) {
    try {
      if (file['file'] is Uint8List) {
        if (kIsWeb) {
          // Create blob URL for web viewing
          final blob = html.Blob([file['file']]);
          final url = html.Url.createObjectUrlFromBlob(blob);
          html.window.open(url, '_blank');
          html.Url.revokeObjectUrl(url);
        } else {
          // Mobile viewing
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(
                  title: Text(file['fileName'] ?? 'Image Preview'),
                  backgroundColor: widget.primaryColor ?? Colors.black,
                ),
                body: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Image.memory(
                          file['file'],
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            print('Error loading image: $error');
                            return Center(
                              child: Text('Error loading image'),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }
      }
    } catch (e) {
      print('Error in _viewFile: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error viewing file. Please try again.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final buttonColor = widget.primaryColor ?? Colors.black;
    
    return ReactiveForm(
      formGroup: controller.form,
      child: Scaffold(
        body: SingleChildScrollView(
          key: ValueKey('form_${controller.currentQuestionIndex}'),
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.showOneByOne) ..._buildOneByOneFields(),
                if (!widget.showOneByOne) ..._buildAllFields(),
                SizedBox(height: 80),
              ],
            ),
          ),
        ),
        bottomNavigationBar: _buildBottomNavigation(buttonColor),
      ),
    );
  }

  Widget _buildBottomNavigation(Color buttonColor) {
    return Padding(
      padding: EdgeInsets.all(16.0),
      child: widget.showOneByOne
          ? _buildStepNavigation(buttonColor)
          : _buildSubmitButton(buttonColor),
    );
  }

  List<Widget> _buildAllFields() {
    return widget.formJson.map((field) => Column(
      children: [
        _buildField(field),
        Divider(height: 32, thickness: 1),
      ],
    )).toList();
  }

  List<Widget> _buildOneByOneFields() {
    if (controller.currentQuestionIndex >= widget.formJson.length) {
      return [];
    }

    final field = widget.formJson[controller.currentQuestionIndex];
    final isLastQuestion = controller.currentQuestionIndex == widget.formJson.length - 1;

    return [
      Padding(
        padding: EdgeInsets.only(bottom: 16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Question ${controller.currentQuestionIndex + 1}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: widget.primaryColor ?? Colors.black,
              ),
            ),
            Container(
              width: 100,
              height: 6,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (controller.currentQuestionIndex + 1) / widget.formJson.length,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    widget.primaryColor ?? Colors.black,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      Container(
        key: ValueKey(controller.currentQuestionIndex),
        child: _buildField(field),
      ),
      SizedBox(height: 20),
    ];
  }

  Widget _buildField(Map<String, dynamic> field) {
    Widget formField;

    switch (field['type']) {
      case 'radio':
        formField = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: (field['options'] as List<dynamic>).map<Widget>((option) {
                return ReactiveRadioListTile<String>(
                  formControlName: field['name'],
                  value: option.toString(),
                  title: Text(option.toString()),
                );
              }).toList(),
            ),
            // Handle sub-questions
            ReactiveValueListenableBuilder(
              formControlName: field['name'],
              builder: (context, control, child) {
                if (control.value != null && 
                    field['subQuestions'] != null && 
                    field['subQuestions'][control.value] != null) {
                  return Padding(
                    padding: EdgeInsets.only(left: 20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: (field['subQuestions'][control.value] as List)
                          .map<Widget>((subField) => Padding(
                                padding: EdgeInsets.only(top: 16.0),
                                child: _buildField(subField),
                              ))
                          .toList(),
                    ),
                  );
                }
                return SizedBox.shrink();
              },
            ),
          ],
        );
        break;

      case 'dropdown':
        formField = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ReactiveDropdownField<String>(
              formControlName: field['name'],
              items: (field['options'] as List<dynamic>).map<DropdownMenuItem<String>>((option) {
                return DropdownMenuItem<String>(
                  value: option.toString(),
                  child: Text(option.toString()),
                );
              }).toList(),
              decoration: InputDecoration(labelText: field['label']),
            ),
            // Handle sub-questions for dropdown
            ReactiveValueListenableBuilder(
              formControlName: field['name'],
              builder: (context, control, child) {
                if (control.value != null && 
                    field['subQuestions'] != null && 
                    field['subQuestions'][control.value] != null) {
                  return Padding(
                    padding: EdgeInsets.only(left: 20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: (field['subQuestions'][control.value] as List)
                          .map<Widget>((subField) => Padding(
                                padding: EdgeInsets.only(top: 16.0),
                                child: _buildField(subField),
                              ))
                          .toList(),
                    ),
                  );
                }
                return SizedBox.shrink();
              },
            ),
          ],
        );
        break;

      case 'input':
        formField = ReactiveTextField(
          formControlName: field['name'],
          keyboardType: field['inputType'] == 'number'
              ? TextInputType.number
              : TextInputType.text,
          decoration: InputDecoration(labelText: field['label']),
        );
        break;

      default:
        formField = SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (field['label'] != null) ...[
          Text(
            field['label'],
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
          if (field['validators']?.contains('required') == true)
            Padding(
              padding: EdgeInsets.only(top: 4.0),
              child: Text(
                '* Required',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.red,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          SizedBox(height: 8),
        ],
        formField,
        SizedBox(height: widget.fieldSpacing),
        if (field['hasAttachments'] == true)
          ReactiveValueListenableBuilder<String>(
            formControlName: field['name'],
            builder: (context, value, child) {
              final showAttachments = value.value != null &&
                  (field['showAttachmentsOn'] == null || value.value == field['showAttachmentsOn']);
              
              if (!showAttachments) return SizedBox.shrink();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: () => _showFilePickerOptions(field['name'], field['label']),
                      icon: Icon(
                        Icons.attach_file,
                        size: 24,
                      ),
                      label: Text(
                        'Add Attachment',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.primaryColor ?? Colors.black,
                        foregroundColor: widget.buttonTextColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      ),
                    ),
                  ),
                  if (controller.uploadedFiles[field['name']]!.isNotEmpty) ...[
                    SizedBox(height: 16),
                    ...controller.uploadedFiles[field['name']]!.map((file) => Card(
                      margin: EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(
                          _getFileIcon(file['fileType']),
                          color: widget.primaryColor ?? Colors.black,
                          size: 24,
                        ),
                        title: Text(
                          file['fileName'] ?? 'Unnamed file',
                          style: TextStyle(fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            setState(() {
                              controller.uploadedFiles[field['name']]!.remove(file);
                            });
                          },
                        ),
                        onTap: () => _viewFile(context, file),
                      ),
                    )).toList(),
                  ],
                ],
              );
            },
          ),
        if (field['hasComments'] == true)
          ReactiveValueListenableBuilder<String>(
            formControlName: field['name'],
            builder: (context, value, child) {
              bool showCommentBox = value.value != null && 
                  (field['showCommentsOn'] is List 
                      ? (field['showCommentsOn'] as List).contains(value.value)
                      : value.value == field['showCommentsOn']);
              
              return showCommentBox
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: widget.fieldSpacing),
                        ReactiveTextField(
                          formControlName: '${field['name']}_comment',
                          decoration: InputDecoration(
                            labelText: field['commentLabel'] ?? 'Comments',
                            hintText: field['commentHint'] ?? 'Enter your comments here',
                          ),
                          maxLines: 3,
                        ),
                      ],
                    )
                  : SizedBox.shrink();
            },
          ),
      ],
    );
  }

  IconData _getFileIcon(String fileType) {
    switch (fileType) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'document':
        return Icons.description;
      case 'spreadsheet':
        return Icons.table_chart;
      case 'image':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  Widget _buildStepNavigation(Color buttonColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (controller.currentQuestionIndex > 0)
          IconButton(
            onPressed: () {
              setState(() {
                controller.currentQuestionIndex--;  // This will move back one question
              });
            },
            icon: Icon(Icons.arrow_back_ios),
            color: buttonColor,
            iconSize: 30,
          )
        else
          SizedBox(width: 48),
        
        if (controller.currentQuestionIndex == widget.formJson.length - 1)
          ElevatedButton(
            onPressed: () {
              if (controller.form.valid) {
                controller.submitForm(context);
              } else {
                controller.form.markAllAsTouched();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Please check all required fields'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: buttonColor,
              foregroundColor: widget.buttonTextColor,
              padding: EdgeInsets.symmetric(horizontal: 30, vertical: 12),
            ),
            child: Text('Submit'),
          )
        else
          IconButton(
            onPressed: () {
              if (controller.validateAndProceed(context)) {
                setState(() {});  // Trigger rebuild with new question index
              }
            },
            icon: Icon(Icons.arrow_forward_ios),
            color: buttonColor,
            iconSize: 30,
          ),
      ],
    );
  }

  Widget _buildSubmitButton(Color buttonColor) {
    return ElevatedButton(
      child: Text('Submit'),
      onPressed: _submitForm,
      style: ElevatedButton.styleFrom(
        backgroundColor: buttonColor,
        foregroundColor: widget.buttonTextColor,
        padding: EdgeInsets.symmetric(vertical: 16),
        minimumSize: Size(double.infinity, 50),
      ),
    );
  }
}