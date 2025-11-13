import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:flutter/cupertino.dart';

class TemperatureScrollWidget extends StatefulWidget {
  final String formControlName;
  final double? min;
  final double? max;
  final double step;
  final double initialValue;
  final String unit;
  final TextStyle? textStyle;
  final Color? primaryColor;
  final Color? backgroundColor;
  final Color? separatorColor;
  final Function(double)? onChanged;
  // Toggle between new 3-column (int.dec unit) picker and legacy single-column picker
  final bool useTriplePicker;

  const TemperatureScrollWidget({
    super.key,
    required this.formControlName,
    this.min = -25.0,
    this.max = 110.0,
    this.step = 0.1,
    this.initialValue = 0.0,
    this.unit = '°C',
    this.textStyle,
    this.primaryColor,
    this.backgroundColor,
    this.separatorColor,
    this.onChanged,
    this.useTriplePicker = true,
  });

  @override
  State<TemperatureScrollWidget> createState() => _TemperatureScrollWidgetState();
}

class _TemperatureScrollWidgetState extends State<TemperatureScrollWidget> {
  // Controllers for 2-column picker (integer + decimal)
  late FixedExtentScrollController _intController;
  late FixedExtentScrollController _decController;
  // Controller for legacy single-column picker
  FixedExtentScrollController? _allController;

  // Current value is stored in Celsius for saving to the form
  late double _currentValueCelsius;

  // Display state
  late List<int> _intValues; // integer part values (-25 to 110)
  int _currentInt = 0;
  int _currentDec = 0; // 0..9
  // Legacy list of values (either °C or °F depending on widget.unit)
  List<double> _allValues = [];

  @override
  void initState() {
    super.initState();
    _currentValueCelsius = widget.initialValue;
    if (widget.useTriplePicker) {
      _rebuildRanges();

      // Derive display parts from initial value (in Celsius)
      _currentInt = _currentValueCelsius.truncate();
      _currentDec = ((_currentValueCelsius.abs() * 10).round() % 10);

      // Snap to valid integer in range and ensure it's in the list
      _currentInt = _closestIntInRange(_currentInt);

      // Ensure we have a valid index
      final intIndex = _intValues.indexOf(_currentInt);
      if (intIndex == -1 && _intValues.isNotEmpty) {
        _currentInt = _intValues.first;
      }

      _intController = FixedExtentScrollController(
        initialItem: _intValues.isNotEmpty ? _intValues.indexOf(_currentInt) : 0,
      );
      _decController = FixedExtentScrollController(initialItem: _currentDec.clamp(0, 9));
    } else {
      _buildAllValues();
      final closest = _allValues.reduce((a, b) =>
          (a - _currentValueCelsius).abs() < (b - _currentValueCelsius).abs() ? a : b);
      final closestIndex = _allValues.indexOf(closest);
      _allController = FixedExtentScrollController(
        initialItem: closestIndex >= 0 ? closestIndex : 0,
      );
    }
  }

  void _rebuildRanges() {
    // Build integer values list for Celsius (-25 to 110)
    _intValues = List<int>.generate(
        (widget.max!.floor() - widget.min!.ceil()) + 1,
        (i) => widget.min!.ceil() + i);
  }

  @override
  void didUpdateWidget(TemperatureScrollWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // If the initial value changed significantly, update our internal state
    if (widget.initialValue != oldWidget.initialValue) {
      final newValue = widget.initialValue;
      if ((_currentValueCelsius - newValue).abs() > 0.01) {
        setValue(newValue);
      }
    }
    
    // If min/max changed, rebuild ranges
    if (widget.min != oldWidget.min || widget.max != oldWidget.max) {
      _rebuildRanges();
      // Recalculate current int value with new range
      _currentInt = _closestIntInRange(_currentInt);
      _jumpToControllers();
    }
  }

  @override
  void dispose() {
    _intController.dispose();
    _decController.dispose();
    _allController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = widget.backgroundColor ?? Colors.white;
    final textStyle = widget.textStyle ?? theme.textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.bold,
      color: Colors.black,
    );

    // Render either the triple picker or the legacy single picker
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SizedBox(
        height: 140,
        child: widget.useTriplePicker ? Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Integer part picker (-25 to 110)
            Expanded(
              flex: 5,
              child: ScrollConfiguration(
  behavior: ScrollConfiguration.of(context).copyWith(
    dragDevices: {
      PointerDeviceKind.touch,
      PointerDeviceKind.mouse,
      PointerDeviceKind.trackpad,
    },
  ),
  child: CupertinoPicker(
                scrollController: _intController,
                itemExtent: 40,
                magnification: 1.25,
                useMagnifier: true,
                squeeze: 1.15,
                selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
                  background: Colors.grey.withOpacity(0.12),
                ),
                onSelectedItemChanged: (idx) {
                  setState(() {
                    _currentInt = _intValues[idx];
                    _updateCurrentCelsiusFromDisplay();
                  });
                  widget.onChanged?.call(_currentValueCelsius);
                },
                children: _intValues
                    .map((v) => Center(
                          child: Text(
                            v.toString(),
                            style: textStyle?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ))
                    .toList(),
              ),),
            ),
            // Decimal separator
            Center(
              child: Text(
                '.',
                style: textStyle?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            // Decimal digit picker (0..9)
            Expanded(
              flex: 3,
              child: ScrollConfiguration(
  behavior: ScrollConfiguration.of(context).copyWith(
    dragDevices: {
      PointerDeviceKind.touch,
      PointerDeviceKind.mouse,
      PointerDeviceKind.trackpad,
    },
  ),
  child:CupertinoPicker(
                scrollController: _decController,
                itemExtent: 40,
                magnification: 1.25,
                useMagnifier: true,
                squeeze: 1.15,
                selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
                  background: Colors.grey.withOpacity(0.12),
                ),
                onSelectedItemChanged: (idx) {
                  setState(() {
                    _currentDec = idx; // 0..9
                    _updateCurrentCelsiusFromDisplay();
                  });
                  widget.onChanged?.call(_currentValueCelsius);
                },
                children: List<Widget>.generate(10, (i) => Center(
                      child: Text(
                        i.toString(),
                        style: textStyle?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    )),
              ),)
            ),
            // Space and unit
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: Center(
                child: Text(
                  '°C',
                  style: textStyle?.copyWith(fontWeight: FontWeight.w600,fontSize: 20),
                ),
              ),
            ),
          ],
        ) : CupertinoPicker(
          scrollController: _allController,
          itemExtent: 40,
          magnification: 1.25,
          useMagnifier: true,
          squeeze: 1.15,
          selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
            background: Colors.grey.withOpacity(0.12),
          ),
          onSelectedItemChanged: (idx) {
            final val = _allValues[idx];
            setState(() {
              _currentValueCelsius = val;
            });
            widget.onChanged?.call(_currentValueCelsius);
          },
          children: _allValues
              .map((v) => Center(
                    child: Text(
                      '${v.toStringAsFixed(1)} °C',
                      style: textStyle?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  // Helpers

  int _closestIntInRange(int value) => _snapToRange(value);

  int _snapToRange(int value) {
    if (_intValues.isEmpty) return value;
    if (value <= _intValues.first) return _intValues.first;
    if (value >= _intValues.last) return _intValues.last;
    // Find closest in sorted list
    int closest = _intValues.first;
    int minDiff = (value - closest).abs();
    for (final v in _intValues) {
      final d = (value - v).abs();
      if (d < minDiff) {
        minDiff = d;
        closest = v;
      }
    }
    return closest;
  }

  void _updateCurrentCelsiusFromDisplay() {
    // Build the signed value from parts (always in Celsius)
    final sign = _currentInt < 0 ? -1 : 1;
    final magnitude = _currentInt.abs() + (_currentDec / 10.0);
    _currentValueCelsius = sign * magnitude;
  }

  void _buildAllValues() {
    _allValues = [];
    // Build in Celsius only
    double current = widget.min!;
    while (current <= widget.max! + 1e-9) {
      _allValues.add(double.parse(current.toStringAsFixed(1)));
      current += widget.step;
    }
  }

  // Method to programmatically set value
  void setValue(double value) {
    // Expecting value in Celsius
    final clamped = value.clamp(widget.min!, widget.max!) as double;
    setState(() {
      _currentValueCelsius = clamped;
      if (widget.useTriplePicker) {
        _currentInt = _snapToRange(_currentValueCelsius.truncate());
        _currentDec = ((_currentValueCelsius.abs() * 10).round() % 10);
        _jumpToControllers();
      } else {
        _buildAllValues();
        final closest = _allValues.reduce((a, b) =>
            (a - _currentValueCelsius).abs() < (b - _currentValueCelsius).abs() ? a : b);
        final idx = _allValues.indexOf(closest);
        if (idx >= 0) {
          _allController?.jumpToItem(idx);
        }
      }
    });
  }

  void _jumpToControllers() {
    if (_intValues.isEmpty) return;
    final intIdx = _intValues.indexOf(_currentInt);
    if (intIdx >= 0) {
      try {
        _intController.jumpToItem(intIdx);
      } catch (e) {
        // Fallback to the first item if jumpToItem fails
        _intController.jumpToItem(0);
      }
    } else {
      // Fallback to first available integer
      _intController.jumpToItem(0);
    }
    try {
      _decController.jumpToItem(_currentDec.clamp(0, 9));
    } catch (e) {
      _decController.jumpToItem(0);
    }
  }
}

// Reactive wrapper for the temperature scroll widget
class ReactiveTemperatureScrollWidget extends StatelessWidget {
  final String formControlName;
  final double? min;
  final double? max;
  final double step;
  final double initialValue;
  final String unit;
  final TextStyle? textStyle;
  final Color? primaryColor;
  final Color? backgroundColor;
  final Color? separatorColor;

  const ReactiveTemperatureScrollWidget({
    super.key,
    required this.formControlName,
    this.min = -25.0,
    this.max = 110.0,
    this.step = 0.1,
    this.initialValue = 0.0,
    this.unit = '°C',
    this.textStyle,
    this.primaryColor,
    this.backgroundColor,
    this.separatorColor,
  });

  @override
  Widget build(BuildContext context) {
    return ReactiveFormField<double, double>(
      formControlName: formControlName,
      builder: (ReactiveFormFieldState<double, double> field) {
        return TemperatureScrollWidget(
          formControlName: formControlName,
          min: min,
          max: max,
          step: step,
          initialValue: field.value ?? initialValue,
          unit: unit,
          textStyle: textStyle,
          primaryColor: primaryColor,
          backgroundColor: backgroundColor,
          separatorColor: separatorColor,
          onChanged: (value) {
            field.didChange(value);
          },
        );
      },
    );
  }
}