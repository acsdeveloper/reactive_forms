import 'package:flutter/material.dart';
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
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: () => widget.onConfirm(_selectedValues),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onChanged: _filterOptions,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _filteredOptions.length,
                itemBuilder: (context, index) {
                  final option = _filteredOptions[index];
                  final isSelected = _selectedValues.contains(option);
                  
                  return ListTile(
                    title: Text(option),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: Colors.blue)
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
          ],
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