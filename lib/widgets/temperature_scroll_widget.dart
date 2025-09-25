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
    this.min = -30.0,
    this.max = 130.0,
    this.step = 0.1,
    this.initialValue = 20.0,
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
  // Controllers for 3-column picker
  late FixedExtentScrollController _intController;
  late FixedExtentScrollController _decController;
  late FixedExtentScrollController _unitController;
  // Controller for legacy single-column picker
  FixedExtentScrollController? _allController;

  // Current value is stored in Celsius for saving to the form
  late double _currentValueCelsius;

  // Display state
  late List<int> _intValues; // integer part values for current unit
  int _currentInt = 0;
  int _currentDec = 0; // 0..9
  String _currentUnit = '°C'; // '°C' or '°F'
  // Legacy list of values (either °C or °F depending on widget.unit)
  List<double> _allValues = [];

  @override
  void initState() {
    super.initState();
    _currentValueCelsius = widget.initialValue;
    if (widget.useTriplePicker) {
      _currentUnit = '°C';
      _rebuildRanges();

      // Derive display parts from initial value (in Celsius)
      final initialInDisplayUnit = _toDisplayUnit(_currentValueCelsius, _currentUnit);
      _currentInt = initialInDisplayUnit.truncate();
      _currentDec = ((initialInDisplayUnit.abs() * 10).round() % 10);

      // Snap to valid integer in range
      if (!_intValues.contains(_currentInt)) {
        _currentInt = _closestIntInRange(_currentInt);
      }

      _intController = FixedExtentScrollController(
        initialItem: _intValues.indexOf(_currentInt),
      );
      _decController = FixedExtentScrollController(initialItem: _currentDec);
      _unitController = FixedExtentScrollController(
        initialItem: _currentUnit == '°C' ? 0 : 1,
      );
    } else {
      _currentUnit = widget.unit;
      _buildAllValues();
      final displayVal = _toDisplayUnit(_currentValueCelsius, _currentUnit);
      final closest = _allValues.reduce((a, b) =>
          (a - displayVal).abs() < (b - displayVal).abs() ? a : b);
      _allController = FixedExtentScrollController(
        initialItem: _allValues.indexOf(closest),
      );
    }
  }

  void _rebuildRanges() {
    // Build integer values list for current unit
    if (_currentUnit == '°C') {
      _intValues = List<int>.generate(
          (widget.max!.floor() - widget.min!.ceil()) + 1,
          (i) => widget.min!.ceil() + i);
    } else {
      // Convert bounds from Celsius to Fahrenheit and build range
      final minF = _cToF(widget.min!);
      final maxF = _cToF(widget.max!);
      final start = minF.round();
      final end = maxF.round();
      _intValues = List<int>.generate((end - start) + 1, (i) => start + i);
    }
  }

  @override
  void dispose() {
    _intController.dispose();
    _decController.dispose();
    _unitController.dispose();
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
            // Integer part picker
            Expanded(
              flex: 5,
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
              ),
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
              child: CupertinoPicker(
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
              ),
            ),
            // Space
            const SizedBox(width: 4),
            // Unit picker (°C / °F)
            Expanded(
              flex: 4,
              child: CupertinoPicker(
                scrollController: _unitController,
                itemExtent: 40,
                magnification: 1.15,
                useMagnifier: true,
                squeeze: 1.15,
                selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
                  background: Colors.grey.withOpacity(0.12),
                ),
                onSelectedItemChanged: (idx) {
                  setState(() {
                    final newUnit = idx == 0 ? '°C' : '°F';
                    if (newUnit != _currentUnit) {
                      // Convert current Celsius value to new unit for display parts
                      _currentUnit = newUnit;
                      _rebuildRanges();
                      final displayVal = _toDisplayUnit(_currentValueCelsius, _currentUnit);
                      _currentInt = _snapToRange(displayVal.truncate());
                      _currentDec = ((displayVal.abs() * 10).round() % 10);
                      _jumpToControllers();
                    }
                  });
                },
                children: ['°C', '°F']
                    .map((u) => Center(
                          child: Text(
                            u,
                            style: textStyle?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ))
                    .toList(),
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
              _currentValueCelsius = _currentUnit == '°C' ? val : _fToC(val);
            });
            widget.onChanged?.call(_currentValueCelsius);
          },
          children: _allValues
              .map((v) => Center(
                    child: Text(
                      '${v.toStringAsFixed(1)} ${_currentUnit}',
                      style: textStyle?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  // Helpers
  double _cToF(double c) => (c * 9 / 5) + 32;
  double _fToC(double f) => (f - 32) * 5 / 9;

  double _toDisplayUnit(double celsius, String unit) =>
      unit == '°C' ? celsius : _cToF(celsius);

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
    // Build the signed value in current unit from parts
    final sign = _currentInt < 0 ? -1 : 1;
    final magnitude = _currentInt.abs() + (_currentDec / 10.0);
    final displayVal = sign * magnitude;
    _currentValueCelsius =
        _currentUnit == '°C' ? displayVal : _fToC(displayVal);
  }

  void _buildAllValues() {
    _allValues = [];
    // Build in display unit (widget.unit)
    if (widget.unit == '°C') {
      double current = widget.min!;
      while (current <= widget.max! + 1e-9) {
        _allValues.add(double.parse(current.toStringAsFixed(1)));
        current += widget.step;
      }
    } else {
      // Fahrenheit list converted from Celsius bounds
      double currentC = widget.min!;
      while (currentC <= widget.max! + 1e-9) {
        final f = _cToF(currentC);
        _allValues.add(double.parse(f.toStringAsFixed(1)));
        currentC += widget.step;
      }
    }
  }

  // Method to programmatically set value
  void setValue(double value) {
    // Expecting value in Celsius
    final clamped = value.clamp(widget.min!, widget.max!) as double;
    setState(() {
      _currentValueCelsius = clamped;
      if (widget.useTriplePicker) {
        final displayVal = _toDisplayUnit(_currentValueCelsius, _currentUnit);
        _currentInt = _snapToRange(displayVal.truncate());
        _currentDec = ((displayVal.abs() * 10).round() % 10);
        _jumpToControllers();
      } else {
        _buildAllValues();
        final displayVal = _toDisplayUnit(_currentValueCelsius, _currentUnit);
        final closest = _allValues.reduce((a, b) =>
            (a - displayVal).abs() < (b - displayVal).abs() ? a : b);
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
      _intController.jumpToItem(intIdx);
    }
    _decController.jumpToItem(_currentDec);
    _unitController.jumpToItem(_currentUnit == '°C' ? 0 : 1);
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
    this.min = -30.0,
    this.max = 130.0,
    this.step = 0.1,
    this.initialValue = 20.0,
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