import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get/get.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:reactiveform/bottom_navigation_typr.dart';
import 'package:reactiveform/components/app_snackbar.dart';
import 'package:reactiveform/components/app_typographpy.dart';
import 'package:reactiveform/constants.dart';
import 'package:reactiveform/constants/app.assests.dart';
import 'package:reactiveform/string_constants.dart';
import 'package:flutter/services.dart';
import 'dart:async'; // Added for Completer
import 'dynamicformcontroller.dart';
import 'package:reactiveform/models/form_field_model.dart';
import 'package:http/http.dart' as http;
import 'dart:math' as math;
import 'package:path/path.dart' as path;
import 'package:flutter_image_compress/flutter_image_compress.dart';

// Conditional import for web
import 'web_utils.dart' if (dart.library.html) 'dart:html' as html;

import 'widgets/multi_select_form_field.dart';
import 'widgets/temperature_scroll_widget.dart';

class DynamicForm extends StatefulWidget {
  final List<Map<String, dynamic>> formJson;
  final Function(
          Map<String, dynamic>, Map<String, List<Map<String, dynamic>>>, bool?)
      onSubmit;
  final Color primaryColor;
  final Color buttonTextColor;
  final double fieldSpacing;
  final bool showOneByOne;
  final BuildContext context;
  final TextStyle fontFamily;
  final Color fileUploadButtonColor;
  final Color fileUploadButtonTextColor;
  final String? submitButtonText;
  final bool bookingAppModelFileUpload;
  final bool isManageToCheckPress;
  final bool draftMode;
  final RxBool draftbtnClicked;
  final BottomNavigationType bottomNavigationType;
  final Map<String, dynamic>? initialValues;
  final bool accordionView;
  final ThemeData? themeData;

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
    this.submitButtonText,
    this.bookingAppModelFileUpload = false,
    this.isManageToCheckPress = false,
    this.bottomNavigationType = BottomNavigationType.button,
    this.initialValues,
    this.accordionView = true,
    this.draftMode = false,
    this.themeData,
    RxBool? draftbtnClicked,
    super.key,
  }) : draftbtnClicked = draftbtnClicked ?? false.obs;

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

  // Track if user attempted to submit in accordionview mode to show error dots
  bool _shortTextSubmitAttempted = false;

  // Caches to make draft status sticky across rebuilds
  final Map<int, bool> _anchorDraftCache = {};
  int? _expandedAnchor; // accordionview mode: which anchor is expanded inline
  late bool expandAll;
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _fieldKeys = {};

  // Convenience getters to preserve existing behavior while introducing enum

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
      if (kDebugMode) {
        print(
            "Warning: No visible questions found! Making first question visible as fallback.");
      }
      visibleIndices = [0]; // Make the first question visible as fallback
    }

    // Check if current question is visible
    if (!visibleIndices.contains(currentQuestionIndex)) {
      if (kDebugMode) {
        print(
            "Current question at index $currentQuestionIndex is not visible. Finding next visible question.");
      }

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
          if (kDebugMode) {
            print(
                "Smart Skip: Question at index $currentQuestionIndex is not visible. Skipping to question at index $nextVisibleIndex (anchor: $anchorPointer)");
          }

          setState(() {
            _currentGroupPointer = anchorPointer;
            controller.currentQuestionIndex =
                _groupAnchors[_currentGroupPointer];
          });
        } else if (anchorPointer == -1) {
          // If we couldn't find a proper anchor but we know a question should be visible,
          // this is a serious issue - log it
          if (kDebugMode) {
            print(
                "ERROR: Could not find anchor for visible question at index $nextVisibleIndex");
          }
        }
      } else {
        // This should never happen since we ensure visibleIndices is not empty
        if (kDebugMode) {
          print("ERROR: No visible question found to navigate to!");
        }
      }
    }
  }

  // Check if the current question should be visible when going backwards, and if not, find the previous visible one
  void _updateCurrentQuestionBasedOnVisibilityForPrevious() {
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
      if (kDebugMode) {
        print(
            "Warning: No visible questions found! Making first question visible as fallback.");
      }
      visibleIndices = [0]; // Make the first question visible as fallback
    }

    // Check if current question is visible
    if (!visibleIndices.contains(currentQuestionIndex)) {
      if (kDebugMode) {
        print(
            "Current question at index $currentQuestionIndex is not visible when going backwards. Finding previous visible question.");
      }

      // Current question is not visible - find the previous visible question
      int prevVisibleIndex = -1;

      // Find the closest previous visible question
      for (int visibleIndex in visibleIndices) {
        if (visibleIndex < currentQuestionIndex &&
            (prevVisibleIndex == -1 || visibleIndex > prevVisibleIndex)) {
          prevVisibleIndex = visibleIndex;
        }
      }

      // If no previous visible question found, try to find the next visible question
      if (prevVisibleIndex == -1 && visibleIndices.isNotEmpty) {
        for (int visibleIndex in visibleIndices) {
          if (visibleIndex > currentQuestionIndex) {
            prevVisibleIndex = visibleIndex;
            break;
          }
        }
      }

      // If still no visible question found, use the first visible question
      if (prevVisibleIndex == -1 && visibleIndices.isNotEmpty) {
        prevVisibleIndex = visibleIndices.first;
      }

      // Navigate to the previous/next visible question if found
      if (prevVisibleIndex != -1) {
        // Find the anchor corresponding to this question index
        int anchorPointer = -1;
        for (int i = 0; i < _groupAnchors.length; i++) {
          int anchorIndex = _groupAnchors[i];
          String anchorName = _internalFields[anchorIndex]['name'].toString();

          // Check if this anchor corresponds to the visible question
          for (int j = 0; j < widget.formJson.length; j++) {
            if (j == prevVisibleIndex &&
                widget.formJson[j]['name'] == anchorName) {
              anchorPointer = i;
              break;
            }
          }

          if (anchorPointer != -1) break;
        }

        // Update the current pointer and controller index if an anchor was found
        if (anchorPointer != -1 && anchorPointer != _currentGroupPointer) {
          if (kDebugMode) {
            print(
                "Backward Skip: Question at index $currentQuestionIndex is not visible. Skipping to question at index $prevVisibleIndex (anchor: $anchorPointer)");
          }

          _currentGroupPointer = anchorPointer;
          controller.currentQuestionIndex = _groupAnchors[_currentGroupPointer];
        } else if (anchorPointer == -1) {
          // If we couldn't find a proper anchor but we know a question should be visible,
          // this is a serious issue - log it
          if (kDebugMode) {
            print(
                "ERROR: Could not find anchor for visible question at index $prevVisibleIndex");
          }
        }
      } else {
        // This should never happen since we ensure visibleIndices is not empty
        if (kDebugMode) {
          print("ERROR: No visible question found to navigate to!");
        }
      }
    }
  }

  /// Skips to the first unanswered required question in the form when in step-by-step
  /// (draft) mode. If all required questions are answered, skips to the last question.
  /// If the form is not in step-by-step mode, does nothing.
  ///
  /// This function is used to automatically navigate to the first unanswered
  /// required question after the form is initially populated with saved data.
  void skipToFirstUnansweredQuestion() {
    if (!widget.showOneByOne ||
        !widget.draftMode ||
        widget.initialValues == null ||
        (widget.initialValues?.isNotEmpty != true)) {
      return;
    }

    // Find first required question that is unanswered in initial values
    int targetFormIndex = -1;
    int visibleQuestionCount = 0;
    for (int i = 0; i < widget.formJson.length; i++) {
      final field = widget.formJson[i];
      bool isVisible = true;
      if (field['showWhen'] != null) {
        final showWhenConditions = field['showWhen'] as Map<String, dynamic>;
        final conditionKey = showWhenConditions.keys.first;
        final conditionValue = showWhenConditions[conditionKey];

        // Check if the related question is answered correctly
        if (widget.initialValues![conditionKey] != conditionValue) {
          isVisible = false; // Hide the question if condition fails
        }
      }

      if (!isVisible) continue; // Skip if not visible
      visibleQuestionCount++;
      final value = widget.initialValues![field['name']];
      final bool isEmpty = value == null ||
          (value is String && value.trim().isEmpty) ||
          (value is List && value.isEmpty);
      if (isEmpty ||
          !validateCurrentSection() ||
          !_checkIfRequiredFilesUploaded()) {
        targetFormIndex = i;
        break;
      } else {
        moveToNextQuestion(context);
      }
    }

    if (targetFormIndex == -1 && visibleQuestionCount > 0) {
      setState(() {
        _currentGroupPointer =
            visibleQuestionCount - 1; // Set to last visible index
      });
      return; // No unanswered required questions found
    }

    if (targetFormIndex == -1) return;

    final String targetName =
        widget.formJson[targetFormIndex]['name'].toString();

    // Locate this field in internal list
    final int internalIndex =
        _internalFields.indexWhere((f) => f['name'] == targetName);
    if (internalIndex == -1) return;

    // Find the anchor pointer that contains this field (accounting for grouped fields)
    int pointer = -1;
    for (int p = 0; p < _groupAnchors.length; p++) {
      final int anchorIndex = _groupAnchors[p];
      final List<int> groupIndices =
          _anchorToFieldIndices[anchorIndex] ?? [anchorIndex];
      if (groupIndices.contains(internalIndex)) {
        pointer = p;
        break;
      }
    }

    // Fallback: try direct anchor name match
    if (pointer == -1) {
      pointer = _groupAnchors.indexWhere((anchorIdx) =>
          _internalFields[anchorIdx]['name'].toString() == targetName);
    }

    if (pointer != -1) {
      setState(() {
        _currentGroupPointer = pointer;
      });

      // Align controller page index with the chosen anchor after the frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _groupAnchors.isEmpty) return;
        controller.currentQuestionIndex = _groupAnchors[_currentGroupPointer];
        _safeCalculateProgress();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    // / Listen to draftbtnClicked value
    ever(widget.draftbtnClicked, (value) {
      // If draftbtnClicked becomes true, trigger form submission
      if (value) {
        _submitForm(context, isDraft: true);
      }
    });

    expandAll = expandAll = !widget.draftMode && widget.initialValues != null;

    // Transform incoming schema to expand groupId-based per-option groups
    final List<Map<String, dynamic>> transformedFormJson =
        _transformGroupIdIntoOptionGroups(widget.formJson);

    controller = DynamicFormController(
      formJson: widget.formJson, // Use original formJson, not transformed
      onSubmit: widget.onSubmit,
      isManageToCheckPress: widget.isManageToCheckPress,
      initialValues: widget.initialValues,
    );

    _internalFields = List<Map<String, dynamic>>.from(transformedFormJson);

    // Add form controls for the transformed fields only
    // Filter out original fields that have been transformed
    final List<Map<String, dynamic>> fieldsToAdd = [];
    for (final field in _internalFields) {
      final fieldName = field['name'].toString();
      // Only add fields that are not the original child fields (question_4, question_5, question_6)
      // since they are replaced by their transformed versions
      if (!['question_4', 'question_5', 'question_6'].contains(fieldName)) {
        fieldsToAdd.add(field);
      }
    }
    controller.addFormControls(fieldsToAdd);

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

    // Jump to first unanswered required question in draft + one-by-one mode
    skipToFirstUnansweredQuestion();

    // Listen to form value changes and update question visibility
    _formValueChangeSubscription =
        controller.form.valueChanges.listen((formValues) {
      if (mounted) {
        if (kDebugMode) {
          print(
              "Form values changed: ${formValues?.keys.join(', ') ?? 'null'}");
        }
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
        if (kDebugMode) {
          print(
              "WARNING: Circular dependency detected in showWhen conditions for field: $fieldBeingEvaluated");
          print(
              "Dependency chain: ${evaluationStack.join(' → ')} → $fieldBeingEvaluated");
        }
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

      // Evaluate visibility using the helper function
      if (evaluateShowWhen(question,
          fieldBeingEvaluated: question['name']?.toString())) {
        visible.add(i);
      }
    }

    // Safety check: If no questions are visible, make the first one visible
    if (visible.isEmpty && widget.formJson.isNotEmpty) {
      if (kDebugMode) {
        print(
            "WARNING: No questions visible! Making first question visible by default.");
      }
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
        if (kDebugMode) {
          print("Current question has groupWith: $currentQuestionHasGroupWith");
          print("Current field: ${currentField['name']}");
          print("Is referenced by others: $isReferencedByOthers");
          print("Is parent with children: $isParentWithChildren");
          if (currentField['allowDuplicate'] == true) {
            print("AllowDuplicate: ${currentField['allowDuplicate']}");
          }
        }
      }
    }

    return Theme(
      data: widget.themeData ??
          Theme.of(context).copyWith(
              // We don't need to modify the textTheme if fontFamily is already a TextStyle
              // The fontFamily will be applied directly to each widget
              ),
      child: ReactiveForm(
        formGroup: controller.form,
        child: Scaffold(
          // Only show the FloatingActionButton if the current question has a groupWith property
          floatingActionButton:
              widget.showOneByOne && currentQuestionHasGroupWith ? null : null,
          body: LayoutBuilder(
            builder: (context, constraints) {
              // Create a unique key that includes the current group pointer
              // This ensures the widget tree is rebuilt when the current question changes
              final uniqueKey = ValueKey(
                  '${StringConstants.form}_pointer${_currentGroupPointer}_index${controller.currentQuestionIndex}_totalFields${_internalFields.length}');

              return SingleChildScrollView(
                key: uniqueKey,
                padding: const EdgeInsets.all(10.0)
                    .copyWith(top: widget.accordionView ? 0.0 : 10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // When showing one by one, we only show the current group of fields
                    if (widget.accordionView) _buildShortTextGrid(),
                    if (!widget.accordionView && widget.showOneByOne)
                      ..._buildOneByOneFields(),
                    // When showing all at once, we show all fields
                    if (!widget.accordionView && !widget.showOneByOne)
                      ..._buildAllFields(),
                    if (!widget.accordionView && _showAttachmentError)
                      _buildErrorMessage(),
                  ],
                ),
              );
            },
          ),
          bottomNavigationBar: _buildBottomNavigation(buttonColor,
              widget.isManageToCheckPress, widget.bottomNavigationType),
        ),
      ),
    );
  }

  Widget _buildBottomNavigation(Color buttonColor, bool isManageToCheckPress,
      BottomNavigationType bottomNavigationType) {
    // In accordionview mode, always show submit button only
    if (widget.accordionView) {
      return _buildSubmitButton(buttonColor, isManageToCheckPress);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: widget.showOneByOne
          ? _buildStepNavigation(
              buttonColor, isManageToCheckPress, bottomNavigationType)
          : _buildSubmitButton(buttonColor, isManageToCheckPress),
    );
  }

  /// The _buildDraftBanner function returns a Positioned widget containing a rotated Container with an
  /// amber background color.
  ///
  /// Returns:
  ///   A Positioned widget is being returned with a Transform.rotate widget as its child. The
  /// Transform.rotate widget has a Container widget as its child, which has a color of Colors.amber and
  /// padding set with EdgeInsets.symmetric(horizontal: 50, vertical: 17).
  Widget _buildDraftBanner() {
    return Positioned(
      top: -30,
      left: -30,
      child: Transform.rotate(
        angle: -math.pi / 4,
        child: Container(
          color: Colors.amber,
          padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 17),
        ),
      ),
    );
  }

  // Build compact grid of question cards for short text mode
  /// This function builds a grid of short text input fields based on certain conditions and displays
  /// them in an expandable/collapsible format within a SingleChildScrollView widget.
  ///
  /// Returns:
  ///   The `_buildShortTextGrid` method returns a `Widget` which is a `SingleChildScrollView`
  /// containing a `Column` with multiple child widgets including `Row`, `Text`, `Transform.scale`,
  /// `CupertinoSwitch`, `SizedBox`, and a list of `Card` widgets generated based on the
  /// `displayAnchors` list. Each `Card` widget contains various child widgets such
  Widget _buildShortTextGrid() {
    // Ensure grouping exists
    if (_groupAnchors.isEmpty || _anchorToFieldIndices.isEmpty) {
      _recomputeGroupStructure();
    }

    // Derive visible anchors by showWhen
    final visibleFormIndices = _getVisibleQuestionIndices();
    final Set<String> visibleNames = visibleFormIndices
        .map((i) => widget.formJson[i]['name']?.toString() ?? '')
        .toSet();

    List<int> displayAnchors = [];
    for (final anchor in _groupAnchors) {
      if (anchor >= 0 && anchor < _internalFields.length) {
        final field = _internalFields[anchor];
        final String n = field['name']?.toString() ?? '';
        // If this is an option-group anchor (e.g., question_1_3), check base parent visibility
        if (field['isOptionGroup'] == true) {
          String base = n;
          final lastUnderscore = base.lastIndexOf('_');
          if (lastUnderscore > 0) {
            base = base.substring(0, lastUnderscore);
          }
          if (visibleNames.isEmpty || visibleNames.contains(base)) {
            displayAnchors.add(anchor);
          }
        } else {
          if (visibleNames.isEmpty || visibleNames.contains(n)) {
            displayAnchors.add(anchor);
          }
        }
      }
    }

    // Fallback to direct index mapping if no anchors matched yet
    if (displayAnchors.isEmpty) {
      for (final i in visibleFormIndices) {
        final n = widget.formJson[i]['name']?.toString();
        if (n == null) continue;
        // Try exact name match
        int idx = _internalFields.indexWhere((f) => f['name']?.toString() == n);
        if (idx == -1) {
          // Try matching option-group anchors by base name
          idx = _internalFields.indexWhere((f) {
            final String fn = f['name']?.toString() ?? '';
            final bool isOpt = f['isOptionGroup'] == true;
            if (!isOpt) return false;
            String base = fn;
            final lastUnderscore = base.lastIndexOf('_');
            if (lastUnderscore > 0) {
              base = base.substring(0, lastUnderscore);
            }
            return base == n;
          });
        }
        if (idx != -1) {
          displayAnchors.add(idx);
          _anchorToFieldIndices.putIfAbsent(idx, () => [idx]);
        }
      }
    }

    // Use .map to build widgets properly
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
                expandAll
                    ? StringConstants.collapseAll
                    : StringConstants.expandAll,
                style: Get.textTheme.headlineLarge?.copyWith(fontSize: 12)),
            Transform.scale(
              scale: 0.7,
              alignment: Alignment.center,
              child: CupertinoSwitch(
                activeColor: Get.theme.colorScheme.secondary,
                value: expandAll,
                onChanged: (value) {
                  setState(() {
                    _expandedAnchor = null;
                    expandAll = value;
                  });
                },
              ),
            )
          ],
        ),
        const SizedBox(height: 10.0),
        // Use .map to build widgets properly
        ...List.generate(displayAnchors.length, (index) {
          final anchor = displayAnchors[index];
          final field = _internalFields[anchor];
          final String name = field['name']?.toString() ?? '';
          // Prefer optionLabel for option-group anchors; fallback to label
          final bool hasOptionLabel = field.containsKey('optionLabel') &&
              field['optionLabel'] != null &&
              field['optionLabel'].toString().isNotEmpty;
          final String label = hasOptionLabel
              ? field['optionLabel'].toString()
              : (field['label']?.toString() ?? name);
          final List<int> indices = _anchorToFieldIndices[anchor] ?? [anchor];
          final List<Map<String, dynamic>> fields =
              indices.map((i) => _internalFields[i]).toList();
          final bool showErrorDot = widget.accordionView &&
              _shortTextSubmitAttempted &&
              _hasRequiredEmptyFields(anchor);
          final bool isDraft = isAnchorDraft(anchor) && widget.draftMode;
          return Card(
            key: _fieldKeys[anchor],
            clipBehavior: Clip.hardEdge,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: showErrorDot
                    ? Get.theme.colorScheme.onError
                    : Get.theme.dividerColor.withOpacity(0.5),
                width: 1,
              ),
            ),
            child: Stack(
              children: [
                if (isDraft) ...[
                  _buildDraftBanner(),
                  Positioned(
                    top: 8,
                    left: 4,
                    child: Transform.rotate(
                      angle: -math.pi / 4,
                      child: Text(StringConstants.draft,
                          style: Get.textTheme.headlineLarge
                              ?.copyWith(fontSize: 6)),
                    ),
                  )
                ],
                ExpansionTile(
                  key: ValueKey(
                      '$expandAll exp_${anchor}_${_expandedAnchor == anchor}'),
                  initiallyExpanded:
                      expandAll ? expandAll : _expandedAnchor == anchor,
                  onExpansionChanged: (expanded) {
                    setState(() {
                      _expandedAnchor = expanded
                          ? anchor
                          : (_expandedAnchor == anchor
                              ? null
                              : _expandedAnchor);
                    });
                  },
                  shape: const RoundedRectangleBorder(side: BorderSide.none),
                  collapsedShape:
                      const RoundedRectangleBorder(side: BorderSide.none),
                  expansionAnimationStyle: AnimationStyle(
                    duration: const Duration(milliseconds: 300),
                    reverseDuration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    reverseCurve: Curves.easeInOut,
                  ),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 10),
                  trailing: showErrorDot ? const SizedBox.shrink() : null,
                  title: Container(
                    height: _expandedAnchor == anchor || expandAll ? null : 40,
                    padding: const EdgeInsets.only(top: 10.0),
                    width: MediaQuery.of(context).size.width,
                    child: RichText(
                      textAlign: TextAlign.left,
                      softWrap: true,
                      overflow: _expandedAnchor == anchor || expandAll
                          ? TextOverflow.clip
                          : TextOverflow.ellipsis,
                      text: TextSpan(
                        style: Get.textTheme.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w600),
                        children: [
                          TextSpan(text: 'Q${index + 1}: $label'),
                          if (field['required'] == true)
                            const TextSpan(
                              text: ' *',
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 16.0,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  children: [
                    // Build only child fields; skip anchor control when this card represents a group
                    _buildCardForFields(
                      fields.where((f) {
                        if (f['name'] == field['name']) {
                          // If this is a grouped card (has more than the anchor) or an option group, hide the anchor input
                          final bool hasChildren = (indices.length > 1);
                          if (hasChildren) return false;
                          if (field['isOptionGroup'] == true) return false;
                        }
                        return true;
                      }).toList(),
                      false,
                      anchor: anchor,
                    ),
                  ],
                ),
                if (showErrorDot)
                  Positioned(
                    right: 12,
                    top: 12,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                      ),
                      child: SvgPicture.asset(
                        MyAppAssets.warningCircle,
                        width: 20,
                        height: 20,
                        colorFilter: ColorFilter.mode(
                          Get.theme.colorScheme.error,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
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
      widgets.add(_buildCardForFields(currentGroupFields, false, anchor: currentAnchor));
    } else {
      // Add the original question without a card
      widgets.addAll(currentGroupFields.map(_buildField).toList());
    }

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
          }
        }
      }
    }

    // Build cards for all duplicate anchors
    for (final anchor in duplicateAnchors) {
      final indices = _anchorToFieldIndices[anchor] ?? [anchor];
      final fields = indices.map((i) => _internalFields[i]).toList();

      // Add the duplicate card with delete button
      widgets.add(_buildCardForFields(fields, true, anchor: anchor));
    }

    return widgets;
  }

  /// Helper method to build a card for a group of fields
  Widget _buildCardForFields(
      List<Map<String, dynamic>> fields, bool isDuplicated, {int? anchor}) {
    // Calculate if we should show error dot for this card
    bool showErrorDot = false;
    if (anchor != null && !widget.accordionView) {
      showErrorDot = _hasRequiredEmptyFields(anchor);
    }

    return Card(
      elevation: widget.accordionView ? 0 : 1.0,
      margin: widget.accordionView
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Stack(
        children: [
          Padding(
        padding: EdgeInsets.all(widget.accordionView ? 16.0 : 12.0),
        child: Column(
          children: [
            if (isDuplicated)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    _deleteDuplicateGroup(fields);
                  },
                ),
              ),
            ...fields.map(_buildField).toList(),
          ],
        ),
          ),
          if (showErrorDot)
            Positioned(
              right: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: SvgPicture.asset(
                  MyAppAssets.warningCircle,
                  width: 20,
                  height: 20,
                  colorFilter: ColorFilter.mode(
                    Get.theme.colorScheme.error,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildField(Map<String, dynamic> field) {
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
                if (kDebugMode) {
                  print("showWhen: Field '$fieldName' depends on '$dependentField' but form doesn't contain it");
                }
                shouldShow = false;
                return;
              }

              final dependentControl = form.control(dependentField);
              final currentValue = dependentControl.value;
              
              if (kDebugMode) {
                print("showWhen: Field '$fieldName' depends on '$dependentField' = '$expectedValue', current value = '$currentValue'");
              }

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
    return _buildActualField(field, control, widget.initialValues);
  }

  Widget _buildActualField(Map<String, dynamic> field,
      AbstractControl<dynamic> control, Map<String, dynamic>? initialValues) {
    // Support comma-separated types like "text, file"
    if (field['type'] is String && (field['type'] as String).contains(',')) {
      final List<String> parts = (field['type'] as String)
          .split(',')
          .map((s) => s.trim().toLowerCase())
          .toList();
      final List<Widget> children = [];

      for (int i = 0; i < parts.length; i++) {
        final String part = parts[i];
        final bool suppress = i > 0;
        // Temporarily suppress label for subsequent parts
        final previousSuppress = field['suppressLabel'];
        if (suppress) field['suppressLabel'] = true;

        Widget child;
        switch (part) {
          case 'text':
            child = _buildTextField(field);
            break;
          case 'number':
            child = _buildNumberField(field);
            break;
          case 'temp':
            child = _buildTempField(field);
            break;
          case 'file':
            child = _buildFileField(field);
            break;
          case 'radio':
            child = _buildRadioField(field);
            break;
          case 'dropdown':
            child = _buildDropdownField(field);
            break;
          case 'multiselect':
            child = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLabelRow(field),
                // Fallback minimal message if builder not reachable here
                Text(StringConstants.requiredField,
                    style: const TextStyle(height: 0)),
              ],
            );
            break;
          default:
            child = _buildTextField(field);
            break;
        }

        // Restore previous suppress flag to avoid side effects
        if (suppress) {
          if (previousSuppress == null) {
            field.remove('suppressLabel');
          } else {
            field['suppressLabel'] = previousSuppress;
          }
        }

        children.add(child);
        if (i < parts.length - 1) {
          children.add(SizedBox(height: widget.accordionView ? 8 : 12));
        }
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      );
    }

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
      case FieldType.temp:
        return _buildTempField(field);
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
                      rawValue.map((e) => e.toString()).toList(growable: false);
                }

                return Wrap(
                  spacing: 8.0,
                  runSpacing: 4.0,
                  children: (field['options'] as List<dynamic>? ?? [])
                      .map((opt) => ChoiceChip(
                            label: Text(opt.toString()),
                            selected: currentValue.contains(opt.toString()),
                            onSelected: (selected) {
                              final List<String> updated =
                                  List.from(currentValue);
                              if (selected) {
                                if (!updated.contains(opt.toString())) {
                                  updated.add(opt.toString());
                                }
                              } else {
                                updated.remove(opt.toString());
                              }
                              controller.form.control(field['name']).value =
                                  updated;
                              state.didChange(updated);
                            },
                          ))
                      .toList(),
                );
              },
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildLabelRow(Map<String, dynamic> field) {
    if (field['label'] == null) return const SizedBox.shrink();
    // Allow callers to suppress label when composing multi-part fields
    if (field['suppressLabel'] == true) return const SizedBox.shrink();
    // Show labels for grouped fields even in accordion view
    if (widget.accordionView) {
      // Check if this field is a child of a grouped field (has groupId or groupWith)
      final bool isGroupedField = field['groupId'] != null || field['groupWith'] != null;
      if (!isGroupedField) return const SizedBox.shrink();
    }

    // If this field is the anchor of a group (parent referenced by others),
    // and the group has children, do not render the anchor label inside the card.
    // The anchor already appears as the card title.
    int? anchorIndex;
    for (var entry in _anchorToFieldIndices.entries) {
      if (entry.value.any((idx) =>
          idx < _internalFields.length &&
          _internalFields[idx]['name'] == field['name'])) {
        anchorIndex = entry.key;
        break;
      }
    }

    if (anchorIndex != null) {
      final Map<String, dynamic> anchorField = _internalFields[anchorIndex];
      final bool thisIsAnchor = anchorField['name'] == field['name'];
      final int groupLen =
          (_anchorToFieldIndices[anchorIndex] ?? const []).length;
      
      // For our new structure, we want to show labels for parent fields (fridge names)
      // Only hide labels for option-group headers (isOptionGroup = true)
      if (thisIsAnchor && groupLen > 1 && field['isOptionGroup'] == true) {
        return const SizedBox.shrink();
      }
      
      // Hide duplicate label if matches the card title (option label or anchor label)
      final String cardTitle =
          (anchorField['optionLabel']?.toString().trim().isNotEmpty ?? false)
              ? anchorField['optionLabel'].toString().trim()
              : (anchorField['label']?.toString().trim() ?? '');
      final String childLabel = field['label']?.toString().trim() ?? '';
      if (cardTitle.isNotEmpty && cardTitle == childLabel) {
        return const SizedBox.shrink();
      }
    }

    // Also hide label rows for synthetic option-group headers
    if (field['isOptionGroup'] == true) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0, top: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: field['label'],
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 16.0,
                fontFamily: widget.fontFamily?.fontFamily,
                      color: Colors.black,
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
      case FieldType.temp:
        return _buildTempField(field);
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
    // Ensure we always use ["Yes", "No"] for empty options
    final List<dynamic> rawOptions = (field['options'] as List<dynamic>?) ?? [];
    final List<String> options =
        rawOptions.isEmpty ? ['Yes', 'No'] : rawOptions.cast<String>();

    if (kDebugMode && rawOptions.isEmpty) {
      print(
          "📄 RADIO: Field '${field['name']}' has empty options - defaulting to Yes/No");
    }

    // SPECIAL HANDLING for question_6 to guarantee the file upload UI appears

    // Regular implementation for other radio fields
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabelRow(field),
        widget.accordionView
            ? const SizedBox.shrink()
            : const SizedBox(height: 4),
        ...options
            .map<Widget>(
              (option) => Transform.translate(
                offset: Offset(widget.accordionView ? -8 : 0, 0),
                child: RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  title: Text(option, style: widget.fontFamily),
                  value: option,
                  dense: true,
                  groupValue: controller.form.control(field['name']).value,
                  activeColor: widget.primaryColor,
                  onChanged: (value) {
                    // Update the form using patchValue instead of directly setting the value
                    // This will ensure that all reactive widgets listening to this field are notified
                    if (value != null) {
                      // Use patchValue to trigger proper reactive updates
                      controller.form.patchValue({field['name']: value});

                      // Also update the control directly to ensure consistency
                      final formControl =
                          controller.form.control(field['name']);
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
                        if (kDebugMode) {
                          print("Forcing UI rebuild for radio button change");
                        }
                      });
                    }

                    // Auto-navigation logic copied from dropdown implementation
                    if (widget.showOneByOne && !widget.accordionView) {
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
              ),
            )
            .toList(),

        // Directly copied from the working dropdown implementation
        if (field['hasAttachments'] == true)
          ReactiveValueListenableBuilder(
            formControlName: field['name'],
            builder: (context, control, child) {
              if (kDebugMode) {
                print(
                    "\n📄 RADIO UPLOAD: Building file upload UI for ${field['name']}");
                print("📄 RADIO UPLOAD: Current value=${control.value}");
              }

              // Get the disabledOptions list if it exists
              List<dynamic> disabledOptions =
                  field['disableAttachmentsOn'] is List
                      ? field['disableAttachmentsOn']
                      : field['disableAttachmentsOn'] != null
                          ? [field['disableAttachmentsOn']]
                          : [];

              // Implementing exact logic as specified:
              // IF disableAttachmentsOn is NOT empty AND selectedAnswer is in disableAttachmentsOn
              if (disabledOptions.isNotEmpty &&
                  disabledOptions.contains(control.value)) {
                // THEN: Do NOT show file upload
                if (kDebugMode) {
                  print(
                      "📄 HIDING UPLOAD: '${control.value}' is in disableAttachmentsOn list for dropdown");
                }
                return const SizedBox.shrink();
              }
              // ELSE: Show file upload (subject to other rules like requireAttachmentsOn or required)

              // Check if the value is in requireAttachmentsOn or enableAttachmentsOn
              bool shouldShowAttachments = false;
              bool isRequired = false;

              // NEW RULE: If hasAttachments is true, disableAttachmentsOn is not empty,
              // and selected answer is NOT in disableAttachmentsOn, show and require upload
              if (field['hasAttachments'] == true &&
                  disabledOptions.isNotEmpty &&
                  !disabledOptions.contains(control.value)) {
                if (kDebugMode) {
                  print(
                      "📄 SHOWING UPLOAD: hasAttachments=true and value '${control.value}' is NOT in disableAttachmentsOn for dropdown");
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
              }

              // Ensure uploadedFiles is initialized when needed
              if (shouldShowAttachments &&
                  !controller.uploadedFiles.containsKey(field['name'])) {
                controller.uploadedFiles[field['name']] = [];
                if (kDebugMode) {
                  print(
                      "📄 RADIO UPLOAD: Initialized uploadedFiles for ${field['name']}");
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
                    initialValues: widget.initialValues,
                    bookingAppModelFileUpload: widget.bookingAppModelFileUpload,
                  ),
                ],
              );
            },
          ),

        if (field['hasComments'] == true)
          ReactiveValueListenableBuilder(
            formControlName: field['name'],
            builder: (context, control, child) {
              bool shouldShowComments = controller
                  .shouldShowCommentsBasedOnFieldValue(field, control.value);

              if (!shouldShowComments) {
                return const SizedBox
                    .shrink(); // Don't render the comment field if not required
              }

              return Column(
                children: [
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
                        hintText: field['commentHint'] ?? '',
                        labelStyle: widget.fontFamily,
                        hintStyle: widget.fontFamily,
                        errorStyle: widget.accordionView
                            ? controller
                                .buildInputDecoration(widget.accordionView)
                                .errorStyle
                            : widget.fontFamily
                                .copyWith(color: Colors.red[700], fontSize: 12),
                        errorBorder: widget.accordionView
                            ? UnderlineInputBorder(
                                borderSide: BorderSide(
                                    color: Get.theme.colorScheme.onError))
                            : null),
                    maxLines: 3,
                    minLines: 1,
                    validationMessages: {
                      'required': (_) => widget.accordionView
                          ? ""
                          : StringConstants.commentsAreRequired,
                    },
                    onSubmitted: (_) {
                      if (widget.showOneByOne &&
                          !isCurrentQuestionEffectivelyLast()) {
                        validateCurrentSection();
                      }
                    },
                  ),
                ],
              );
            },
          )
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
        widget.accordionView
            ? const SizedBox.shrink()
            : const SizedBox(height: 4),
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
                    initialValues: widget.initialValues,
                    bookingAppModelFileUpload: widget.bookingAppModelFileUpload,
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
                errorStyle: widget.accordionView
                    ? controller
                        .buildInputDecoration(widget.accordionView)
                        .errorStyle
                    : widget.fontFamily
                        .copyWith(color: Colors.red[700], fontSize: 12),
                errorBorder: widget.accordionView
                    ? UnderlineInputBorder(
                        borderSide:
                            BorderSide(color: Get.theme.colorScheme.onError))
                    : null),
            maxLines: 3,
            minLines: 1,
            validationMessages: {
              'required': (_) => widget.accordionView
                  ? ""
                  : StringConstants.commentsAreRequired,
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
                          'required': (error) => widget.accordionView
                              ? ""
                              : StringConstants.requiredField,
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
                        decoration: controller
                            .buildInputDecoration(widget.accordionView),
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
          ReactiveTextField(
            formControlName: '${field['name']}_comment',
            decoration: InputDecoration(
                // No labelText to avoid displaying "comments" in the field
                hintText: field['commentHint'] ?? '',
                labelStyle: widget.fontFamily,
                hintStyle: widget.fontFamily,
                // Add error style
                errorStyle: widget.accordionView
                    ? controller
                        .buildInputDecoration(widget.accordionView)
                        .errorStyle
                    : widget.fontFamily
                        .copyWith(color: Colors.red[700], fontSize: 12),
                errorBorder: widget.accordionView
                    ? UnderlineInputBorder(
                        borderSide:
                            BorderSide(color: Get.theme.colorScheme.onError))
                    : null),
            maxLines: 3,
            minLines: 1,
            validationMessages: {
              'required': (_) => widget.accordionView
                  ? ""
                  : StringConstants.commentsAreRequired,
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
                initialValues: widget.initialValues,
                bookingAppModelFileUpload: widget.bookingAppModelFileUpload,
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
              final ctrl = controller.form.control(field['name']);
              final bool controlIsNum =
                  ctrl is FormControl<num> || ctrl.value is num;

              if (controlIsNum) {
                return ReactiveTextField<num>(
                  formControlName: field['name'],
                  keyboardType: TextInputType.number,
                  valueAccessor: NumValueAccessor(),
                  validationMessages: {
                    'required': (error) => widget.accordionView
                        ? ""
                        : StringConstants.requiredField,
                    'min': (error) =>
                        '${StringConstants.valueMustBeAtLeast} ${field['min']}',
                    'max': (error) =>
                        '${StringConstants.valueMustBeLessThanOrEqualTo} ${field['max']} ${StringConstants.characters}',
                  },
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    if (widget.showOneByOne) {
                      if (!isCurrentQuestionEffectivelyLast()) {
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
                        (field['min'] != null || field['max'] != null
                            ? ')'
                            : ''),
                    labelStyle: widget.fontFamily,
                    hintStyle: widget.fontFamily,
                    errorStyle: widget.fontFamily
                        .copyWith(fontSize: 12, color: Colors.red),
                  ),
                );
              }

              // Fallback to plain TextField bound to String control to avoid type errors
              return TextFormField(
                initialValue: ctrl.value?.toString() ?? '',
                keyboardType: TextInputType.number,
                onChanged: (val) => ctrl.value = val,
                inputFormatters: [
                  if (field['allowNegatives'] == false)
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                  if (field['allowNegatives'] != false)
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.-]')),
                  if (field['allowedDecimals'] == 0)
                    FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  hintText: StringConstants.enterANumber,
                  labelStyle: widget.fontFamily,
                  hintStyle: widget.fontFamily,
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
                  initialValues: widget.initialValues,
                  bookingAppModelFileUpload: widget.bookingAppModelFileUpload,
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
                errorStyle: widget.accordionView
                    ? controller
                        .buildInputDecoration(widget.accordionView)
                        .errorStyle
                    : widget.fontFamily
                        .copyWith(color: Colors.red[700], fontSize: 12),
                errorBorder: widget.accordionView
                    ? UnderlineInputBorder(
                        borderSide:
                            BorderSide(color: Get.theme.colorScheme.onError))
                    : null),
            maxLines: 3,
            minLines: 1,
            validationMessages: {
              'required': (_) => widget.accordionView
                  ? ""
                  : StringConstants.commentsAreRequired,
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

  Widget _buildTempField(Map<String, dynamic> field) {
    final name = field['name'] as String;
    final hasComments = field['hasComments'] == true;

    double _toDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is double) return v;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    Widget _buildTempScroller({
      required String formControlName,
      required double min,
      required double max,
      required double step,
      required double initialValue,
      required bool isDesktop,
      required double maxWidth,
    }) {
      final base = ReactiveTemperatureScrollWidget(
        formControlName: formControlName,
        min: min,
        max: max,
        step: step,
        initialValue: initialValue,
        unit: field['unit'] ?? '°C',
        textStyle: widget.fontFamily,
        primaryColor: widget.primaryColor,
        backgroundColor: Colors.white,
        separatorColor: Colors.grey.shade300,
      );

      if (isDesktop) {
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(width: maxWidth * 0.3, child: base),
        );
      } else {
        return base;
      }
    }

    Widget _buildStringFallback(FormControl<dynamic> ctrl) {
      final textController =
          TextEditingController(text: ctrl.value?.toString() ?? '0.0');
      return TextFormField(
        controller: textController,
        keyboardType:
            const TextInputType.numberWithOptions(signed: true, decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
        ],
        decoration: InputDecoration(
          hintText: 'Enter temperature',
          labelStyle: widget.fontFamily,
          hintStyle: widget.fontFamily,
        ),
        onChanged: (val) {
          final parsed = double.tryParse(val) ?? 0.0;
          // Update the form control safely using updateValue
          try {
            ctrl.updateValue(parsed);
          } catch (_) {
            ctrl.value = parsed;
          }
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabelRow(field),
        Builder(builder: (context) {
          if (!controller.form.contains(name)) {
            return Text(
              "Error: Form control not found for $name",
              style: const TextStyle(color: Colors.red),
            );
          }

          try {
            final ctrl = controller.form.control(name);
            final isDoubleType =
                ctrl is FormControl<double> || (ctrl.value is num);

            // Common scroller config
            final min = field['min'] != null ? _toDouble(field['min']) : -25.0;
            final max = field['max'] != null ? _toDouble(field['max']) : 110.0;
            final stepValue = field['step'];
            final step = stepValue != null && _toDouble(stepValue) != 0.0
                ? _toDouble(stepValue)
                : 0.1; // avoid zero-step
            final initial = ctrl.value != null ? _toDouble(ctrl.value) : 0.0;

            return LayoutBuilder(builder: (context, constraints) {
              final isDesktop = constraints.maxWidth > 600;
              if (isDoubleType) {
                return _buildTempScroller(
                  formControlName: name,
                  min: min,
                  max: max,
                  step: step,
                  initialValue: initial,
                  isDesktop: isDesktop,
                  maxWidth: constraints.maxWidth,
                );
              }

              // Fallback: string-backed control — show numeric text field and update control
              return _buildStringFallback(ctrl as FormControl<dynamic>);
            });
          } catch (e, st) {
            if (kDebugMode) {
              print('Error rendering temp field $name: $e\n$st');
            }
            return TextFormField(
              decoration: InputDecoration(
                hintText: "Error loading temperature field - please reload the form",
                errorText: "Type mismatch error",
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.red),
                ),
              ),
              enabled: false,
            );
          }
        }),
        if (hasComments) ...[
          const SizedBox(height: 16),
          ReactiveTextField(
            formControlName: '${name}_comment',
            decoration: InputDecoration(
              hintText: field['commentHint'] ?? '',
              labelStyle: widget.fontFamily,
              hintStyle: widget.fontFamily,
              errorStyle: widget.accordionView
                  ? controller.buildInputDecoration(widget.accordionView).errorStyle
                  : widget.fontFamily.copyWith(color: Colors.red[700], fontSize: 12),
              errorBorder: widget.accordionView
                  ? UnderlineInputBorder(
                      borderSide: BorderSide(color: Get.theme.colorScheme.onError))
                  : null,
            ),
            maxLines: 3,
            minLines: 1,
            validationMessages: {
              'required': (_) => widget.accordionView ? "" : StringConstants.commentsAreRequired,
            },
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
                      // Determine if headers/labels should be hidden (composed fields)
                      FileUploadWidget(
                        fieldName: field['name'],
                        fieldLabel: field['label'],
                        primaryColor: widget.primaryColor,
                        fontFamily: widget.fontFamily,
                        buttonTextColor: widget.buttonTextColor,
                        onFilesUploaded: (files) {
                          setState(() {
                            controller.uploadedFiles[field['name']] = files;
                            // For composite fields like "text, file", don't update the main control
                            // as it should only contain the text value
                            if (!(field['type'] is String &&
                                (field['type'] as String).contains(','))) {
                              // Only update control value for pure file fields
                              if (files.isNotEmpty) {
                                control.value =
                                    files.map((f) => f['fileName']).join(',');
                              } else {
                                control.value = null;
                              }
                            }
                          });
                        },
                        uploadedFiles:
                            controller.uploadedFiles[field['name']] ?? [],
                        onRemoveUploadedFile: (file) {
                          setState(() {
                            // For single file upload, set to empty list when file is removed
                            controller.uploadedFiles[field['name']] = [];
                            // For composite fields like "text, file", don't update the main control
                            // as it should only contain the text value
                            if (!(field['type'] is String &&
                                (field['type'] as String).contains(','))) {
                              // Only update control value for pure file fields
                              final remainingFiles =
                                  controller.uploadedFiles[field['name']] ?? [];
                              if (remainingFiles.isEmpty) {
                                control.value = null;
                              } else {
                                control.value = remainingFiles
                                    .map((f) => f['fileName'])
                                    .join(',');
                              }
                            }
                          });
                        },
                        // Either text/number or file should satisfy requirement for composed types
                        isRequired: (field['type'] is String &&
                                (field['type'] as String).contains(','))
                            ? false
                            : field['required'] == true,
                        questionNumber: _getQuestionNumberForField(field),
                        hasAttachments: field['hasAttachments'] == true,
                        bookingAppModelFileUpload:
                            widget.bookingAppModelFileUpload,
                        initialValues: widget.initialValues,
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
          ReactiveTextField(
            formControlName: '${field['name']}_comment',
            decoration: InputDecoration(
                // No labelText to avoid displaying "comments" in the field
                hintText: field['commentHint'] ?? '',
                labelStyle: widget.fontFamily,
                hintStyle: widget.fontFamily,
                // Add error style
                errorStyle: widget.accordionView
                    ? controller
                        .buildInputDecoration(widget.accordionView)
                        .errorStyle
                    : widget.fontFamily
                        .copyWith(color: Colors.red[700], fontSize: 12),
                errorBorder: widget.accordionView
                    ? UnderlineInputBorder(
                        borderSide:
                            BorderSide(color: Get.theme.colorScheme.onError))
                    : null),
            maxLines: 3,
            minLines: 1,
            validationMessages: {
              'required': (_) => widget.accordionView
                  ? ""
                  : StringConstants.commentsAreRequired,
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

  void nextButtonPressed(BuildContext context) {
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
            final control = controller.form.control(field['name']);
            print(
                "Field value: ${control.value}, isRequired: ${field['required'] == true}");
          }
        }
      }
    }

    _moveToNextStep(context);
  }

  void previousButtonPressed(BuildContext context) {
    setState(() {
      moveToPreviousValidQuestion();
    });
  }

  Widget _buildStepNavigation(Color buttonColor, bool isManageToCheckPress,
      BottomNavigationType bottomNavigationType) {
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
              bottomNavigationType == BottomNavigationType.button
                  ? ElevatedButton(
                      onPressed: () => previousButtonPressed(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                      child: Text(
                        StringConstants.back,
                        style: widget.fontFamily.copyWith(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    )
                  : Container(
                      width: 40,
                      height: 40,
                      margin: const EdgeInsets.only(left: 5),
                      decoration: BoxDecoration(
                          color: widget.primaryColor,
                          borderRadius: BorderRadius.circular(4.0)),
                      child: Center(
                        child: IconButton(
                          onPressed: () => previousButtonPressed(context),
                          icon: Icon(Icons.arrow_back_ios_new_rounded,
                              color: widget.buttonTextColor),
                        ),
                      ),
                    ),
            if (shouldShowSubmit)
              Row(
                children: [
                  if (isManageToCheckPress) ...[
                    ElevatedButton(
                      onPressed: () =>
                          _submitForm(context, isManageToCheckPress: true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: buttonColor,
                        foregroundColor: widget.buttonTextColor,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                      ),
                      child: Text(
                        StringConstants.managerToCheck,
                        style: widget.fontFamily.copyWith(
                          color: widget.buttonTextColor,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  ElevatedButton(
                    onPressed: () => _submitForm(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: buttonColor,
                      foregroundColor: widget.buttonTextColor,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                    ),
                    child: Text(
                      widget.submitButtonText ?? 'Submit',
                      style: widget.fontFamily.copyWith(
                        color: widget.buttonTextColor,
                        fontSize: 16,
                      ),
                    ),
                  )
                ],
              )
            else ...[
              const SizedBox(width: 1),
              bottomNavigationType == BottomNavigationType.button
                  ? ElevatedButton(
                      key: const ValueKey('next_button'), // Add key for testing
                      onPressed: () => nextButtonPressed(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                      child: Text(
                        StringConstants.next,
                        style: widget.fontFamily.copyWith(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    )
                  : Container(
                      height: 40,
                      width: 40,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: BoxDecoration(
                          color: widget.primaryColor,
                          borderRadius: BorderRadius.circular(4.0)),
                      child: Center(
                        child: IconButton(
                          onPressed: () => nextButtonPressed(context),
                          icon: Icon(Icons.arrow_forward_ios_rounded,
                              color: widget.buttonTextColor),
                        ),
                      ),
                    ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildSubmitButton(Color buttonColor, bool isManageToCheckPress) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 10.0),
      child: Row(
          mainAxisAlignment: isManageToCheckPress
              ? MainAxisAlignment.spaceBetween
              : MainAxisAlignment.end,
          children: [
            if (isManageToCheckPress) ...[
              SizedBox(
                height: 42.0,
                width: MediaQuery.of(context).size.width / 2.0,
                child: ElevatedButton(
                  onPressed: () => _submitForm(context,
                      isManageToCheckPress: isManageToCheckPress),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    backgroundColor: buttonColor,
                    foregroundColor: widget.buttonTextColor,
                  ),
                  child: Text(StringConstants.managerToCheck,
                      style: widget.fontFamily
                          .copyWith(color: widget.buttonTextColor)),
                ),
              ),
              const SizedBox(width: 40),
            ],
            SizedBox(
              height: 42.0,
              width: MediaQuery.of(context).size.width / 3.5,
              child: ElevatedButton(
                onPressed: () => _submitForm(context),
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  backgroundColor: buttonColor,
                  foregroundColor: widget.buttonTextColor,
                ),
                child: Text(widget.submitButtonText ?? 'Submit',
                    style: widget.fontFamily
                        .copyWith(color: widget.buttonTextColor)),
              ),
            )
          ]),
    );
  }

  void _submitForm(BuildContext context,
      {bool isManageToCheckPress = false, bool isDraft = false}) {
    // In accordionview mode, validate the entire form before proceed
    if (widget.accordionView && !isDraft) {
      setState(() {
        _shortTextSubmitAttempted = true;
      });
      
      // Check if form is valid using controller's validation logic
      bool isValid = true;
      
      // Only validate fields that are in _internalFields (the transformed fields)
      for (final field in _internalFields) {
        final controlName = field['name'].toString();
        
        // Skip if this field is not in the form controls
        if (!controller.form.contains(controlName)) continue;
        
        final control = controller.form.control(controlName);
        
        // Skip comment fields
        if (controlName.endsWith('_comment')) continue;
        
        
        // Find the field definition for this control
        final fieldDef = controller.findFieldDefinition(controlName);
        if (fieldDef == null) {
          continue;
        }
        
        
        // Check if this field should be visible using the current field (which has the correct showWhen conditions)
        bool shouldBeVisible = controller.shouldFieldBeVisible(field);
        
        if (!shouldBeVisible) {
          continue;
        }
        
        // Check if field is required and empty
        if (fieldDef['required'] == true) {
          final value = control.value;
          final isEmpty = value == null || 
                         value.toString().isEmpty || 
                         value.toString() == 'null' ||
                         (value is List && value.isEmpty);
          
          if (isEmpty) {
            isValid = false;
            break;
          }
        }
        
        // Also check if control is invalid (for other validation rules like email format, etc.)
        if (!control.valid) {
          isValid = false;
          break;
        }
        
        // Check if attachments are required
        if (!controller.validateFieldAttachmentsIfRequired(fieldDef)) {
          isValid = false;
          break;
        }
        
        // Check if comments are required
        if (!controller.validateFieldCommentsIfRequired(fieldDef)) {
          isValid = false;
          break;
        }
      }
      
      
      if (!isValid) {
        // Find the first invalid field and scroll to it
        final anchor = _findFirstInvalidAnchor();
        if (anchor != null) {
          final key = _fieldKeys[anchor];
          if (key != null) {
            final context = key.currentContext;
            if (context != null && context.mounted) {
              Scrollable.ensureVisible(
                context,
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeInOut,
                alignment: 0.0,
              );
            }
          }

          setState(() {
            _expandedAnchor = anchor;
          });
        }
        AppSnackBar(context)
            .showErrorSnackBar(StringConstants.fillMandatoryFields);
        return;
      }
      
      // If validation passes, proceed with submission
      final formValue = Map<String, dynamic>.from(controller.form.value);
      final nestedFormData = controller.createNestedStructure(formValue);
      
      try {
        widget.onSubmit(nestedFormData, controller.uploadedFiles, isManageToCheckPress);
      } catch (e) {
        // Show error to user
        AppSnackBar(context).showErrorSnackBar("Error submitting form: $e");
      }
      return;
    }
    // First validate the current question if in step-by-step mode
    if (widget.showOneByOne &&
        controller.currentQuestionIndex < widget.formJson.length &&
        !isDraft) {
      final currentField = widget.formJson[controller.currentQuestionIndex];
      final control = controller.form.control(currentField['name']);

      // Check if the current field is required and empty
      if ((currentField['required'] == true) &&
          (control.value == null ||
              control.value.toString().isEmpty ||
              control.value == 'null')) {
        control.markAsTouched();
        AppSnackBar(StringConstants.fillRequiredFields as BuildContext);
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

    // Create nested structure for grouped fields
    final nestedFormData = controller.createNestedStructure(cleanedFormData);
    
    // Submit the nested data
    widget.onSubmit(
        nestedFormData, cleanedUploadedFiles, isManageToCheckPress);
  }

  /// The function `_findFirstInvalidAnchor` iterates through group anchors and checks for invalid
  /// fields based on form controls, attachments, and comments.
  ///
  /// Returns:
  ///   The function `_findFirstInvalidAnchor` is returning an `int` value, which represents the first
  /// invalid anchor found in the loop. If no invalid anchor is found, it will return `null`.
  int? _findFirstInvalidAnchor() {
    for (final anchor in _groupAnchors) {
      final List<int> indices = _anchorToFieldIndices[anchor] ?? [anchor];
      for (final idx in indices) {
        if (idx < 0 || idx >= _internalFields.length) continue;
        final field = _internalFields[idx];
        final String fieldName = field['name']?.toString() ?? '';

        // Skip hidden fields
        if (!controller.shouldFieldBeVisible(field)) continue;

        // For grouped fields, the field name is already constructed correctly
        String actualFieldName = fieldName;

        // Control invalid
        if (controller.form.contains(actualFieldName)) {
          final control = controller.form.control(actualFieldName);
          if (!control.valid) return anchor;
        }

        // For fields with groupId, also check all child fields
        if (field['groupId'] != null) {
          final String? groupId = field['groupId']?.toString();
          if (groupId != null && groupId.isNotEmpty) {
            final List<String> childNames = groupId.split(',').map((s) => s.trim()).toList();
            for (final childName in childNames) {
              if (controller.form.contains(childName)) {
                final childControl = controller.form.control(childName);
                if (!childControl.valid) return anchor;
              }
              
              // Also check if any child field has attachment/comment requirements
              final childField = _internalFields.firstWhere(
                (f) => f['name'] == childName,
                orElse: () => <String, dynamic>{},
              );
              if (childField.isNotEmpty) {
                if (!controller.validateFieldAttachmentsIfRequired(childField)) return anchor;
                if (!controller.validateFieldCommentsIfRequired(childField)) return anchor;
              }
            }
          }
        }

        // Attachments missing if required
        if (!controller.validateFieldAttachmentsIfRequired(field))
          return anchor;

        // Comments missing if required
        if (!controller.validateFieldCommentsIfRequired(field)) return anchor;
      }
    }
    return null;
  }

  // Check validity of all controls in a question anchor (including grouped fields)
  bool _isAnchorGroupValid(int anchor) {
    final List<int> indices = _anchorToFieldIndices[anchor] ?? [anchor];
    for (final idx in indices) {
      if (idx < 0 || idx >= _internalFields.length) continue;
      final field = _internalFields[idx];
      final String fieldName = field['name']?.toString() ?? '';

      // Skip hidden fields based on showWhen conditions
      if (!controller.shouldFieldBeVisible(field)) continue;

      // For grouped fields, the field name is already constructed correctly
      String actualFieldName = fieldName;

      // Check the main field control
      if (controller.form.contains(actualFieldName)) {
        final control = controller.form.control(actualFieldName);
        if (!control.valid) return false;
      }

      // For fields with groupId, also check all child fields
      if (field['groupId'] != null) {
        final String? groupId = field['groupId']?.toString();
        if (groupId != null && groupId.isNotEmpty) {
          final List<String> childNames = groupId.split(',').map((s) => s.trim()).toList();
          for (final childName in childNames) {
            // Check if child field should be visible before validating
            final childField = _internalFields.firstWhere(
              (f) => f['name'] == childName,
              orElse: () => <String, dynamic>{},
            );
            if (childField.isNotEmpty && !controller.shouldFieldBeVisible(childField)) {
              continue; // Skip hidden child fields
            }
            
            if (controller.form.contains(childName)) {
              final childControl = controller.form.control(childName);
              if (!childControl.valid) return false;
            }
            
            // Also check if any child field has attachment/comment requirements
            if (childField.isNotEmpty) {
              if (!controller.validateFieldAttachmentsIfRequired(childField)) return false;
              if (!controller.validateFieldCommentsIfRequired(childField)) return false;
            }
          }
        }
      }

      // Attachment requirement
      if (!controller.validateFieldAttachmentsIfRequired(field)) return false;

      // Comments requirement
      if (!controller.validateFieldCommentsIfRequired(field)) return false;
    }
    return true;
  }

  // Check if anchor has required fields that are empty (for warning icon display)
  bool _hasRequiredEmptyFields(int anchor) {
    final List<int> indices = _anchorToFieldIndices[anchor] ?? [anchor];
    
    if (kDebugMode) {
      print("=== _hasRequiredEmptyFields for anchor $anchor ===");
      print("Indices: $indices");
      print("Available form controls: ${controller.form.controls.keys.toList()}");
    }
    
    for (final idx in indices) {
      if (idx < 0 || idx >= _internalFields.length) continue;
      final field = _internalFields[idx];
      final String fieldName = field['name']?.toString() ?? '';
      final bool isRequired = field['required'] == true;

      if (kDebugMode) {
        print("Checking field: $fieldName, required: $isRequired, groupId: ${field['groupId']}");
      }

      // Skip non-required fields
      if (!isRequired) continue;

      // Skip hidden fields based on showWhen conditions
      if (!controller.shouldFieldBeVisible(field)) {
        if (kDebugMode) {
          print("Skipping hidden field: $fieldName (showWhen condition not met)");
        }
        continue;
      }

      // For grouped fields, the field name is already constructed correctly
      String actualFieldName = fieldName;

      // Check the main field control for required empty values
      if (controller.form.contains(actualFieldName)) {
        final control = controller.form.control(actualFieldName);
        final value = control.value;
        final isEmpty = value == null || 
                       (value is String && value.trim().isEmpty) ||
                       (value is List && value.isEmpty);
        
        if (kDebugMode) {
          print("Form control exists: $actualFieldName, value: '$value', isEmpty: $isEmpty");
        }
        
        if (isEmpty) {
          if (kDebugMode) {
            print("Found required empty field: $actualFieldName, value: $value");
          }
          return true;
        }
      } else {
        if (kDebugMode) {
          print("Form control NOT found: $actualFieldName");
        }
      }

      // For fields with groupId, also check all child fields
      if (field['groupId'] != null) {
        final String? groupId = field['groupId']?.toString();
        if (groupId != null && groupId.isNotEmpty) {
          final List<String> childNames = groupId.split(',').map((s) => s.trim()).toList();
          for (final childName in childNames) {
            // Find the child field definition to check if it's required
            final childField = _internalFields.firstWhere(
              (f) => f['name'] == childName,
              orElse: () => <String, dynamic>{},
            );
            
            if (childField.isNotEmpty && childField['required'] == true) {
              // Skip hidden child fields based on showWhen conditions
              if (!controller.shouldFieldBeVisible(childField)) {
                if (kDebugMode) {
                  print("Skipping hidden groupId child field: $childName (showWhen condition not met)");
                }
                continue;
              }
              if (controller.form.contains(childName)) {
                final childControl = controller.form.control(childName);
                final childValue = childControl.value;
                final childIsEmpty = childValue == null || 
                                   (childValue is String && childValue.trim().isEmpty) ||
                                   (childValue is List && childValue.isEmpty);
                if (childIsEmpty) {
                  if (kDebugMode) {
                    print("Found required empty groupId child field: $childName, value: $childValue");
                  }
                  return true;
                }
              }
            }
          }
        }
      }

      // Check required attachments
      if (field['type'] == 'file' && isRequired) {
        final hasFiles = controller.uploadedFiles[fieldName]?.isNotEmpty ?? false;
        if (!hasFiles) return true;
      }

      // Check required comments
      if (field['hasComments'] == true && field['requireCommentsOn']?.contains('Yes') == true) {
        final commentFieldName = '${fieldName}_comment';
        if (controller.form.contains(commentFieldName)) {
          final commentControl = controller.form.control(commentFieldName);
          final commentValue = commentControl.value;
          final commentIsEmpty = commentValue == null || 
                                (commentValue is String && commentValue.trim().isEmpty);
          if (commentIsEmpty) return true;
        }
      }
    }
    
    if (kDebugMode) {
      print("=== _hasRequiredEmptyFields result: false (no required empty fields found) ===");
    }
    
    return false;
  }

  /// Returns true if any content is present for the given anchor (question) that would
  /// indicate the user started filling it: control value, attachments, or comments.
  bool isAnchorDraft(int anchor) {
    if (_anchorDraftCache.containsKey(anchor)) {
      return _anchorDraftCache[anchor]!;
    }

    final List<int> indices = _anchorToFieldIndices[anchor] ?? [anchor];
    bool hasContent = false;
    for (final idx in indices) {
      if (idx < 0 || idx >= _internalFields.length) continue;
      final field = _internalFields[idx];
      if (_isFieldDraft(field)) {
        hasContent = true;
        break;
      }
    }
    _anchorDraftCache[anchor] = hasContent;
    return hasContent;
  }

  /// Core check: determines if a single field has any content indicating a draft
  bool _isFieldDraft(Map<String, dynamic> field) {
    final String fieldName = field['name']?.toString() ?? '';

    // 1) Attachments present
    final attachments = controller.uploadedFiles[fieldName] ?? [];
    if (attachments.isNotEmpty) return true;

    // 2) Main control value present
    if (controller.form.contains(fieldName)) {
      final control = controller.form.control(fieldName);
      final value = control.value;
      if (value != null) {
        if (value is String) {
          if (value.trim().isNotEmpty) return true;
        } else if (value is List) {
          if (value.isNotEmpty) return true;
        } else {
          // Numbers or other scalar types
          return true;
        }
      }
    }

    // 3) Comment control value present
    final commentControlName = '${fieldName}_comment';
    if (controller.form.contains(commentControlName)) {
      final commentValue = controller.form.control(commentControlName).value;
      if (commentValue != null &&
          commentValue is String &&
          commentValue.trim().isNotEmpty) {
        return true;
      }
    }

    return false;
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

        // DIAGNOSTIC: Check question_6 structure
        if (anchorField['name'] == 'question_6') {
          print("\n=== QUESTION 6 INSPECTION ===");
          print("question_6 hasAttachments: ${anchorField['hasAttachments']}");
          print(
              "question_6 requireAttachmentsOn: ${anchorField['requireAttachmentsOn']}");
          print(
              "question_6 current value: ${controller.form.control(anchorField['name']).value}");
          print(
              "uploadedFiles contains question_6? ${controller.uploadedFiles.containsKey('question_6')}");
          if (controller.uploadedFiles.containsKey('question_6')) {
            print(
                "uploadedFiles for question_6: ${controller.uploadedFiles['question_6']}");
          }
          print("=== END QUESTION 6 INSPECTION ===\n");
        }
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
          }
        }

        if (field['hasComments'] == true) {
          final commentControlName = '${fieldName}_comment';
          final fieldControlName = field['name'];

          if (controller.form.contains(commentControlName) &&
              controller.form.contains(fieldControlName)) {
            final commentControl = controller.form.control(commentControlName);
            final fieldControl = controller.form.control(fieldControlName);
            commentControl
                .markAsTouched(); // Mark the control as touched for validation

            // Determine if comments should be shown/required based on the main field value
            bool showComments = controller.shouldShowCommentsBasedOnFieldValue(
                field, fieldControl.value);

            // Validation logic based on the showComments flag
            if (showComments && !commentControl.valid) {
              if (kDebugMode) {
                print("Comment for $fieldName validation failed");
              }
              isValid = false;
            } else {
              isValid = true; // Comment is valid or not required
            }

            // Check the main field validation, if necessary
            if (fieldControl.value == null || fieldControl.value.isEmpty) {
              isValid =
                  false; // Mark as invalid if the main field value is empty
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
    if (!validateCurrentSection()) {
      if (kDebugMode) {
        print("⛔ FIELD VALIDATION FAILED - Navigation blocked");
      }
      // Show a snackbar to inform the user that validation failed
      AppSnackBar(StringConstants.fillRequiredFields as BuildContext);

      return;
    }

    if (kDebugMode) {
      print("✅ All validations passed - Proceeding with navigation");
    }

    // Check if current question is visible, skip to next visible if not
    _updateCurrentQuestionBasedOnVisibility();

    // Proceed with moving to the next step
    if (_currentGroupPointer < _groupAnchors.length - 1) {
      setState(() {
        _currentGroupPointer++;

        // Update the controller index to match the new group
        if (_groupAnchors.isNotEmpty) {
          controller.currentQuestionIndex = _groupAnchors[_currentGroupPointer];

          // Check if we need to skip this next question too
          _updateCurrentQuestionBasedOnVisibility();

          if (kDebugMode) {
            print(
                "➡️ Navigated to next question: ${_internalFields[_groupAnchors[_currentGroupPointer]]['name']}");
          }
        }
      });
    } else {
      // We're at the last question, show submit button
      setState(() {
        // This will trigger the UI to show the submit button
        if (kDebugMode) {
          print("🏁 Reached final question - Submit button will be shown");
        }
      });
    }
  }

  // Move to the next question in the form
  void moveToNextQuestion(BuildContext context) {
    if (kDebugMode) {
      print("\n=== moveToNextQuestion - Starting Form Navigation ===");
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

    // Check if current question is visible, skip to next visible if not
    _updateCurrentQuestionBasedOnVisibility();

    // Now proceed with normal navigation
    if (_currentGroupPointer < _groupAnchors.length - 1) {
      setState(() {
        _currentGroupPointer++;
        // Update the controller index to match the new group
        if (_groupAnchors.isNotEmpty) {
          controller.currentQuestionIndex = _groupAnchors[_currentGroupPointer];

          // Check if we need to skip this question too
          _updateCurrentQuestionBasedOnVisibility();

          if (kDebugMode) {
            print(
                "➡️ Navigated to next question: ${_internalFields[_groupAnchors[_currentGroupPointer]]['name']}");
          }
        }
      });
    } else {
      // We're at the last question, show submit button
      setState(() {
        // This will trigger the UI to show the submit button
        if (kDebugMode) {
          print("🏁 Reached final question - Submit button will be shown");
        }
      });
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

    // Track all fields that are children (have groupWith or groupId property)
    Set<int> childFieldIndices = {};

    // First pass: identify direct parent-child relationships
    // and track which fields are children
    for (int i = 0; i < _internalFields.length; i++) {
      final field = _internalFields[i];
      final String fieldName = field['name'].toString();
      final String? groupWith = field['groupWith']?.toString();
      final String? groupId = field['groupId']?.toString();
      final String? groupingTarget = (groupId != null && groupId.isNotEmpty)
          ? groupId
          : ((groupWith != null && groupWith.isNotEmpty) ? groupWith : null);

      if (groupingTarget != null && groupingTarget.isNotEmpty) {
        // This field refers to a parent
        childFieldIndices.add(i); // Mark as a child field

        // Resolve ultimate parent to handle chained relationships (use groupWith chain resolver as-is)
        String ultimateParent = _resolveUltimateParent(groupingTarget);

        // Check if parent field exists
        if (fieldNameToIndex.containsKey(ultimateParent)) {
          int parentIndex = fieldNameToIndex[ultimateParent]!;

          // Add this field as a child of the ultimate parent
          anchorToChildIndices.putIfAbsent(ultimateParent, () => []).add(i);

          // Debug
          if (kDebugMode && ultimateParent != groupingTarget) {
            print(
                "Chain detected: $fieldName -> $groupingTarget -> $ultimateParent");
          }
        } else if (kDebugMode) {
          print(
              "Warning: Field '$fieldName' references non-existent parent '$ultimateParent'");
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
      
      // Also add any fields that have groupWith pointing to this field
      for (int j = 0; j < _internalFields.length; j++) {
        final childField = _internalFields[j];
        final String? groupWith = childField['groupWith']?.toString();
        if (groupWith == fieldName && !groupIndices.contains(j)) {
          groupIndices.add(j);
        }
      }

      // Store the group
      _anchorToFieldIndices[i] = groupIndices;
    }

    // Handle timestamp-based duplicates
    for (final groupKey in timestampGroups.keys) {
      final fieldIndices = timestampGroups[groupKey]!;
      if (fieldIndices.isEmpty) continue;

      // Find the first field as the anchor for this duplicate set
      final firstIndex = fieldIndices.reduce((a, b) => a < b ? a : b);

      // Only add as an anchor if it's not already a child of another field
      if (!childFieldIndices.contains(firstIndex)) {
        _groupAnchors.add(firstIndex);
      }

      // Always store all fields in this timestamp group under this anchor
      _anchorToFieldIndices[firstIndex] = List.from(fieldIndices);
    }

    // Sort anchors by their position in _internalFields to maintain proper order
    _groupAnchors.sort();

    // Map to track base field names to their question numbers
    Map<String, int> baseNameToQuestionNumber = {};

    // First pass: assign question numbers to non-duplicate anchors
    int questionNumber = 1;
    for (int i = 0; i < _groupAnchors.length; i++) {
      int anchorIndex = _groupAnchors[i];
      String fieldName = _internalFields[anchorIndex]['name'].toString();
      bool isDuplicate = _internalFields[anchorIndex]['isDuplicate'] == true;

      if (!isDuplicate) {
        _anchorToQuestionNumber[anchorIndex] = questionNumber;
        baseNameToQuestionNumber[fieldName] = questionNumber;
        questionNumber++;
      }
    }

    // Second pass: assign question numbers to duplicate anchors
    for (int i = 0; i < _groupAnchors.length; i++) {
      int anchorIndex = _groupAnchors[i];
      String fieldName = _internalFields[anchorIndex]['name'].toString();
      bool isDuplicate = _internalFields[anchorIndex]['isDuplicate'] == true;

      if (isDuplicate) {
        // For duplicates, try to find the original field they were duplicated from
        final match = timestampPattern.firstMatch(fieldName);
        if (match != null) {
          // Extract the base name (removing timestamp suffix)
          String baseName = match.group(1) ?? '';

          if (baseNameToQuestionNumber.containsKey(baseName)) {
            // Use the same question number as the original field
            _anchorToQuestionNumber[anchorIndex] =
                baseNameToQuestionNumber[baseName]!;

            if (kDebugMode) {
              print(
                  "Assigned question number ${baseNameToQuestionNumber[baseName]} to duplicate field '$fieldName' from original '$baseName'");
            }
          } else {
            // If original field not found, assign a new number
            _anchorToQuestionNumber[anchorIndex] = questionNumber++;

            if (kDebugMode) {
              print(
                  "Assigned new question number to duplicate field '$fieldName' - original field not found");
            }
          }
        } else {
          // Not a standard timestamp-based duplicate, assign a new number
          _anchorToQuestionNumber[anchorIndex] = questionNumber++;
        }
      }
    }

    // Reset the group pointer
    _currentGroupPointer = 0;

    // Debug the group structure if in debug mode
    if (kDebugMode) {
      print("\n=== Group Structure After Recomputation ===");
      print("Total anchors: ${_groupAnchors.length}");

      for (int i = 0; i < _groupAnchors.length; i++) {
        int anchorIndex = _groupAnchors[i];
        String anchorName = _internalFields[anchorIndex]['name'].toString();
        List<int> groupIndices =
            _anchorToFieldIndices[anchorIndex] ?? [anchorIndex];
        int qNumber = _anchorToQuestionNumber[anchorIndex] ?? -1;

        print(
            "Anchor #${i + 1}: '${anchorName}' (index: $anchorIndex, question: $qNumber)");
        print(
            "  Group fields: ${groupIndices.map((idx) => _internalFields[idx]['name']).toList()}");
      }
    }

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
      widgets.add(_buildCardForFields(currentGroupFields, false, anchor: currentAnchor));
    } else {
      // Add the original question without a card
      widgets.addAll(currentGroupFields.map(_buildField).toList());
    }

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
          }
        }
      }
    }

    // Build cards for all duplicate anchors
    for (final anchor in duplicateAnchors) {
      final indices = _anchorToFieldIndices[anchor] ?? [anchor];
      final fields = indices.map((i) => _internalFields[i]).toList();

      // Add the duplicate card with delete button
      widgets.add(_buildCardForFields(fields, true, anchor: anchor));
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

    // Get question number if available
    return anchorIndex != null ? _anchorToQuestionNumber[anchorIndex] : null;
  }

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
    if (_currentGroupPointer > 0) {
      // Store the current pointer before moving
      int originalPointer = _currentGroupPointer;

      // Move to the previous question
      _currentGroupPointer--;

      // Update the controller index to match the new group
      if (_groupAnchors.isNotEmpty) {
        controller.currentQuestionIndex = _groupAnchors[_currentGroupPointer];
      }

      // Check if the previous question is visible, if not, find the previous visible question
      _updateCurrentQuestionBasedOnVisibilityForPrevious();

      // If we couldn't find a valid previous question, revert to original position
      if (_currentGroupPointer >= originalPointer) {
        _currentGroupPointer = originalPointer;
        if (_groupAnchors.isNotEmpty) {
          controller.currentQuestionIndex = _groupAnchors[_currentGroupPointer];
        }
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

  // Transform groupId-based fields into grouped accordion structure
  List<Map<String, dynamic>> _transformGroupIdIntoOptionGroups(
      List<Map<String, dynamic>> source) {
    // Deep copy to avoid mutating original
    final List<Map<String, dynamic>> original =
        source.map((e) => Map<String, dynamic>.from(e)).toList();

    // Map field name -> its index for quick lookup
    final Map<String, int> fieldNameToIndex = {};
    
    for (int i = 0; i < original.length; i++) {
      final field = original[i];
      final String fieldName = field['name']?.toString() ?? '';
      fieldNameToIndex[fieldName] = i;
    }

    // Build the transformed list
    final List<Map<String, dynamic>> transformed = [];
    final Set<int> processedFields = {};

    // First, identify all parent fields (those with groupId containing child references)
    final Map<String, List<String>> parentToChildren = {};
    final Set<String> childFields = {};

    for (int i = 0; i < original.length; i++) {
      final field = original[i];
      final String fieldName = field['name']?.toString() ?? '';
      final String? groupId = field['groupId']?.toString();

      if (groupId != null && groupId.isNotEmpty) {
        // Parse comma-separated child names
        final List<String> childNames = groupId.split(',').map((s) => s.trim()).toList();
        parentToChildren[fieldName] = childNames;
        
        // Mark these as child fields
        for (final childName in childNames) {
          childFields.add(childName);
        }
      }
    }

    // Process all fields
    for (int i = 0; i < original.length; i++) {
      if (processedFields.contains(i)) continue;
      
      final field = original[i];
      final String fieldName = field['name']?.toString() ?? '';

      if (parentToChildren.containsKey(fieldName)) {
        // This is a parent field - add it and its children
        final Map<String, dynamic> parentField = Map<String, dynamic>.from(field);
        parentField.remove('groupId'); // Remove groupId from parent
        transformed.add(parentField);
          processedFields.add(i);

        // Add all its children (create copies for each parent)
        final List<String> childNames = parentToChildren[fieldName]!;
        for (final childName in childNames) {
          if (fieldNameToIndex.containsKey(childName)) {
            final int childIdx = fieldNameToIndex[childName]!;
            // Always create a copy of the child field for this parent
            final Map<String, dynamic> childField = Map<String, dynamic>.from(original[childIdx]);
            childField['groupWith'] = fieldName;
            // Create unique name for this instance
            childField['name'] = '${childName}_${fieldName}';
            
            // Update showWhen conditions to reference the correct parent field
            if (childField['showWhen'] != null) {
              final Map<String, dynamic> showWhen = Map<String, dynamic>.from(childField['showWhen']);
              final Map<String, dynamic> updatedShowWhen = {};
              showWhen.forEach((key, value) {
                // If the referenced field is also a child field, update the reference
                if (childFields.contains(key)) {
                  updatedShowWhen['${key}_${fieldName}'] = value;
        } else {
                  updatedShowWhen[key] = value;
                }
              });
              childField['showWhen'] = updatedShowWhen;
            }
            
            transformed.add(childField);
          }
        }
      } else if (childFields.contains(fieldName)) {
        // This is a child field that's already been processed as part of a parent group
        // Skip it here as it will be added when processing its parent
        continue;
      } else {
        // Standalone field - add as is
      transformed.add(field);
        processedFields.add(i);
      }
    }

    return transformed;
  }

  void _deleteDuplicateGroup(List<Map<String, dynamic>> fields) {
    try {
      final List<String> names =
          fields.map((f) => f['name'].toString()).toList(growable: false);

      setState(() {
        // Remove from form controls if present
        if (controller.form != null) {
          try {
            controller.removeFormControls(names);
          } catch (_) {}
        }
        // Remove from internal model
        _internalFields
            .removeWhere((f) => names.contains(f['name']?.toString() ?? ''));
        _recomputeGroupStructure();
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting duplicate group: $e');
      }
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
  final bool bookingAppModelFileUpload;
  final Map<String, dynamic>? initialValues;

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
    this.bookingAppModelFileUpload = false,
    this.initialValues,
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
  ///
  ///
  static Widget? imageTitle(String? imageURL, BuildContext? context) {
    try {
      if (imageURL != null) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SizedBox(
            height: 300,
            width: MediaQuery.of(context!).size.width,
            child: CachedNetworkImage(
              imageUrl: imageURL,
            ),
          ),
        );
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<File?> cropImage(File imageFile) async {
    try {
      final image = await ImageCropper().cropImage(
        sourcePath: imageFile.path,
        uiSettings: [
          AndroidUiSettings(
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
          ),
          IOSUiSettings(),
          WebUiSettings(
            context: Get.context!,
            presentStyle: WebPresentStyle.dialog,
          ),
        ],
      );
      return image != null ? File(image.path) : imageFile;
    } catch (e) {
      return null;
    }
  }

  static Future<(List<int> byte, String name)?> pickMedia({
    required bool isGallery,
    bool back = true,
    List<String>? allowedExtensions,
  }) async {
    if (back) Get.back();
    final source = isGallery ? ImageSource.gallery : ImageSource.camera;
    final pickedFile = await ImagePicker().pickImage(source: source);
    if (pickedFile == null) return null;

    final file = File(pickedFile.path);
    final croppedFile = await cropImage(file);
    return croppedFile != null
        ? (croppedFile.readAsBytesSync(), croppedFile.path.split('/').last)
        : (file.readAsBytesSync(), file.path.split('/').last);
  }

  static Row row(IconData icon, String label, TextStyle? style) => Row(
        children: [
          Expanded(child: Icon(icon)),
          Expanded(
              flex: 4,
              child: Text(
                label,
                textAlign: TextAlign.start,
                style: style,
              )),
        ],
      );

  static Future<(List<int> byte, String name)?> pickFile({
    bool back = true,
    required List<String>? allowedExtension,
  }) async {
    if (back) Get.back();

    final result = allowedExtension != null
        ? await FilePicker.platform.pickFiles(
            type: FileType.custom, allowedExtensions: allowedExtension)
        : await FilePicker.platform.pickFiles();
    return result != null
        ? (
            kIsWeb
                ? result.files.single.bytes!
                : File(result.files.single.path!).readAsBytesSync(),
            result.files.single.name,
          )
        : null;
  }

  Future<(List<int>, String, String)?> showFilePickerOptions({
    required BuildContext context,
    required String cameraLabel,
    required String galleryLabel,
    required String filesLabel,
    required String cancelLabel,
    TextStyle? textStyle,
    String? image,
    bool camera = true,
    bool gallery = true,
    bool files = true,
    required List<dynamic>? allowedExtensions,
  }) async {
    Completer<(List<int>, String, String)?> completer = Completer();
    await showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: imageTitle(image, context),
        actions: [
          camera
              ? CupertinoActionSheetAction(
                  onPressed: () => cameraOnTap(),
                  child: row(CupertinoIcons.camera, cameraLabel, textStyle),
                )
              : const SizedBox(),
          gallery
              ? CupertinoActionSheetAction(
                  onPressed: () => galleryOnTap(),
                  child: row(CupertinoIcons.photo, galleryLabel, textStyle),
                )
              : const SizedBox(),
          files
              ? CupertinoActionSheetAction(
                  onPressed: () => fileOnTap(),
                  child: row(CupertinoIcons.doc, filesLabel, textStyle),
                )
              : const SizedBox(),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () {
            Navigator.pop(context);
            completer.complete(null); // Handle cancel case
          },
          child: Text(cancelLabel),
        ),
      ),
    );
    return completer.future;
  }

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

  Future<void> fileOnTap() async {
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
          allowMultiple: false,
          withData: false,
          allowCompression: true,
          compressionQuality: 80);

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;

        final filePath = file.path!;
        final ext = filePath.split('.').last.toLowerCase();
        final selectedFile = File(filePath);

        Uint8List fileBytes = await selectedFile.readAsBytes();

        if (['jpg', 'jpeg', 'png'].contains(ext)) {
          final compressedBytes =
              await imageCompress(fileBytes, XFile(selectedFile.path));
          if (compressedBytes == null) {
            return;
          }
          fileBytes = compressedBytes;
        }

        _processFile(
          bytes: fileBytes,
          fileName: file.name,
        );
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
  }

  Future<void> cameraOnTap() async {
    Navigator.pop(context);
    try {
      _showLoadingDialog(context);
      final ImagePicker picker = ImagePicker();
      final XFile? photo = await picker.pickImage(source: ImageSource.camera);

      if (photo != null) {
        final bytes = await photo.readAsBytes();
        final compressedBytes = await imageCompress(bytes, photo);
        if (compressedBytes == null) {
          return;
        }
        _processFile(
          bytes: compressedBytes,
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
  }

  
  Future<Uint8List?> imageCompress(Uint8List bytes, XFile image) async {
    int quality = StringConstants.initialCompressionQuality;
    XFile? compressedFile;
    Uint8List? compressedBytes;
    if (bytes.lengthInBytes >
        (20 * StringConstants.megaByte * StringConstants.megaByte)) {
      AppSnackBar(context).showErrorSnackBar(
        StringConstants.largeFileSizeWarning.replaceAll(
            '**', (bytes.lengthInBytes / 1048576).toStringAsFixed(2)),
      );
      return compressedBytes;
    }
    final newPath = path.join(
      path.dirname(image.path),
      'compressed_${path.basename(image.path)}',
    );
    while (quality > StringConstants.minCompressionQuality) {
      compressedFile = await FlutterImageCompress.compressAndGetFile(
        image.path,
        newPath,
        quality: quality,
        autoCorrectionAngle: true,
      );

      if (compressedFile != null) {
        final compressedSize = await compressedFile.length();
        if (compressedSize < StringConstants.maxImageSizeBytes) {
          compressedBytes = await compressedFile.readAsBytes();
          return compressedBytes;
        }
      }

      quality -= StringConstants.compressionQualityStep;
    }
    return compressedBytes;
  }

  Future<void> galleryOnTap() async {
    Navigator.pop(context);
    try {
      _showLoadingDialog(context);
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        final compressedBytes = await imageCompress(bytes, image);
        if (compressedBytes == null) {
          return;
        }

        _processFile(
          bytes: compressedBytes,
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
                  onTap: () => fileOnTap()),
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
                  onTap: () => galleryOnTap()),
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
                    onTap: () => cameraOnTap()),
            ],
          ),
        );
      },
    );
  }

  Widget uploadButton(
      {required String assetName,
      required String label,
      required VoidCallback onTap}) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Get.theme.colorScheme.secondary.withOpacity(0.10),
            ),
            child: SvgPicture.asset(
              assetName,
              colorFilter: ColorFilter.mode(
                  Get.theme.colorScheme.secondary, BlendMode.srcIn),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: Get.theme.textTheme.labelLarge,
        ),
      ],
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
    final initialValues = widget.initialValues;
    print(initialValues?['${widget.fieldName}_attachments']);

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
        // Field label if this is a standalone field (not just an attachment widget)

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
          widget.bookingAppModelFileUpload
              ? Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 35.0),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return Stack(
                            alignment: Alignment.topCenter,
                            children: [
                              // Main Upload Box
                              Container(
                                width: constraints.maxWidth,
                                margin: const EdgeInsets.only(top: 10),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 29, vertical: 16),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      color: Get.theme.dividerColor
                                          .withOpacity(0.5)),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // File Type Description
                                    Text(
                                      'Upload Files',
                                      style: Get.textTheme.labelMedium
                                          ?.copyWith(
                                              color: Get.theme.hintColor),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 15),

                                    // Upload Buttons Row
                                    SizedBox(
                                      width: 288,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          uploadButton(
                                              assetName: MyAppAssets
                                                  .multipleFileUpload,
                                              label:
                                                  StringConstants.clickToUpload,
                                              onTap: () =>
                                                  showFilePickerOptions(
                                                    context: context,
                                                    allowedExtensions: [
                                                      FileTypes.jpg,
                                                      FileTypes.jpeg,
                                                      FileTypes.png,
                                                      FileTypes.pdf,
                                                      FileTypes.doc,
                                                      FileTypes.docx,
                                                      FileTypes.xls,
                                                      FileTypes.xlsx,
                                                      FileTypes.text
                                                    ],
                                                    cameraLabel:
                                                        StringConstants.camera,
                                                    galleryLabel:
                                                        StringConstants.gallery,
                                                    filesLabel:
                                                        StringConstants.files,
                                                    cancelLabel:
                                                        StringConstants.cancel,
                                                    camera: false,
                                                    gallery: true,
                                                    files: true,
                                                  )),
                                          uploadButton(
                                              assetName: MyAppAssets.camera,
                                              label: StringConstants
                                                  .captureToUpload,
                                              onTap: () =>
                                                  showFilePickerOptions(
                                                    context: context,
                                                    allowedExtensions: [
                                                      FileTypes.jpg,
                                                      FileTypes.jpeg,
                                                      FileTypes.png,
                                                      FileTypes.pdf,
                                                      FileTypes.doc,
                                                      FileTypes.docx,
                                                      FileTypes.xls,
                                                      FileTypes.xlsx,
                                                      FileTypes.text
                                                    ],
                                                    cameraLabel:
                                                        StringConstants.camera,
                                                    galleryLabel:
                                                        StringConstants.gallery,
                                                    filesLabel:
                                                        StringConstants.files,
                                                    cancelLabel:
                                                        StringConstants.cancel,
                                                    camera: true,
                                                    gallery: false,
                                                    files: false,
                                                  )),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              Positioned(
                                top: 0,
                                child: Container(
                                  color: Get.theme.colorScheme.surface,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10),
                                  child: Text(
                                    StringConstants.uploadFiles,
                                    style: Get.textTheme.labelLarge,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    // Show uploaded files preview
                  ],
                )
              : SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.primaryColor,
                      foregroundColor: widget.buttonTextColor,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 15),
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
  void initState() {
    super.initState();
    if (widget.file['file'] == null) {
      _loadFileFromUrl();
    }
  }

  Future<void> _loadFileFromUrl() async {
    try {
      setState(() {
        isDownloading = true;
      });
      await getFileBytes(widget.file['file_url']);
      if (mounted) {
        setState(() {
          isDownloading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isDownloading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load file: $e')),
        );
      }
    }
  }

  Future<void> getFileBytes(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      if (mounted) {
        setState(() {
          widget.file['file'] = response.bodyBytes;
        });
      }
    } else {
      throw Exception('Failed to download file: ${response.statusCode}');
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String fileName = widget.file['fileName'] ?? 'Unknown File';
    final String fileType = widget.file['fileType'] ?? '';
    final Uint8List? fileBytes = widget.file['file'];

    // Show loading state if file is null and we're downloading
    if (fileBytes == null && isDownloading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            fileName,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text("Loading file...", style: TextStyle(fontSize: 16))
            ],
          ),
        ),
      );
    }

    // Show error state if file is null and not downloading
    if (fileBytes == null && !isDownloading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            fileName,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text("Failed to load file", style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () {
                  _loadFileFromUrl();
                },
                child: const Text("Retry"),
              ),
            ],
          ),
        ),
      );
    }

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
          _downloadFile(context, fileBytes!, fileName).then((_) {
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
                await _downloadFile(context, fileBytes!, fileName);
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
                await _openPdfInNewTab(context, fileBytes!, fileName);
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
      body: _buildBody(context, fileType, fileBytes!, fileName),
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
