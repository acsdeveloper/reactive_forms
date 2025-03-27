import 'package:flutter/material.dart';
import 'package:reactiveform/components/app_typographpy.dart';
import '../models/form_field_model.dart';

class MultiSelectFormField extends StatelessWidget {
  final FormFieldModel field;
  final Function(List<String>) onChanged;
  final List<String> value;
  final bool hasError;
  final String? errorText;

  const MultiSelectFormField({
    Key? key,
    required this.field,
    required this.onChanged,
    required this.value,
    this.hasError = false,
    this.errorText,
  }) : super(key: key);

  void _showMultiSelectBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
      ),
      builder: (BuildContext context) {
        return MultiSelectBottomSheet(
          options: field.options ?? [],
          selectedValues: List.from(value),
          onConfirm: (selectedItems) {
            onChanged(selectedItems);
            Navigator.pop(context);
          },
          title: '',
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Text(
        //   field.label + (field.required ? ' *' : ''),
        //   style: const TextStyle(
        //     fontSize: 16,
        //     fontWeight: FontWeight.w500,
        //   ),
        // ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => _showMultiSelectBottomSheet(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(
                color: hasError ? Colors.red : Colors.grey.shade400,
                width: hasError ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Expanded(
                  child: value.isEmpty
                      ? Text(
                          field.required 
                              ? 'Please select at least one option' 
                              : 'Select options',
                          style: TextStyle(
                            color: hasError ? Colors.red : Colors.grey.shade600,
                          ),
                        )
                      : Text(
                          value.join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  color: hasError ? Colors.red : Colors.grey.shade600,
                ),
              ],
            ),
          ),
        ),
        if (hasError && errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              errorText!,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

class MultiSelectBottomSheet extends StatefulWidget {
  final List<String> options;
  final List<String> selectedValues;
  final Function(List<String>) onConfirm;
  final String title;

  const MultiSelectBottomSheet({
    Key? key,
    required this.options,
    required this.selectedValues,
    required this.onConfirm,
    required this.title,
  }) : super(key: key);

  @override
  State<MultiSelectBottomSheet> createState() => _MultiSelectBottomSheetState();
}

class _MultiSelectBottomSheetState extends State<MultiSelectBottomSheet> {
  late List<String> _selectedValues;
  late TextEditingController _searchController;
  List<String> _filteredOptions = [];

  @override
  void initState() {
    super.initState();
    _selectedValues = List.from(widget.selectedValues);
    _searchController = TextEditingController();
    _filteredOptions = List.from(widget.options);
  }

  void _filterOptions(String query) {
    setState(() {
      _filteredOptions = widget.options
          .where((option) => 
              option.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  @override
  /// The function builds a draggable scrollable sheet with a header, search bar, and options list for
  /// selecting values.
  /// 
  /// Args:
  ///   context (BuildContext): The `context` parameter in Flutter represents the location of a widget
  /// within the widget tree. It provides access to various properties and methods related to the
  /// current build context, such as theme, localization, and navigation.
  /// 
  /// Returns:
  ///   The `build` method is returning a `DraggableScrollableSheet` widget with various properties and
  /// child widgets. The main structure includes a container with a top header containing a gray notch
  /// and a "Done" button, a search bar, and an options list displayed in a ListView. The
  /// `DraggableScrollableSheet` allows for a draggable bottom sheet that can be expanded or collapsed
  /// within the specified
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
                        Text(
                          widget.title,
                          style: AppTypography.searchInput,
                        ),
                        TextButton(
                          onPressed: () => widget.onConfirm(_selectedValues),
                          child: Text(
                            'Done',
                            style: AppTypography.searchInput,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Search bar
              Padding(
                padding: const EdgeInsets.only(left: 16.0, right: 16.0),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.zero,
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      border: InputBorder.none,
                      hintStyle: AppTypography.searchHint,
                      icon: const Icon(Icons.search),
                    ),
                    onChanged: _filterOptions,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Options List
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 20.0, right: 20.0),
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: _filteredOptions.length,
                    itemBuilder: (context, index) {
                      final option = _filteredOptions[index];
                      final isSelected = _selectedValues.contains(option);
                      return ListTile(
                        title: Text(option, style: AppTypography.searchInput),
                        trailing: isSelected
                            ? const Icon(Icons.check, color: Colors.black)
                            : null,
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedValues.remove(option);
                            } else {
                              _selectedValues.add(option);
                            }
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
