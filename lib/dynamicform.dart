import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:reactiveform/constants.dart';
import 'package:reactiveform/string_constants.dart';
import 'package:flutter/services.dart';
import 'dynamicformcontroller.dart';
import 'package:reactiveform/models/form_field_model.dart';

import 'widgets/multi_select_form_field.dart';

class DynamicForm extends StatefulWidget {
  final List<Map<String, dynamic>> formJson;
  final Function(Map<String, dynamic>,
      Map<String, List<Map<String, dynamic>>> uploadedFiles) onSubmit;
  final Color primaryColor;
  final Color buttonTextColor;
  final double fieldSpacing;
  final bool showOneByOne;
  final BuildContext context;
  final TextStyle fontFamily;
  final Color fileUploadButtonColor;
  final Color fileUploadButtonTextColor;

  const DynamicForm({
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
    Key? key,
  }) : super(key: key);

  @override
  State<DynamicForm> createState() => _DynamicFormState();
}

class _DynamicFormState extends State<DynamicForm> {
  late DynamicFormController controller;
  late BuildContext dialogContext;
  static const _maxFileSize = 3 * 1024 * 1024; // 5MB
  static const double _iconSize = 24.0;
  List<int> questionSequence = [0];
  Set<String> visitedQuestions = {};
  int currentVisibleQuestionIndex = 0;
  int totalVisibleQuestions = 1;
  late PageController _pageController;
  final _progressKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    controller = DynamicFormController(
      formJson: widget.formJson,
      onSubmit: widget.onSubmit,
    );
    
    // Add a listener to the controller to update the UI when the question changes
    controller.addListener(_onControllerChanged);
    
    // Initialize PageController to the current question
    _pageController = PageController(initialPage: controller.currentQuestionIndex);
    
    // Calculate initial progress
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculateProgress();
    });
  }

  @override
  void dispose() {
    // Remove the listener when the widget is disposed
    controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  // This will be called whenever the controller notifies its listeners
  void _onControllerChanged() {
    // When controller changes, update the PageView if needed
    if (_pageController.page?.round() != controller.currentQuestionIndex) {
      _pageController.animateToPage(
        controller.currentQuestionIndex,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
    _calculateProgress();
  }

  // Calculate the progress based on visible questions
  void _calculateProgress() {
    List<int> visibleIndices = _getVisibleQuestionIndices();
    
    int position = visibleIndices.indexOf(controller.currentQuestionIndex);
    if (position == -1 && visibleIndices.isNotEmpty) {
      // Find the closest position
      for (int i = 0; i < visibleIndices.length; i++) {
        if (visibleIndices[i] >= controller.currentQuestionIndex) {
          position = i;
          break;
        }
      }
      if (position == -1) position = visibleIndices.length - 1;
    }
    
    setState(() {
      currentVisibleQuestionIndex = position >= 0 ? position : 0;
      totalVisibleQuestions = visibleIndices.isNotEmpty ? visibleIndices.length : 1;
      print("Progress updated: ${currentVisibleQuestionIndex + 1}/$totalVisibleQuestions");
    });
  }

  // Get the list of visible question indices
  List<int> _getVisibleQuestionIndices() {
    List<int> visible = [];
    
    for (int i = 0; i < widget.formJson.length; i++) {
      final question = widget.formJson[i];
      
      if (question['showWhen'] == null) {
        visible.add(i);
        continue;
      }
      
      bool shouldShow = true;
      final conditions = question['showWhen'] as Map<String, dynamic>;
      
      conditions.forEach((field, expectedValues) {
        if (!controller.form.contains(field)) {
          shouldShow = false;
          return;
        }
        
        final value = controller.form.control(field).value;
        bool matches = false;
        
        if (expectedValues is List) {
          matches = expectedValues.contains(value);
        } else {
          matches = (value == expectedValues);
        }
        
        shouldShow = shouldShow && matches;
      });
      
      if (shouldShow) {
        visible.add(i);
      }
    }
    
    return visible;
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild progress in the main build method to ensure it updates
    _calculateProgress();
    
    final buttonColor = widget.primaryColor;

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
            key: ValueKey(
                '${StringConstants.form}${controller.currentQuestionIndex}'),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.showOneByOne) ..._buildOneByOneFields(),
                if (!widget.showOneByOne) ..._buildAllFields(),
                
              ],
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
    return widget.formJson
        .map((field) => Column(
              children: [
                _buildField(field),
                const Divider(height: 32, thickness: 1),
              ],
            ))
        .toList();
  }

  List<Widget> _buildOneByOneFields() {
    if (controller.currentQuestionIndex >= widget.formJson.length) {
      return [];
    }

    final field = widget.formJson[controller.currentQuestionIndex];

    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${StringConstants.questionNumber} ${currentVisibleQuestionIndex + 1}',
              style: widget.fontFamily.copyWith(fontWeight: FontWeight.bold),
            ),
            SizedBox(
              width: 100,
              height: 6,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: totalVisibleQuestions > 0 
                    ? (currentVisibleQuestionIndex + 1) / totalVisibleQuestions 
                    : 0,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    widget.primaryColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: Row(
          children: [
            Expanded(
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: field['label'],
                      style: widget.fontFamily.copyWith(fontWeight: FontWeight.bold,color: Colors.black),
                    ),
                    if (field['required'] == true)
                      TextSpan(
                        text: ' *',
                        style: widget.fontFamily.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      if (field['description'] != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Text(
            field['description'],
            style: widget.fontFamily,
          ),
        ),
      KeyedSubtree(
        key: ValueKey(controller.currentQuestionIndex),
        child: _buildField(field),
      ),
      const SizedBox(height: 20),
    ];
  }

  Widget _buildField(Map<String, dynamic> field) {
    if (field['showWhen'] != null) {
      return ReactiveFormConsumer(
        builder: (context, form, child) {
          bool shouldShow = false;  // Initialize to false for OR logic
          final conditions = field['showWhen'] as Map<String, dynamic>;

          conditions.forEach((dependentField, expectedValue) {
            final dependentControl = form.control(dependentField);
            final currentValue = dependentControl.value;

            if (expectedValue is List) {
              shouldShow = shouldShow || expectedValue.contains(currentValue);
            } else {
              shouldShow = shouldShow || currentValue == expectedValue;
            }
          });

          if (!shouldShow) {
            return const SizedBox.shrink();
          }

          return _buildFieldWidget(field);
        },
      );
    }

    return _buildFieldWidget(field);
  }

  Widget _buildFieldWidget(Map<String, dynamic> field) {
    final control = controller.form.control(field['name']);
    return _buildActualField(field, control);
  }

  Widget _buildActualField(
      Map<String, dynamic> field, AbstractControl<dynamic> control) {
    switch (field['type']) {
      case 'option':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (field['options'] != null)
              ...field['options']
                  .map<Widget>(
                    (option) => RadioListTile<String>(
                      title: Text(option.toString(), style: widget.fontFamily),
                      value: option.toString(),
                      groupValue: control.value,
                      activeColor: widget.primaryColor,
                      onChanged: (value) {
                        setState(() {
                          control.value = value;
                        });
                      },
                    ),
                  )
                  .toList(),
            if (control.touched && control.hasErrors)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  control.errors.toString(),
                  style: widget.fontFamily
                      .copyWith(color: Colors.red[700], fontSize: 12),
                ),
              ),
          ],
        );
      case FieldType.radio:
        return _buildRadioField(field);
      case FieldType.dropdown:
        return _buildDropdownField(field);
      case FieldType.text:
        return _buildTextField(field);
      case FieldType.number:
        return _buildNumberField(field);
      case FieldType.file:
        return _buildFileField(field);
      case 'multiselect':
        return ReactiveFormField<List<String>, List<String>>(
          formControlName: field['name'],
          validationMessages: {
            'required': (_) => 'Please select at least one option',
          },
          builder: (ReactiveFormFieldState<List<String>, List<String>> state) {
            // Get current control value, ensuring it's a List<String>
            List<String> currentValue = [];
            final rawValue = controller.form.control(field['name']).value;
            
            if (rawValue is List) {
              currentValue = List<String>.from(rawValue.map((e) => e.toString()));
            } else if (rawValue != null && rawValue != "") {
              // Handle case when it's a single value
              currentValue = [rawValue.toString()];
            }
            
            return MultiSelectFormField(
              field: FormFieldModel.fromJson(field),
              onChanged: (List<String> value) {
                // Force direct update to the FormGroup's value
                controller.form.patchValue({field['name']: value});
                
                // Explicitly update control to ensure type consistency
                final control = controller.form.control(field['name']);
                if (control is FormControl<dynamic>) {
                  control.updateValue(value);
                }
                
                // Debug info
                print('Updated ${field['name']} with: $value (type: ${value.runtimeType})');
                print('Current form value: ${controller.form.value}');
                
                state.didChange(value);
                state.control.markAsTouched();
              },
              value: currentValue,
              hasError: state.control.touched && !state.control.valid,
              errorText: state.control.touched && !state.control.valid
                  ? 'Please select at least one option'
                  : null,
            );
          },
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildQuestionHeader(Map<String, dynamic> field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (field['required'] == true)
          Text(
            ' *',
            style: widget.fontFamily.copyWith(color: Colors.red),
          ),
        SizedBox(height: 8),
        Text(
          field['label'],
          style: widget.fontFamily,
        ),
      ],
    );
  }

  Widget _buildFormField(Map<String, dynamic> field) {
    final fieldType = field['type'];

    switch (fieldType) {
      case FieldType.radio:
        return _buildRadioField(field);
      case FieldType.dropdown:
        return _buildDropdownField(field);
      case FieldType.text:
        return _buildTextField(field);
      case FieldType.number:
        return _buildNumberField(field);
      case FieldType.file:
        return _buildFileField(field);
      case 'multiselect':
        return ReactiveFormField<List<String>, List<String>>(
          formControlName: field['name'],
          validationMessages: {
            'required': (_) => 'Please select at least one option',
          },
          builder: (ReactiveFormFieldState<List<String>, List<String>> state) {
            // Get current control value, ensuring it's a List<String>
            List<String> currentValue = [];
            final rawValue = controller.form.control(field['name']).value;
            
            if (rawValue is List) {
              currentValue = List<String>.from(rawValue.map((e) => e.toString()));
            } else if (rawValue != null && rawValue != "") {
              // Handle case when it's a single value
              currentValue = [rawValue.toString()];
            }
            
            return MultiSelectFormField(
              field: FormFieldModel.fromJson(field),
              onChanged: (List<String> value) {
                // Force direct update to the FormGroup's value
                controller.form.patchValue({field['name']: value});
                
                // Explicitly update control to ensure type consistency
                final control = controller.form.control(field['name']);
                if (control is FormControl<dynamic>) {
                  control.updateValue(value);
                }
                
                // Debug info
                print('Updated ${field['name']} with: $value (type: ${value.runtimeType})');
                print('Current form value: ${controller.form.value}');
                
                state.didChange(value);
                state.control.markAsTouched();
              },
              value: currentValue,
              hasError: state.control.touched && !state.control.valid,
              errorText: state.control.touched && !state.control.valid
                  ? 'Please select at least one option'
                  : null,
            );
          },
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildRadioField(Map<String, dynamic> field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: (field['options'] as List<dynamic>).map<Widget>((option) {
            return Container(
              padding: EdgeInsets.zero,
              margin: const EdgeInsets.symmetric(vertical: 4.0),
              child: Transform.translate(
                offset: const Offset(-12, 0),
                child: ReactiveRadioListTile<String>(
                  formControlName: field['name'],
                  value: option.toString(),
                  title: Text(option.toString(), style: widget.fontFamily),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            );
          }).toList(),
        ),
        if (field['hasAttachments'] == true)
          ReactiveValueListenableBuilder(
            formControlName: field['name'],
            builder: (context, control, child) {
              // First check if requireAttachmentsOn is specified
              if (field['requireAttachmentsOn'] != null) {
                // Handle both single value and array of values
                List<dynamic> requiredOptions =
                    field['requireAttachmentsOn'] is List
                        ? field['requireAttachmentsOn']
                        : [field['requireAttachmentsOn']];

                List<dynamic> disabledOptions =
                    field['disableAttachmentsOn'] is List
                        ? field['disableAttachmentsOn']
                        : field['disableAttachmentsOn'] != null
                            ? [field['disableAttachmentsOn']]
                            : [];

                final showAttachments =
                    requiredOptions.contains(control.value) &&
                        !disabledOptions.contains(control.value);

                if (!showAttachments) return const SizedBox.shrink();

                return Column(
                  children: [
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(
                          StringConstants.uploadFiles,
                          style: widget.fontFamily,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '*',
                          style: widget.fontFamily.copyWith(
                            color: const Color.fromARGB(255, 222, 75, 64),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    FileUploadWidget(
                      fieldName: field['name'],
                      fieldLabel: field['label'],
                      primaryColor: widget.primaryColor,
                      fontFamily: widget.fontFamily,
                      buttonTextColor: widget.buttonTextColor,
                      onFilesUploaded: (files) {
                        setState(() {
                          controller.uploadedFiles[field['name']] = files;
                        });
                      },
                      uploadedFiles:
                          controller.uploadedFiles[field['name']] ?? [],
                      onRemoveUploadedFile: (file) {
                        setState(() {
                          controller.uploadedFiles[field['name']]!.remove(file);
                        });
                      },
                      isRequired: true,
                    ),
                  ],
                );
              }
              // If no requireAttachmentsOn, check showAttachmentsOn
              else if (field['showAttachmentsOn'] != null) {
                // Handle both single value and array of values
                List<dynamic> showOptions = field['showAttachmentsOn'] is List
                    ? field['showAttachmentsOn']
                    : [field['showAttachmentsOn']];

                List<dynamic> disabledOptions =
                    field['disableAttachmentsOn'] is List
                        ? field['disableAttachmentsOn']
                        : field['disableAttachmentsOn'] != null
                            ? [field['disableAttachmentsOn']]
                            : [];

                final showAttachments = showOptions.contains(control.value) &&
                    !disabledOptions.contains(control.value);

                if (!showAttachments) return const SizedBox.shrink();

                return Column(
                  children: [
                    const SizedBox(height: 16),
                    FileUploadWidget(
                      fieldName: field['name'],
                      fieldLabel: field['label'],
                      primaryColor: widget.primaryColor,
                      fontFamily: widget.fontFamily,
                      buttonTextColor: widget.buttonTextColor,
                      onFilesUploaded: (files) {
                        setState(() {
                          controller.uploadedFiles[field['name']] = files;
                        });
                      },
                      uploadedFiles:
                          controller.uploadedFiles[field['name']] ?? [],
                      onRemoveUploadedFile: (file) {
                        setState(() {
                          controller.uploadedFiles[field['name']]!.remove(file);
                        });
                      },
                      isRequired: false,
                    ),
                  ],
                );
              }

              return const SizedBox.shrink();
            },
          ),
        if (field['hasComments'] == true) ...[
          const SizedBox(height: 16),
          ReactiveTextField(
            formControlName: '${field['name']}_comment',
            decoration: InputDecoration(
              labelText: field['commentLabel'] ?? StringConstants.comments,
              hintText:
                  field['commentHint'] ?? StringConstants.enterCommentsHere,
              labelStyle: widget.fontFamily,
              hintStyle: widget.fontFamily,
            ),
            maxLines: 3,
          ),
        ],
      ],
    );
  }

  Widget _buildDropdownField(Map<String, dynamic> field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(15))),
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
                    control.value ?? StringConstants.selectOption,
                    style: widget.fontFamily,
                  ),
                  trailing:
                      Icon(Icons.arrow_drop_down, color: Colors.grey.shade600),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  visualDensity: VisualDensity.compact,
                ),
              );
            },
          ),
        ),
        ReactiveValueListenableBuilder(
          formControlName: field['name'],
          builder: (context, control, child) {
            if (control.value != null &&
                field['subQuestions'] != null &&
                field['subQuestions'][control.value] != null) {
              return Padding(
                padding: const EdgeInsets.only(left: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: (field['subQuestions'][control.value] as List)
                      .map<Widget>((subField) => Padding(
                            padding: const EdgeInsets.only(top: 16.0),
                            child: _buildField(subField),
                          ))
                      .toList(),
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
        if (field['hasAttachments'] == true)
          ReactiveValueListenableBuilder(
            formControlName: field['name'],
            builder: (context, control, child) {
              // First check if requireAttachmentsOn is specified
              if (field['requireAttachmentsOn'] != null) {
                // Handle both single value and array of values
                List<dynamic> requiredOptions =
                    field['requireAttachmentsOn'] is List
                        ? field['requireAttachmentsOn']
                        : [field['requireAttachmentsOn']];

                List<dynamic> disabledOptions =
                    field['disableAttachmentsOn'] is List
                        ? field['disableAttachmentsOn']
                        : field['disableAttachmentsOn'] != null
                            ? [field['disableAttachmentsOn']]
                            : [];

                final showAttachments =
                    requiredOptions.contains(control.value) &&
                        !disabledOptions.contains(control.value);

                if (!showAttachments) return const SizedBox.shrink();

                return Column(
                  children: [
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(
                          StringConstants.uploadFiles,
                          style: widget.fontFamily,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '*',
                          style: widget.fontFamily.copyWith(
                            color: const Color.fromARGB(255, 222, 75, 64),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    FileUploadWidget(
                      fieldName: field['name'],
                      fieldLabel: field['label'],
                      primaryColor: widget.primaryColor,
                      fontFamily: widget.fontFamily,
                      buttonTextColor: widget.buttonTextColor,
                      onFilesUploaded: (files) {
                        setState(() {
                          controller.uploadedFiles[field['name']] = files;
                        });
                      },
                      uploadedFiles:
                          controller.uploadedFiles[field['name']] ?? [],
                      onRemoveUploadedFile: (file) {
                        setState(() {
                          controller.uploadedFiles[field['name']]!.remove(file);
                        });
                      },
                      isRequired: true,
                    ),
                  ],
                );
              }
              // If no requireAttachmentsOn, check showAttachmentsOn
              else if (field['showAttachmentsOn'] != null) {
                // Handle both single value and array of values
                List<dynamic> showOptions = field['showAttachmentsOn'] is List
                    ? field['showAttachmentsOn']
                    : [field['showAttachmentsOn']];

                List<dynamic> disabledOptions =
                    field['disableAttachmentsOn'] is List
                        ? field['disableAttachmentsOn']
                        : field['disableAttachmentsOn'] != null
                            ? [field['disableAttachmentsOn']]
                            : [];

                final showAttachments = showOptions.contains(control.value) &&
                    !disabledOptions.contains(control.value);

                if (!showAttachments) return const SizedBox.shrink();

                return Column(
                  children: [
                    const SizedBox(height: 16),
                    FileUploadWidget(
                      fieldName: field['name'],
                      fieldLabel: field['label'],
                      primaryColor: widget.primaryColor,
                      fontFamily: widget.fontFamily,
                      buttonTextColor: widget.buttonTextColor,
                      onFilesUploaded: (files) {
                        setState(() {
                          controller.uploadedFiles[field['name']] = files;
                        });
                      },
                      uploadedFiles:
                          controller.uploadedFiles[field['name']] ?? [],
                      onRemoveUploadedFile: (file) {
                        setState(() {
                          controller.uploadedFiles[field['name']]!.remove(file);
                        });
                      },
                      isRequired: false,
                    ),
                  ],
                );
              }

              return const SizedBox.shrink();
            },
          ),
        if (field['hasComments'] == true) ...[
          const SizedBox(height: 16),
          ReactiveTextField(
            formControlName: '${field['name']}_comment',
            decoration: InputDecoration(
              labelText: field['commentLabel'] ?? StringConstants.comments,
              hintText:
                  field['commentHint'] ?? StringConstants.enterCommentsHere,
              labelStyle: widget.fontFamily,
              hintStyle: widget.fontFamily,
            ),
            maxLines: 3,
          ),
        ],
      ],
    );
  }

  Widget _buildTextField(Map<String, dynamic> field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReactiveValueListenableBuilder<String>(
          formControlName: field['name'],
          builder: (context, control, child) {
            if (control.value != null &&
                control.value.toString().toLowerCase() ==
                    field['inputType']?.toString().toLowerCase()) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                controller.form.control(field['name']).value = '';
              });
            }

            return ReactiveTextField(
              formControlName: field['name'],
              keyboardType: field['type'] == 'number'
                  ? TextInputType.number
                  : TextInputType.text,
            );
          },
        ),
        if (field['hasComments'] == true) ...[
          const SizedBox(height: 16),
          ReactiveTextField(
            formControlName: '${field['name']}_comment',
            decoration: InputDecoration(
              labelText: field['commentLabel'] ?? StringConstants.comments,
              hintText:
                  field['commentHint'] ?? StringConstants.enterCommentsHere,
              labelStyle: widget.fontFamily,
              hintStyle: widget.fontFamily,
            ),
            maxLines: 3,
          ),
        ],
        if (field['hasAttachments'] == true) ...[
          const SizedBox(height: 16),
          FileUploadWidget(
            fieldName: field['name'],
            fieldLabel: field['label'],
            primaryColor: widget.primaryColor,
            fontFamily: widget.fontFamily,
            buttonTextColor: widget.buttonTextColor,
            onFilesUploaded: (files) {
              setState(() {
                controller.uploadedFiles[field['name']] = files;
              });
            },
            uploadedFiles: controller.uploadedFiles[field['name']] ?? [],
            onRemoveUploadedFile: (file) {
              setState(() {
                controller.uploadedFiles[field['name']]!.remove(file);
              });
            },
          ),
        ],
      ],
    );
  }

  Widget _buildNumberField(Map<String, dynamic> field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReactiveTextField<num>(
          formControlName: field['name'],
          keyboardType: TextInputType.number,
          valueAccessor: NumValueAccessor(),
          validationMessages: {
            'required': (error) => StringConstants.requiredField,
            'min': (error) =>
                '${StringConstants.valueMustBeAtLeast} ${field['min']}',
            'max': (error) =>
                '${StringConstants.valueMustBeLessThanOrEqualTo} ${field['max']}',
          },
          inputFormatters: [
            if (field['allowNegatives'] == false)
              FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
            if (field['allowNegatives'] != false)
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.-]')),
            if (field['allowedDecimals'] == 0)
              FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            hintText: StringConstants.enterANumber +
                (field['min'] != null || field['max'] != null ? ' (' : '') +
                (field['min'] != null ? 'min: ${field['min']}' : '') +
                (field['min'] != null && field['max'] != null ? ', ' : '') +
                (field['max'] != null ? 'max: ${field['max']}' : '') +
                (field['min'] != null || field['max'] != null ? ')' : ''),
            labelStyle: widget.fontFamily,
            hintStyle: widget.fontFamily,
            errorStyle: widget.fontFamily.copyWith(color: Colors.red),
          ),
        ),
        if (field['hasAttachments'] == true ||
            field['attachmentsRequired'] == true) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                StringConstants.uploadFiles,
                style: widget.fontFamily,
              ),
              if (field['attachmentsRequired'] == true) ...[
                const SizedBox(width: 4),
                Text(
                  '*',
                  style: widget.fontFamily.copyWith(
                    color: const Color.fromARGB(255, 222, 75, 64),
                    fontSize: 16,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          FileUploadWidget(
            fieldName: field['name'],
            fieldLabel: field['label'],
            primaryColor: widget.primaryColor,
            fontFamily: widget.fontFamily,
            buttonTextColor: widget.buttonTextColor,
            onFilesUploaded: (files) {
              setState(() {
                controller.uploadedFiles[field['name']] = files;
              });
            },
            uploadedFiles: controller.uploadedFiles[field['name']] ?? [],
            onRemoveUploadedFile: (file) {
              setState(() {
                controller.uploadedFiles[field['name']]!.remove(file);
              });
            },
            isRequired: field['attachmentsRequired'] == true,
          ),
        ],
        if (field['hasComments'] == true) ...[
          const SizedBox(height: 16),
          ReactiveTextField(
            formControlName: '${field['name']}_comment',
            decoration: InputDecoration(
              labelText: field['commentLabel'] ?? StringConstants.comments,
              hintText:
                  field['commentHint'] ?? StringConstants.enterCommentsHere,
              labelStyle: widget.fontFamily,
              hintStyle: widget.fontFamily,
            ),
            maxLines: 3,
          ),
        ],
      ],
    );
  }

  Widget _buildFileField(Map<String, dynamic> field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReactiveValueListenableBuilder<String>(
          formControlName: field['name'],
          builder: (context, control, child) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FileUploadWidget(
                  fieldName: field['name'],
                  fieldLabel: field['label'],
                  primaryColor: widget.primaryColor,
                  fontFamily: widget.fontFamily,
                  buttonTextColor: widget.buttonTextColor,
                  onFilesUploaded: (files) {
                    setState(() {
                      controller.uploadedFiles[field['name']] = files;
                      // Update the form control value when files are uploaded
                      if (files.isNotEmpty) {
                        control.value =
                            files.map((f) => f['fileName']).join(',');
                      } else {
                        control.value = null;
                      }
                    });
                  },
                  uploadedFiles: controller.uploadedFiles[field['name']] ?? [],
                  onRemoveUploadedFile: (file) {
                    setState(() {
                      controller.uploadedFiles[field['name']]!.remove(file);
                      // Update the form control value when files are removed
                      final remainingFiles =
                          controller.uploadedFiles[field['name']] ?? [];
                      if (remainingFiles.isEmpty) {
                        control.value = null;
                      } else {
                        control.value =
                            remainingFiles.map((f) => f['fileName']).join(',');
                      }
                    });
                  },
                  isRequired: field['required'] == true,
                ),
                if (control.touched && control.hasErrors)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      StringConstants.fileIsRequired,
                      style: TextStyle(color: Colors.red[700], fontSize: 12),
                    ),
                  ),
              ],
            );
          },
        ),
        if (field['hasComments'] == true) ...[
          const SizedBox(height: 16),
          ReactiveTextField(
            formControlName: '${field['name']}_comment',
            decoration: InputDecoration(
              labelText: field['commentLabel'] ?? StringConstants.comments,
              hintText:
                  field['commentHint'] ?? StringConstants.enterCommentsHere,
              labelStyle: widget.fontFamily,
              hintStyle: widget.fontFamily,
            ),
            maxLines: 3,
          ),
        ],
      ],
    );
  }

  Widget _buildStepNavigation(Color buttonColor) {
    return StreamBuilder(
      stream: controller.form.valueChanges,
      builder: (context, snapshot) {
        // Check if current question is effectively the last one
        final isEffectivelyLastQuestion = isCurrentQuestionEffectivelyLast();
        final shouldShowSubmit =
            controller.shouldShowSubmitButton() || isEffectivelyLastQuestion;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (controller.currentQuestionIndex > 0)
              IconButton(
                onPressed: () {
                  setState(() {
                    moveToPreviousValidQuestion();
                  });
                },
                icon: const Icon(Icons.arrow_back_ios),
                color: buttonColor,
                iconSize: 30,
              )
            else
              const SizedBox(width: 48),
            if (shouldShowSubmit)
              ElevatedButton(
                onPressed: () => _submitForm(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: buttonColor,
                  foregroundColor: widget.buttonTextColor,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: Text(
                  StringConstants.submit,
                  style: widget.fontFamily.copyWith(
                    color: widget.buttonTextColor,
                    fontSize: 16,
                  ),
                ),
              )
            else
              IconButton(
                onPressed: () {
                  moveToNextQuestion(context);
                },
                icon: const Icon(Icons.arrow_forward_ios),
                color: buttonColor,
                iconSize: 30,
              ),
          ],
        );
      },
    );
  }

  Widget _buildSubmitButton(Color buttonColor) {
    return ElevatedButton(
      onPressed: () => _submitForm(context),
      style: ElevatedButton.styleFrom(
        backgroundColor: buttonColor,
        foregroundColor: widget.buttonTextColor,
        padding: const EdgeInsets.symmetric(vertical: 16),
        minimumSize: const Size(double.infinity, 50),
      ),
      child: Text(StringConstants.submit,
          style: widget.fontFamily.copyWith(color: widget.buttonTextColor)),
    );
  }

  void _submitForm(BuildContext context) {
    // First validate the current question if in step-by-step mode
    if (widget.showOneByOne && controller.currentQuestionIndex < widget.formJson.length) {
      final currentField = widget.formJson[controller.currentQuestionIndex];
      final control = controller.form.control(currentField['name']);
      
      // Check if the current field is required and empty
      if ((currentField['required'] == true) &&
          (control.value == null || control.value.toString().isEmpty || control.value == 'null')) {
        control.markAsTouched();
        popuperror(StringConstants.pleaseFillInAllRequiredFields);
        return;
      }
      
      // Check for required file uploads
      if (currentField['type'] == 'file' && currentField['required'] == true) {
        final hasFiles = controller.uploadedFiles[currentField['name']]?.isNotEmpty ?? false;
        if (!hasFiles) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${currentField['label']} ${StringConstants.isRequired}',
                  style: widget.fontFamily),
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }
      }
    }
    
    // Clean up form data before submission
    Map<String, dynamic> cleanedFormData = Map.from(controller.form.value);
    Map<String, List<Map<String, dynamic>>> cleanedUploadedFiles = {};

    // Iterate through all form fields
    for (var field in widget.formJson) {
      final fieldName = field['name'];
      final value = cleanedFormData[fieldName];
      
      // Remove empty or null values
      if (value == null || value.toString().isEmpty || value == 'null') {
        cleanedFormData.remove(fieldName);
        controller.uploadedFiles.remove(fieldName);
        
        // Also remove associated comment if it exists
        if (field['hasComments'] == true) {
          cleanedFormData.remove('${fieldName}_comment');
        }
      } else {
        // Keep the uploaded files for answered questions
        if (controller.uploadedFiles.containsKey(fieldName)) {
          cleanedUploadedFiles[fieldName] = controller.uploadedFiles[fieldName]!;
        }
      }
    }

    // Submit the cleaned data
    widget.onSubmit(cleanedFormData, cleanedUploadedFiles);
  }

  String _getFileType(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case FileTypes.pdf:
        return 'pdf';
      case FileTypes.doc:
      case FileTypes.docx:
        return 'document';
      case FileTypes.xls:
      case FileTypes.xlsx:
        return 'spreadsheet';
      case FileTypes.jpg:
      case FileTypes.jpeg:
      case FileTypes.png:
      case FileTypes.gif:
        return 'image';
      default:
        return FileTypes.any;
    }
  }

  String getCurrentQuestionNumber() {
    return '${questionSequence.length}/${getTotalQuestions()}';
  }

  int getTotalQuestions() {
    int total = 1; // Start with 1 for the first question
    int currentIndex = 0;

    while (currentIndex < widget.formJson.length) {
      final currentField = widget.formJson[currentIndex];

      // Check if current question has branching
      if (currentField['branching'] != null) {
        // Get the selected value for this question
        final control = controller.form.control(currentField['name']);
        if (control.value != null) {
          // Follow the branch path
          final targetQuestionName = currentField['branching'][control.value];
          final targetIndex = widget.formJson
              .indexWhere((question) => question['name'] == targetQuestionName);
          if (targetIndex != -1) {
            currentIndex = targetIndex;
            total++;
            continue;
          }
        }
      }
      // Move to next sequential question if no branching
      currentIndex++;
      if (currentIndex < widget.formJson.length) total++;
    }
    return total;
  }

  void updateQuestionSequence(int index) {
    _calculateProgress();
  }

  void moveToNextQuestion(BuildContext context) {
    // Use validateAndProceed instead of manual validation
    if (controller.validateAndProceed(context)) {
      setState(() {
        final currentField = widget.formJson[controller.currentQuestionIndex];
        final control = controller.form.control(currentField['name']);
        visitedQuestions.add(currentField['name']);

        if (currentField['branching'] != null &&
            currentField['branching'][control.value] != null) {
          final targetQuestionName = currentField['branching'][control.value];

          if (visitedQuestions.contains(targetQuestionName)) {
            moveToNextValidQuestion();
          } else {
            final targetIndex = widget.formJson.indexWhere(
                (question) => question['name'] == targetQuestionName);

            if (targetIndex != -1) {
              widget.formJson[targetIndex]['prevQuestion'] = currentField['name'];
              moveToIndex(targetIndex);
            } else {
              moveToNextValidQuestion();
            }
          }
        } else {
          moveToNextValidQuestion();
        }
      });
    }
  }

  void moveToNextValidQuestion() {
    // The controller handles the actual navigation
    print("moveToNextValidQuestion called");
  }

  void moveToPreviousValidQuestion() {
    print("BACK BUTTON PRESSED at index: ${controller.currentQuestionIndex}");
    
    // Can't go back from the first question
    if (controller.currentQuestionIndex <= 0) {
      print("Already at first question");
      return;
    }
    
    // Simply go back one question directly - simplest possible approach
    int newIndex = controller.currentQuestionIndex - 1;
    print("Moving back to question index: $newIndex");
    
    // Update controller index
    controller.currentQuestionIndex = newIndex;
    
    // If using PageView, update it directly
    if (_pageController != null && _pageController.hasClients) {
      _pageController.jumpToPage(newIndex);
    }
    
    // Force UI update and recalculate progress
    setState(() {
      _calculateProgress();
    });
    
    print("Back navigation complete, now at index: ${controller.currentQuestionIndex}");
  }

  // Helper method to find the next visible question using the same logic as the controller
  int findNextVisibleQuestionIndex() {
    // Start checking from the next question
    int startIndex = controller.currentQuestionIndex + 1;
    
    // Check each question in order
    for (int i = startIndex; i < widget.formJson.length; i++) {
      final question = widget.formJson[i];
      
      // No conditions means the question is always visible
      if (question['showWhen'] == null) {
        return i;
      }
      
      // Check the conditions
      final Map<String, dynamic> conditions = question['showWhen'];
      bool shouldShow = false;
      
      // Check each field condition
      for (final entry in conditions.entries) {
        final dependentField = entry.key;
        final expectedValues = entry.value;
        
        // Skip if field doesn't exist in the form
        if (!controller.form.contains(dependentField)) {
          continue;
        }
        
        final currentValue = controller.form.control(dependentField).value;
        
        // Check if value matches
        if (expectedValues is List) {
          if (expectedValues.contains(currentValue)) {
            shouldShow = true;
            break; // Exit early if any condition matches
          }
        } else if (currentValue == expectedValues) {
          shouldShow = true;
          break; // Exit early if any condition matches
        }
      }
      
      if (shouldShow) {
        return i;
      }
    }
    
    return -1; // No visible questions found
  }

  void moveToIndex(int index) {
    if (index >= 0 && index < widget.formJson.length) {
      final nextField = widget.formJson[index];

      // Check if this field should be shown based on showWhen
      if (nextField['showWhen'] != null) {
        bool shouldShow = true;
        final conditions = nextField['showWhen'] as Map<String, dynamic>;

        conditions.forEach((dependentField, expectedValue) {
          final dependentControl = controller.form.control(dependentField);
          final currentValue = dependentControl.value;

          if (expectedValue is List) {
            shouldShow = shouldShow && expectedValue.contains(currentValue);
          } else {
            shouldShow = shouldShow && currentValue == expectedValue;
          }
        });

        if (!shouldShow) {
          // Skip this question and find the next valid one
          moveToNextValidQuestion();
          return;
        }
      }

      // This question should be shown
      updateQuestionSequence(index);
      controller.currentQuestionIndex = index;
    }
  }

  // Helper method to check if current question is effectively the last visible one
  bool isCurrentQuestionEffectivelyLast() {
    int nextVisibleIndex = findNextVisibleQuestionIndex();
    return nextVisibleIndex == -1;
  }

  void popuperror(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${message} ${StringConstants.isRequired}',
          style: widget.fontFamily,
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Reset the form navigation to ensure we start at the beginning
  void resetNavigation() {
    controller.currentQuestionIndex = 0;
    updateQuestionSequence(0);
  }

  // Update how the back button works to use the hardcoded navigation
  Widget _buildBackButton() {
    return TextButton.icon(
      icon: Icon(Icons.arrow_back, color: widget.primaryColor),
      label: Text(
        'Back',
        style: TextStyle(color: widget.primaryColor),
      ),
      onPressed: controller.currentQuestionIndex > 0
          ? () {
              print("Back button tapped!");
              moveToPreviousValidQuestion();
            }
          : null,
    );
  }

  // Completely rebuild the progress indicator widget
  Widget _buildProgressIndicator({Key? key}) {
    // Calculate values directly here to ensure they're current
    double progress = totalVisibleQuestions > 0 
        ? (currentVisibleQuestionIndex + 1) / totalVisibleQuestions
        : 0;
    
    print("RENDERING progress bar: ${currentVisibleQuestionIndex + 1}/$totalVisibleQuestions");
    
    // Use RepaintBoundary to force redraw
    return RepaintBoundary(
      key: key,
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 10,
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              color: widget.primaryColor,
              backgroundColor: Colors.grey[300],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              'Question ${currentVisibleQuestionIndex + 1} of $totalVisibleQuestions',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
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
    Key? key,
  }) : super(key: key);

  @override
  State<_DropdownSearch> createState() => _DropdownSearchState();
}

class _DropdownSearchState extends State<_DropdownSearch> {
  late List<dynamic> filteredOptions;
  final TextEditingController searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    filteredOptions = List.from(widget.options);
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  void _filterOptions(String query) {
    setState(() {
      filteredOptions = widget.options
          .where((option) =>
              option.toString().toLowerCase().contains(query.toLowerCase()))
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
                  hintText: StringConstants.search,
                  prefixIcon: const Icon(Icons.search),
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

// Reusable FileUploadWidget
class FileUploadWidget extends StatefulWidget {
  final String fieldName;
  final String fieldLabel;
  final Function(List<Map<String, dynamic>> files) onFilesUploaded;
  final Color primaryColor;
  final TextStyle fontFamily;
  final Color buttonTextColor;
  final List<Map<String, dynamic>> uploadedFiles;
  final Function(Map<String, dynamic>) onRemoveUploadedFile;
  final bool isRequired;

  const FileUploadWidget({
    Key? key,
    required this.fieldName,
    required this.fieldLabel,
    required this.onFilesUploaded,
    required this.primaryColor,
    required this.fontFamily,
    required this.buttonTextColor,
    required this.uploadedFiles,
    required this.onRemoveUploadedFile,
    this.isRequired = false,
  }) : super(key: key);

  @override
  _FileUploadWidgetState createState() => _FileUploadWidgetState();
}

class _FileUploadWidgetState extends State<FileUploadWidget> {
  Future<void> _pickAndUploadFile(BuildContext context) async {
    BuildContext? loadingContext;

    void showLoadingDialog(BuildContext context) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          loadingContext = context;
          return Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(widget.primaryColor),
                  ),
                  const SizedBox(height: 16),
                  Text(StringConstants.processingFilePleaseWait,
                      style: widget.fontFamily),
                ],
              ),
            ),
          );
        },
      );
    }

    void hideLoadingDialog() {
      if (loadingContext != null) {
        try {
          Navigator.of(loadingContext!).pop();
        } catch (e) {
          if (kDebugMode) {
            print('Error closing dialog: $e');
          }
        } finally {
          loadingContext = null;
        }
      }
    }

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(
                  Icons.description_outlined,
                  size: _DynamicFormState._iconSize,
                ),
                title:
                    Text(StringConstants.chooseFile, style: widget.fontFamily),
                onTap: () async {
                  Navigator.pop(context);
                  FilePickerResult? result;
                  try {
                    showLoadingDialog(context);
                    result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                  
                      allowedExtensions: [
                    
                         FileTypes.pdf,
                         FileTypes.jpg,
                         FileTypes.gif,
                         FileTypes.jpeg,
                         FileTypes.png,
                         FileTypes.xlsx,
                         FileTypes.xls,
                         FileTypes.text

                      ],
                      allowMultiple: false,
                      withData: true,
                      allowCompression: true,
                    );

                    if (result != null && result.files.isNotEmpty) {
                      if ((result.files.first.bytes?.length ?? 0) >
                          _DynamicFormState._maxFileSize) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                StringConstants.fileSizeMustBeLessThan5MB,
                                style: widget.fontFamily),
                            duration: const Duration(seconds: 2),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      final newFile = {
                        'question_name': widget.fieldName,
                        'question_label': widget.fieldLabel,
                        'file': result.files.first.bytes,
                        'fileName': result.files.first.name,
                        'fileType': _getFileType(result.files.first.name),
                        'mimeType': result.files.first.extension != null
                            ? 'application/${result.files.first.extension}'
                            : 'application/octet-stream',
                      };

                      widget
                          .onFilesUploaded([...widget.uploadedFiles, newFile]);
                    }
                  } catch (e) {
                    if (kDebugMode) {
                      print('Error picking file: $e');
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            StringConstants.errorSelectingFilePleaseTryAgain,
                            style: widget.fontFamily),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  } finally {
                    hideLoadingDialog();
                    result = null;
                  }
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.collections_outlined,
                  size: _DynamicFormState._iconSize,
                ),
                title: Text(StringConstants.chooseFromGallery,
                    style: widget.fontFamily),
                onTap: () async {
                  Navigator.pop(context);
                  XFile? image;
                  try {
                    showLoadingDialog(context);
                    final ImagePicker picker = ImagePicker();
                    image = await picker.pickImage(
                      source: ImageSource.gallery,
                      imageQuality: 80,
                    );

                    if (image != null) {
                      final bytes = await image.readAsBytes();
                      if (bytes.length > _DynamicFormState._maxFileSize) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                StringConstants.fileSizeMustBeLessThan5MB,
                                style: widget.fontFamily),
                            duration: const Duration(seconds: 2),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      final newFile = {
                        'question_name': widget.fieldName,
                        'question_label': widget.fieldLabel,
                        'file': bytes,
                        'fileName': image.name,
                        'fileType': 'image',
                        'mimeType': 'image/${image.name.split('.').last}',
                      };
                      widget
                          .onFilesUploaded([...widget.uploadedFiles, newFile]);
                    }
                  } catch (e) {
                    if (kDebugMode) {
                      print('Error picking image from gallery: $e');
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            StringConstants.errorSelectingImagePleaseTryAgain,
                            style: widget.fontFamily),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  } finally {
                    hideLoadingDialog();
                    image = null;
                  }
                },
              ),
              if (!kIsWeb)
                ListTile(
                  leading: const Icon(
                    Icons.photo_camera_outlined,
                    size: _DynamicFormState._iconSize,
                  ),
                  title:
                      Text(StringConstants.takePhoto, style: widget.fontFamily),
                  onTap: () async {
                    Navigator.pop(context);
                    XFile? photo;
                    try {
                      showLoadingDialog(context);
                      final ImagePicker picker = ImagePicker();
                      photo = await picker.pickImage(
                        source: ImageSource.camera,
                        imageQuality: 80,
                      );

                      if (photo != null) {
                        final bytes = await photo.readAsBytes();
                        if (bytes.length > _DynamicFormState._maxFileSize) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  StringConstants.fileSizeMustBeLessThan5MB,
                                  style: widget.fontFamily),
                              duration: const Duration(seconds: 2),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        final newFile = {
                          'question_name': widget.fieldName,
                          'question_label': widget.fieldLabel,
                          'file': bytes,
                          'fileName': photo.name,
                          'fileType': 'image',
                          'mimeType': 'image/${photo.name.split('.').last}',
                        };
                        widget.onFilesUploaded(
                            [...widget.uploadedFiles, newFile]);
                      }
                    } catch (e) {
                      if (kDebugMode) {
                        print('Error taking photo: $e');
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              StringConstants.errorTakingPhotoPleaseTryAgain,
                              style: widget.fontFamily),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    } finally {
                      hideLoadingDialog();
                      photo = null;
                    }
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  String _getFileType(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case FileTypes.pdf:
        return 'pdf';
      case FileTypes.doc:
      case FileTypes.docx:
        return 'document';
      case FileTypes.xls:
      case FileTypes.xlsx:
        return 'spreadsheet';
      case FileTypes.jpg:
      case FileTypes.jpeg:
      case FileTypes.png:
      case FileTypes.gif:
        return 'image';
      default:
        return FileTypes.any;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 60,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.primaryColor,
              foregroundColor: widget.buttonTextColor,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => _pickAndUploadFile(context),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.upload_file_rounded,
                  color: widget.buttonTextColor,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Text(StringConstants.uploadFiles,
                    style: widget.fontFamily.copyWith(
                      color: widget.buttonTextColor,
                      fontSize: 18,
                    )),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (widget.uploadedFiles.isNotEmpty) ...[
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.uploadedFiles.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final file = widget.uploadedFiles[index];
              return Card(
                margin: EdgeInsets.zero,
                elevation: 1,
                child: ListTile(
                  leading: Icon(_getFileIcon(file['fileType'])),
                  title: Text(
                    file['fileName'],
                    style: widget.fontFamily,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => widget.onRemoveUploadedFile(file),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

IconData _getFileIcon(String fileType) {
  switch (fileType) {
    case FileTypes.pdf:
      return Icons.picture_as_pdf;
    case FileTypes.doc:
      return Icons.description;
    case FileTypes.xls:
      return Icons.table_chart;
    case FileTypes.image:
      return Icons.image;
    default:
      return Icons.insert_drive_file;
  }
}
