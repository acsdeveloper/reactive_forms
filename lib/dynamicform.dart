import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:flutter/material.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:universal_html/html.dart' as html;
import 'package:flutter/services.dart';

import 'dynmaicformcontroller.dart';



class DynamicForm extends StatefulWidget {
  final List<Map<String, dynamic>> formJson;
  final void Function(Map<String, dynamic>, Map<String, List<Map<String, dynamic>>> uploadedFiles) onSubmit;
  final Color primaryColor;
  final Color buttonTextColor;
  final double fieldSpacing;
  final bool showOneByOne;
  final BuildContext context;
  final TextStyle fontFamily;
  final Color fileUploadButtonColor;
  final Color fileUploadButtonTextColor;

  DynamicForm({
    required this.formJson,
    required this.onSubmit,
    required this.context,
    this.primaryColor = const Color(0xFF4BA7D1),
    this.buttonTextColor = Colors.white,
    this.fieldSpacing = 20.0,
    this.showOneByOne = false,
    required this.fontFamily,
    this.fileUploadButtonColor = Colors.black,
    this.fileUploadButtonTextColor = Colors.white,
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

  @override
  Widget build(BuildContext context) {
    final buttonColor = widget.primaryColor ?? Colors.black;
    
    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(context).textTheme.apply(
          fontFamily: widget.fontFamily.fontFamily,
        ),
      ),
      child: ReactiveForm(
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
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
          bottomNavigationBar: _buildBottomNavigation(buttonColor),
        ),
      ),
    );
  }

  Widget _buildBottomNavigation(Color buttonColor) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: widget.showOneByOne
          ? _buildStepNavigation(buttonColor)
          : _buildSubmitButton(buttonColor),
    );
  }

  List<Widget> _buildAllFields() {
    return widget.formJson.map((field) => Column(
      children: [
        _buildField(field),
        const Divider(height: 32, thickness: 1),
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
              style: widget.fontFamily.copyWith(fontWeight: FontWeight.bold),
            ),
            SizedBox(
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
      const SizedBox(height: 20),
    ];
  }

  Widget _buildField(Map<String, dynamic> field) {
    Widget formField;

    switch (field['type']) {
      case 'radio':
        formField = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: (field['options'] as List<dynamic>).map<Widget>((option) {
            return Container(
              padding: EdgeInsets.zero,
              margin: EdgeInsets.symmetric(vertical: 4.0),
              child: Transform.translate(
                offset: Offset(-12, 0),
                child: ReactiveRadioListTile<String>(
                  formControlName: field['name'],
                  value: option.toString(),
                  title: Text(
                    option.toString(),
                    style: widget.fontFamily
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            );
          }).toList(),
        );
        break;

      case 'dropdown':
        formField = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
                  ),
                  builder: (context) => _DropdownSearch(
                    fontFamily: widget.fontFamily,
                    options: field['options'] as List<dynamic>,
                    selectedValue: controller.form.control(field['name']).value,
                    onSelect: (value) {
                      controller.form.control(field['name']).value = value;
                      Navigator.pop(context);
                    },
                    primaryColor: widget.primaryColor,
                  ),
                );
              },
              child: ReactiveValueListenableBuilder<String>(
                formControlName: field['name'],
                builder: (context, control, child) {
                  return Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ListTile(
                      title: Text(
                        control.value ?? 'Select an option',
                        style: widget.fontFamily,
                      ),
                      trailing: Icon(Icons.arrow_drop_down, color: Colors.grey.shade600),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                },
              ),
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
        formField = ReactiveValueListenableBuilder<String>(
          formControlName: field['name'],
          builder: (context, control, child) {
            if (control.value != null && 
                control.value.toString().toLowerCase() == field['inputType']?.toString().toLowerCase()) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                controller.form.control(field['name']).value = '';
              });
            }
            
            return ReactiveTextField(
              formControlName: field['name'],
              keyboardType: field['inputType'] == 'number'
                  ? TextInputType.number
                  : TextInputType.text,
             
            );
          },
        );
        break;
      case 'number':
        formField = ReactiveTextField<num>(
          formControlName: field['name'],
          keyboardType: TextInputType.number,
          valueAccessor: NumValueAccessor(),
          validationMessages: {
            'required': (error) => 'This field is required',
            'min': (error) => 'Value must be at least ${field['min']}',
            'max': (error) => 'Value must be at most ${field['max']}',
          },
          decoration: InputDecoration(
            hintText: 'Enter a number' + 
              (field['min'] != null || field['max'] != null ? ' (' : '') +
              (field['min'] != null ? 'min: ${field['min']}' : '') +
              (field['min'] != null && field['max'] != null ? ', ' : '') +
              (field['max'] != null ? 'max: ${field['max']}' : '') +
              (field['min'] != null || field['max'] != null ? ')' : ''),
            labelStyle: widget.fontFamily,
            hintStyle: widget.fontFamily,
            errorStyle: widget.fontFamily.copyWith(color: Colors.red),
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.-]')), // Allow numbers, decimal point, and minus sign
          ],
        );
        break;

    
    
       
      default:
        formField = SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (field['label'] != null) ...[
          Container(
            padding: EdgeInsets.zero,
            child: Text(
              field['label'],
              style: widget.fontFamily,
            ),
          ),
          if (field['validators']?.contains('required') == true)
            Container(
              padding: EdgeInsets.only(top: 4.0),
              child: Text(
                '*',
                style: widget.fontFamily.copyWith(color: const Color.fromARGB(255, 222, 75, 64)),
              ),
            ),
          const SizedBox(height: 8),
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

              // Initialize the comment control if it doesn't exist and if comments are enabled
              final commentControlName = '${field['name']}_comment';
              if (field['hasComments'] == true && !controller.form.contains(commentControlName)) {
                controller.form.addAll({
                  commentControlName: FormControl<String>(value: ''),
                });
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 16),
                  InkWell(
                    onTap: () => _showFilePickerOptions(field['name'], field['label']),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: widget.primaryColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.upload_file_rounded,
                            color: widget.buttonTextColor,
                            size: 24,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Upload Files',
                            style: widget.fontFamily.copyWith(color: Colors.white),
                          )
                        ],
                      ),
                    ),
                  ),
                  if (controller.uploadedFiles[field['name']]?.isNotEmpty ?? false) ...[
                    SizedBox(height: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: controller.uploadedFiles[field['name']]!.map((file) {
                        return Card(
                          margin: EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            onTap: () => _viewFile(context, file),
                            leading: Icon(_getFileIcon(file['fileType'])),
                            title: Text(
                              file['fileName'] ?? 'Unnamed file',
                              style: widget.fontFamily,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.delete),
                                  color: const Color.fromARGB(255, 199, 86, 86),
                                  onPressed: () {
                                    setState(() {
                                      controller.uploadedFiles[field['name']]!.remove(file);
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  if (field['hasComments'] == true) ...[
                    SizedBox(height: widget.fieldSpacing),
                    ReactiveTextField(
                      formControlName: commentControlName,
                      decoration: InputDecoration(
                        labelText: 'Add a comment',
                       
                        border: OutlineInputBorder(),
                       labelStyle: widget.fontFamily,
                       hintStyle: widget.fontFamily,
                       hoverColor: widget.buttonTextColor,

                      ),
                      maxLines: 3,
                    ),
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
                            labelStyle: widget.fontFamily,
                            hintStyle: widget.fontFamily,
                          ),
                          maxLines: 3,
                        ),
                      ],
                    )
                  : const SizedBox.shrink();
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

  void _viewFile(BuildContext context, Map<String, dynamic> file) {
    try {
      if (file['file'] is Uint8List) {
        if (kIsWeb) {
          // Web-specific file viewing
          final blob = html.Blob([file['file']]);
          final url = html.Url.createObjectUrlFromBlob(blob);
          
          // Check if it's an image type
          if (file['fileType'] == 'image' || (file['mimeType'] ?? '').startsWith('image/')) {
            // Open image in new tab
            html.window.open(url, '_blank');
          } else {
            // Trigger download for non-image files
            final anchor = html.AnchorElement()
              ..href = url
              ..download = file['fileName'] ?? 'download'
              ..click();
          }
          html.Url.revokeObjectUrl(url);
        } else {
          // Mobile viewing
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(
                  title: Text(file['fileName'] ?? 'File Preview',style: widget.fontFamily),
                  backgroundColor: widget.primaryColor ?? Colors.black,
                ),
                body: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: file['fileType'] == 'image' || (file['mimeType'] ?? '').startsWith('image/')
                            ? Image.memory(
                                file['file'],
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  print('Error loading image: $error');
                                  return Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.error_outline, size: 48, color: Colors.red),
                                      SizedBox(height: 16),
                                      Text('Error loading image',style: widget.fontFamily),
                                    ],
                                  );
                                },
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(_getFileIcon(file['fileType']), size: 48),
                                  SizedBox(height: 16),
                                  Text(file['fileName'] ?? 'File',style: widget.fontFamily),
                                  Text('This file type cannot be previewed',style: widget.fontFamily),
                                ],
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
          content: Text('Error viewing file. Please try again.',style: widget.fontFamily),
          duration: Duration(seconds: 2),
        ),
      );
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
                controller.currentQuestionIndex--;
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
              bool isValid = true;
              
              // Check each field's validation
              for (var field in widget.formJson) {
                final fieldName = field['name'];
                final control = controller.form.control(fieldName);
                
                // If field has file upload and files are present, consider it valid
                if (field['type'] == 'file') {
                  if (field['validators']?.contains('required') == true) {
                    // Check if there are uploaded files for this field
                    isValid = isValid && (controller.uploadedFiles[fieldName]?.isNotEmpty ?? false);
                  }
                  continue; // Skip further validation for file fields
                }
                
                // For non-file fields, check form control validity
                if (control != null && !control.valid) {
                  isValid = false;
                  break;
                }
              }

              if (isValid) {
                controller.submitForm(widget.context);
              } else {
                controller.form.markAllAsTouched();
                ScaffoldMessenger.of(widget.context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Please check all required fields',
                      style: widget.fontFamily,
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: buttonColor,
              foregroundColor: widget.buttonTextColor,
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
            ),
            child: Text('Submit',style: widget.fontFamily),
          )
        else
          IconButton(
            onPressed: () {
              if (controller.validateAndProceed(widget.context)) {
                setState(() {});
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
      child: Text('Submit',style: widget.fontFamily),
      onPressed: () => _submitForm(widget.context),
      style: ElevatedButton.styleFrom(
        backgroundColor: buttonColor,
        foregroundColor: widget.buttonTextColor,
        padding: const EdgeInsets.symmetric(vertical: 16),
        minimumSize: const Size(double.infinity, 50),
      ),
    );
  }

  void _submitForm(contaxt) {
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
          
          ScaffoldMessenger.of(widget.context).showSnackBar(
            SnackBar(
              content: Text('Please fill in all required fields',style: widget.fontFamily),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  String _getFileType(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
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
        return 'other';
    }
  }

  void _showFilePickerOptions(String fieldName, String fieldLabel) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
        allowCompression: true,
      );
      
      if (result != null && result.files.isNotEmpty) {
        setState(() {
          controller.uploadedFiles[fieldName]!.clear();
          
          for (var file in result.files) {
            if (file.bytes != null) {
              controller.uploadedFiles[fieldName]!.add({
                'question_name': fieldName,
                'question_label': fieldLabel,
                'file': file.bytes,
                'fileName': file.name,
                'fileType': _getFileType(file.name),
                'mimeType': file.extension != null ? 'application/${file.extension}' : 'application/octet-stream',
              });
            }
          }
        });
      }
    } catch (e) {
      print('Error in file upload: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error selecting file. Please try again.',
            style:widget.fontFamily,
          ),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
}

class _DropdownSearch extends StatefulWidget {
  final List<dynamic> options;
  final String? selectedValue;
  final Function(String) onSelect;
  final Color? primaryColor;
  final TextStyle fontFamily;

  const _DropdownSearch({
    required this.options,
    required this.selectedValue,
    required this.onSelect,
    this.primaryColor,
    required this.fontFamily,
  });

  @override
  _DropdownSearchState createState() => _DropdownSearchState();
}

class _DropdownSearchState extends State<_DropdownSearch> {
  late List<dynamic> filteredOptions;
  final TextEditingController searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    filteredOptions = List.from(widget.options);
  }

  void _filterOptions(String query) {
    setState(() {
      filteredOptions = widget.options
          .where((option) => option.toString().toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: TextField(
                style: widget.fontFamily,
                controller: searchController,
                decoration: InputDecoration(
                  hintText: 'Search...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: _filterOptions,
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: filteredOptions.length,
                itemBuilder: (context, index) {
                  final option = filteredOptions[index];
                  return ListTile(
                    title: Text(option.toString()),
                    onTap: () => widget.onSelect(option.toString()),
                    trailing: widget.selectedValue == option.toString()
                      ? Icon(Icons.check, color: widget.primaryColor)
                      : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }
}

class NumValueAccessor extends ControlValueAccessor<num, String> {
  @override
  String modelToViewValue(num? modelValue) {
    return modelValue?.toString() ?? '';
  }

  @override
  num? viewToModelValue(String? viewValue) {
    if (viewValue == null || viewValue.isEmpty) return null;
    return num.tryParse(viewValue);
  }
}