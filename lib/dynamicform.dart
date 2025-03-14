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

  @override
  void initState() {
    super.initState();
    controller = DynamicFormController(
      formJson: widget.formJson,
      onSubmit: widget.onSubmit,
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                const SizedBox(height: 80),
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
              '${StringConstants.questionNumber} ${questionSequence.length}',
              style: widget.fontFamily.copyWith(fontWeight: FontWeight.bold),
            ),
            SizedBox(
              width: 100,
              height: 6,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (questionSequence.length) / widget.formJson.length,
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
      // Get all dependent field names from showWhen conditions
      final dependentFields =
          (field['showWhen'] as Map<String, dynamic>).keys.toList();

      // Create a ReactiveValueListenableBuilder for each dependent field
      return ReactiveFormConsumer(
        builder: (context, form, child) {
          bool shouldShow = true;
          final conditions = field['showWhen'] as Map<String, dynamic>;

          conditions.forEach((dependentField, expectedValue) {
            final dependentControl = form.control(dependentField);
            final currentValue = dependentControl.value;

            if (kDebugMode) {
              print(
                  'Field: ${field['name']} checking condition on $dependentField');
              print('Expected: $expectedValue, Actual: $currentValue');
            }

            if (expectedValue is List) {
              final containsValue = expectedValue.contains(currentValue);
              shouldShow = shouldShow && containsValue;
              if (kDebugMode) {
                print('List comparison result: $containsValue');
              }
            } else {
              final equals = currentValue == expectedValue;
              shouldShow = shouldShow && equals;
              if (kDebugMode) {
                print('Direct comparison result: $equals');
              }
            }
          });

          if (kDebugMode) {
            print('Field: ${field['name']} shouldShow: $shouldShow');
          }

          if (!shouldShow) {
            return const SizedBox.shrink();
          }

          // If conditions are met, build the actual field
          final control = controller.form.control(field['name']);
          return _buildActualField(field, control);
        },
      );
    }

    // If no showWhen conditions, build the field directly
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

  void updateQuestionSequence(int newIndex) {
    if (newIndex > controller.currentQuestionIndex) {
      // Moving forward
      questionSequence.add(newIndex);
    } else {
      // Moving backward
      questionSequence.removeLast();
    }
  }

  void moveToNextQuestion(BuildContext context) {
    final currentField = widget.formJson[controller.currentQuestionIndex];
    bool isValid = true;
    bool hasRequiredFiles = true;

    // Validation checks
    if (currentField['required'] == true ||
        (currentField['requiredWhen'] != null &&
            isRequiredBasedOnCondition(currentField))) {
      final control = controller.form.control(currentField['name']);

      if (currentField['type'] == 'file') {
        hasRequiredFiles = control.value != null &&
            control.value.toString().isNotEmpty &&
            control.value != 'null';

        if (!hasRequiredFiles) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${currentField['label']} ${StringConstants.isRequired}',
                style: widget.fontFamily,
              ),
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }
      } else if (currentField['type'] == 'number') {
        if (currentField['min'] != null && currentField['max'] != null ||
            currentField['min'] != '' && currentField['max'] == '') {
          if (control.value != null) {
            isValid = control.value >= currentField['min'] &&
                control.value <= currentField['max'];
            if (!isValid) {
              control.value = null;
              popuperror(
                  '${StringConstants.pleaseEnterNumberBetween} ${currentField['min']} ${StringConstants.and} ${currentField['max']}');
              return;
            }
          }
          else if (control.value == null) {
            isValid = false;
             control.value = null;
            popuperror(
                '${StringConstants.pleaseEnterNumberBetween} ${currentField['min']} ${StringConstants.and} ${currentField['max']}');
            return;
          }
        
        } else {
          isValid = control.value != null &&
              control.value.toString().isNotEmpty &&
              control.value != 'null';
        }
      } else {
        isValid = control.value != null &&
            control.value.toString().isNotEmpty &&

            /// main part
            control.value != 'null';

        if (!isValid) {
          popuperror('${currentField['label']} ${StringConstants.isRequired}');

          return;
        }
      }
    }

    if (isValid && hasRequiredFiles) {
      setState(() {
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
              widget.formJson[targetIndex]['prevQuestion'] =
                  currentField['name'];
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
    // Start from the next question
    int nextIndex = controller.currentQuestionIndex + 1;

    // Loop until we find a valid question or reach the end
    while (nextIndex < widget.formJson.length) {
      final nextField = widget.formJson[nextIndex];

      // Skip questions that shouldn't be shown based on showWhen conditions
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
          // This question should be skipped, try the next one
          nextIndex++;
          continue;
        }
      }

      // Skip questions we've already visited
      if (visitedQuestions.contains(nextField['name'])) {
        nextIndex++;
        continue;
      }

      // Found a valid question, move to it
      break;
    }

    // If we reached the end, show the last question
    if (nextIndex >= widget.formJson.length) {
      controller.currentQuestionIndex = widget.formJson.length - 1;
    } else {
      updateQuestionSequence(nextIndex);
      controller.currentQuestionIndex = nextIndex;
    }
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

  bool isRequiredBasedOnCondition(Map<String, dynamic> field) {
    if (field['requiredWhen'] == null) return false;

    final conditions = field['requiredWhen'] as Map<String, dynamic>;
    bool isRequired = true;

    conditions.forEach((fieldName, expectedValue) {
      final dependentControl = controller.form.control(fieldName);
      if (expectedValue is List) {
        isRequired =
            isRequired && expectedValue.contains(dependentControl.value);
      } else {
        isRequired = isRequired && dependentControl.value == expectedValue;
      }
    });

    return isRequired;
  }

  void moveToPreviousValidQuestion() {
    // Start from the previous question
    int prevIndex = controller.currentQuestionIndex - 1;

    // Loop until we find a valid previous question or reach the beginning
    while (prevIndex >= 0) {
      final prevField = widget.formJson[prevIndex];

      // Skip questions that shouldn't be shown based on showWhen conditions
      if (prevField['showWhen'] != null) {
        bool shouldShow = true;
        final conditions = prevField['showWhen'] as Map<String, dynamic>;

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
          // This question should be skipped, try the previous one
          prevIndex--;
          continue;
        }
      }

      // Found a valid previous question, move to it
      break;
    }

    // If we reached the beginning, show the first question
    if (prevIndex < 0) {
      controller.currentQuestionIndex = 0;
    } else {
      // Move to the valid previous question
      final currentField = widget.formJson[controller.currentQuestionIndex];
      visitedQuestions.remove(currentField['name']);
      updateQuestionSequence(prevIndex);
      controller.currentQuestionIndex = prevIndex;
    }
  }

  // Helper method to check if current question is effectively the last visible one
  bool isCurrentQuestionEffectivelyLast() {
    int nextVisibleIndex = findNextVisibleQuestionIndex();
    return nextVisibleIndex == -1;
  }

  // Find the index of the next question that should be visible
  int findNextVisibleQuestionIndex() {
    // Start checking from the next question
    int index = controller.currentQuestionIndex + 1;

    while (index < widget.formJson.length) {
      final question = widget.formJson[index];

      // If the question has showWhen conditions, check if they're satisfied
      if (question['showWhen'] != null) {
        bool shouldShow = true;
        final conditions = question['showWhen'] as Map<String, dynamic>;

        conditions.forEach((dependentField, expectedValue) {
          final dependentControl = controller.form.control(dependentField);
          final currentValue = dependentControl.value;

          if (expectedValue is List) {
            shouldShow = shouldShow && expectedValue.contains(currentValue);
          } else {
            shouldShow = shouldShow && currentValue == expectedValue;
          }
        });

        // If this question should be shown, return its index
        if (shouldShow) {
          return index;
        }
      } else {
        // If the question has no showWhen conditions, it should always be shown
        return index;
      }

      // Move to the next question
      index++;
    }

    // If no more visible questions found, return -1
    return -1;
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
                      type: FileType.image, // Allow all file types
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
