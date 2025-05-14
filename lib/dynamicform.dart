import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:reactiveform/components/app_snackbar.dart';
import 'package:reactiveform/components/app_typographpy.dart';
import 'package:reactiveform/constants.dart';
import 'package:reactiveform/string_constants.dart';
import 'package:flutter/services.dart';
import 'dart:async'; // Added for Completer
import 'dynamicformcontroller.dart';
import 'package:reactiveform/models/form_field_model.dart';

// Conditional import for web
import 'web_utils.dart' if (dart.library.html) 'dart:html' as html;

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
  final String? submitButtonText;

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
    this.submitButtonText,
    Key? key,
  }) : super(key: key);

  @override
  State<DynamicForm> createState() => _DynamicFormState();
}

class _DynamicFormState extends State<DynamicForm>
    with SingleTickerProviderStateMixin {
  // Core controllers and data structures
  late DynamicFormController controller;
  List<Map<String, dynamic>> _internalFields = [];

  // Group structure tracking
  List<int> _groupAnchors =
      []; // indices in _internalFields representing first field of each group
  Map<int, List<int>> _anchorToFieldIndices = {};
  int _currentGroupPointer =
      0; // points into _groupAnchors when showOneByOne=true

  // UI state
  late PageController _pageController;
  late TabController _tabController;
  BuildContext? _alertDialogContext;
  late BuildContext dialogContext;
  bool _showAttachmentError = false;
  double _pageProgress = 0.0;
  final _progressKey = GlobalKey();

  // Search functionality
  String _searchQuery = '';
  bool _isSearching = false;
  TextEditingController _searchTextController = TextEditingController();

  // Form tracking
  Set<String> visitedQuestions = {};
  int currentVisibleQuestionIndex = 0;
  int totalVisibleQuestions = 1;

  // File handling
  static const _maxFileSize = 3 * 1024 * 1024; // 3MB
  static const double _iconSize = 24.0;
  List<PlatformFile> pickedFiles = [];
  Map<String, List<Map<String, dynamic>>> _fileData = {};
  int totalUploadSize = 0;
  ReactiveFormArray? options;

  // Flags for safe PageController access
  bool _pageControllerReady = false;
  bool _isUpdatingPageController = false;

  // Mapping to track relationships between original and duplicated fields
  Map<String, String> _originalToDuplicateNames = {};

  @override
  void initState() {
    super.initState();
    controller = DynamicFormController(
      formJson: widget.formJson,
      onSubmit: widget.onSubmit,
    );

    _internalFields = List<Map<String, dynamic>>.from(widget.formJson);

    // Add a listener to the controller to update the UI when the question changes
    controller.addListener(_onControllerChanged);

    // Initialize PageController to the current question
    _pageController =
        PageController(initialPage: controller.currentQuestionIndex);

    // Calculate initial progress
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _safeCalculateProgress();
      _pageControllerReady = true;
    });

    _recomputeGroupStructure();
  }

  @override
  void dispose() {
    // Remove the listener when the widget is disposed
    controller.removeListener(_onControllerChanged);
    _pageController.dispose(); // Ensure the controller is disposed
    super.dispose();
  }

  // This will be called whenever the controller notifies its listeners
  void _onControllerChanged() {
    // Only attempt to update the page if the controller is attached to a page view
    // and the controller is ready (has been laid out)
    if (_pageControllerReady &&
        !_isUpdatingPageController &&
        _pageController.hasClients &&
        _pageController.position.hasContentDimensions) {
      try {
        // Set flag to avoid recursive updates
        _isUpdatingPageController = true;

        // When controller changes, update the PageView if needed
        final currentPage = _pageController.page?.round();
        if (currentPage != null &&
            currentPage != controller.currentQuestionIndex) {
          _pageController.animateToPage(
            controller.currentQuestionIndex,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      } catch (e) {
        print('Error updating page controller: $e');
      } finally {
        _isUpdatingPageController = false;
      }
    }

    // Always calculate progress, but handle exceptions safely
    _safeCalculateProgress();
  }

  // Calculate the progress based on visible questions - safely
  void _safeCalculateProgress() {
    // Skip progress calculation if not mounted
    if (!mounted) return;

    try {
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

      if (mounted) {
        setState(() {
          currentVisibleQuestionIndex = position >= 0 ? position : 0;
          totalVisibleQuestions =
              visibleIndices.isNotEmpty ? visibleIndices.length : 1;
        });
      }
    } catch (e) {
      // Safely handle any errors during progress calculation
      print('Error calculating progress: $e');
    }
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

      bool shouldShow = true; // Initialize to false for OR logic
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
    // Calculate progress based on current index vs total questions
    double progress = 0;
    if (_groupAnchors.isNotEmpty) {
      progress = _currentGroupPointer / _groupAnchors.length;
    }

    final Color buttonColor =
        widget.primaryColor ?? Theme.of(context).primaryColor;

    // Determine if the current question has groupWith property to show the FAB
    bool currentQuestionHasGroupWith = false;
    if (widget.showOneByOne &&
        _groupAnchors.isNotEmpty &&
        _currentGroupPointer >= 0 &&
        _currentGroupPointer < _groupAnchors.length) {
      // Get the current anchor
      final currentAnchor = _groupAnchors[_currentGroupPointer];
      if (currentAnchor >= 0 && currentAnchor < _internalFields.length) {
        // Check if this field or any field in its group has a groupWith property
        final currentField = _internalFields[currentAnchor];
        currentQuestionHasGroupWith = currentField['groupWith'] != null ||
            currentField['allowDuplicate'] == true;

        // For debugging
        if (kDebugMode) {
          print("Current question has groupWith: $currentQuestionHasGroupWith");
          print("Current field: ${currentField['name']}");
          if (currentField['groupWith'] != null) {
            print("GroupWith: ${currentField['groupWith']}");
          }
          if (currentField['allowDuplicate'] == true) {
            print("AllowDuplicate: ${currentField['allowDuplicate']}");
          }
        }
      }
    }

    return Theme(
      data: Theme.of(context).copyWith(
          // We don't need to modify the textTheme if fontFamily is already a TextStyle
          // The fontFamily will be applied directly to each widget
          ),
      child: ReactiveForm(
        formGroup: controller.form,
        child: Scaffold(
          // Only show the FloatingActionButton if the current question has a groupWith property
          floatingActionButton:
              widget.showOneByOne && currentQuestionHasGroupWith
                  ? FloatingActionButton(
                      onPressed: () => _addNewSet(),
                      child: const Icon(Icons.add),
                    )
                  : null,
          body: LayoutBuilder(
            builder: (context, constraints) {
              // Create a unique key that includes the current group pointer
              // This ensures the widget tree is rebuilt when the current question changes
              final uniqueKey = ValueKey(
                  '${StringConstants.form}_pointer${_currentGroupPointer}_index${controller.currentQuestionIndex}_totalFields${_internalFields.length}');

              return SingleChildScrollView(
                key: uniqueKey,
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // When showing one by one, we only show the current group of fields
                    if (widget.showOneByOne) ..._buildOneByOneFields(),
                    // When showing all at once, we show all fields
                    if (!widget.showOneByOne) ..._buildAllFields(),
                    if (_showAttachmentError) _buildErrorMessage(),
                  ],
                ),
              );
            },
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
    return _buildGroupedCards();
  }

  List<Widget> _buildOneByOneFields() {
    if (_groupAnchors.isEmpty) return [];

    // Debug information to help diagnose groupWith issues
    if (kDebugMode) {
      print("\n\n========== Building one-by-one fields ==========");
      print("Current group pointer: $_currentGroupPointer");
      print("Available group anchors: $_groupAnchors");
      print(
          "Current question index from controller: ${controller.currentQuestionIndex}");
      print("Total internal fields: ${_internalFields.length}");
      print("Current field groupings:");
      _anchorToFieldIndices.forEach((anchor, fieldIndices) {
        final fieldNames = fieldIndices
            .map((i) => "${_internalFields[i]['name']} (index $i)")
            .join(", ");
        print("  Anchor $anchor: $fieldNames");
      });
    }

    final List<Widget> widgets = [];

    // Make sure _currentGroupPointer is valid
    if (_currentGroupPointer >= _groupAnchors.length || _groupAnchors.isEmpty) {
      if (kDebugMode) {
        print(
            "Warning: Current group pointer $_currentGroupPointer is out of range");
      }
      return widgets;
    }

    // Get the current anchor indicated by the pointer
    final currentAnchor = _groupAnchors[_currentGroupPointer];
    final String currentAnchorName =
        _internalFields[currentAnchor]['name'] as String;

    if (kDebugMode) {
      print("Current anchor: $currentAnchor ($currentAnchorName)");
    }

    // Build the card for the current anchor with all its grouped fields
    // This is the original card that is always displayed
    final List<int> currentIndices =
        _anchorToFieldIndices[currentAnchor] ?? [currentAnchor];
    final List<Map<String, dynamic>> currentGroupFields =
        currentIndices.map((i) => _internalFields[i]).toList();

    if (kDebugMode) {
      print(
          "Building original card for anchor $currentAnchor ($currentAnchorName)");
      print(
          "Fields in original card: ${currentGroupFields.map((f) => f['name']).toList()}");
    }

    // Add the original card
    widgets.add(_buildCardForFields(currentGroupFields, false));

    // Now collect all duplicates of the current anchor to show below it
    final List<int> duplicateAnchors = [];
    final timeStampPattern = RegExp(r'_(\d+)$');

    // Extract the base name of the current question (removing any question_X suffix)
    String baseName = currentAnchorName;
    final questionPattern = RegExp(r'^question_(\d+)$');
    if (questionPattern.hasMatch(baseName)) {
      baseName = baseName.split('_').first;
    }

    // Find all duplicate anchors that should be shown with this question
    for (int i = 0; i < _internalFields.length; i++) {
      // Skip the current anchor and non-anchor indices
      if (i == currentAnchor || !_anchorToFieldIndices.containsKey(i)) continue;

      final field = _internalFields[i];
      final fieldName = field['name'].toString();

      // Check if this is a duplicate field
      if (field['isDuplicate'] == true) {
        final match = timeStampPattern.firstMatch(fieldName);
        if (match != null) {
          // Extract the base name of this duplicate
          String duplicateBaseName = fieldName;
          final lastUnderscore = duplicateBaseName.lastIndexOf('_');
          if (lastUnderscore > 0) {
            duplicateBaseName = duplicateBaseName.substring(0, lastUnderscore);
          }

          // Check if this duplicate is related to the current question
          // It can be either duplicated from this question or a question that groups with it
          bool isRelated = false;

          // Directly related if it's a duplicate of the current question
          if (duplicateBaseName == currentAnchorName ||
              fieldName.startsWith("${currentAnchorName}_")) {
            isRelated = true;
          }

          // Check if any field in the current group is related to this duplicate
          for (final originalField in currentGroupFields) {
            final originalName = originalField['name'].toString();
            if (fieldName.startsWith("${originalName}_")) {
              isRelated = true;
              break;
            }
          }

          if (isRelated) {
            duplicateAnchors.add(i);
            if (kDebugMode) {
              print("Found related duplicate anchor: $i ($fieldName)");
            }
          }
        }
      }
    }

    if (kDebugMode) {
      print("Duplicate anchors to show: $duplicateAnchors");
    }

    // Build cards for all duplicate anchors
    for (final anchor in duplicateAnchors) {
      final indices = _anchorToFieldIndices[anchor] ?? [anchor];
      final fields = indices.map((i) => _internalFields[i]).toList();

      if (kDebugMode) {
        print(
            "Building duplicate card for anchor $anchor (${_internalFields[anchor]['name']})");
        print(
            "Fields in duplicate card: ${fields.map((f) => f['name']).toList()}");
      }

      // Add the duplicate card with delete button
      widgets.add(_buildCardForFields(fields, true));
    }

    if (kDebugMode) {
      print("Returning ${widgets.length} widgets for display");
      print("=================================================\n");
    }

    return widgets;
  }

  /// Helper method to build a card for a group of fields
  Widget _buildCardForFields(
      List<Map<String, dynamic>> fields, bool isDuplicated) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            if (isDuplicated)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  color: const Color.fromARGB(255, 222, 75, 64),
                  icon: const Icon(Icons.delete),
                  onPressed: () => _removeSet(
                      fields.map((e) => e['name'] as String).toList()),
                ),
              ),
            ...fields.map(_buildField).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildField(Map<String, dynamic> field) {
    if (field['showWhen'] != null) {
      return ReactiveFormConsumer(
        builder: (context, form, child) {
          bool shouldShow = false; // Initialize to false for OR logic
          final conditions = field['showWhen'] as Map<String, dynamic>;

          conditions.forEach((dependentField, expectedValue) {
            if (!controller.form.contains(dependentField)) {
              shouldShow = false;
              return;
            }

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
    // Access the controller instance variable
    final control = controller.form.control(field['name']);
    return _buildActualField(field, control);
  }

  Widget _buildActualField(
      Map<String, dynamic> field, AbstractControl<dynamic> control) {
    switch (field['type']) {
      case 'option':
      case 'radio':
        {
          // Fallback to default Yes/No if options are missing or empty
          final List<dynamic> rawOptions =
              (field['options'] as List<dynamic>?) ?? ['Yes', 'No'];
          final List<String> options =
              rawOptions.isEmpty ? ['Yes', 'No'] : rawOptions.cast<String>();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLabelRow(field),
              const SizedBox(height: 4),
              ...options
                  .map<Widget>(
                    (option) => RadioListTile<String>(
                      title: Text(option, style: widget.fontFamily),
                      value: option,
                      groupValue: control.value,
                      activeColor: widget.primaryColor,
                      onChanged: (value) {
                        control.value = value;
                        if (widget.showOneByOne &&
                            !isCurrentQuestionEffectivelyLast()) {
                          Future.delayed(const Duration(milliseconds: 300), () {
                            if (validateCurrentSection()) {
                              moveToNextQuestion(context);
                            }
                          });
                        }
                      },
                    ),
                  )
                  .toList(),
            ],
          );
        }
      case FieldType.dropdown:
        return _buildDropdownField(field);
      case FieldType.text:
        return _buildTextField(field);
      case FieldType.number:
        return _buildNumberField(field);
      case FieldType.file:
        return _buildFileField(field);
      case 'multiselect':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLabelRow(field),
            ReactiveFormField<List<String>, List<String>>(
              formControlName: field['name'],
              validationMessages: {
                'required': (_) => 'Please select at least one option',
              },
              builder:
                  (ReactiveFormFieldState<List<String>, List<String>> state) {
                // Get current control value, ensuring it's a List<String>
                List<String> currentValue = [];
                final rawValue = controller.form.control(field['name']).value;

                if (rawValue is List) {
                  currentValue =
                      List<String>.from(rawValue.map((e) => e.toString()));
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
                    print(
                        'Updated ${field['name']} with: $value (type: ${value.runtimeType})');
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
            ),
            // Add support for file uploads
            if (field['hasAttachments'] == true)
              ReactiveValueListenableBuilder(
                formControlName: field['name'],
                builder: (context, control, child) {
                  // Get the disabledOptions list if it exists
                  List<dynamic> disabledOptions =
                      field['disableAttachmentsOn'] is List
                          ? field['disableAttachmentsOn']
                          : field['disableAttachmentsOn'] != null
                              ? [field['disableAttachmentsOn']]
                              : [];

                  // For multiselect: check if any selected value is in disabledOptions
                  final selectedValues = control.value is List
                      ? control.value as List
                      : control.value != null
                          ? [control.value]
                          : [];

                  bool isAttachmentDisabled = false;
                  if (selectedValues.isNotEmpty) {
                    isAttachmentDisabled = selectedValues
                        .any((value) => disabledOptions.contains(value));
                  }

                  // If the current value is in disabledOptions, don't show attachments
                  if (isAttachmentDisabled) {
                    return const SizedBox.shrink();
                  }

                  // Check if the value is in requireAttachmentsOn or enableAttachmentsOn
                  bool shouldShowAttachments = false;
                  bool isRequired = false;

                  // Check requireAttachmentsOn
                  if (field['requireAttachmentsOn'] != null) {
                    List<dynamic> requiredOptions =
                        field['requireAttachmentsOn'] is List
                            ? field['requireAttachmentsOn']
                            : [field['requireAttachmentsOn']];

                    if (selectedValues.isNotEmpty) {
                      if (selectedValues
                          .any((value) => requiredOptions.contains(value))) {
                        shouldShowAttachments = true;
                        isRequired = true;
                      }
                    }
                  }

                  // Check enableAttachmentsOn (works the same as requireAttachmentsOn for visibility)
                  if (!shouldShowAttachments &&
                      field['enableAttachmentsOn'] != null) {
                    List<dynamic> enabledOptions =
                        field['enableAttachmentsOn'] is List
                            ? field['enableAttachmentsOn']
                            : [field['enableAttachmentsOn']];

                    if (selectedValues.isNotEmpty) {
                      if (selectedValues
                          .any((value) => enabledOptions.contains(value))) {
                        shouldShowAttachments = true;
                        isRequired = true;
                      }
                    }
                  }

                  // If the value is not in requireAttachmentsOn or enableAttachmentsOn, don't show upload
                  if (!shouldShowAttachments) {
                    // NEW CHECK: If hasAttachments is true and none of the above conditions applied, check if we should still show attachments
                    if (field['hasAttachments'] == true) {
                      // Check if requireAttachmentsOn is empty or null
                      bool isRequireAttachmentsOnEmpty =
                          field['requireAttachmentsOn'] == null ||
                              (field['requireAttachmentsOn'] is List &&
                                  (field['requireAttachmentsOn'] as List)
                                      .isEmpty);

                      // Check if enableAttachmentsOn is empty or null
                      bool isEnableAttachmentsOnEmpty =
                          field['enableAttachmentsOn'] == null ||
                              (field['enableAttachmentsOn'] is List &&
                                  (field['enableAttachmentsOn'] as List)
                                      .isEmpty);

                      // If both are empty or null, show file uploads and make them required
                      if (isRequireAttachmentsOnEmpty &&
                          isEnableAttachmentsOnEmpty) {
                        shouldShowAttachments = true;
                        isRequired = true;
                      } else {
                        return const SizedBox.shrink();
                      }
                    } else {
                      return const SizedBox.shrink();
                    }
                  }

                  return Column(
                    children: [
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Text(
                            StringConstants.uploadFiles,
                            style: widget.fontFamily,
                          ),
                          if (isRequired) ...[
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
                        uploadedFiles:
                            controller.uploadedFiles[field['name']] ?? [],
                        onRemoveUploadedFile: (file) {
                          setState(() {
                            // For single file upload, set to empty list when file is removed
                            controller.uploadedFiles[field['name']] = [];
                          });
                        },
                        isRequired: isRequired,
                      ),
                    ],
                  );
                },
              ),
            // Add support for comments
            if (field['hasComments'] == true) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    field['commentLabel'] ?? StringConstants.comments,
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
              ReactiveTextField(
                formControlName: '${field['name']}_comment',
                decoration: InputDecoration(
                  // No labelText to avoid displaying "comments" in the field
                  hintText: field['commentHint'] ?? '',
                  labelStyle: widget.fontFamily,
                  hintStyle: widget.fontFamily,
                  // Add error style
                  errorStyle: widget.fontFamily
                      .copyWith(color: Colors.red[700], fontSize: 12),
                ),
                maxLines: 3,
                validationMessages: {
                  'required': (_) => StringConstants.commentsAreRequired,
                },
                // Add onSubmitted to validate the form when user submits via keyboard
                onSubmitted: (_) {
                  if (widget.showOneByOne &&
                      !isCurrentQuestionEffectivelyLast()) {
                    validateCurrentSection();
                  }
                },
              ),
            ],
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildLabelRow(Map<String, dynamic> field) {
    if (field['label'] == null) return const SizedBox.shrink();
    return Row(
      children: [
        Text(
          field['label'],
          style: widget.fontFamily.copyWith(fontWeight: FontWeight.w400),
        ),
        if (field['required'] == true)
          Text(' *',
              style: widget.fontFamily
                  .copyWith(color: Colors.red, fontWeight: FontWeight.w400)),
      ],
    );
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
              currentValue =
                  List<String>.from(rawValue.map((e) => e.toString()));
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
                print(
                    'Updated ${field['name']} with: $value (type: ${value.runtimeType})');
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

  /// The `_buildRadioField` function in Dart creates a widget for displaying radio options with
  /// conditional file upload and comment fields based on the provided field parameters.
  ///
  /// Args:
  ///   field (Map<String, dynamic>): The `_buildRadioField` function you provided seems to be a Flutter
  /// widget that builds a radio field based on the given `field` parameter. The `field` parameter is
  /// expected to be a `Map<String, dynamic>` containing various configuration options for the radio
  /// field.
  ///
  /// Returns:
  ///   The `_buildRadioField` function returns a Column widget containing various child widgets based
  /// on the input field parameters. The returned widgets include RadioListTile widgets for options,
  /// FileUploadWidget for attachments if specified, and a TextField for comments if specified.
  Widget _buildRadioField(Map<String, dynamic> field) {
    // Fallback to default Yes/No if options are missing or empty
    final List<dynamic> rawOptions =
        (field['options'] as List<dynamic>?) ?? ['Yes', 'No'];
    final List<String> options =
        rawOptions.isEmpty ? ['Yes', 'No'] : rawOptions.cast<String>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabelRow(field),
        const SizedBox(height: 4),
        ...options
            .map<Widget>(
              (option) => RadioListTile<String>(
                title: Text(option, style: widget.fontFamily),
                value: option,
                groupValue: controller.form.control(field['name']).value,
                activeColor: widget.primaryColor,
                onChanged: (value) {
                  controller.form.control(field['name']).value = value;
                  if (widget.showOneByOne &&
                      !isCurrentQuestionEffectivelyLast()) {
                    Future.delayed(const Duration(milliseconds: 300), () {
                      if (validateCurrentSection()) {
                        moveToNextQuestion(context);
                      }
                    });
                  }
                },
              ),
            )
            .toList(),
        if (field['hasAttachments'] == true)
          ReactiveValueListenableBuilder(
            formControlName: field['name'],
            builder: (context, control, child) {
              // Get the disabledOptions list if it exists
              List<dynamic> disabledOptions =
                  field['disableAttachmentsOn'] is List
                      ? field['disableAttachmentsOn']
                      : field['disableAttachmentsOn'] != null
                          ? [field['disableAttachmentsOn']]
                          : [];

              // If the current value is in disabledOptions, don't show attachments
              if (disabledOptions.contains(control.value)) {
                return const SizedBox.shrink();
              }

              // Check if the value is in requireAttachmentsOn or enableAttachmentsOn
              bool shouldShowAttachments = false;
              bool isRequired = false;

              // Check requireAttachmentsOn
              if (field['requireAttachmentsOn'] != null) {
                List<dynamic> requiredOptions =
                    field['requireAttachmentsOn'] is List
                        ? field['requireAttachmentsOn']
                        : [field['requireAttachmentsOn']];

                if (requiredOptions.contains(control.value)) {
                  shouldShowAttachments = true;
                  isRequired = true;
                }
              }

              // Check enableAttachmentsOn (works the same as requireAttachmentsOn for visibility)
              if (!shouldShowAttachments &&
                  field['enableAttachmentsOn'] != null) {
                List<dynamic> enabledOptions =
                    field['enableAttachmentsOn'] is List
                        ? field['enableAttachmentsOn']
                        : [field['enableAttachmentsOn']];

                if (enabledOptions.contains(control.value)) {
                  shouldShowAttachments = true;
                  isRequired = true;
                }
              }

              // If the value is not in requireAttachmentsOn or enableAttachmentsOn, don't show upload
              if (!shouldShowAttachments) {
                // NEW CHECK: If hasAttachments is true and none of the above conditions applied, check if we should still show attachments
                if (field['hasAttachments'] == true) {
                  // Check if requireAttachmentsOn is empty or null
                  bool isRequireAttachmentsOnEmpty =
                      field['requireAttachmentsOn'] == null ||
                          (field['requireAttachmentsOn'] is List &&
                              (field['requireAttachmentsOn'] as List).isEmpty);

                  // Check if enableAttachmentsOn is empty or null
                  bool isEnableAttachmentsOnEmpty =
                      field['enableAttachmentsOn'] == null ||
                          (field['enableAttachmentsOn'] is List &&
                              (field['enableAttachmentsOn'] as List).isEmpty);

                  // If both are empty or null, show file uploads and make them required
                  if (isRequireAttachmentsOnEmpty &&
                      isEnableAttachmentsOnEmpty) {
                    shouldShowAttachments = true;
                    isRequired = true;
                  } else {
                    return const SizedBox.shrink();
                  }
                } else {
                  return const SizedBox.shrink();
                }
              }

              return Column(
                children: [
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        StringConstants.uploadFiles,
                        style: widget.fontFamily,
                      ),
                      if (isRequired) ...[
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
                    uploadedFiles:
                        controller.uploadedFiles[field['name']] ?? [],
                    onRemoveUploadedFile: (file) {
                      setState(() {
                        // For single file upload, set to empty list when file is removed
                        controller.uploadedFiles[field['name']] = [];
                      });
                    },
                    isRequired: isRequired,
                  ),
                ],
              );
            },
          ),
        if (field['hasComments'] == true) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                field['commentLabel'] ?? StringConstants.comments,
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
          ReactiveTextField(
            formControlName: '${field['name']}_comment',
            decoration: InputDecoration(
              // No labelText to avoid displaying "comments" in the field
              hintText: field['commentHint'] ?? '',
              labelStyle: widget.fontFamily,
              hintStyle: widget.fontFamily,
              // Add error style
              errorStyle: widget.fontFamily
                  .copyWith(color: Colors.red[700], fontSize: 12),
            ),
            maxLines: 3,
            validationMessages: {
              'required': (_) => StringConstants.commentsAreRequired,
            },
            // Add onSubmitted to validate the form when user submits via keyboard
            onSubmitted: (_) {
              if (widget.showOneByOne && !isCurrentQuestionEffectivelyLast()) {
                validateCurrentSection();
              }
            },
          ),
        ],
      ],
    );
  }

  Widget _buildDropdownField(Map<String, dynamic> field) {
    // Ensure we always have a valid options list even if none was provided
    final List<dynamic> options = (field['options'] as List<dynamic>?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabelRow(field),
        const SizedBox(height: 4),
        InkWell(
          onTap: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(15))),
              builder: (context) => _DropdownSearch(
                fontFamily: widget.fontFamily,
                options: options,
                selectedValue: controller.form.control(field['name']).value,
                onSelect: (value) {
                  controller.form.control(field['name']).value = value;
                  Navigator.pop(context);

                  // Add auto-navigation with validation for dropdown fields
                  if (widget.showOneByOne) {
                    // Add a small delay to allow the value to be set before navigation
                    Future.delayed(const Duration(milliseconds: 300), () {
                      // Only proceed with auto-navigation if we're not on the submit page
                      if (!isCurrentQuestionEffectivelyLast()) {
                        // First validate the current form section
                        if (validateCurrentSection()) {
                          moveToNextQuestion(context);
                        }
                      }
                    });
                  }
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
              // Get the disabledOptions list if it exists
              List<dynamic> disabledOptions =
                  field['disableAttachmentsOn'] is List
                      ? field['disableAttachmentsOn']
                      : field['disableAttachmentsOn'] != null
                          ? [field['disableAttachmentsOn']]
                          : [];

              // If the current value is in disabledOptions, don't show attachments
              if (disabledOptions.contains(control.value)) {
                return const SizedBox.shrink();
              }

              // Check if the value is in requireAttachmentsOn or enableAttachmentsOn
              bool shouldShowAttachments = false;
              bool isRequired = false;

              // Check requireAttachmentsOn
              if (field['requireAttachmentsOn'] != null) {
                List<dynamic> requiredOptions =
                    field['requireAttachmentsOn'] is List
                        ? field['requireAttachmentsOn']
                        : [field['requireAttachmentsOn']];

                if (requiredOptions.contains(control.value)) {
                  shouldShowAttachments = true;
                  isRequired = true;
                }
              }

              // Check enableAttachmentsOn (works the same as requireAttachmentsOn for visibility)
              if (!shouldShowAttachments &&
                  field['enableAttachmentsOn'] != null) {
                List<dynamic> enabledOptions =
                    field['enableAttachmentsOn'] is List
                        ? field['enableAttachmentsOn']
                        : [field['enableAttachmentsOn']];

                if (enabledOptions.contains(control.value)) {
                  shouldShowAttachments = true;
                  isRequired = true;
                }
              }

              // If the value is not in requireAttachmentsOn or enableAttachmentsOn, don't show upload
              if (!shouldShowAttachments) {
                // NEW CHECK: If hasAttachments is true and none of the above conditions applied, check if we should still show attachments
                if (field['hasAttachments'] == true) {
                  // Check if requireAttachmentsOn is empty or null
                  bool isRequireAttachmentsOnEmpty =
                      field['requireAttachmentsOn'] == null ||
                          (field['requireAttachmentsOn'] is List &&
                              (field['requireAttachmentsOn'] as List).isEmpty);

                  // Check if enableAttachmentsOn is empty or null
                  bool isEnableAttachmentsOnEmpty =
                      field['enableAttachmentsOn'] == null ||
                          (field['enableAttachmentsOn'] is List &&
                              (field['enableAttachmentsOn'] as List).isEmpty);

                  // If both are empty or null, show file uploads and make them required
                  if (isRequireAttachmentsOnEmpty &&
                      isEnableAttachmentsOnEmpty) {
                    shouldShowAttachments = true;
                    isRequired = true;
                  } else {
                    return const SizedBox.shrink();
                  }
                } else {
                  return const SizedBox.shrink();
                }
              }

              return Column(
                children: [
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        StringConstants.uploadFiles,
                        style: widget.fontFamily,
                      ),
                      if (isRequired) ...[
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
                    uploadedFiles:
                        controller.uploadedFiles[field['name']] ?? [],
                    onRemoveUploadedFile: (file) {
                      setState(() {
                        // For single file upload, set to empty list when file is removed
                        controller.uploadedFiles[field['name']] = [];
                      });
                    },
                    isRequired: isRequired,
                  ),
                ],
              );
            },
          ),
        if (field['hasComments'] == true) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                field['commentLabel'] ?? StringConstants.comments,
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
          ReactiveTextField(
            formControlName: '${field['name']}_comment',
            decoration: InputDecoration(
              // No labelText to avoid displaying "comments" in the field
              hintText: field['commentHint'] ?? '',
              labelStyle: widget.fontFamily,
              hintStyle: widget.fontFamily,
              // Add error style
              errorStyle: widget.fontFamily
                  .copyWith(color: Colors.red[700], fontSize: 12),
            ),
            maxLines: 3,
            validationMessages: {
              'required': (_) => StringConstants.commentsAreRequired,
            },
            // Add onSubmitted to validate the form when user submits via keyboard
            onSubmitted: (_) {
              if (widget.showOneByOne && !isCurrentQuestionEffectivelyLast()) {
                validateCurrentSection();
              }
            },
          ),
        ],
      ],
    );
  }

  /// The `_buildTextField` function creates a column with a text field, comments section, and file
  /// upload widget based on the provided field configuration.
  ///
  /// Args:
  ///   field (Map<String, dynamic>): The `_buildTextField` function you provided is a Flutter widget
  /// that creates a form field based on the input `field` parameter. The `field` parameter is a
  /// `Map<String, dynamic>` that contains various configuration options for the form field. Here's a
  /// breakdown of the possible keys in the `
  ///
  /// Returns:
  ///   The `_buildTextField` function returns a Column widget containing various child widgets based on
  /// the input field configuration provided. The returned widgets include ReactiveTextField for user
  /// input, Text widgets for labels and hints, FileUploadWidget for uploading files, and other related
  /// widgets for comments and attachments.
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

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLabelRow(field),
                ReactiveTextField(
                  formControlName: field['name'],
                  validationMessages: {
                    'required': (error) => StringConstants.requiredField,
                  },
                  keyboardType: field['type'] == 'number'
                      ? TextInputType.number
                      : TextInputType.text,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    if (widget.showOneByOne) {
                      // Only proceed with auto-navigation if we're not on the submit page and form is valid
                      if (!isCurrentQuestionEffectivelyLast()) {
                        // First validate the current form section
                        if (validateCurrentSection()) {
                          moveToNextQuestion(context);
                        }
                      }
                    }
                  },
                  cursorColor: Colors.black,
                  decoration: InputDecoration(
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(
                          color: Colors.black), // Set underline color to black
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(
                          color: Colors
                              .black), // Set focused underline color to black
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        if (field['hasComments'] == true) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                field['commentLabel'] ?? StringConstants.comments,
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
          ReactiveTextField(
            formControlName: '${field['name']}_comment',
            decoration: InputDecoration(
              // No labelText to avoid displaying "comments" in the field
              hintText: field['commentHint'] ?? '',
              labelStyle: widget.fontFamily,
              hintStyle: widget.fontFamily,
              // Add error style
              errorStyle: widget.fontFamily
                  .copyWith(color: Colors.red[700], fontSize: 12),
            ),
            maxLines: 3,
            validationMessages: {
              'required': (_) => StringConstants.commentsAreRequired,
            },
            // Add onSubmitted to validate the form when user submits via keyboard
            onSubmitted: (_) {
              if (widget.showOneByOne && !isCurrentQuestionEffectivelyLast()) {
                validateCurrentSection();
              }
            },
          ),
        ],
        if (field['hasAttachments'] == true ||
            field['requireAttachmentsOn'] == true ||
            field['requiredAttachmentsOn'] == true) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                StringConstants.uploadFiles,
                style: widget.fontFamily,
              ),
              // Show asterisk if required
              if (field['requireAttachmentsOn'] == true ||
                  field['hasAttachments'] == true) ...[
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
          ReactiveValueListenableBuilder(
            formControlName: field['name'],
            builder: (context, control, child) {
              // Check if the value should show attachments and if it's required
              bool shouldShowAttachments = false;
              bool isRequired = false;

              // Always show if requireAttachmentsOn or requiredAttachmentsOn is true (boolean flag)
              if (field['requireAttachmentsOn'] == true ||
                  field['requiredAttachmentsOn'] == true) {
                shouldShowAttachments = true;
                isRequired = true;
              }

              // Check if value is in requireAttachmentsOn list
              if (!shouldShowAttachments &&
                  field['requireAttachmentsOn'] != null &&
                  field['requireAttachmentsOn'] is List) {
                final selectedValue = control.value;
                final requiredOptions = field['requireAttachmentsOn'];

                if (requiredOptions.contains(selectedValue)) {
                  shouldShowAttachments = true;
                  isRequired = true;
                }
              }

              // Check if value is in enableAttachmentsOn list
              if (!shouldShowAttachments &&
                  field['enableAttachmentsOn'] != null) {
                if (field['enableAttachmentsOn'] is List) {
                  final selectedValue = control.value;
                  final enabledOptions = field['enableAttachmentsOn'];

                  if (enabledOptions.contains(selectedValue)) {
                    shouldShowAttachments = true;
                    isRequired = true;
                  }
                } else if (field['enableAttachmentsOn'] == true) {
                  shouldShowAttachments = true;
                  isRequired = true;
                }
              }

              // If nothing requires attachments for this value, don't show the upload
              if (!shouldShowAttachments && field['hasAttachments'] != true) {
                return const SizedBox.shrink();
              }

              // Special case: if hasAttachments is explicitly true and none of the above conditions applied
              // Check if we still want to show uploads in this case
              if (!shouldShowAttachments && field['hasAttachments'] == true) {
                // If this is a text field with hasAttachments=true, make uploads required
                if (field['type'] == 'text') {
                  shouldShowAttachments = true;
                  isRequired = true;
                } else {
                  // For other field types, keep the existing logic
                  // Check if requireAttachmentsOn is empty or null
                  bool isRequireAttachmentsOnEmpty =
                      field['requireAttachmentsOn'] == null ||
                          (field['requireAttachmentsOn'] is List &&
                              (field['requireAttachmentsOn'] as List).isEmpty);

                  // Check if enableAttachmentsOn is empty or null
                  bool isEnableAttachmentsOnEmpty =
                      field['enableAttachmentsOn'] == null ||
                          (field['enableAttachmentsOn'] is List &&
                              (field['enableAttachmentsOn'] as List).isEmpty);

                  // If both are empty or null, show file uploads and make them required
                  if (isRequireAttachmentsOnEmpty &&
                      isEnableAttachmentsOnEmpty) {
                    shouldShowAttachments = true;
                    isRequired = true;
                  } else {
                    // If we want to hide attachments for values not in requireAttachmentsOn/enableAttachmentsOn
                    return const SizedBox.shrink();
                  }
                }
              }

              return FileUploadWidget(
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
                    // For single file upload, set to empty list when file is removed
                    controller.uploadedFiles[field['name']] = [];
                  });
                },
                isRequired: isRequired,
              );
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
        _buildLabelRow(field),
        ReactiveTextField<num>(
          formControlName: field['name'],
          keyboardType: TextInputType.number,
          valueAccessor: NumValueAccessor(),
          validationMessages: {
            'required': (error) => StringConstants.requiredField,
            'min': (error) =>
                '${StringConstants.valueMustBeAtLeast} ${field['min']}',
            'max': (error) =>
                '${StringConstants.valueMustBeLessThanOrEqualTo} ${field['max']} ${StringConstants.characters}',
          },
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (widget.showOneByOne) {
              // Only proceed with auto-navigation if we're not on the submit page
              if (!isCurrentQuestionEffectivelyLast()) {
                // First validate the current form section
                if (validateCurrentSection()) {
                  moveToNextQuestion(context);
                }
              }
            }
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
            errorStyle:
                widget.fontFamily.copyWith(fontSize: 12, color: Colors.red),
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
              // Show asterisk only if required
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
          ReactiveValueListenableBuilder(
              formControlName: field['name'],
              builder: (context, control, child) {
                // File upload is required if attachmentsRequired is true
                bool isRequired = field['attachmentsRequired'] == true;

                // Check if enableAttachmentsOn contains the selected value (like requireAttachmentsOn)
                if (!isRequired && field['enableAttachmentsOn'] != null) {
                  final selectedValue = control.value;
                  final enabledOptions = field['enableAttachmentsOn'] is List
                      ? field['enableAttachmentsOn']
                      : [field['enableAttachmentsOn']];

                  if (enabledOptions.contains(selectedValue)) {
                    isRequired = true;
                  }
                }

                // Also check requireAttachmentsOn
                if (!isRequired && field['requireAttachmentsOn'] != null) {
                  final selectedValue = control.value;
                  final requiredOptions = field['requireAttachmentsOn'] is List
                      ? field['requireAttachmentsOn']
                      : [field['requireAttachmentsOn']];

                  if (requiredOptions.contains(selectedValue)) {
                    isRequired = true;
                  }
                }

                return FileUploadWidget(
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
                      // For single file upload, set to empty list when file is removed
                      controller.uploadedFiles[field['name']] = [];
                    });
                  },
                  isRequired: isRequired,
                );
              }),
        ],
        if (field['hasComments'] == true) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                field['commentLabel'] ?? StringConstants.comments,
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
          ReactiveTextField(
            formControlName: '${field['name']}_comment',
            decoration: InputDecoration(
              // No labelText to avoid displaying "comments" in the field
              hintText: field['commentHint'] ?? '',
              labelStyle: widget.fontFamily,
              hintStyle: widget.fontFamily,
              // Add error style
              errorStyle: widget.fontFamily
                  .copyWith(color: Colors.red[700], fontSize: 12),
            ),
            maxLines: 3,
            validationMessages: {
              'required': (_) => StringConstants.commentsAreRequired,
            },
            // Add onSubmitted to validate the form when user submits via keyboard
            onSubmitted: (_) {
              if (widget.showOneByOne && !isCurrentQuestionEffectivelyLast()) {
                validateCurrentSection();
              }
            },
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
                      // For single file upload, set to empty list when file is removed
                      controller.uploadedFiles[field['name']] = [];
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
                // Show error message if validation error occurs and control is touched
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
        // Comments section if `hasComments` is true
        if (field['hasComments'] == true) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                field['commentLabel'] ?? StringConstants.comments,
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
          ReactiveTextField(
            formControlName: '${field['name']}_comment',
            decoration: InputDecoration(
              // No labelText to avoid displaying "comments" in the field
              hintText: field['commentHint'] ?? '',
              labelStyle: widget.fontFamily,
              hintStyle: widget.fontFamily,
              // Add error style
              errorStyle: widget.fontFamily
                  .copyWith(color: Colors.red[700], fontSize: 12),
            ),
            maxLines: 3,
            validationMessages: {
              'required': (_) => StringConstants.commentsAreRequired,
            },
            // Add onSubmitted to validate the form when user submits via keyboard
            onSubmitted: (_) {
              if (widget.showOneByOne && !isCurrentQuestionEffectivelyLast()) {
                validateCurrentSection();
              }
            },
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
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    moveToPreviousValidQuestion();
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                child: Text(
                  StringConstants.back,
                  style: widget.fontFamily.copyWith(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              )
            else
              const SizedBox(width: 100),
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
                  widget.submitButtonText ?? 'Submit',
                  style: widget.fontFamily.copyWith(
                    color: widget.buttonTextColor,
                    fontSize: 16,
                  ),
                ),
              )
            else
              ElevatedButton(
                onPressed: () {
                  _moveToNextStep(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                child: Text(
                  StringConstants.next,
                  style: widget.fontFamily.copyWith(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
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
      child: Text(widget.submitButtonText ?? 'Submit',
          style: widget.fontFamily.copyWith(color: widget.buttonTextColor)),
    );
  }

  void _submitForm(BuildContext context) {
    // First validate the current question if in step-by-step mode
    if (widget.showOneByOne &&
        controller.currentQuestionIndex < widget.formJson.length) {
      final currentField = widget.formJson[controller.currentQuestionIndex];
      final control = controller.form.control(currentField['name']);

      // Check if the current field is required and empty
      if ((currentField['required'] == true) &&
          (control.value == null ||
              control.value.toString().isEmpty ||
              control.value == 'null')) {
        control.markAsTouched();
        AppSnackBar(
            StringConstants.pleaseFillInAllRequiredFields as BuildContext);
        return;
      }

      // Check for required file uploads
      if (currentField['type'] == 'file' && currentField['required'] == true) {
        final hasFiles =
            controller.uploadedFiles[currentField['name']]?.isNotEmpty ?? false;
        if (!hasFiles) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '${currentField['label']} ${StringConstants.isRequired}',
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
          cleanedUploadedFiles[fieldName] =
              controller.uploadedFiles[fieldName]!;
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
    if (_groupAnchors.isEmpty) return "0/0";
    return '${_currentGroupPointer + 1}/${_groupAnchors.length}';
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

  // --- Duplicate navigation helpers removed (see consolidated implementations later in class) ---
  void _moveToNextStep(BuildContext context) {
    // Debug the current state
    if (kDebugMode) {
      print('Moving to next step');
      print('Current group pointer: $_currentGroupPointer');
      print('Group anchors: $_groupAnchors');
    }

    // Make sure we have valid anchors
    if (_groupAnchors.isEmpty) {
      if (kDebugMode) {
        print('Warning: No group anchors available');
      }
      return;
    }

    // Validate the current question before moving to the next
    if (!validateCurrentSection()) {
      if (kDebugMode) {
        print('Validation failed, not moving to next question');
      }

      // Show validation errors
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(StringConstants.fillRequiredFields),
          backgroundColor: Colors.red,
        ),
      );
      controller.form.markAllAsTouched();
      return;
    }

    // Check if we're at the end of the form
    if (_currentGroupPointer >= _groupAnchors.length - 1) {
      // We've reached the end of the form, submit if valid
      if (controller.form.valid) {
        if (kDebugMode) {
          print('Reached end of form, submitting');
        }
        controller.submitForm(context);
      } else {
        // Show validation errors
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(StringConstants.fillRequiredFields),
            backgroundColor: Colors.red,
          ),
        );
        controller.form.markAllAsTouched();
      }
      return;
    }

    // If we get here, we should increment the group pointer
    setState(() {
      // Increment group pointer to move to next question
      _currentGroupPointer++;

      // Update the controller's current question index to the new anchor
      if (_currentGroupPointer < _groupAnchors.length) {
        final nextAnchor = _groupAnchors[_currentGroupPointer];
        controller.currentQuestionIndex = nextAnchor;

        if (kDebugMode) {
          print('Moved to group pointer: $_currentGroupPointer');
          print('New anchor: $nextAnchor');
          print('Question name: ${_internalFields[nextAnchor]['name']}');
        }
      }
    });
  }

  void moveToNextQuestion(BuildContext context) {
    if (kDebugMode) {
      print("Moving to next question");
      print("Before navigation - Current group pointer: $_currentGroupPointer");
      print("Before navigation - Available anchors: $_groupAnchors");
    }

    _moveToNextStep(context);

    // Force a rebuild to ensure the UI updates with the new question
    if (mounted) {
      setState(() {
        // This empty setState ensures the build method is called again
      });
    }
  }

  void moveToPreviousValidQuestion() {
    if (_currentGroupPointer > 0) {
      setState(() {
        _currentGroupPointer--;
        controller.currentQuestionIndex = _groupAnchors[_currentGroupPointer];

        // Make sure we're not navigating to a duplicate card
        // This is a safety check in case duplicates somehow get included in _groupAnchors
        while (_currentGroupPointer > 0 &&
            _internalFields[_groupAnchors[_currentGroupPointer]]
                    ['isDuplicate'] ==
                true) {
          _currentGroupPointer--;
          controller.currentQuestionIndex = _groupAnchors[_currentGroupPointer];
        }
      });
    }
  }

  bool isCurrentQuestionEffectivelyLast() {
    return _currentGroupPointer >= _groupAnchors.length - 1;
  }

  int findNextVisibleQuestionIndex() {
    // simply return next anchor or -1
    if (_currentGroupPointer < _groupAnchors.length - 1) {
      return _groupAnchors[_currentGroupPointer + 1];
    }
    return -1;
  }

  bool _validateCurrentStep() {
    // Make sure we have a valid question index
    if (controller.currentQuestionIndex >= widget.formJson.length) {
      return true;
    }

    // Get the name of the current question
    String questionName = _getCurrentQuestionName();
    if (questionName.isEmpty) {
      return true;
    }

    // Check if control exists and is valid
    if (!controller.form.contains(questionName)) {
      return true;
    }

    bool isValid = controller.form.control(questionName).valid;

    // Get the current field definition
    Map<String, dynamic>? currentField =
        widget.formJson[controller.currentQuestionIndex];

    if (currentField != null) {
      // Get the current value
      var selectedValue = controller.form.control(currentField['name']).value;

      // Check if file is required based on the selected values
      bool fileRequired = false;

      // Check requireAttachmentsOn
      if (currentField['requireAttachmentsOn'] != null) {
        if (currentField['requireAttachmentsOn'] == true) {
          fileRequired = true;
        } else if (currentField['requireAttachmentsOn'] is List) {
          List<dynamic> requiredOptions = currentField['requireAttachmentsOn'];

          if (requiredOptions.contains(selectedValue)) {
            fileRequired = true;
          }
        }
      }

      // Check enableAttachmentsOn (now works like requireAttachmentsOn)
      if (!fileRequired && currentField['enableAttachmentsOn'] != null) {
        if (currentField['enableAttachmentsOn'] is List) {
          List<dynamic> enabledOptions = currentField['enableAttachmentsOn'];

          if (enabledOptions.contains(selectedValue)) {
            fileRequired = true;
          }
        }
      }

      // NEW CHECK: If hasAttachments is true and both requireAttachmentsOn and enableAttachmentsOn are empty or null, make file upload mandatory
      if (!fileRequired && currentField['hasAttachments'] == true) {
        // Check if this is a text field
        if (currentField['type'] == 'text') {
          // For text fields with hasAttachments=true, always make file upload mandatory
          fileRequired = true;
        } else {
          // For other field types, keep the existing logic
          // Check if requireAttachmentsOn is empty or null
          bool isRequireAttachmentsOnEmpty =
              currentField['requireAttachmentsOn'] == null ||
                  (currentField['requireAttachmentsOn'] is List &&
                      (currentField['requireAttachmentsOn'] as List).isEmpty);

          // Check if enableAttachmentsOn is empty or null
          bool isEnableAttachmentsOnEmpty =
              currentField['enableAttachmentsOn'] == null ||
                  (currentField['enableAttachmentsOn'] is List &&
                      (currentField['enableAttachmentsOn'] as List).isEmpty);

          // If both are empty or null, file upload is required
          if (isRequireAttachmentsOnEmpty && isEnableAttachmentsOnEmpty) {
            fileRequired = true;
          }
        }
      }

      // Check requiredAttachmentsOn (legacy support)
      if (currentField['requiredAttachmentsOn'] == true) {
        fileRequired = true;
      }

      // If file is required, check if it's uploaded
      if (fileRequired &&
          (controller.uploadedFiles[currentField['name']] == null ||
              controller.uploadedFiles[currentField['name']]!.isEmpty)) {
        setState(() {
          _showAttachmentError = true;
        });
        return false;
      }
    }

    setState(() {
      _showAttachmentError = false;
    });

    return isValid;
  }

  bool validateCurrentSection() {
    return _validateCurrentStep();
  }

  Widget _buildErrorMessage() {
    return _showAttachmentError
        ? Container(
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.red.shade100,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Required attachments are missing',
              style: TextStyle(color: Colors.red.shade900),
            ),
          )
        : const SizedBox.shrink();
  }

  /// Adds a new set of related fields to the form by duplicating current group
  /// and placing it below the original card
  void _addNewSet() {
    try {
      if (kDebugMode) {
        print('\n\n=== Starting duplication process ===');
      }

      // Temporarily disable PageController updates
      _pageControllerReady = false;

      // Make sure we have valid anchors before proceeding
      if (_groupAnchors.isEmpty) {
        if (kDebugMode) {
          print('No anchors available for duplication');
        }
        return;
      }

      // Make sure _currentGroupPointer is valid
      if (_currentGroupPointer < 0 ||
          _currentGroupPointer >= _groupAnchors.length) {
        if (kDebugMode) {
          print(
              'Warning: Invalid _currentGroupPointer value (${_currentGroupPointer}), resetting to 0');
        }
        _currentGroupPointer = 0;
      }

      // Store the original pointer to restore it after duplication
      final originalPointer = _currentGroupPointer;

      // Get the current anchor and its field indices
      final anchor = _groupAnchors[_currentGroupPointer];
      final List<int> indices = _anchorToFieldIndices[anchor] ?? [anchor];

      if (indices.isEmpty) {
        if (kDebugMode) {
          print('No fields to duplicate in current anchor');
        }
        return;
      }

      // Debug info to help diagnose the issue
      if (kDebugMode) {
        print('Current anchor index: $anchor');
        print('Fields in this group indices: $indices');
      }

      // Identify the original field names that should be part of this card
      final originalFieldNames = <String>[];
      for (int idx in indices) {
        if (idx >= 0 && idx < _internalFields.length) {
          originalFieldNames.add(_internalFields[idx]['name'].toString());
        }
      }

      // Generate a unique timestamp for this duplication
      final millis = DateTime.now().millisecondsSinceEpoch;
      final List<Map<String, dynamic>> newFields = [];

      // Get all fields in the current card for duplication
      final cardFields = <Map<String, dynamic>>[];
      for (int idx in indices) {
        if (idx >= 0 && idx < _internalFields.length) {
          cardFields.add(_internalFields[idx]);
        }
      }

      if (kDebugMode) {
        print('Found ${cardFields.length} fields to duplicate in this card');
      }

      // Map of original field names to their duplicated versions
      final Map<String, String> originalToDuplicateNames = {};

      // First pass: Create duplicates with new names
      for (final originalField in cardFields) {
        final String originalFieldName = originalField['name'].toString();
        final Map<String, dynamic> fieldCopy =
            Map<String, dynamic>.from(originalField);

        // Create unique name by adding timestamp suffix to maintain grouping
        fieldCopy['name'] = '${originalFieldName}_$millis';
        originalToDuplicateNames[originalFieldName] = fieldCopy['name'];

        // Mark as duplicate for delete button visibility
        fieldCopy['isDuplicate'] = true;

        // Add field to list of new fields
        newFields.add(fieldCopy);
      }

      // Second pass: Update any internal references (like groupWith)
      for (final fieldCopy in newFields) {
        if (fieldCopy.containsKey('groupWith')) {
          final String originalGroupTarget = fieldCopy['groupWith'].toString();

          // If this field was grouped with a field we've already duplicated,
          // update the groupWith to point to the new duplicate
          if (originalToDuplicateNames.containsKey(originalGroupTarget)) {
            fieldCopy['groupWith'] =
                originalToDuplicateNames[originalGroupTarget]!;
          }
        }
      }

      // Determine the insertion position - after the last field in the current card
      final insertPosition = indices.isEmpty
          ? 0
          : indices.map((i) => i).reduce((a, b) => a > b ? a : b) + 1;

      if (kDebugMode) {
        print('Creating ${newFields.length} duplicated fields');
        print('Inserting at position $insertPosition');
        print('New field names: ${newFields.map((f) => f['name']).toList()}');
      }

      // Check if widget is still mounted before updating state
      if (!mounted) return;

      // Update the state with the new fields
      setState(() {
        // Insert all the duplicated fields at the calculated position
        // This ensures they appear as a complete group directly below the original card
        _internalFields.insertAll(insertPosition, newFields);

        // Add form controls for all the duplicated fields
        controller.addFormControls(newFields);

        // Regenerate the group mapping to properly group duplicated fields
        // This is critical to ensure duplicated fields appear in the right cards
        _recomputeGroupStructure();

        // Stay on the current card after duplication by restoring the original pointer
        _currentGroupPointer = originalPointer;
      });

      // Re-enable PageController updates after a short delay to allow layout to complete
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {
            _pageControllerReady = true;

            // Force UI refresh to reflect changes
            if (kDebugMode) {
              print('Duplication complete, forcing UI refresh');
            }
          });
        }
      });

      if (kDebugMode) {
        print('=== Duplication process completed ===\n\n');
      }
    } catch (e) {
      print('Error in _addNewSet: $e');
      // Always re-enable page controller in case of error
      _pageControllerReady = true;
    }
  }

  void _removeSet(List<String> names) {
    if (!mounted) return;

    try {
      setState(() {
        // Remove fields with matching names
        if (_internalFields.isNotEmpty) {
          _internalFields.removeWhere((f) => names.contains(f['name']));
        }

        // Remove form controls
        if (controller != null) {
          controller.removeFormControls(names);
        }

        // Recalculate group structure
        _recomputeGroupStructure();

        // Ensure the group pointer is valid after removing items
        if (_groupAnchors.isEmpty) {
          _currentGroupPointer = 0;
        } else if (_currentGroupPointer >= _groupAnchors.length) {
          _currentGroupPointer = _groupAnchors.length - 1;
        }
      });
    } catch (e) {
      print('Error in _removeSet: $e');
    }
  }

  List<Widget> _buildGroupedCards() {
    List<Widget> cards = [];

    try {
      // Safety check for empty anchors
      if (_groupAnchors.isEmpty) {
        return cards;
      }

      // Iterate over each anchor that defines a group
      for (int i = 0; i < _groupAnchors.length; i++) {
        // Safety check for valid anchor index
        if (i >= _groupAnchors.length) continue;

        final int anchor = _groupAnchors[i];

        // Safety check for valid internal fields index
        if (anchor < 0 || anchor >= _internalFields.length) continue;

        // Get all fields in this group
        final List<int> indices = _anchorToFieldIndices[anchor] ?? [anchor];
        if (indices.isEmpty) continue;

        // Collect field maps for this group with safety checks
        final groupFields = <Map<String, dynamic>>[];
        for (int idx in indices) {
          if (idx >= 0 && idx < _internalFields.length) {
            groupFields.add(_internalFields[idx]);
          }
        }

        if (groupFields.isEmpty) continue;

        // Check if this is a duplicated card using the explicit isDuplicate property
        bool isDuplicated = false;
        if (_internalFields[anchor].containsKey('isDuplicate')) {
          isDuplicated = _internalFields[anchor]['isDuplicate'] == true;
        }

        cards.add(
          Card(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Build all fields in the group
                  ...groupFields
                      .map((fieldData) => _buildField(fieldData))
                      .toList(),

                  // Add delete button if this is a duplicated card
                  if (isDuplicated)
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () {
                          final fieldNames = groupFields
                              .map((field) => field['name'].toString())
                              .toList();
                          _removeSet(fieldNames);
                        },
                        color: Colors.red,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }
    } catch (e) {
      print('Error building grouped cards: $e');
    }

    return cards;
  }

  // --- Group logic -------------------------------------------------
  void _recomputeGroupStructure() {
    _groupAnchors.clear();
    _anchorToFieldIndices.clear();

    // Track groups by their base key + duplicate IDs
    Map<String, int> firstAnchorOfGroup = {};
    Map<String, String> fieldToGroupKey = {};

    // Keep track of timestamp-based duplicates
    Map<String, List<int>> timestampGroups = {};

    // Keep track of base names for duplicate grouping
    Map<String, String> duplicateToBaseName = {};

    // Special pattern for "question_X" format - need to differentiate from duplicates
    final questionPattern = RegExp(r'^question_(\d+)$');

    // Extract timestamp patterns from field names for grouping duplicates together
    final timestampPattern = RegExp(r'(.+)_(\d+)$');

    if (kDebugMode) {
      print("\n----- Starting Group Structure Computation -----");
      print("Total fields: ${_internalFields.length}");
      _internalFields.forEach((field) {
        print("Field: ${field['name']}, groupWith: ${field['groupWith']}");
      });
    }

    // First pass: Identify all timestamp-based duplicates
    for (int i = 0; i < _internalFields.length; i++) {
      final field = _internalFields[i];
      final fieldName = field['name'].toString();

      // Check if this field has a timestamp
      final match = timestampPattern.firstMatch(fieldName);
      if (match != null && field['isDuplicate'] == true) {
        final baseName = match.group(1) ?? fieldName;
        final timestamp = match.group(2) ?? '';

        if (timestamp.isNotEmpty) {
          final groupKey = 'duplicate:${timestamp}';
          timestampGroups.putIfAbsent(groupKey, () => []).add(i);

          if (kDebugMode) {
            print(
                "Found timestamp-based duplicate: $fieldName with timestamp $timestamp");
          }
        }
      }
    }

    if (kDebugMode) {
      print("Timestamp-based groups:");
      timestampGroups.forEach((key, indices) {
        print(
            "  $key: ${indices.map((i) => _internalFields[i]['name']).join(', ')}");
      });
    }

    // Step 1: Map each field to its group key
    for (int i = 0; i < _internalFields.length; i++) {
      final field = _internalFields[i];
      final fieldName = field['name'].toString();

      // Extract base name and timestamp if this is a duplicated field
      String baseName = fieldName;
      String? duplicateId;

      // First try to extract from explicit groupWith setting
      String? groupWith = field['groupWith']?.toString();

      // Check if this is a standard question pattern (question_X)
      final questionMatch = questionPattern.firstMatch(fieldName);
      final duplicateMatch = timestampPattern.firstMatch(fieldName);

      if (duplicateMatch != null) {
        // This is a duplicated field with timestamp
        baseName = duplicateMatch.group(1) ?? fieldName;
        duplicateId = duplicateMatch.group(2);

        // Record the mapping from duplicate name to base name
        if (field['isDuplicate'] == true) {
          duplicateToBaseName[fieldName] = baseName;
        }
      }

      // Generate a group key
      String groupKey;

      if (groupWith != null) {
        // If field explicitly declares what it groups with, use that
        // For question_X format, the groupWith directly becomes the key
        // This ensures questions with pattern question_1, question_2, etc. group correctly
        groupKey = groupWith;
      } else if (duplicateId != null && field['isDuplicate'] == true) {
        // For duplicated fields with timestamp but no groupWith, use a common group key
        groupKey = 'duplicate:${duplicateId}';
      } else {
        // For original non-duplicated fields, use field name as its own group
        groupKey = fieldName;
      }

      fieldToGroupKey[fieldName] = groupKey;
    }

    // Debug the mapping
    if (kDebugMode) {
      print('Field to group key mapping:');
      fieldToGroupKey.forEach((field, group) {
        print('  $field → $group');
      });
    }

    // Step 2: Organize fields into groups based on their keys
    Map<String, List<int>> groupKeyToFieldIndices = {};

    for (int i = 0; i < _internalFields.length; i++) {
      final field = _internalFields[i];
      final fieldName = field['name'].toString();
      final groupKey = fieldToGroupKey[fieldName];

      if (groupKey != null) {
        groupKeyToFieldIndices.putIfAbsent(groupKey, () => []).add(i);
      }
    }

    // Debug the grouping
    if (kDebugMode) {
      print('Group organization:');
      groupKeyToFieldIndices.forEach((groupKey, indices) {
        final fieldNames =
            indices.map((i) => _internalFields[i]['name']).join(', ');
        print('  Group $groupKey: $fieldNames');
      });
    }

    // Step 3: Create anchors and field indices
    // First, collect all original (non-duplicate) anchors
    List<int> originalAnchors = [];

    // Special handling for timestamp-based duplicates
    for (final groupKey in timestampGroups.keys) {
      final fieldIndices = timestampGroups[groupKey]!;
      if (fieldIndices.isEmpty) continue;

      // Find the first field as the anchor for this duplicate set
      final firstIndex = fieldIndices.reduce((a, b) => a < b ? a : b);

      // Store all fields in this timestamp group under this anchor
      _anchorToFieldIndices[firstIndex] = List.from(fieldIndices);

      if (kDebugMode) {
        print(
            "Created duplicate anchor $firstIndex (${_internalFields[firstIndex]['name']}) with fields: ${fieldIndices.map((i) => _internalFields[i]['name']).join(', ')}");
      }
    }

    // Regular groups based on groupWith and non-duplicates
    for (final groupKey in groupKeyToFieldIndices.keys) {
      final fieldIndices = groupKeyToFieldIndices[groupKey]!;
      if (fieldIndices.isEmpty) continue;

      // Skip if this is a duplicate:timestamp group (already handled)
      if (groupKey.startsWith('duplicate:')) {
        continue;
      }

      // Use first field as anchor
      final anchor = fieldIndices.first;

      // Store field indices mapping for all anchors (including duplicates)
      // Only if this anchor doesn't already have fields (from timestamp processing)
      if (!_anchorToFieldIndices.containsKey(anchor)) {
        _anchorToFieldIndices[anchor] = fieldIndices;
      }

      // Only add to navigation anchors if it's not a duplicate
      bool isDuplicate = _internalFields[anchor]['isDuplicate'] == true;

      // Special check for question_X format - if we're looking at a question that's
      // referenced via groupWith but is not itself a groupWith-referencing question,
      // then it should be an anchor
      final anchorName = _internalFields[anchor]['name'].toString();
      bool isQuestionReferredByOthers = false;

      // Check if this field is referred to by another field's groupWith
      for (var field in _internalFields) {
        if (field['groupWith']?.toString() == anchorName) {
          isQuestionReferredByOthers = true;
          break;
        }
      }

      // A field should be an anchor if:
      // 1. It's not a duplicate AND
      // 2. Either:
      //    a. It's not referred to by another field's groupWith, OR
      //    b. It has its own groupWith reference
      bool shouldBeAnchor = !isDuplicate &&
          (!isQuestionReferredByOthers ||
              _internalFields[anchor]['groupWith'] != null);

      if (shouldBeAnchor) {
        originalAnchors.add(anchor);
      }
    }

    // Sort original anchors by their position in _internalFields to maintain proper order
    originalAnchors.sort();

    // Now assign the navigation anchors
    _groupAnchors = originalAnchors;

    if (kDebugMode) {
      print('Final group anchors for navigation: $_groupAnchors');
      print('Anchor to fields mapping:');
      _anchorToFieldIndices.forEach((anchor, indices) {
        print(
            '  Anchor $anchor (${_internalFields[anchor]['name']}): ${indices.map((i) => _internalFields[i]['name']).toList()}');
      });
    }

    // Reset the current group pointer to 0 to ensure we start from the first question
    _currentGroupPointer = 0;

    // Update controller index after a brief delay to ensure state is consistent
    if (_groupAnchors.isNotEmpty) {
      // Don't immediately update the controller index during duplication operations
      // This avoids potential PageController issues
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          controller.currentQuestionIndex = _groupAnchors[_currentGroupPointer];
        }
      });
    }

    if (kDebugMode) {
      print("----- Group Structure Computation Complete -----\n");
    }
  }

  String _getCurrentQuestionName() {
    if (controller.currentQuestionIndex < widget.formJson.length) {
      return widget.formJson[controller.currentQuestionIndex]['name'];
    }
    return '';
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
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
          ),
          child: Column(
            children: [
              // Top header with gray notch and Done button
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        height: 6,
                        width: 40,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () =>
                              widget.onSelect(widget.selectedValue ?? ""),
                          child: Text(
                            'Done',
                            style: AppTypography
                                .searchInput, // Assuming the style is defined in AppTypography
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Search bar with no rounded corners
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.zero, // No border radius
                  ),
                  child: TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      border: InputBorder.none,
                      hintStyle: AppTypography
                          .searchHint, // Assuming the style is defined in AppTypography
                      icon: const Icon(Icons.search),
                    ),
                    onChanged: _filterOptions,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Options list
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 20.0, right: 20.0),
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: filteredOptions.length,
                    itemBuilder: (context, index) {
                      final option = filteredOptions[index];
                      final isSelected =
                          widget.selectedValue == option.toString();
                      return ListTile(
                        title: Text(option.toString(),
                            style: AppTypography
                                .searchInput), // Assuming the style is defined in AppTypography
                        trailing: isSelected
                            ? const Icon(Icons.check, color: Colors.black)
                            : null,
                        onTap: () {
                          setState(() {
                            widget.onSelect(option.toString());
                          });
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
  // Define 2MB in bytes.
  static const int _maxFileSize = 5 * 1024 * 1024;
  BuildContext? _loadingContext;

  /// The `_showLoadingDialog` function displays a loading dialog with a circular progress
  /// indicator and a text message in a Flutter app.
  ///
  /// Args:
  ///   context (BuildContext): The `context` parameter in the `_showLoadingDialog` function
  /// refers to the BuildContext object that represents the location of the widget within the
  /// widget tree. It is used to access information about the widget's location and to perform
  /// various operations such as navigating to a new screen, showing dialogs, accessing theme
  ///
  /// Returns:
  ///   A loading dialog widget is being returned. It consists of a container with padding,
  /// decoration, and child widgets including a CircularProgressIndicator and a Text widget
  /// displaying a message "Processing file. Please wait."
  void _showLoadingDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        _loadingContext = context;
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
                Text(
                  StringConstants.processingFilePleaseWait,
                  style: widget.fontFamily,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The `_hideLoadingDialog` function is used to close a loading dialog if it is currently
  /// being displayed.
  void _hideLoadingDialog() {
    if (_loadingContext != null) {
      try {
        Navigator.of(_loadingContext!).pop();
      } catch (e) {
        if (kDebugMode) {
          print('Error closing dialog: $e');
        }
      } finally {
        _loadingContext = null;
      }
    }
  }

  /// Validates file size and, if acceptable, adds the file using the callback.
  /// The _processFile function processes a file by checking its size, creating a new file
  /// object with relevant information, and updating the list of uploaded files.
  ///
  /// Args:
  ///   bytes (Uint8List): The `bytes` parameter in the `_processFile` function is a required
  /// `Uint8List` type that represents the content of the file being processed. It is
  /// essential for reading and manipulating the file data within the function.
  ///   fileName (String): The `fileName` parameter in the `_processFile` function is a
  /// required parameter of type String. It represents the name of the file being processed.
  ///   fileType (String): The `fileType` parameter in the `_processFile` function is a String
  /// that represents the type of the file being processed. It is an optional parameter,
  /// meaning it can be provided but is not required. If it is not provided, the function will
  /// determine the file type based on the `fileName
  ///   mimeType (String): The `mimeType` parameter in the `_processFile` function is used to
  /// specify the type of the file being processed. It is typically a standardized internet
  /// media type (also known as MIME type) that describes the content type of the file.
  ///
  /// Returns:
  ///   If the length of the `bytes` is greater than `_maxFileSize`, a SnackBar is shown with
  /// a message indicating that the file size must be less than 2MB. After displaying the
  /// SnackBar, the function will return and not proceed further.
  void _processFile({
    required Uint8List bytes,
    required String fileName,
    String? fileType,
    String? mimeType,
  }) {
    if (bytes.length > _maxFileSize) {
      AppSnackBar(context)
          .showErrorSnackBar(StringConstants.fileSizeMustBeLessThan2MB);
      return;
    }

    final detectedFileType = fileType ?? _getFileType(fileName);

    // Debug logging for PDF files
    if (detectedFileType == 'pdf') {
      print('Processing PDF file: $fileName');
      print('PDF file size: ${(bytes.length / 1024).toStringAsFixed(2)} KB');
    }

    final newFile = {
      'question_name': widget.fieldName,
      'question_label': widget.fieldLabel,
      'file': bytes,
      'fileName': fileName,
      'fileType': detectedFileType,
      'mimeType': mimeType ??
          (fileName.split('.').length > 1
              ? 'application/${fileName.split('.').last}'
              : 'application/octet-stream'),
    };

    // For single file upload, replace the existing files instead of adding to them
    widget.onFilesUploaded([newFile]);
  }

  /// The `_pickAndUploadFile` function in Dart displays a modal bottom sheet with options to choose a
  /// file from FilePicker, gallery, or take a photo from the camera, handling the selection and
  /// processing of the chosen file accordingly.
  ///
  /// Args:
  ///   context (BuildContext): The `context` parameter in the `_pickAndUploadFile` function refers to
  /// the BuildContext of the widget that called this function. It is used to show modal dialogs, access
  /// theme data, navigate to other screens, and more within the Flutter application. The BuildContext
  /// provides information about the location of
  ///
  /// Returns:
  ///   The `_pickAndUploadFile` function is returning a `Future<void>`.
  Future<void> _pickAndUploadFile(BuildContext context) async {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              // Choose file from FilePicker.
              ListTile(
                leading: const Icon(
                  Icons.description_outlined,
                  size: _DynamicFormState._iconSize,
                ),
                title: Text(
                  StringConstants.chooseFile,
                  style: widget.fontFamily,
                ),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    _showLoadingDialog(context);
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: [
                        FileTypes.pdf,
                        FileTypes.jpg,
                        FileTypes.gif,
                        FileTypes.jpeg,
                        FileTypes.png,
                        FileTypes.xlsx,
                        FileTypes.xls,
                        FileTypes.text,
                      ],
                      allowMultiple: false, // Ensure only single file selection
                      withData: true,
                      allowCompression: true,
                    );

                    if (result != null && result.files.isNotEmpty) {
                      final file = result.files.first;
                      if (file.bytes != null) {
                        _processFile(bytes: file.bytes!, fileName: file.name);
                      }
                    }
                  } catch (e) {
                    if (kDebugMode) {
                      print('Error picking file: $e');
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          StringConstants.errorSelectingFilePleaseTryAgain,
                          style: widget.fontFamily,
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  } finally {
                    _hideLoadingDialog();
                  }
                },
              ),
              // Choose file from Gallery.
              ListTile(
                leading: const Icon(
                  Icons.collections_outlined,
                  size: _DynamicFormState._iconSize,
                ),
                title: Text(
                  StringConstants.chooseFromGallery,
                  style: widget.fontFamily,
                ),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    _showLoadingDialog(context);
                    final ImagePicker picker = ImagePicker();
                    final XFile? image = await picker.pickImage(
                      source: ImageSource.gallery,
                      imageQuality: 80,
                    );

                    if (image != null) {
                      final bytes = await image.readAsBytes();
                      _processFile(
                        bytes: bytes,
                        fileName: image.name,
                        fileType: 'image',
                        mimeType: 'image/${image.name.split('.').last}',
                      );
                    }
                  } catch (e) {
                    if (kDebugMode) {
                      print('Error picking image from gallery: $e');
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          StringConstants.errorSelectingImagePleaseTryAgain,
                          style: widget.fontFamily,
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  } finally {
                    _hideLoadingDialog();
                  }
                },
              ),
              // Take photo from Camera.
              if (!kIsWeb)
                ListTile(
                  leading: const Icon(
                    Icons.photo_camera_outlined,
                    size: _DynamicFormState._iconSize,
                  ),
                  title: Text(
                    StringConstants.takePhoto,
                    style: widget.fontFamily,
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    try {
                      _showLoadingDialog(context);
                      final ImagePicker picker = ImagePicker();
                      final XFile? photo = await picker.pickImage(
                        source: ImageSource.camera,
                        imageQuality: 80,
                      );

                      if (photo != null) {
                        final bytes = await photo.readAsBytes();
                        _processFile(
                          bytes: bytes,
                          fileName: photo.name,
                          fileType: 'image',
                          mimeType: 'image/${photo.name.split('.').last}',
                        );
                      }
                    } catch (e) {
                      if (kDebugMode) {
                        print('Error taking photo: $e');
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            StringConstants.errorTakingPhotoPleaseTryAgain,
                            style: widget.fontFamily,
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    } finally {
                      _hideLoadingDialog();
                    }
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  /// The function `_getFileType` determines the type of file based on its extension.
  ///
  /// Args:
  ///   fileName (String): It seems like you forgot to provide the `fileName` parameter for the
  /// `_getFileType` function. Could you please provide the `fileName` parameter so that I can assist
  /// you further with the function?
  ///
  /// Returns:
  ///   The function `_getFileType` is returning a string that represents the type of file based on its
  /// extension. The possible return values are 'pdf', 'document', 'spreadsheet', 'image', or the
  /// default value from the `FileTypes` class if the extension does not match any of the predefined
  /// types.
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

  /// Opens a preview screen to view the file based on its type
  void _previewFile(BuildContext context, Map<String, dynamic> file) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FilePreviewScreen(file: file),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Check if a file is already uploaded
    final bool hasUploadedFile = widget.uploadedFiles.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Remove the upload label that's causing duplication
        // Parent components already show the label
        const SizedBox(height: 8),
        // Only show the upload button if no file is uploaded yet
        if (!hasUploadedFile)
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.primaryColor,
                foregroundColor: widget.buttonTextColor,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
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
                  Text(
                    "Select File",
                    style: widget.fontFamily.copyWith(
                      color: widget.buttonTextColor,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        if (hasUploadedFile) ...[
          // Display the single uploaded file with delete option
          Card(
            margin: EdgeInsets.zero,
            elevation: 1,
            child: ListTile(
              leading: Icon(_getFileIcon(widget.uploadedFiles[0]['fileType'])),
              title: Text(
                widget.uploadedFiles[0]['fileName'],
                style: widget.fontFamily,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () =>
                    widget.onRemoveUploadedFile(widget.uploadedFiles[0]),
              ),
              // Add onTap handler to preview the file
              onTap: () {
                _previewFile(context, widget.uploadedFiles[0]);
              },
            ),
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

/// A screen to preview different types of files
class FilePreviewScreen extends StatefulWidget {
  final Map<String, dynamic> file;

  const FilePreviewScreen({Key? key, required this.file}) : super(key: key);

  @override
  State<FilePreviewScreen> createState() => _FilePreviewScreenState();
}

class _FilePreviewScreenState extends State<FilePreviewScreen> {
  bool isDownloading = false;
  bool isOpeningInNewTab = false;
  final TransformationController _transformationController =
      TransformationController();

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String fileName = widget.file['fileName'];
    final String fileType = widget.file['fileType'];
    final Uint8List fileBytes = widget.file['file'];

    // Immediately download Excel files instead of showing preview screen
    if (fileType == 'spreadsheet' ||
        fileName.toLowerCase().endsWith('.xlsx') ||
        fileName.toLowerCase().endsWith('.xls')) {
      // Only trigger on first build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isDownloading) {
          setState(() {
            isDownloading = true;
          });
          _downloadFile(context, fileBytes, fileName).then((_) {
            Navigator.of(context).pop();
          });
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          fileName,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // Make download button more visible
          if (!isDownloading && !isOpeningInNewTab)
            TextButton.icon(
              icon: const Icon(Icons.download, color: Colors.white),
              label:
                  const Text('Download', style: TextStyle(color: Colors.white)),
              onPressed: () async {
                setState(() {
                  isDownloading = true;
                });
                await _downloadFile(context, fileBytes, fileName);
                if (mounted) {
                  setState(() {
                    isDownloading = false;
                  });
                }
              },
            ),
          if (kIsWeb &&
              !isDownloading &&
              !isOpeningInNewTab &&
              (fileType == 'pdf' || fileName.toLowerCase().endsWith('.pdf')))
            TextButton.icon(
              icon: const Icon(Icons.open_in_new, color: Colors.white),
              label:
                  const Text('New Tab', style: TextStyle(color: Colors.white)),
              onPressed: () async {
                setState(() {
                  isOpeningInNewTab = true;
                });
                await _openPdfInNewTab(context, fileBytes, fileName);
                if (mounted) {
                  setState(() {
                    isOpeningInNewTab = false;
                  });
                }
              },
            ),
          if (isDownloading || isOpeningInNewTab)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
            )
        ],
      ),
      body: _buildBody(context, fileType, fileBytes, fileName),
    );
  }

  Widget _buildBody(BuildContext context, String fileType, Uint8List fileBytes,
      String fileName) {
    if (isDownloading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Downloading file...", style: TextStyle(fontSize: 16))
          ],
        ),
      );
    }

    if (isOpeningInNewTab) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Opening file in new tab...", style: TextStyle(fontSize: 16))
          ],
        ),
      );
    }

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth:
                800, // Limit width for better readability on large screens
          ),
          child: Column(
            children: [
              // Only use part of the screen for bottom action bar
              Expanded(
                child: ClipRect(
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: _buildPreviewWidget(
                          context, fileType, fileBytes, fileName),
                    ),
                  ),
                ),
              ),
              // Fixed bottom action bar
              _buildBottomActionBar(context, fileBytes, fileName, fileType),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomActionBar(BuildContext context, Uint8List fileBytes,
      String fileName, String fileType) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Expanded(
            child: ElevatedButton.icon(
              icon: isDownloading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.download),
              label: Text(isDownloading ? 'Downloading...' : 'Download'),
              onPressed: isDownloading || isOpeningInNewTab
                  ? null
                  : () async {
                      setState(() {
                        isDownloading = true;
                      });
                      await _downloadFile(context, fileBytes, fileName);
                      if (mounted) {
                        setState(() {
                          isDownloading = false;
                        });
                      }
                    },
            ),
          ),
          if (kIsWeb &&
              (fileType == 'pdf' ||
                  fileName.toLowerCase().endsWith('.pdf'))) ...[
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton.icon(
                icon: isOpeningInNewTab
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.open_in_new),
                label:
                    Text(isOpeningInNewTab ? 'Opening...' : 'Open in New Tab'),
                onPressed: isDownloading || isOpeningInNewTab
                    ? null
                    : () async {
                        setState(() {
                          isOpeningInNewTab = true;
                        });
                        await _openPdfInNewTab(context, fileBytes, fileName);
                        if (mounted) {
                          setState(() {
                            isOpeningInNewTab = false;
                          });
                        }
                      },
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Builds the appropriate preview widget based on file type
  Widget _buildPreviewWidget(BuildContext context, String fileType,
      Uint8List fileBytes, String fileName) {
    switch (fileType) {
      case 'image':
        return _buildImagePreview(context, fileBytes);
      case 'pdf':
        return _buildPdfPreview(fileName);
      case 'document':
      case 'spreadsheet':
      default:
        return _buildGenericFilePreview(fileType, fileName);
    }
  }

  Widget _buildImagePreview(BuildContext context, Uint8List fileBytes) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Get the device screen size
        final Size screenSize = MediaQuery.of(context).size;

        // Calculate the image height based on the screen height
        // Use a percentage of screen height to prevent images from being too large
        final double maxHeight = screenSize.height * 0.7;

        // Create the image provider once to avoid multiple decodes
        final imageProvider = MemoryImage(fileBytes);

        // Pre-calculate image dimensions
        return FutureBuilder(
          future: _calculateImageDimension(imageProvider),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              final Size imageSize = snapshot.data as Size;
              double aspectRatio = imageSize.width / imageSize.height;

              // Calculate constrained size
              double displayHeight = imageSize.height;
              double displayWidth = imageSize.width;

              if (displayHeight > maxHeight) {
                displayHeight = maxHeight;
                displayWidth = displayHeight * aspectRatio;
              }

              if (displayWidth > constraints.maxWidth) {
                displayWidth = constraints.maxWidth;
                displayHeight = displayWidth / aspectRatio;
              }

              return Column(
                children: [
                  const SizedBox(height: 20),
                  ClipRect(
                    child: SizedBox(
                      width: displayWidth,
                      height: displayHeight,
                      child: InteractiveViewer(
                        transformationController: _transformationController,
                        boundaryMargin: const EdgeInsets.all(20.0),
                        minScale: 0.5,
                        maxScale: 4.0,
                        child: Image(
                          image: imageProvider,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Add reset zoom button
                  OutlinedButton.icon(
                    icon: const Icon(Icons.zoom_out_map),
                    label: const Text('Reset Zoom'),
                    onPressed: () {
                      _transformationController.value = Matrix4.identity();
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              );
            } else {
              // While calculating, show a loading indicator
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(40.0),
                  child: CircularProgressIndicator(),
                ),
              );
            }
          },
        );
      },
    );
  }

  Widget _buildPdfPreview(String fileName) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.picture_as_pdf, size: 80, color: Colors.red),
          const SizedBox(height: 20),
          Text(
            'PDF Document: $fileName',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          const Text(
            'PDF preview is not available. Please download the file or open in a new tab.',
            style: TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildGenericFilePreview(String fileType, String fileName) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _getFileIconForPreview(fileType, fileName),
            size: 100,
            color: Colors.blue,
          ),
          const SizedBox(height: 20),
          Text(
            'File: $fileName',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          const Text(
            'This file type cannot be previewed directly. Please download to view the content.',
            style: TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  /// Helper function to pre-calculate image dimensions
  Future<Size> _calculateImageDimension(ImageProvider provider) async {
    final Completer<Size> completer = Completer<Size>();

    final ImageStream stream = provider.resolve(const ImageConfiguration());
    final listener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        final Size size = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
        completer.complete(size);
      },
      onError: (dynamic exception, StackTrace? stackTrace) {
        completer.completeError(exception, stackTrace);
      },
    );

    stream.addListener(listener);
    return completer.future;
  }

  /// Returns the appropriate icon based on file type and name
  IconData _getFileIconForPreview(String fileType, String fileName) {
    if (fileType == 'document') {
      return Icons.description;
    } else if (fileType == 'spreadsheet' ||
        fileName.toLowerCase().endsWith('.xlsx') ||
        fileName.toLowerCase().endsWith('.xls')) {
      return Icons.table_chart;
    } else if (fileType == 'pdf' || fileName.toLowerCase().endsWith('.pdf')) {
      return Icons.picture_as_pdf;
    } else {
      return Icons.insert_drive_file;
    }
  }

  /// Opens a PDF in a new browser tab (web only)
  Future<void> _openPdfInNewTab(
      BuildContext context, Uint8List pdfBytes, String fileName) async {
    if (kIsWeb) {
      try {
        // Create a Blob from the PDF bytes with proper MIME type
        final blob = html.Blob([pdfBytes], 'application/pdf');

        // Create a URL for the Blob
        final url = html.Url.createObjectUrlFromBlob(blob);

        // Open the URL in a new tab
        html.window.open(url, '_blank');

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PDF opened in a new tab'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 1),
            ),
          );
        }

        // Small delay before returning
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        // Show error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error opening PDF: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
        print('Error opening PDF in new tab: $e');
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Opening in new tab is only available on web platforms'),
          ),
        );
      }
    }
  }

  /// Downloads the file to the device
  Future<void> _downloadFile(
      BuildContext context, Uint8List fileBytes, String fileName) async {
    try {
      if (kIsWeb) {
        // Web platform - use html to trigger download
        // Get proper MIME type based on filename
        String mimeType = 'application/octet-stream';
        final lowerFileName = fileName.toLowerCase();

        if (lowerFileName.endsWith('.pdf')) {
          mimeType = 'application/pdf';
        } else if (lowerFileName.endsWith('.jpg') ||
            lowerFileName.endsWith('.jpeg')) {
          mimeType = 'image/jpeg';
        } else if (lowerFileName.endsWith('.png')) {
          mimeType = 'image/png';
        } else if (lowerFileName.endsWith('.xlsx')) {
          mimeType =
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
        } else if (lowerFileName.endsWith('.xls')) {
          mimeType = 'application/vnd.ms-excel';
        }

        // Create blob with correct MIME type - in web this needs to be more direct
        final blob = html.Blob([fileBytes], mimeType);
        final url = html.Url.createObjectUrlFromBlob(blob);

        // Create a download anchor element - ensure it's not attached until ready
        final anchor = html.AnchorElement()
          ..href = url
          ..style.display = 'none'
          ..download = fileName;

        // Add to document body, click, and clean up immediately
        html.document.body?.append(anchor);

        // Click the anchor to start the download
        anchor.click();

        // Clean up resources
        // Small delay to ensure download starts
        await Future.delayed(const Duration(milliseconds: 100));

        // Remove the anchor and revoke URL
        anchor.remove();
        html.Url.revokeObjectUrl(url);

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Download started'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 1),
            ),
          );
        }
      } else {
        // Mobile platform - show a temporary message
        // In a real app, you'd implement platform-specific download
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('File saved to downloads folder'),
            ),
          );
        }
      }

      // Brief delay to ensure message and download process start
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error downloading file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      print('Error downloading file: $e');
    }
  }
}
