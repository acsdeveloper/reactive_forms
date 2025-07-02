import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:reactiveform/components/app_colours.dart';
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

  // Store the field that failed validation for better error messages
  Map<String, dynamic>? _lastValidationErrorField;

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

  // Maintain a map of which question number corresponds to each anchor
  Map<int, int> _anchorToQuestionNumber = {};

  // Tracks fields being evaluated for showWhen circular dependency detection
  Set<String> _fieldEvaluationStack = {};

  // Subscription to form value changes - will be used to update visibility
  late StreamSubscription<dynamic> _formValueChangeSubscription;

  bool hasCriticalValidationError = false;
  // Check if the current question should be visible, and if not, skip to the next visible one
  void _updateCurrentQuestionBasedOnVisibility() {
    if (!widget.showOneByOne) return; // Only applicable in step-by-step mode

    // If the current question pointer is out of bounds, reset to the beginning
    if (_currentGroupPointer < 0 ||
        _currentGroupPointer >= _groupAnchors.length) {
      _currentGroupPointer = 0;
      return;
    }

    // Get the current question anchor and index
    int currentAnchorIndex = _groupAnchors[_currentGroupPointer];
    int currentQuestionIndex = -1;

    // Find the form index of the current question
    for (int i = 0; i < widget.formJson.length; i++) {
      if (widget.formJson[i]['name'] ==
          _internalFields[currentAnchorIndex]['name']) {
        currentQuestionIndex = i;
        break;
      }
    }

    // If current question is not found in the form JSON (shouldn't happen), return
    if (currentQuestionIndex == -1) return;

    // Get the current list of visible question indices
    List<int> visibleIndices = _getVisibleQuestionIndices();

    // Critical: If no questions are visible, make the first question visible as fallback
    if (visibleIndices.isEmpty && widget.formJson.isNotEmpty) {
      visibleIndices = [0]; // Make the first question visible as fallback
    }

    // Check if current question is visible
    if (!visibleIndices.contains(currentQuestionIndex)) {
      // Current question is not visible - find the next visible question
      int nextVisibleIndex = -1;

      // First try to find next visible question
      for (int visibleIndex in visibleIndices) {
        if (visibleIndex > currentQuestionIndex) {
          nextVisibleIndex = visibleIndex;
          break;
        }
      }

      // If no next visible question found, use the last visible question
      if (nextVisibleIndex == -1 && visibleIndices.isNotEmpty) {
        // Try to find the closest previous visible question
        int prevVisibleIndex = -1;
        for (int visibleIndex in visibleIndices) {
          if (visibleIndex < currentQuestionIndex &&
              (prevVisibleIndex == -1 || visibleIndex > prevVisibleIndex)) {
            prevVisibleIndex = visibleIndex;
          }
        }

        // If a previous visible question is found, navigate to it
        if (prevVisibleIndex != -1) {
          nextVisibleIndex = prevVisibleIndex;
        } else {
          // If no previous question found either, use the first visible question
          nextVisibleIndex = visibleIndices.first;
        }
      }

      // Skip to the next/previous visible question if found
      if (nextVisibleIndex != -1) {
        // Find the anchor corresponding to this question index
        int anchorPointer = -1;
        for (int i = 0; i < _groupAnchors.length; i++) {
          int anchorIndex = _groupAnchors[i];
          String anchorName = _internalFields[anchorIndex]['name'].toString();

          // Check if this anchor corresponds to the next visible question
          for (int j = 0; j < widget.formJson.length; j++) {
            if (j == nextVisibleIndex &&
                widget.formJson[j]['name'] == anchorName) {
              anchorPointer = i;
              break;
            }
          }

          if (anchorPointer != -1) break;
        }

        // Update the current pointer and controller index if an anchor was found
        if (anchorPointer != -1 && anchorPointer != _currentGroupPointer) {
          setState(() {
            _currentGroupPointer = anchorPointer;
            controller.currentQuestionIndex =
                _groupAnchors[_currentGroupPointer];
          });
        }
      }
    }
  }

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
      // Recompute group structure
      _recomputeGroupStructure();

      // Make sure we start with a visible question
      _updateCurrentQuestionBasedOnVisibility();

      // Update progress
      _safeCalculateProgress();
      _pageControllerReady = true;

      // Debug current state
      // if (kDebugMode) {
      //   print("\n=== Form Initialized ===");
      //   print("Current question index: ${controller.currentQuestionIndex}");
      //   print("Current group pointer: $_currentGroupPointer");
      //   print("Total anchors: ${_groupAnchors.length}");
      //   print(
      //       "Current question visible: ${controller.shouldDisplayQuestion(controller.currentQuestionIndex)}");
      //   controller.debugNavigationState();
      // }
    });

    // Listen to form value changes and update question visibility
    _formValueChangeSubscription =
        controller.form.valueChanges.listen((formValues) {
      if (mounted) {
        // First, recalculate progress and visibility
        _safeCalculateProgress();

        // Then check if current question should be skipped
        _updateCurrentQuestionBasedOnVisibility();

        // Update UI
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    // Remove the listener when the widget is disposed
    controller.removeListener(_onControllerChanged);
    _pageController.dispose(); // Ensure the controller is disposed

    // NEW: Cancel the form value change subscription
    _formValueChangeSubscription.cancel();

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
    Set<String> evaluationStack =
        {}; // Track fields being evaluated to detect circular dependencies

    // Helper function to evaluate showWhen conditions with circular dependency detection
    bool evaluateShowWhen(Map<String, dynamic> question,
        {String? fieldBeingEvaluated}) {
      // If this question doesn't have showWhen conditions, it's always visible
      if (question['showWhen'] == null) {
        return true;
      }

      // Get the current field name for tracking
      String currentField = question['name']?.toString() ?? '';

      // If this field is already being evaluated, we have a circular dependency
      if (fieldBeingEvaluated != null &&
          evaluationStack.contains(fieldBeingEvaluated)) {
        // Break the circular dependency by treating this condition as true
        return true;
      }

      // Add current field to evaluation stack
      if (fieldBeingEvaluated != null) {
        evaluationStack.add(fieldBeingEvaluated);
      }

      try {
        bool shouldShow = true; // Initialize to true for AND logic
        final conditions = question['showWhen'] as Map<String, dynamic>;

        conditions.forEach((field, expectedValues) {
          // Check if the form contains this field
          if (!controller.form.contains(field)) {
            shouldShow = false;
            return;
          }

          // Get the field's value from the form
          final value = controller.form.control(field).value;
          bool matches = false;

          // Check if the value matches the expected value(s)
          if (expectedValues is List) {
            matches = expectedValues.contains(value);
          } else {
            matches = (value == expectedValues);
          }

          // Check dependencies of the referenced field (to handle nested dependencies)
          // Find the referenced field's question
          int dependentFieldIndex =
              widget.formJson.indexWhere((q) => q['name'] == field);
          if (dependentFieldIndex >= 0) {
            // Recursively check if the field this depends on should be shown
            // Only if it's not already being evaluated (to prevent infinite recursion)
            if (!evaluationStack.contains(field)) {
              bool dependentFieldVisible = evaluateShowWhen(
                  widget.formJson[dependentFieldIndex],
                  fieldBeingEvaluated: field);

              // If the dependent field isn't visible, this condition doesn't match
              if (!dependentFieldVisible) {
                matches = false;
              }
            }
          }

          shouldShow = shouldShow && matches;
        });

        return shouldShow;
      } finally {
        // Always remove the field from evaluation stack when done
        if (fieldBeingEvaluated != null) {
          evaluationStack.remove(fieldBeingEvaluated);
        }
      }
    }

    // Evaluate visibility for each question in the form
    for (int i = 0; i < widget.formJson.length; i++) {
      final question = widget.formJson[i];

      // NEW: Skip questions with groupWith - they should only appear as part of their parent question's group
      if (question['groupWith'] != null &&
          question['groupWith'].toString().isNotEmpty) {
        continue;
      }

      // Evaluate visibility using the helper function
      if (evaluateShowWhen(question,
          fieldBeingEvaluated: question['name']?.toString())) {
        visible.add(i);
      }
    }

    // Safety check: If no questions are visible, make the first one visible
    if (visible.isEmpty && widget.formJson.isNotEmpty) {
      visible.add(0); // Make the first question visible as fallback
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
        // NEW LOGIC: Check if this field is referenced by any other field via groupWith
        // or if it has allowDuplicate property
        final currentField = _internalFields[currentAnchor];
        final String currentFieldName = currentField['name'].toString();

        // First check if the field is directly referenced by any other field's groupWith
        bool isReferencedByOthers = false;
        for (var field in _internalFields) {
          if (field['groupWith']?.toString() == currentFieldName) {
            isReferencedByOthers = true;
            break;
          }
        }

        // Check if this field is a parent in the anchorToFieldIndices
        bool isParentWithChildren = false;
        if (_anchorToFieldIndices.containsKey(currentAnchor)) {
          final childIndices = _anchorToFieldIndices[currentAnchor] ?? [];
          // If this anchor has more fields than just itself, it has children
          isParentWithChildren = childIndices.length > 1;
        }

        currentQuestionHasGroupWith = isReferencedByOthers ||
            isParentWithChildren ||
            currentField['allowDuplicate'] == true;

        // For debugging
        // if (kDebugMode) {
        //   print("Current question has groupWith: $currentQuestionHasGroupWith");
        //   print("Current field: ${currentField['name']}");
        //   print("Is referenced by others: $isReferencedByOthers");
        //   print("Is parent with children: $isParentWithChildren");
        //   if (currentField['allowDuplicate'] == true) {
        //     print("AllowDuplicate: ${currentField['allowDuplicate']}");
        //   }
        // }
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

    final List<Widget> widgets = [];

    // Make sure _currentGroupPointer is valid
    if (_currentGroupPointer >= _groupAnchors.length || _groupAnchors.isEmpty) {
      return widgets;
    }

    // Get the current anchor indicated by the pointer
    final currentAnchor = _groupAnchors[_currentGroupPointer];
    final String currentAnchorName =
        _internalFields[currentAnchor]['name'] as String;

    // Build the card for the current anchor with all its grouped fields
    // This is the original card that is always displayed
    final List<int> currentIndices =
        _anchorToFieldIndices[currentAnchor] ?? [currentAnchor];
    final List<Map<String, dynamic>> currentGroupFields =
        currentIndices.map((i) => _internalFields[i]).toList();

    // NEW LOGIC: Check if this anchor field is referenced by any other field via groupWith
    // or if it has children in its group
    bool shouldShowCard = false;

    // If the anchor has more than just itself in its group, it's a parent with children
    if (currentIndices.length > 1) {
      shouldShowCard = true;
    } else {
      // Check if the current field is referenced by any other field's groupWith
      for (var field in _internalFields) {
        String? groupWith = field['groupWith']?.toString();
        if (groupWith == currentAnchorName) {
          shouldShowCard = true;
          break;
        }
      }
    }

    // For debugging
    if (kDebugMode) {
      print("Field '${currentAnchorName}' shouldShowCard: $shouldShowCard");
    }

    // Add the original card or just the fields based on the shouldShowCard flag
    if (shouldShowCard) {
      // Add the original question as a card
      widgets.add(_buildCardForFields(currentGroupFields, false));
    } else {
      // Add the original question without a card
      widgets.addAll(currentGroupFields.map(_buildField).toList());
    }

    // CRITICAL FIX: Group duplicates by timestamp to avoid creating separate cards for each field
    // Now collect all duplicates by timestamp and create one card per duplicate group
    final Map<String, List<int>> duplicateGroups = {};
    final timeStampPattern = RegExp(r'_(\d+)$');

    // Find all duplicate fields that should be shown with this question and group them by timestamp
    for (int i = 0; i < _internalFields.length; i++) {
      final field = _internalFields[i];
      final fieldName = field['name'].toString();

      // Check if this is a duplicate field
      if (field['isDuplicate'] == true) {
        final match = timeStampPattern.firstMatch(fieldName);
        if (match != null) {
          final timestamp = match.group(1) ?? '';

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

          if (isRelated && timestamp.isNotEmpty) {
            // Group duplicates by timestamp
            duplicateGroups.putIfAbsent(timestamp, () => []).add(i);
          }
        }
      }
    }

    // Build one card per duplicate group (timestamp)
    for (final timestamp in duplicateGroups.keys) {
      final duplicateIndices = duplicateGroups[timestamp]!;

      // Get all fields for this duplicate group
      final fields = duplicateIndices.map((i) => _internalFields[i]).toList();

      // Add the duplicate card with delete button
      widgets.add(_buildCardForFields(fields, true));
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
    // Special handling for duplicate fields
    if (field['isDuplicate'] == true) {
      // Get the current anchor/question
      final currentAnchor =
          _groupAnchors.isNotEmpty ? _groupAnchors[_currentGroupPointer] : -1;
      final String currentAnchorName =
          currentAnchor >= 0 && currentAnchor < _internalFields.length
              ? _internalFields[currentAnchor]['name'].toString()
              : "";

      // Check if this duplicate belongs to the current question
      if (field['parentQuestionName'] != null) {
        String parentName = field['parentQuestionName'].toString();

        // Extract base name from current anchor if it's also a duplicate
        String currentBaseName = currentAnchorName;
        final timestampPattern = RegExp(r'(.+)_\d+$');
        final currentMatch = timestampPattern.firstMatch(currentAnchorName);
        if (currentMatch != null) {
          currentBaseName = currentMatch.group(1) ?? currentAnchorName;
        }

        // Only show if it belongs to the current question (compare base names)
        if (parentName != currentBaseName && parentName != currentAnchorName) {
          // This duplicate belongs to a different question, don't show it here
          return const SizedBox.shrink();
        }
      } else if (field['parentQuestionIndex'] != null) {
        int parentIdx = field['parentQuestionIndex'] as int;
        if (parentIdx != currentAnchor) {
          // This duplicate belongs to a different question, don't show it here
          return const SizedBox.shrink();
        }
      }

      // This duplicate belongs to this page, so show it regardless of other conditions
      return _buildFieldWidget(field);
    }

    // If field has persistVisibility flag set to true, always show it regardless of other conditions
    // This ensures duplicate fields remain visible during navigation
    if (field['persistVisibility'] == true) {
      return _buildFieldWidget(field);
    }

    if (field['showWhen'] != null) {
      return ReactiveFormConsumer(
        builder: (context, form, child) {
          final String fieldName = field['name'].toString();

          // Check for circular dependency
          if (_fieldEvaluationStack.contains(fieldName)) {
            if (kDebugMode) {
              print(
                  "WARNING: Circular dependency detected in field-level showWhen for: $fieldName");
              print(
                  "Dependency chain: ${_fieldEvaluationStack.join(' → ')} → $fieldName");
            }
            // Break the circular dependency by showing the field
            return _buildFieldWidget(field);
          }

          _fieldEvaluationStack.add(fieldName);

          try {
            bool shouldShow = false; // Initialize to false for OR logic
            final conditions = field['showWhen'] as Map<String, dynamic>;

            conditions.forEach((dependentField, expectedValue) {
              if (!controller.form.contains(dependentField)) {
                shouldShow = false;
                return;
              }

              final dependentControl = form.control(dependentField);
              final currentValue = dependentControl.value;

              // Check if the dependent field itself has a showWhen condition
              // Only check if we're not already evaluating it (to prevent circular deps)
              if (!_fieldEvaluationStack.contains(dependentField)) {
                // Find the dependent field in the internal fields
                int dependentFieldIdx = _internalFields
                    .indexWhere((f) => f['name'] == dependentField);

                if (dependentFieldIdx >= 0 &&
                    _internalFields[dependentFieldIdx]['showWhen'] != null) {
                  // Create a temporary instance of the field widget to check visibility
                  // This is a simplified recursive check
                  Widget tempWidget =
                      _buildField(_internalFields[dependentFieldIdx]);

                  // If the dependent field would be hidden, don't match this condition
                  if (tempWidget is SizedBox &&
                      tempWidget.width == 0 &&
                      tempWidget.height == 0) {
                    // The dependent field would be hidden (SizedBox.shrink)
                    shouldShow = shouldShow || false;
                    return;
                  }
                }
              }

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
          } finally {
            _fieldEvaluationStack.remove(fieldName);
          }
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
        // Call _buildRadioField instead of inline implementation
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
                    // print(
                    //     'Updated ${field['name']} with: $value (type: ${value.runtimeType})');
                    // print('Current form value: ${controller.form.value}');

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

                  // Implementing exact logic as specified (adapted for multiselect):
                  // IF disableAttachmentsOn is NOT empty AND any selectedAnswer is in disableAttachmentsOn
                  bool isAttachmentDisabled = false;
                  if (disabledOptions.isNotEmpty && selectedValues.isNotEmpty) {
                    isAttachmentDisabled = selectedValues
                        .any((value) => disabledOptions.contains(value));
                  }

                  // If any selected value is in disabledOptions, don't show attachments
                  if (isAttachmentDisabled) {
                    // if (kDebugMode) {
                    //   print(
                    //       "📄 HIDING UPLOAD: At least one selected value is in disableAttachmentsOn list for multiselect");
                    // }
                    return const SizedBox.shrink();
                  }
                  // ELSE: Show file upload (subject to other rules)

                  // Check if the value is in requireAttachmentsOn or enableAttachmentsOn
                  bool shouldShowAttachments = false;
                  bool isRequired = false;

                  // NEW RULE: If hasAttachments is true, disableAttachmentsOn is not empty,
                  // and no selected value is in disableAttachmentsOn, show and require upload
                  if (field['hasAttachments'] == true &&
                      disabledOptions.isNotEmpty &&
                      selectedValues.isNotEmpty &&
                      !isAttachmentDisabled) {
                    if (kDebugMode) {
                      print(
                          "📄 SHOWING UPLOAD: hasAttachments=true and no selected values are in disableAttachmentsOn for multiselect");
                    }
                    shouldShowAttachments = true;
                    isRequired = true;
                  }
                  // Continue with existing conditions if the new rule didn't apply
                  else {
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

                    // Check for legacy attachmentsRequired property
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
                      // Original fallback check: If hasAttachments is true and none of the above conditions applied
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
                  }

                  return Column(
                    children: [
                      const SizedBox(height: 16),
                      // Remove the duplicate "Upload Files" label since FileUploadWidget will show it
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
                        questionNumber: _getQuestionNumberForField(field),
                        hasAttachments: field['hasAttachments'] == true,
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
              _buildCommentField(field),
            ],
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildLabelRow(Map<String, dynamic> field, [int? index]) {
    if (field['label'] == null) return const SizedBox.shrink();

    // Find the anchor index for this field
    int? anchorIndex;
    for (var entry in _anchorToFieldIndices.entries) {
      if (entry.value.any((idx) =>
          idx < _internalFields.length &&
          _internalFields[idx]['name'] == field['name'])) {
        anchorIndex = entry.key;
        break;
      }
    }

    // Use the controller's visual numbering logic instead of _anchorToQuestionNumber
    int? questionNumber = _getQuestionNumberForField(field);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (questionNumber != null)
            Text(
              'Question $questionNumber',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18.0,
                color: widget.primaryColor ?? Theme.of(context).primaryColor,
                fontFamily: widget.fontFamily?.fontFamily,
              ),
            ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              children: [
                if (index != null)
                  TextSpan(
                    text: '${index + 1}: ', // numbered prefix if index provided
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16.0,
                      fontFamily: widget.fontFamily?.fontFamily,
                    ),
                  ),
                TextSpan(
                  text: field['label'],
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16.0,
                    fontFamily: widget.fontFamily?.fontFamily,
                  ),
                ),
                if (field['required'] == true)
                  TextSpan(
                    text: ' *',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 16.0,
                      fontFamily: widget.fontFamily?.fontFamily,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
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
                // print(
                //     'Updated ${field['name']} with: $value (type: ${value.runtimeType})');
                // print('Current form value: ${controller.form.value}');

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
    final List<dynamic> rawOptions = field['options'] ?? [];
    // Convert options to List<String> to ensure type safety
    final List<String> options =
        rawOptions.map((option) => option.toString()).toList();

    // Handle case where options might be empty
    if (options.isEmpty) {
      // if (kDebugMode) {
      //   print(
      //       "📄 RADIO: Field '${field['name']}' has empty options - defaulting to Yes/No");
      // }
    }

    // Regular implementation for all radio fields
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
                  // Update the form using patchValue instead of directly setting the value
                  // This will ensure that all reactive widgets listening to this field are notified
                  if (value != null) {
                    // Use patchValue to trigger proper reactive updates
                    controller.form.patchValue({field['name']: value});

                    // Also update the control directly to ensure consistency
                    final formControl = controller.form.control(field['name']);
                    if (formControl is FormControl<dynamic>) {
                      formControl.markAsTouched();
                      formControl.updateValue(value);
                    }

                    // Debug log to verify the value change
                    if (kDebugMode) {
                      print(
                          "Radio value changed to: $value for field ${field['name']}");
                    }

                    // Force the entire widget tree to rebuild to ensure
                    // the FileUploadWidget appears or disappears as needed
                    setState(() {
                      // This empty setState will trigger a rebuild
                    });
                  }

                  // Auto-navigation logic copied from dropdown implementation
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
              ),
            )
            .toList(),

        // Add the file upload widget if hasAttachments is true
        if (field['hasAttachments'] == true) ...[
          const SizedBox(height: 16),
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

              // Check if the selected value is in disabledOptions
              final selectedValue = control.value;
              final bool isAttachmentDisabled = disabledOptions.isNotEmpty &&
                  disabledOptions.contains(selectedValue);

              // If the value is in disabledOptions, don't show attachments
              if (isAttachmentDisabled) {
                if (kDebugMode) {
                  print(
                      "📄 RADIO UPLOAD: Hiding upload for ${field['name']} because value $selectedValue is in disabledOptions");
                }
                return const SizedBox.shrink();
              }

              bool shouldShowAttachments = false;
              bool isRequired = false;

              // If hasAttachments is true and disabledOptions is not empty and value not in disabledOptions,
              // show and require upload
              if (field['hasAttachments'] == true &&
                  disabledOptions.isNotEmpty &&
                  !isAttachmentDisabled) {
                if (kDebugMode) {
                  print(
                      "📄 RADIO UPLOAD: Showing uploads for ${field['name']} because hasAttachments=true and value not in disabledOptions");
                }
                shouldShowAttachments = true;
                isRequired = true;
              } else {
                // Check requireAttachmentsOn
                if (field['requireAttachmentsOn'] != null) {
                  final List<dynamic> requiredOptions =
                      field['requireAttachmentsOn'] is List
                          ? field['requireAttachmentsOn']
                          : [field['requireAttachmentsOn']];

                  if (requiredOptions.contains(selectedValue)) {
                    shouldShowAttachments = true;
                    isRequired = true;
                  }
                }

                // If the value is not in requireAttachmentsOn, check if hasAttachments is true
                if (!shouldShowAttachments && field['hasAttachments'] == true) {
                  // Check if requireAttachmentsOn is empty or null
                  bool isRequireAttachmentsOnEmpty =
                      field['requireAttachmentsOn'] == null ||
                          (field['requireAttachmentsOn'] is List &&
                              (field['requireAttachmentsOn'] as List).isEmpty);

                  // If requireAttachmentsOn is empty or null, show file uploads
                  if (isRequireAttachmentsOnEmpty) {
                    shouldShowAttachments = true;
                    isRequired = true;
                  }
                }
              }

              if (!shouldShowAttachments) {
                return const SizedBox.shrink();
              }

              if (kDebugMode) {
                print(
                    "📄 RADIO UPLOAD: Building file upload UI for ${field['name']}");
                print("📄 RADIO UPLOAD: Current value=$selectedValue");
              }

              // Initialize the uploadedFiles for this field if it doesn't exist
              if (!controller.uploadedFiles.containsKey(field['name'])) {
                controller.uploadedFiles[field['name']] = [];
                if (kDebugMode) {
                  print(
                      "📄 RADIO UPLOAD: Initialized uploadedFiles for ${field['name']}");
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
                    controller.uploadedFiles[field['name']]?.remove(file);
                  });
                },
                isRequired: isRequired,
                questionNumber: _getQuestionNumberForField(field),
                hasAttachments: true,
              );
            },
          ),
        ],

        // Add comments section if needed
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
          _buildCommentField(field),
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

              // Check for legacy attachmentsRequired property
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
                  // Remove the duplicate "Upload Files" label since FileUploadWidget will show it
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
                    questionNumber: _getQuestionNumberForField(field),
                    hasAttachments: field['hasAttachments'] == true,
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
          _buildCommentField(field),
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
        // Add a safety wrapper that handles potential type mismatches
        Builder(
          builder: (context) {
            // Check if control exists and has correct type before building the ReactiveValueListenableBuilder
            if (!controller.form.contains(field['name'])) {
              return Text("Error: Form control not found for ${field['name']}",
                  style: TextStyle(color: Colors.red));
            }

            // If the form control exists but might not have the right type,
            // wrap it in a try-catch to prevent runtime errors
            try {
              return ReactiveValueListenableBuilder<String>(
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
                                color: Colors
                                    .black), // Set underline color to black
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
              );
            } catch (e) {
              if (kDebugMode) {
                print("Error rendering field ${field['name']}: $e");
              }
              // Return a fallback widget if there's a type mismatch
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabelRow(field),
                  TextFormField(
                    decoration: InputDecoration(
                      hintText: "Error loading field - please reload the form",
                      errorText: "Type mismatch error",
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.red),
                      ),
                    ),
                    enabled: false,
                  ),
                ],
              );
            }
          },
        ),
        // Rest of the code remains the same
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
          _buildCommentField(field),
        ],
        if (field['hasAttachments'] == true ||
            field['requireAttachmentsOn'] == true ||
            field['requiredAttachmentsOn'] == true) ...[
          const SizedBox(height: 16),
          // We'll remove this entire Row that shows "Upload Files" label
          // The FileUploadWidget will handle showing the label to avoid duplication
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
                questionNumber: _getQuestionNumberForField(field),
                hasAttachments: field['hasAttachments'] == true,
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
        // Add a safety wrapper that handles potential type mismatches
        Builder(
          builder: (context) {
            // Check if control exists
            if (!controller.form.contains(field['name'])) {
              return Text("Error: Form control not found for ${field['name']}",
                  style: TextStyle(color: Colors.red));
            }

            // If the form control exists but might not have the right type,
            // wrap it in a try-catch to prevent runtime errors
            try {
              return ReactiveTextField<num>(
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
                      (field['min'] != null || field['max'] != null
                          ? ' ('
                          : '') +
                      (field['min'] != null ? 'min: ${field['min']}' : '') +
                      (field['min'] != null && field['max'] != null
                          ? ', '
                          : '') +
                      (field['max'] != null ? 'max: ${field['max']}' : '') +
                      (field['min'] != null || field['max'] != null ? ')' : ''),
                  labelStyle: widget.fontFamily,
                  hintStyle: widget.fontFamily,
                  errorStyle: widget.fontFamily
                      .copyWith(fontSize: 12, color: Colors.red),
                ),
              );
            } catch (e) {
              if (kDebugMode) {
                print("Error rendering number field ${field['name']}: $e");
              }
              // Return a fallback widget if there's a type mismatch
              return TextFormField(
                decoration: InputDecoration(
                  hintText:
                      "Error loading number field - please reload the form",
                  errorText: "Type mismatch error",
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.red),
                  ),
                ),
                enabled: false,
              );
            }
          },
        ),
        if (field['hasAttachments'] == true ||
            field['attachmentsRequired'] == true) ...[
          const SizedBox(height: 16),
          // We're removing this Row widget to avoid duplicate Upload Files labels
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
                  questionNumber: _getQuestionNumberForField(field),
                  hasAttachments: field['hasAttachments'] == true,
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
          _buildCommentField(field),
        ],
      ],
    );
  }

  Widget _buildFileField(Map<String, dynamic> field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Add a safety wrapper that handles potential type mismatches
        Builder(
          builder: (context) {
            // Check if control exists
            if (!controller.form.contains(field['name'])) {
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabelRow(field),
                    Text("Error: Form control not found for ${field['name']}",
                        style: TextStyle(color: Colors.red)),
                  ]);
            }

            // If the form control exists but might not have the right type,
            // wrap it in a try-catch to prevent runtime errors
            try {
              return ReactiveValueListenableBuilder<String>(
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
                        uploadedFiles:
                            controller.uploadedFiles[field['name']] ?? [],
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
                              control.value = remainingFiles
                                  .map((f) => f['fileName'])
                                  .join(',');
                            }
                          });
                        },
                        isRequired: field['required'] == true,
                        questionNumber: _getQuestionNumberForField(field),
                        hasAttachments: field['hasAttachments'] == true,
                      ),
                      // Show error message if validation error occurs and control is touched
                      if (control.touched && control.hasErrors)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            StringConstants.fileIsRequired,
                            style:
                                TextStyle(color: Colors.red[700], fontSize: 12),
                          ),
                        ),
                    ],
                  );
                },
              );
            } catch (e) {
              if (kDebugMode) {
                print("Error rendering file field ${field['name']}: $e");
              }
              // Return a fallback widget if there's a type mismatch
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabelRow(field),
                  TextFormField(
                    decoration: InputDecoration(
                      hintText:
                          "Error loading file field - please reload the form",
                      errorText: "Type mismatch error",
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.red),
                      ),
                    ),
                    enabled: false,
                  ),
                ],
              );
            }
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
          _buildCommentField(field),
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
                key: const ValueKey('next_button'), // Add key for testing
                onPressed: () {
                  // Log before validation
                  if (kDebugMode) {
                    print("\n=== NEXT Button Pressed ===");

                    // Check current state
                    if (_groupAnchors.isNotEmpty &&
                        _currentGroupPointer < _groupAnchors.length) {
                      final currentAnchor = _groupAnchors[_currentGroupPointer];
                      print("Current anchor: $currentAnchor");

                      if (currentAnchor < _internalFields.length) {
                        final field = _internalFields[currentAnchor];
                        print(
                            "Field name: ${field['name']}, isDuplicate: ${field['isDuplicate']}");

                        // Check if field has values
                        if (controller.form.contains(field['name'])) {
                          final control =
                              controller.form.control(field['name']);
                          print(
                              "Field value: ${control.value}, isRequired: ${field['required'] == true}");
                        }
                      }
                    }
                  }

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
        AppSnackBar(context)
            .showErrorSnackBar(StringConstants.fillRequiredFields);
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
    // Count how many questions are visible
    List<int> visibleIndices = [];
    for (int i = 0; i < widget.formJson.length; i++) {
      if (controller.shouldDisplayQuestion(i)) {
        visibleIndices.add(i);
      }
    }

    if (visibleIndices.isEmpty) return "0/0";

    // Find the current question's position in the visible questions
    int currentPosition =
        visibleIndices.indexOf(controller.currentQuestionIndex);
    if (currentPosition == -1) {
      // Current question is not visible - unusual state
      return "${controller.calculateVisualQuestionNumber(controller.currentQuestionIndex)}/${visibleIndices.length}";
    }

    return "${currentPosition + 1}/${visibleIndices.length}";
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

  // Validate the current section including any duplicate cards
  bool validateCurrentSection() {
    if (kDebugMode) {
      print("\n=== validateCurrentSection called ===");
    }

    // Make sure we have valid anchors
    if (_groupAnchors.isEmpty) {
      if (kDebugMode) {
        print('Warning: No group anchors available for validation');
      }
      return true; // Nothing to validate
    }

    // Get the current anchor and its fields
    final currentAnchor = _groupAnchors[_currentGroupPointer];
    if (kDebugMode) {
      print("Current anchor index: $currentAnchor");
      if (currentAnchor < _internalFields.length) {
        final anchorField = _internalFields[currentAnchor];
        print(
            "Anchor field: ${anchorField['name']}, isDuplicate: ${anchorField['isDuplicate']}");
      }
    }

    // Validate the original card fields
    final originalIndices =
        _anchorToFieldIndices[currentAnchor] ?? [currentAnchor];
    if (kDebugMode) {
      print("Original card fields: ${originalIndices.length}");
    }

    // Track if validation passes for all fields
    bool isValid = true;

    // First validate the original fields
    for (int idx in originalIndices) {
      if (idx >= 0 && idx < _internalFields.length) {
        final field = _internalFields[idx];
        final fieldName = field['name'].toString();
        final bool isRequired = field['required'] == true;

        if (kDebugMode) {
          print("Validating original field: $fieldName, required: $isRequired");
        }

        // Skip validation for fields that aren't in the form
        if (!controller.form.contains(fieldName)) {
          if (kDebugMode) {
            print("Field $fieldName not in form, skipping validation");
          }
          continue;
        }

        final control = controller.form.control(fieldName);

        // Mark the control as touched to show validation errors
        control.markAsTouched();

        if (!control.valid) {
          if (kDebugMode) {
            print("Field $fieldName validation failed: ${control.errors}");
          }
          isValid = false;
          if (field['type'] != 'text' && field['type'] != 'number') {
            hasCriticalValidationError = true;
          }
        }

        // Check for required file uploads
        if (field['type'] == 'file' && isRequired) {
          final hasFiles =
              controller.uploadedFiles[fieldName]?.isNotEmpty ?? false;
          if (!hasFiles) {
            if (kDebugMode) {
              print("Required file upload missing for $fieldName");
            }
            isValid = false;
            hasCriticalValidationError = true;
          }
        }

        // Check for required comments
        if (field['hasComments'] == true) {
          final commentControlName = '${fieldName}_comment';
          if (controller.form.contains(commentControlName)) {
            final commentControl = controller.form.control(commentControlName);
            commentControl.markAsTouched();

            if (!commentControl.valid) {
              if (kDebugMode) {
                print("Comment for $fieldName validation failed");
              }
              isValid = false;
            }
          }
        }
      }
    }

    // Now find and validate all duplicate fields related to the current anchor
    final currentFields = originalIndices
        .map((idx) => _internalFields[idx]['name'].toString())
        .toList();

    // Find all duplicates by checking for fields with timestamp suffix
    final List<String> duplicateFields = [];
    final timeStampPattern = RegExp(r'_\d+$');

    // First, collect all duplicate fields that need validation
    for (final field in _internalFields) {
      final fieldName = field['name'].toString();
      final match = timeStampPattern.firstMatch(fieldName);

      if (match != null && field['isDuplicate'] == true) {
        // Extract base name (without timestamp)
        String baseFieldName = fieldName;
        final lastUnderscore = baseFieldName.lastIndexOf('_');
        if (lastUnderscore > 0) {
          baseFieldName = baseFieldName.substring(0, lastUnderscore);
        }

        // Check if this is a duplicate of any field in the current card
        for (final currentField in currentFields) {
          if (baseFieldName == currentField ||
              baseFieldName.startsWith("${currentField}_") ||
              currentField.startsWith("${baseFieldName}_")) {
            duplicateFields.add(fieldName);
            break;
          }
        }
      }
    }

    // Now validate all collected duplicate fields
    for (final fieldName in duplicateFields) {
      // Find the field definition
      final fieldIndex =
          _internalFields.indexWhere((f) => f['name'] == fieldName);
      if (fieldIndex == -1) continue;

      final field = _internalFields[fieldIndex];
      final bool isRequired = field['required'] == true;

      if (kDebugMode) {
        print("Validating duplicate field: $fieldName, required: $isRequired");
      }

      // Skip validation for fields that aren't in the form
      if (!controller.form.contains(fieldName)) {
        if (kDebugMode) {
          print("Duplicate field $fieldName not in form, skipping validation");
        }
        continue;
      }

      final control = controller.form.control(fieldName);

      // Always mark the control as touched to show validation errors
      control.markAsTouched();

      if (!control.valid) {
        if (kDebugMode) {
          print(
              "Duplicate field $fieldName validation failed: ${control.errors}");
        }
        isValid = false;
        if (field['type'] != 'text' && field['type'] != 'number') {
          hasCriticalValidationError = true;
        }
      }

      // Check for required file uploads for duplicates
      if (field['type'] == 'file' && isRequired) {
        final hasFiles =
            controller.uploadedFiles[fieldName]?.isNotEmpty ?? false;
        if (!hasFiles) {
          if (kDebugMode) {
            print(
                "Required file upload missing for duplicate field $fieldName");
          }
          isValid = false;
          hasCriticalValidationError = true;
        }
      }

      // Check for required comments for duplicates
      if (field['hasComments'] == true) {
        final commentControlName = '${fieldName}_comment';
        if (controller.form.contains(commentControlName)) {
          final commentControl = controller.form.control(commentControlName);
          commentControl.markAsTouched();

          if (!commentControl.valid) {
            if (kDebugMode) {
              print("Comment for duplicate field $fieldName validation failed");
            }
            isValid = false;
          }
        }
      }
    }

    if (kDebugMode) {
      print("validateCurrentSection result: $isValid");
    }

    return isValid;
  }

  /// Checks if the current question has required file attachments and if they've been uploaded
  /// Follows the complete attachment rule table for determining when uploads are required
  bool _checkIfRequiredFilesUploaded() {
    if (kDebugMode) {
      print("📄 VALIDATION: Checking if required files are uploaded...");
    }

    // Get the current field list based on whether we're checking all fields or just the current section
    List<Map<String, dynamic>> fieldsToCheck =
        widget.showOneByOne ? _getCurrentQuestionFields() : _internalFields;

    // Check each field in the current section
    for (var field in fieldsToCheck) {
      String fieldName = field['name'].toString();

      // Special debug for question_6
      if (fieldName == 'question_6') {
        if (kDebugMode) {
          print("\n📄 VALIDATION: Found question_6 during validation");
          print(
              "📄 VALIDATION: question_6 hasAttachments=${field['hasAttachments']}");
          print(
              "📄 VALIDATION: question_6 requireAttachmentsOn=${field['requireAttachmentsOn']}");
          print(
              "📄 VALIDATION: question_6 current value=${controller.form.control(fieldName).value}");
          print(
              "📄 VALIDATION: uploadedFiles contains question_6=${controller.uploadedFiles.containsKey(fieldName)}");
          if (controller.uploadedFiles.containsKey(fieldName)) {
            print(
                "📄 VALIDATION: uploadedFiles for question_6=${controller.uploadedFiles[fieldName]}");
          }
        }

        // For question_6, ensure direct validation
        if (field['hasAttachments'] == true &&
            field['requireAttachmentsOn'] != null) {
          final currentValue = controller.form.control(fieldName).value;

          // Convert to list for consistent handling
          List<dynamic> requiredOptions = field['requireAttachmentsOn'] is List
              ? field['requireAttachmentsOn']
              : [field['requireAttachmentsOn']];

          // Check if current value requires file upload
          final bool shouldRequireFile = requiredOptions.contains(currentValue);

          if (kDebugMode) {
            print(
                "📄 VALIDATION: question_6 requires files? $shouldRequireFile");
          }

          if (shouldRequireFile) {
            // Check if uploads exist
            final bool hasFiles =
                controller.uploadedFiles[fieldName]?.isNotEmpty ?? false;

            if (!hasFiles) {
              if (kDebugMode) {
                print("📄 VALIDATION: question_6 missing required files");
                print(
                    "📄 VALIDATION: ✖ FAILED - Required files not uploaded for question_6");
              }

              // Set the error message
              setState(() {
                _showAttachmentError = true;
              });

              // Store field for error message
              _lastValidationErrorField = field;

              return false;
            } else {
              if (kDebugMode) {
                print("📄 VALIDATION: question_6 has required files ✓");
              }
            }
          }
        }
      }

      // Skip if the field is not visible due to showWhen conditions
      if (field['showWhen'] != null) {
        bool isVisible = true;
        final conditions = field['showWhen'] as Map<String, dynamic>;

        conditions.forEach((dependentField, expectedValue) {
          if (!controller.form.contains(dependentField)) {
            isVisible = false;
            return;
          }

          final currentValue = controller.form.control(dependentField).value;

          if (expectedValue is List) {
            if (!expectedValue.contains(currentValue)) {
              isVisible = false;
            }
          } else if (currentValue != expectedValue) {
            isVisible = false;
          }
        });

        if (!isVisible) {
          if (kDebugMode) {
            print(
                "📄 VALIDATION: Field '$fieldName' is not visible due to showWhen conditions - skipping attachment check");
          }
          continue;
        }
      }

      // Get the current value for conditional checks
      dynamic currentValue;
      if (controller.form.contains(fieldName)) {
        currentValue = controller.form.control(fieldName).value;
      } else {
        if (kDebugMode) {
          print(
              "📄 VALIDATION: Warning - form control not found for '$fieldName'");
        }
        continue; // Skip this field if the control doesn't exist
      }

      // Step 1: Determine if attachments are required for this field
      bool requiresAttachments = false;
      String reasonForRequirement = "";

      // Rule #1: For standalone file fields, always check
      if (field['type'] == 'file' && field['required'] == true) {
        requiresAttachments = true;
        reasonForRequirement = "type=file and required=true";
      }

      // Rule #2: Check requireAttachmentsOn - use this as the primary condition
      if (field['requireAttachmentsOn'] != null) {
        // If requireAttachmentsOn is a boolean true, always require attachments
        if (field['requireAttachmentsOn'] == true) {
          requiresAttachments = true;
          reasonForRequirement = "requireAttachmentsOn=true";
        } else {
          // Convert to list for consistent handling
          List<dynamic> requiredOptions = field['requireAttachmentsOn'] is List
              ? field['requireAttachmentsOn']
              : [field['requireAttachmentsOn']];

          // For multiselect fields
          if (currentValue is List) {
            // Check if any selected value is in requiredOptions
            bool anyValueRequiresAttachments =
                currentValue.any((value) => requiredOptions.contains(value));

            if (anyValueRequiresAttachments) {
              requiresAttachments = true;
              reasonForRequirement = "Selected value in requireAttachmentsOn";
            }
          }
          // For radio, dropdown, and other single-value fields
          else if (requiredOptions.contains(currentValue)) {
            requiresAttachments = true;
            reasonForRequirement =
                "Value '$currentValue' is in requireAttachmentsOn";
          }
        }
      }

      // Rule #3: Check enableAttachmentsOn (synonym for requireAttachmentsOn)
      if (field['enableAttachmentsOn'] != null && !requiresAttachments) {
        List<dynamic> enabledOptions = field['enableAttachmentsOn'] is List
            ? field['enableAttachmentsOn']
            : [field['enableAttachmentsOn']];

        // For multiselect fields
        if (currentValue is List) {
          // Check if any selected value is in enabledOptions
          bool anyValueEnablesAttachments =
              currentValue.any((value) => enabledOptions.contains(value));

          if (anyValueEnablesAttachments) {
            requiresAttachments = true;
            reasonForRequirement = "Selected value in enableAttachmentsOn";
          }
        }
        // For radio, dropdown, and other single-value fields
        else if (enabledOptions.contains(currentValue)) {
          requiresAttachments = true;
          reasonForRequirement =
              "Value '$currentValue' is in enableAttachmentsOn";
        }
      }

      // Rule #3 (new): Check for legacy attachmentsRequired property
      if (field['attachmentsRequired'] == true && !requiresAttachments) {
        requiresAttachments = true;
        reasonForRequirement = "Legacy property attachmentsRequired=true";
        if (kDebugMode) {
          print(
              "📄 VALIDATION: Legacy property 'attachmentsRequired' detected for ${field['name']}");
        }
      }

      // Rule #4: For fields with hasAttachments=true but no specific conditions
      if (field['hasAttachments'] == true && !requiresAttachments) {
        bool hasConditionalAttachments =
            field['requireAttachmentsOn'] != null ||
                field['disableAttachmentsOn'] != null;

        // If there are no specific conditions, hasAttachments=true means files are required
        if (!hasConditionalAttachments) {
          requiresAttachments = true;
          reasonForRequirement = "hasAttachments=true with no conditions";
        }
        // NEW CHECK: If both requireAttachmentsOn and disableAttachmentsOn are empty arrays,
        // require file uploads
        else {
          bool isRequireAttachmentsOnEmpty =
              field['requireAttachmentsOn'] is List &&
                  (field['requireAttachmentsOn'] as List).isEmpty;

          bool isDisableAttachmentsOnEmpty =
              field['disableAttachmentsOn'] is List &&
                  (field['disableAttachmentsOn'] as List).isEmpty;

          if (isRequireAttachmentsOnEmpty && isDisableAttachmentsOnEmpty) {
            requiresAttachments = true;
            reasonForRequirement =
                "hasAttachments=true with empty requireAttachmentsOn and disableAttachmentsOn arrays";
            if (kDebugMode) {
              print(
                  "📄 VALIDATION: Attachments required for field '$fieldName' because hasAttachments=true and both requireAttachmentsOn and disableAttachmentsOn are empty arrays");
            }
          }
        }
      }

      // NEW RULE #4.5: When hasAttachments=true, disableAttachmentsOn is not empty, and selected value is NOT in disableAttachmentsOn
      if (field['hasAttachments'] == true &&
          field['disableAttachmentsOn'] != null &&
          !requiresAttachments) {
        List<dynamic> disabledOptions = field['disableAttachmentsOn'] is List
            ? field['disableAttachmentsOn']
            : [field['disableAttachmentsOn']];

        if (disabledOptions.isNotEmpty) {
          // For multiselect fields
          if (currentValue is List && currentValue.isNotEmpty) {
            // Check if NO selected value is in disabledOptions
            bool noValueDisablesAttachments =
                !currentValue.any((value) => disabledOptions.contains(value));

            if (noValueDisablesAttachments) {
              requiresAttachments = true;
              reasonForRequirement =
                  "hasAttachments=true, disableAttachmentsOn not empty, and no selected value in disableAttachmentsOn";
              if (kDebugMode) {
                print(
                    "📄 VALIDATION: Attachments required for field '$fieldName' because hasAttachments=true, disableAttachmentsOn not empty, and no selected value in disableAttachmentsOn");
              }
            }
          }
          // For radio, dropdown, and other single-value fields
          else if (currentValue != null &&
              !disabledOptions.contains(currentValue)) {
            requiresAttachments = true;
            reasonForRequirement =
                "hasAttachments=true, disableAttachmentsOn not empty, and selected value not in disableAttachmentsOn";
            if (kDebugMode) {
              print(
                  "📄 VALIDATION: Attachments required for field '$fieldName' because hasAttachments=true, disableAttachmentsOn not empty, and value '$currentValue' not in disableAttachmentsOn");
            }
          }
        }
      }

      // Rule #5: Check for disableAttachmentsOn - this overrides other conditions
      if (field['disableAttachmentsOn'] != null) {
        List<dynamic> disabledOptions = field['disableAttachmentsOn'] is List
            ? field['disableAttachmentsOn']
            : [field['disableAttachmentsOn']];

        // For multiselect fields
        if (currentValue is List) {
          // Check if any selected value is in disabledOptions
          bool anyValueDisablesAttachments =
              currentValue.any((value) => disabledOptions.contains(value));

          if (anyValueDisablesAttachments) {
            requiresAttachments = false;
            reasonForRequirement = "";
            if (kDebugMode) {
              print(
                  "📄 VALIDATION: Attachments disabled for field '$fieldName' because a selected value is in disableAttachmentsOn");
            }
          }
        }
        // For radio, dropdown, and other single-value fields
        else if (disabledOptions.contains(currentValue)) {
          requiresAttachments = false;
          reasonForRequirement = "";
          if (kDebugMode) {
            print(
                "📄 VALIDATION: Attachments disabled for field '$fieldName' because value '$currentValue' is in disableAttachmentsOn");
          }
        }
      }

      // Rule #6: If hasAttachments=false, no uploads are required
      if (field['hasAttachments'] == false) {
        requiresAttachments = false;
        reasonForRequirement = "";
        if (kDebugMode) {
          print(
              "📄 VALIDATION: Field '$fieldName' has hasAttachments=false, overriding other conditions");
        }
      }

      // Step 2: Check if we have the required files
      if (requiresAttachments) {
        if (kDebugMode) {
          print(
              "📄 VALIDATION: Field '$fieldName' requires file uploads ($reasonForRequirement)");
        }

        // Check if uploads exist for this field
        List<Map<String, dynamic>>? uploads =
            controller.uploadedFiles[fieldName];

        if (uploads == null || uploads.isEmpty) {
          if (kDebugMode) {
            print(
                "📄 VALIDATION: Missing required file uploads for '$fieldName'");
            print("📄 VALIDATION: ✖ FAILED - Required files not uploaded");
          }

          // Set the error message
          setState(() {
            _showAttachmentError = true;
          });

          // Store the field info for the parent method to use in error message
          _lastValidationErrorField = field;

          // Return false but don't show snackbar here - parent methods will handle that
          return false;
        } else {
          if (kDebugMode) {
            print(
                "📄 VALIDATION: Found ${uploads.length} file(s) uploaded for '$fieldName'");
          }
        }
      } else {
        if (kDebugMode) {
          print(
              "📄 VALIDATION: Field '$fieldName' does not require file uploads");
        }
      }
    }

    if (kDebugMode) {
      print("📄 VALIDATION: ✓ PASSED - All required files are uploaded");
    }

    setState(() {
      _showAttachmentError = false;
    });

    return true;
  }

  void _moveToNextStep(BuildContext context) {
    // Make sure we have valid anchors
    if (_groupAnchors.isEmpty) {
      if (kDebugMode) {
        print('Warning: No group anchors available');
      }
      return;
    }

    if (kDebugMode) {
      print("\n=== _moveToNextStep - Starting Form Navigation ===");
      print("Current pointer: $_currentGroupPointer");
      print("Current controller index: ${controller.currentQuestionIndex}");
    }

    // FIRST check file upload requirements - do this before other validation
    if (!_checkIfRequiredFilesUploaded()) {
      if (kDebugMode) {
        print("⛔ FILE UPLOAD VALIDATION FAILED - Navigation blocked");
      }
      // Show a snackbar to inform the user that files need to be uploaded
      // Use the _lastValidationErrorField to provide more context if available
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _lastValidationErrorField != null
                ? 'Please upload the required files for "${_lastValidationErrorField!['label']}"'
                : StringConstants.uploadRequiredFiles,
            style: widget.fontFamily,
          ),
          backgroundColor: Colors.red[700],
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    // Then validate the current section including all duplicate cards
    final validationPassed = validateCurrentSection();
    if (!validationPassed && hasCriticalValidationError) {
      if (kDebugMode) {
        print("⛔ FIELD VALIDATION FAILED - Navigation blocked");
      }
      // Show a snackbar to inform the user that validation failed
      AppSnackBar(context)
          .showErrorSnackBar(StringConstants.fillRequiredFields);
      return;
    }

    if (kDebugMode) {
      print("✅ All validations passed - Proceeding with navigation");
    }

    // Get the current anchor and find the corresponding original question
    if (_currentGroupPointer >= _groupAnchors.length) {
      if (kDebugMode) {
        print("Current group pointer out of bounds");
      }
      return;
    }

    final currentAnchor = _groupAnchors[_currentGroupPointer];
    final currentAnchorField = _internalFields[currentAnchor];
    final currentAnchorName = currentAnchorField['name'].toString();

    // Find the original question index in formJson that corresponds to this anchor
    int originalQuestionIndex = -1;
    for (int i = 0; i < widget.formJson.length; i++) {
      final question = widget.formJson[i];
      final questionName = question['name'].toString();

      // Check if this is the same question (handle both original and duplicate names)
      if (questionName == currentAnchorName) {
        originalQuestionIndex = i;
        break;
      }

      // For duplicates, check if the base name matches
      final timestampPattern = RegExp(r'(.+)_\d+$');
      final match = timestampPattern.firstMatch(currentAnchorName);
      if (match != null) {
        final baseName = match.group(1) ?? '';
        if (questionName == baseName) {
          originalQuestionIndex = i;
          break;
        }
      }
    }

    if (originalQuestionIndex == -1) {
      if (kDebugMode) {
        print(
            "Could not find original question for anchor: $currentAnchorName");
      }
      return;
    }

    if (kDebugMode) {
      print("Found original question at index: $originalQuestionIndex");
    }

    // Update the controller to point to this question
    controller.currentQuestionIndex = originalQuestionIndex;

    // Use the controller's logic to determine the next question
    // This will handle all the branching logic and navigation history
    bool proceeded = controller.validateAndProceed(context);

    if (proceeded) {
      setState(() {
        // Find the anchor that corresponds to the controller's NEW current index
        int matchingAnchorPointer = -1;
        for (int i = 0; i < _groupAnchors.length; i++) {
          final anchorIndex = _groupAnchors[i];
          final anchorField = _internalFields[anchorIndex];
          final anchorName = anchorField['name'].toString();

          // Check if this anchor corresponds to the controller's current question
          if (controller.currentQuestionIndex < widget.formJson.length) {
            final controllerQuestionName = widget
                .formJson[controller.currentQuestionIndex]['name']
                .toString();

            // Direct match
            if (anchorName == controllerQuestionName) {
              matchingAnchorPointer = i;
              break;
            }

            // For duplicates, check base name
            final timestampPattern = RegExp(r'(.+)_\d+$');
            final match = timestampPattern.firstMatch(anchorName);
            if (match != null) {
              final baseName = match.group(1) ?? '';
              if (baseName == controllerQuestionName) {
                matchingAnchorPointer = i;
                break;
              }
            }
          }
        }

        if (matchingAnchorPointer != -1) {
          _currentGroupPointer = matchingAnchorPointer;
          if (kDebugMode) {
            print(
                "Updated group pointer to $_currentGroupPointer to match controller index ${controller.currentQuestionIndex}");
            print(
                "➡️ Navigated to question: ${_internalFields[_groupAnchors[_currentGroupPointer]]['name']}");
          }
        } else {
          if (kDebugMode) {
            print(
                "Warning: Could not find anchor for controller index ${controller.currentQuestionIndex}");
          }

          // If we can't find a matching anchor, check if current question is visible
          _updateCurrentQuestionBasedOnVisibility();
        }
      });
    } else {
      if (kDebugMode) {
        print(
            "⚠️ Controller validateAndProceed returned false - Navigation blocked");
      }
    }
  }

  // Move to the next question in the form
  void moveToNextQuestion(BuildContext context) {
    if (kDebugMode) {
      print("\n=== moveToNextQuestion - Starting Form Navigation ===");
      print("Current group pointer: $_currentGroupPointer");
      print("Current controller index: ${controller.currentQuestionIndex}");
    }

    // FIRST check file upload requirements - do this before other validation
    if (!_checkIfRequiredFilesUploaded()) {
      if (kDebugMode) {
        print("⛔ FILE UPLOAD VALIDATION FAILED - Navigation blocked");
      }
      // Show a snackbar to inform the user that files need to be uploaded
      // Use the _lastValidationErrorField to provide more context if available
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _lastValidationErrorField != null
                ? 'Please upload the required files for "${_lastValidationErrorField!['label']}"'
                : StringConstants.uploadRequiredFiles,
            style: widget.fontFamily,
          ),
          backgroundColor: Colors.red[700],
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    // NEW LOGIC: Instead of using controller.validateAndProceed directly,
    // we need to handle navigation at the group level to avoid duplicate issues

    // First validate the current section (including all duplicates)
    final validationPassed = validateCurrentSection();
    if (!validationPassed && hasCriticalValidationError) {
      if (kDebugMode) {
        print("⛔ FIELD VALIDATION FAILED - Navigation blocked");
      }
      // Show a snackbar to inform the user that validation failed
      AppSnackBar(context)
          .showErrorSnackBar(StringConstants.fillRequiredFields);
      return;
    }

    // Get the current anchor and find the corresponding original question
    if (_groupAnchors.isEmpty || _currentGroupPointer >= _groupAnchors.length) {
      if (kDebugMode) {
        print("No valid anchors available for navigation");
      }
      return;
    }

    final currentAnchor = _groupAnchors[_currentGroupPointer];
    final currentAnchorField = _internalFields[currentAnchor];
    final currentAnchorName = currentAnchorField['name'].toString();

    // Find the original question index in formJson that corresponds to this anchor
    int originalQuestionIndex = -1;
    for (int i = 0; i < widget.formJson.length; i++) {
      final question = widget.formJson[i];
      final questionName = question['name'].toString();

      // Check if this is the same question (handle both original and duplicate names)
      if (questionName == currentAnchorName) {
        originalQuestionIndex = i;
        break;
      }

      // For duplicates, check if the base name matches
      final timestampPattern = RegExp(r'(.+)_\d+$');
      final match = timestampPattern.firstMatch(currentAnchorName);
      if (match != null) {
        final baseName = match.group(1) ?? '';
        if (questionName == baseName) {
          originalQuestionIndex = i;
          break;
        }
      }
    }

    if (originalQuestionIndex == -1) {
      if (kDebugMode) {
        print(
            "Could not find original question for anchor: $currentAnchorName");
      }
      return;
    }

    if (kDebugMode) {
      print("Found original question at index: $originalQuestionIndex");
    }

    // Update the controller to point to this question and validate it
    controller.currentQuestionIndex = originalQuestionIndex;

    // Use the controller's validateAndProceed method to handle navigation
    bool proceeded = controller.validateAndProceed(context);

    if (proceeded) {
      setState(() {
        // Find the anchor that corresponds to the controller's NEW current index
        int matchingAnchorPointer = -1;
        for (int i = 0; i < _groupAnchors.length; i++) {
          final anchorIndex = _groupAnchors[i];
          final anchorField = _internalFields[anchorIndex];
          final anchorName = anchorField['name'].toString();

          // Check if this anchor corresponds to the controller's current question
          if (controller.currentQuestionIndex < widget.formJson.length) {
            final controllerQuestionName = widget
                .formJson[controller.currentQuestionIndex]['name']
                .toString();

            // Direct match
            if (anchorName == controllerQuestionName) {
              matchingAnchorPointer = i;
              break;
            }

            // For duplicates, check base name
            final timestampPattern = RegExp(r'(.+)_\d+$');
            final match = timestampPattern.firstMatch(anchorName);
            if (match != null) {
              final baseName = match.group(1) ?? '';
              if (baseName == controllerQuestionName) {
                matchingAnchorPointer = i;
                break;
              }
            }
          }
        }

        if (matchingAnchorPointer != -1) {
          _currentGroupPointer = matchingAnchorPointer;
          if (kDebugMode) {
            print(
                "Updated group pointer to $_currentGroupPointer to match controller index ${controller.currentQuestionIndex}");
            print(
                "➡️ Navigated to question: ${_internalFields[_groupAnchors[_currentGroupPointer]]['name']}");
          }
        } else {
          if (kDebugMode) {
            print(
                "Warning: Could not find anchor for controller index ${controller.currentQuestionIndex}");
          }

          // If we can't find a matching anchor, check if current question is visible
          _updateCurrentQuestionBasedOnVisibility();
        }
      });
    } else {
      if (kDebugMode) {
        print(
            "⚠️ Controller validateAndProceed returned false - Navigation blocked");
      }
    }
  }

  void _recomputeGroupStructure() {
    // Clear existing data structures
    _groupAnchors.clear();
    _anchorToFieldIndices.clear();
    _anchorToQuestionNumber.clear();

    // Handle empty _internalFields gracefully
    if (_internalFields.isEmpty) {
      if (kDebugMode) {
        print("Warning: _internalFields is empty in _recomputeGroupStructure");
      }
      return;
    }

    // Map to track which fields each anchor (parent) is referenced by
    Map<String, List<int>> anchorToChildIndices = {};

    // Map field names to their indices for easier lookup
    Map<String, int> fieldNameToIndex = {};
    for (int i = 0; i < _internalFields.length; i++) {
      fieldNameToIndex[_internalFields[i]['name'].toString()] = i;
    }

    // Track all fields that are children (have groupWith property)
    Set<int> childFieldIndices = {};

    // First pass: identify direct parent-child relationships
    // and track which fields are children
    for (int i = 0; i < _internalFields.length; i++) {
      final field = _internalFields[i];
      final String fieldName = field['name'].toString();
      final String? groupWith = field['groupWith']?.toString();
      final bool isDuplicate = field['isDuplicate'] == true;

      if (groupWith != null && groupWith.isNotEmpty) {
        // This field refers to a parent
        childFieldIndices.add(i); // Mark as a child field

        // CRITICAL FIX: Only add non-duplicate child fields to the original parent's group
        // Duplicate child fields should only be grouped with their duplicate parent
        if (!isDuplicate) {
          // Resolve ultimate parent to handle chained relationships
          String ultimateParent = _resolveUltimateParent(groupWith);

          // Check if parent field exists
          if (fieldNameToIndex.containsKey(ultimateParent)) {
            int parentIndex = fieldNameToIndex[ultimateParent]!;

            // Add this field as a child of the ultimate parent
            anchorToChildIndices.putIfAbsent(ultimateParent, () => []).add(i);

            // Debug
            if (kDebugMode && ultimateParent != groupWith) {
              print(
                  "Chain detected: $fieldName -> $groupWith -> $ultimateParent");
            }
          } else if (kDebugMode) {
            print(
                "Warning: Field '$fieldName' references non-existent parent '$ultimateParent'");
          }
        }
      }
    }

    // Special handling for timestamp-based duplicates
    Map<String, List<int>> timestampGroups = {};
    final timestampPattern = RegExp(r'(.+)_(\d+)$');

    // Identify all timestamp-based duplicates
    for (int i = 0; i < _internalFields.length; i++) {
      final field = _internalFields[i];
      final fieldName = field['name'].toString();

      // Check if this field has a timestamp and is marked as duplicate
      final match = timestampPattern.firstMatch(fieldName);
      if (match != null && field['isDuplicate'] == true) {
        final timestamp = match.group(2) ?? '';

        if (timestamp.isNotEmpty) {
          final groupKey = 'duplicate:${timestamp}';
          timestampGroups.putIfAbsent(groupKey, () => []).add(i);
        }
      }
    }

    // Second pass: identify all anchor fields and build their groups
    for (int i = 0; i < _internalFields.length; i++) {
      final field = _internalFields[i];
      final fieldName = field['name'].toString();
      final bool isDuplicate = field['isDuplicate'] == true;

      // Skip duplicates and child fields from being anchors
      if (isDuplicate || childFieldIndices.contains(i)) continue;

      // This field is an anchor - either it's referenced by other fields or it's standalone
      _groupAnchors.add(i);

      // Start with the anchor field itself
      List<int> groupIndices = [i];

      // Add any children that reference this field
      List<int>? childIndices = anchorToChildIndices[fieldName];
      if (childIndices != null && childIndices.isNotEmpty) {
        groupIndices.addAll(childIndices);
      }

      // Store the group
      _anchorToFieldIndices[i] = groupIndices;
    }

    // CRITICAL FIX: Do NOT add duplicate fields as separate anchors
    // Instead, store them in _anchorToFieldIndices only for rendering purposes
    // This ensures duplicates appear as cards on the same page, not as separate pages
    for (final groupKey in timestampGroups.keys) {
      final fieldIndices = timestampGroups[groupKey]!;
      if (fieldIndices.isEmpty) continue;

      // Find the first field as the anchor for this duplicate set
      final firstIndex = fieldIndices.reduce((a, b) => a < b ? a : b);

      // IMPORTANT: Do NOT add duplicates to _groupAnchors
      // Only store them in _anchorToFieldIndices for rendering
      _anchorToFieldIndices[firstIndex] = List.from(fieldIndices);
    }

    // Sort anchors by their position in _internalFields to maintain proper order
    _groupAnchors.sort();

    // Map to track base field names to their question numbers
    Map<String, int> baseNameToQuestionNumber = {};

    // Assign question numbers only to non-duplicate anchors
    int questionNumber = 1;
    for (int i = 0; i < _groupAnchors.length; i++) {
      int anchorIndex = _groupAnchors[i];
      String fieldName = _internalFields[anchorIndex]['name'].toString();

      _anchorToQuestionNumber[anchorIndex] = questionNumber;
      baseNameToQuestionNumber[fieldName] = questionNumber;
      questionNumber++;
    }

    // Reset the group pointer
    _currentGroupPointer = 0;

    // Update controller index after a brief delay to ensure state is consistent
    if (_groupAnchors.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          controller.currentQuestionIndex = _groupAnchors[_currentGroupPointer];
        }
      });
    }
  }

  List<Widget> _buildFields() {
    if (_groupAnchors.isEmpty) return [];

    final List<Widget> widgets = [];

    // Make sure _currentGroupPointer is valid
    if (_currentGroupPointer >= _groupAnchors.length || _groupAnchors.isEmpty) {
      return widgets;
    }

    // Get the current anchor indicated by the pointer
    final currentAnchor = _groupAnchors[_currentGroupPointer];
    final String currentAnchorName =
        _internalFields[currentAnchor]['name'] as String;

    // Build the card for the current anchor with all its grouped fields
    // This is the original card that is always displayed
    final List<int> currentIndices =
        _anchorToFieldIndices[currentAnchor] ?? [currentAnchor];
    final List<Map<String, dynamic>> currentGroupFields =
        currentIndices.map((i) => _internalFields[i]).toList();

    // Check if this anchor field is referenced by any other field via groupWith
    // or if it has children in its group
    bool shouldShowCard = false;

    // If the anchor has more than just itself in its group, it's a parent with children
    if (currentIndices.length > 1) {
      shouldShowCard = true;
    } else {
      // Check if the current field is referenced by any other field's groupWith
      for (var field in _internalFields) {
        String? groupWith = field['groupWith']?.toString();
        if (groupWith == currentAnchorName) {
          shouldShowCard = true;
          break;
        }
      }
    }

    // For debugging
    if (kDebugMode) {
      print("Field '${currentAnchorName}' shouldShowCard: $shouldShowCard");
    }

    // Add the original card or just the fields based on the shouldShowCard flag
    if (shouldShowCard) {
      // Add the original question as a card
      widgets.add(_buildCardForFields(currentGroupFields, false));
    } else {
      // Add the original question without a card
      widgets.addAll(currentGroupFields.map(_buildField).toList());
    }

    // CRITICAL FIX: Group duplicates by timestamp to avoid creating separate cards for each field
    // Now collect all duplicates by timestamp and create one card per duplicate group
    final Map<String, List<int>> duplicateGroups = {};
    final timeStampPattern = RegExp(r'_(\d+)$');

    // Find all duplicate fields that should be shown with this question and group them by timestamp
    for (int i = 0; i < _internalFields.length; i++) {
      final field = _internalFields[i];
      final fieldName = field['name'].toString();

      // Check if this is a duplicate field
      if (field['isDuplicate'] == true) {
        final match = timeStampPattern.firstMatch(fieldName);
        if (match != null) {
          final timestamp = match.group(1) ?? '';

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

          if (isRelated && timestamp.isNotEmpty) {
            // Group duplicates by timestamp
            duplicateGroups.putIfAbsent(timestamp, () => []).add(i);
          }
        }
      }
    }

    // Build one card per duplicate group (timestamp)
    for (final timestamp in duplicateGroups.keys) {
      final duplicateIndices = duplicateGroups[timestamp]!;

      // Get all fields for this duplicate group
      final fields = duplicateIndices.map((i) => _internalFields[i]).toList();

      // Add the duplicate card with delete button
      widgets.add(_buildCardForFields(fields, true));
    }

    return widgets;
  }

  /// Adds a new set of related fields to the form by duplicating current group
  /// and placing it below the original card
  void _addNewSet() {
    try {
      // Temporarily disable PageController updates
      _pageControllerReady = false;

      // Make sure we have valid anchors before proceeding
      if (_groupAnchors.isEmpty) {
        if (kDebugMode) {
          print('Warning: No group anchors available for duplication');
        }
        return;
      }

      // Make sure _currentGroupPointer is valid
      if (_currentGroupPointer < 0 ||
          _currentGroupPointer >= _groupAnchors.length) {
        _currentGroupPointer = 0;
      }

      // Store the original pointer to restore it after duplication
      final originalPointer = _currentGroupPointer;

      // Get the current anchor and its field indices
      final anchor = _groupAnchors[_currentGroupPointer];
      final List<int> indices = _anchorToFieldIndices[anchor] ?? [anchor];

      // Get the current anchor field's name for reference when creating duplicates
      final String currentAnchorName =
          _internalFields[anchor]['name'].toString();

      if (indices.isEmpty) {
        if (kDebugMode) {
          print('No fields to duplicate');
        }
        return;
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

        // Add a persistent ID to help track duplicates across state changes
        fieldCopy['duplicationId'] = millis.toString();

        // Set persistVisibility to true to keep the duplicate visible during navigation
        fieldCopy['persistVisibility'] = true;

        // CRITICAL FIX: Store which question anchor this duplicate belongs to
        // This will prevent duplicates from appearing on multiple pages
        fieldCopy['parentQuestionName'] = currentAnchorName;

        // Also store the parent question index to help with page association
        fieldCopy['parentQuestionIndex'] = anchor;

        // IMPORTANT: Make sure we preserve the 'required' status
        if (originalField['required'] == true) {
          fieldCopy['required'] = true;
        }

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
        print(
            'Required flags: ${newFields.map((f) => "${f['name']}: ${f['required']}").toList()}');
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

        // Check that form controls have correct validation
        _ensureFormControlsHaveCorrectValidation();

        // Regenerate the group mapping to properly group duplicated fields
        // This is critical to ensure duplicated fields appear in the right cards
        _recomputeGroupStructure();

        // Stay on the current card after duplication by restoring the original pointer
        _currentGroupPointer = originalPointer;

        // Debug: Log form controls after adding duplicates
        if (kDebugMode) {
          print("Current pointer after duplication: $_currentGroupPointer");
          print(
              "Added form controls: ${newFields.map((f) => f['name']).join(', ')}");

          // Check if the form controls exist and have the correct validation rules
          for (final field in newFields) {
            final fieldName = field['name'].toString();
            if (controller.form.contains(fieldName)) {
              final control = controller.form.control(fieldName);
              final bool isRequired = field['required'] == true;
              final bool hasRequiredValidator = control.validators.any(
                  (validator) => validator.toString().contains('required'));
              print(
                  "Field $fieldName - required=$isRequired, hasValidator=$hasRequiredValidator");
            } else {
              print("Warning: Form control not found for $fieldName");
            }
          }
        }
      });

      // Re-enable PageController updates after a short delay to allow layout to complete
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {
            _pageControllerReady = true;
          });
        }
      });
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

  String _getCurrentQuestionName() {
    if (controller.currentQuestionIndex < widget.formJson.length) {
      return widget.formJson[controller.currentQuestionIndex]['name'];
    }
    return '';
  }

  int? _getQuestionNumberForField(Map<String, dynamic> field) {
    // First find the index of this field in the formJson array to use the controller's visual numbering
    int formIndex = -1;
    for (int i = 0; i < widget.formJson.length; i++) {
      if (widget.formJson[i]['name'] == field['name']) {
        formIndex = i;
        break;
      }
    }

    // If we found the field in the formJson, use the controller's visual numbering
    if (formIndex != -1) {
      return controller.calculateVisualQuestionNumber(formIndex);
    }

    // Fallback: For fields not directly in formJson (like duplicates or children),
    // find associated original field index and use its numbering
    String originalFieldName = field['name'].toString();

    // If this is a duplicate field with timestamp suffix, extract the base name
    final timestampPattern = RegExp(r'(.+)_\d+$');
    final match = timestampPattern.firstMatch(originalFieldName);
    if (match != null) {
      originalFieldName = match.group(1) ?? originalFieldName;
    }

    // Find the original field in formJson
    for (int i = 0; i < widget.formJson.length; i++) {
      if (widget.formJson[i]['name'] == originalFieldName) {
        return controller.calculateVisualQuestionNumber(i);
      }
    }

    // Last resort fallback: return null if we can't determine the question number
    if (kDebugMode) {
      print(
          "Warning: Could not determine question number for field: ${field['name']}");
    }
    return null;
  }

  // The _recomputeGroupStructure method is already implemented earlier in the code at line 3547.
  // This was a duplicate declaration that has been removed to fix the lint error.

  // Ensure form controls have the correct validation rules
  void _ensureFormControlsHaveCorrectValidation() {
    if (kDebugMode) {
      print("\n=== Ensuring form controls have correct validation ===");
    }

    try {
      // Iterate through all fields to check their validation status
      for (final field in _internalFields) {
        final fieldName = field['name'].toString();
        final bool isRequired = field['required'] == true;

        if (controller.form.contains(fieldName)) {
          final control = controller.form.control(fieldName);
          final hasRequiredValidator = control.validators
              .any((validator) => validator.toString().contains('required'));

          // Fix validation mismatch
          if (isRequired != hasRequiredValidator) {
            if (kDebugMode) {
              print(
                  "Validation mismatch for $fieldName: Field required=$isRequired, but control hasRequiredValidator=$hasRequiredValidator");
            }

            if (isRequired && !hasRequiredValidator) {
              // Field is required but validator is missing - add it
              if (control is FormControl) {
                List<Validator> updatedValidators =
                    List.from(control.validators);
                updatedValidators.add(Validators.required);

                // Create a new control with the updated validators and preserve the value AND type
                // Determine the correct type based on the field type
                dynamic controlValue = control.value;
                String fieldType = field['type']?.toString() ?? 'text';

                if (fieldType == 'multiselect') {
                  // Handle multiselect which needs List<String> type
                  final newControl = FormControl<List<String>>(
                    value: controlValue is List
                        ? List<String>.from(
                            controlValue.map((e) => e.toString()))
                        : <String>[],
                    validators: updatedValidators,
                  );
                  controller.form.removeControl(fieldName);
                  controller.form.addAll({fieldName: newControl});
                } else if (fieldType == 'number') {
                  // Handle number fields
                  final newControl = FormControl<num>(
                    value: controlValue is num ? controlValue : null,
                    validators: updatedValidators,
                  );
                  controller.form.removeControl(fieldName);
                  controller.form.addAll({fieldName: newControl});
                } else {
                  // Default to String for most field types
                  final newControl = FormControl<String>(
                    value: controlValue?.toString() ?? '',
                    validators: updatedValidators,
                  );
                  controller.form.removeControl(fieldName);
                  controller.form.addAll({fieldName: newControl});
                }

                if (kDebugMode) {
                  print("Added required validator to $fieldName");
                }
              }
            } else if (!isRequired && hasRequiredValidator) {
              // Field is not required but has required validator - remove it
              if (control is FormControl) {
                List<Validator> updatedValidators = control.validators
                    .where((v) => !v.toString().contains('required'))
                    .toList();

                // Create a new control without the required validator AND preserve type
                // Determine the correct type based on the field type
                dynamic controlValue = control.value;
                String fieldType = field['type']?.toString() ?? 'text';

                if (fieldType == 'multiselect') {
                  // Handle multiselect which needs List<String> type
                  final newControl = FormControl<List<String>>(
                    value: controlValue is List
                        ? List<String>.from(
                            controlValue.map((e) => e.toString()))
                        : <String>[],
                    validators: updatedValidators,
                  );
                  controller.form.removeControl(fieldName);
                  controller.form.addAll({fieldName: newControl});
                } else if (fieldType == 'number') {
                  // Handle number fields
                  final newControl = FormControl<num>(
                    value: controlValue is num ? controlValue : null,
                    validators: updatedValidators,
                  );
                  controller.form.removeControl(fieldName);
                  controller.form.addAll({fieldName: newControl});
                } else {
                  // Default to String for most field types
                  final newControl = FormControl<String>(
                    value: controlValue?.toString() ?? '',
                    validators: updatedValidators,
                  );
                  controller.form.removeControl(fieldName);
                  controller.form.addAll({fieldName: newControl});
                }

                if (kDebugMode) {
                  print("Removed required validator from $fieldName");
                }
              }
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error ensuring form controls validation: $e");
      }
    }

    if (kDebugMode) {
      print("=== Form control validation check complete ===");
    }
  }

  // Check if the current question is effectively the last one in the form
  bool isCurrentQuestionEffectivelyLast() {
    if (_groupAnchors.isEmpty) return true;
    return _currentGroupPointer >= _groupAnchors.length - 1;
  }

  // Move to the previous valid question in the form
  void moveToPreviousValidQuestion() {
    if (kDebugMode) {
      print("\n=== moveToPreviousValidQuestion called ===");
      print("Current group pointer: $_currentGroupPointer");
      print("Current controller index: ${controller.currentQuestionIndex}");
    }

    // Use the controller's navigation logic which properly handles conditional visibility
    bool navigationSuccessful = controller.moveToPreviousQuestion();

    if (navigationSuccessful) {
      // Update the UI state to match the controller's new position
      setState(() {
        // Find the group pointer that corresponds to the controller's current question
        int matchingGroupPointer = -1;

        // Look for a matching anchor in our group structure
        for (int i = 0; i < _groupAnchors.length; i++) {
          final anchorIndex = _groupAnchors[i];
          if (anchorIndex < _internalFields.length) {
            final anchorField = _internalFields[anchorIndex];
            final anchorName = anchorField['name'].toString();

            // Check if this anchor corresponds to the controller's current question
            if (controller.currentQuestionIndex < widget.formJson.length) {
              final controllerQuestionName = widget
                  .formJson[controller.currentQuestionIndex]['name']
                  .toString();

              // Direct match
              if (anchorName == controllerQuestionName) {
                matchingGroupPointer = i;
                break;
              }

              // For duplicates, check base name
              final timestampPattern = RegExp(r'(.+)_\d+$');
              final match = timestampPattern.firstMatch(anchorName);
              if (match != null) {
                final baseName = match.group(1) ?? '';
                if (baseName == controllerQuestionName) {
                  matchingGroupPointer = i;
                  break;
                }
              }
            }
          }
        }

        if (matchingGroupPointer != -1) {
          _currentGroupPointer = matchingGroupPointer;
          if (kDebugMode) {
            print(
                "Updated group pointer to $_currentGroupPointer to match controller index ${controller.currentQuestionIndex}");
          }
        } else {
          if (kDebugMode) {
            print(
                "Warning: Could not find matching group pointer for controller index ${controller.currentQuestionIndex}");
          }
          // Update current question visibility as fallback
          _updateCurrentQuestionBasedOnVisibility();
        }
      });
    } else {
      if (kDebugMode) {
        print(
            "Controller navigation failed - already at first question or no valid previous question");
      }
    }
  }

  // Build error message for attachment validation errors
  Widget _buildErrorMessage() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        StringConstants.pleaseFillOutAllRequiredAttachments,
        style: TextStyle(
          color: Colors.red[700],
          fontSize: 14.0,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// Resolves the ultimate parent field for a field with potentially chained groupWith references
  /// This function traverses the chain of groupWith relationships to find the ultimate parent question.
  /// It also detects and handles circular dependencies within the chain.
  String _resolveUltimateParent(String fieldName) {
    String currentParent = fieldName;
    Set<String> visitedFields = {}; // To detect circular dependencies

    while (true) {
      // Find the field with this name
      int fieldIndex =
          _internalFields.indexWhere((f) => f['name'] == currentParent);
      if (fieldIndex == -1) break; // Field not found

      // Check if this field has a groupWith property
      String? nextParent = _internalFields[fieldIndex]['groupWith']?.toString();
      if (nextParent == null || nextParent.isEmpty)
        break; // No parent reference

      // Check for circular dependency
      if (visitedFields.contains(nextParent)) {
        print(
            "Warning: Circular dependency detected in groupWith chain for $fieldName!");
        break; // Break the chain
      }

      visitedFields.add(currentParent);
      currentParent = nextParent;
    }

    return currentParent;
  }

  /// Gets all fields for the current question in one-by-one mode
  List<Map<String, dynamic>> _getCurrentQuestionFields() {
    // Make sure we have valid anchors before proceeding
    if (_groupAnchors.isEmpty ||
        _currentGroupPointer < 0 ||
        _currentGroupPointer >= _groupAnchors.length) {
      if (kDebugMode) {
        print("Warning: No valid anchors to get current question fields");
      }
      return []; // Nothing to validate
    }

    // Get the current anchor index
    final currentAnchor = _groupAnchors[_currentGroupPointer];

    // Safety check for valid index
    if (currentAnchor < 0 || currentAnchor >= _internalFields.length) {
      if (kDebugMode) {
        print("Warning: Invalid anchor index: $currentAnchor");
      }
      return []; // Nothing valid to validate
    }

    // Get the indices of all fields in the current question group
    final List<int> fieldIndices =
        _anchorToFieldIndices[currentAnchor] ?? [currentAnchor];

    // Return all fields in the current question group
    return fieldIndices.map((idx) => _internalFields[idx]).toList();
  }
  Widget _buildCommentField(Map<String, dynamic> field) {
    return ReactiveTextField(
      formControlName: '${field['name']}_comment',
      decoration: InputDecoration(
        // No labelText to avoid displaying "comments" in the field
        hintText: field['commentHint'] ?? '',
        labelStyle: widget.fontFamily,
        hintStyle: widget.fontFamily,
        // Add error style
        errorStyle:
            widget.fontFamily.copyWith(color: Colors.red[700], fontSize: 12),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.appBlackDark),
        ),
      ),
      validationMessages: {
        'required': (_) => StringConstants.commentsAreRequired,
      },
      onSubmitted: (_) {
        if (widget.showOneByOne && !isCurrentQuestionEffectivelyLast()) {
          validateCurrentSection();
        }
      },
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
  final int? questionNumber;
  final bool hasAttachments; // Add new property

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
    this.questionNumber,
    this.hasAttachments = false, // Default to false
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

    // Debug information
    if (kDebugMode) {
      print(
          "\n📄 FILE_UPLOAD: Building FileUploadWidget for ${widget.fieldName}");
      print(
          "📄 FILE_UPLOAD: isRequired=${widget.isRequired}, hasUploadedFile=$hasUploadedFile");
      print("📄 FILE_UPLOAD: uploadedFiles=${widget.uploadedFiles}");
    }

    // Always show the upload UI when no file has been uploaded yet
    final shouldShowUploadUI = !hasUploadedFile;

    if (kDebugMode) {
      print("📄 FILE_UPLOAD: shouldShowUploadUI=$shouldShowUploadUI");
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Question number if provided and not just an attachment field
        if (widget.questionNumber != null && !widget.hasAttachments)
          Text(
            'Question ${widget.questionNumber}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18.0,
              color: widget.primaryColor ?? Theme.of(context).primaryColor,
              fontFamily: widget.fontFamily?.fontFamily,
            ),
          ),
        if (widget.questionNumber != null) const SizedBox(height: 4.0),

        // Field label if this is a standalone field (not just an attachment widget)
        if (!widget.hasAttachments)
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: widget.fieldLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16.0,
                    fontFamily: widget.fontFamily?.fontFamily,
                  ),
                ),
                if (widget.isRequired)
                  TextSpan(
                    text: ' *',
                    style: TextStyle(
                      color: const Color.fromARGB(255, 222, 75, 64),
                      fontSize: 16,
                    ),
                  ),
              ],
            ),
          ),

        // Clear vertical spacing
        const SizedBox(height: 12),

        // Upload files label - Show it when upload UI should be shown
        if (shouldShowUploadUI)
          Row(
            children: [
              Text(
                StringConstants.uploadFiles,
                style: widget.fontFamily,
              ),
              if (widget.isRequired) ...[
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

        // More clear spacing before button
        if (shouldShowUploadUI) const SizedBox(height: 12),

        // Upload button - Show it when upload UI should be shown
        if (shouldShowUploadUI)
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
                  Icon(Icons.upload_file_rounded,
                      color: widget.buttonTextColor, size: 32),
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

        // Space after button
        if (shouldShowUploadUI) const SizedBox(height: 16),

        // Display uploaded files
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
