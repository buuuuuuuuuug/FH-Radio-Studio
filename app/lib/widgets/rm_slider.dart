import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Windows Material Slider can emit orphan overlay semantics when a dialog closes.
/// Keep one accessible slider node without OverlayPortal until Flutter #190357 is fixed.
class RmSlider extends Slider {
  const RmSlider({
    super.key,
    required super.value,
    required super.onChanged,
    super.onChangeStart,
    super.onChangeEnd,
    super.min,
    super.max,
    super.divisions,
    super.label,
    super.activeColor,
    super.inactiveColor,
    super.padding,
    super.semanticFormatterCallback,
  });
  @override
  // Retain the stock implementation on platforms unaffected by the Windows bug.
  State<Slider> createState() =>
      // ignore: no_logic_in_create_state
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows
      ? _WindowsSliderState()
      : super.createState();
}

class _WindowsSliderState extends State<Slider> {
  final _focus = FocusNode();
  int? _pointer;
  double get _step => widget.max == widget.min
      ? 0
      : (widget.max - widget.min) / (widget.divisions ?? 100);
  bool get _enabled => widget.onChanged != null && widget.max > widget.min;
  double _next(double direction) =>
      (widget.value + _step * direction).clamp(widget.min, widget.max);
  String _format(double value) =>
      widget.semanticFormatterCallback?.call(value) ??
      '${widget.max == widget.min ? 0 : ((value - widget.min) / (widget.max - widget.min) * 100).round()}%';
  void _change(double value) {
    widget.onChanged?.call(value.clamp(widget.min, widget.max));
  }

  void _nudge(double value) {
    if (!_enabled) return;
    widget.onChangeStart?.call(widget.value);
    _change(value);
    widget.onChangeEnd?.call(value);
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = SliderTheme.of(context);
    final direction = Directionality.of(context);
    final padding =
        (widget.padding ?? const EdgeInsets.symmetric(horizontal: 24)).resolve(
          direction,
        );
    final shape = theme.thumbShape;
    final radius = shape is RoundSliderThumbShape
        ? shape.enabledThumbRadius
        : 6.0;
    final active =
        widget.activeColor ??
        theme.activeTrackColor ??
        Theme.of(context).colorScheme.primary;
    final inactive =
        widget.inactiveColor ??
        theme.inactiveTrackColor ??
        Theme.of(context).colorScheme.surfaceContainerHighest;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final track = (width - padding.horizontal).clamp(1.0, double.infinity);
        void changeAt(Offset point) {
          var ratio = ((point.dx - padding.left) / track).clamp(0.0, 1.0);
          if (direction == TextDirection.rtl) ratio = 1 - ratio;
          if (widget.divisions != null) {
            ratio = (ratio * widget.divisions!).round() / widget.divisions!;
          }
          _change(widget.min + ratio * (widget.max - widget.min));
        }

        return Semantics(
          container: true,
          slider: true,
          enabled: _enabled,
          focusable: _enabled,
          focused: _focus.hasFocus,
          label: widget.label,
          value: _format(widget.value),
          increasedValue: _enabled ? _format(_next(1)) : null,
          decreasedValue: _enabled ? _format(_next(-1)) : null,
          onIncrease: _enabled ? () => _nudge(_next(1)) : null,
          onDecrease: _enabled ? () => _nudge(_next(-1)) : null,
          child: Focus(
            focusNode: _focus,
            canRequestFocus: _enabled,
            includeSemantics: false,
            onFocusChange: (_) => setState(() {}),
            onKeyEvent: (_, event) {
              if (!_enabled ||
                  event is! KeyDownEvent && event is! KeyRepeatEvent) {
                return KeyEventResult.ignored;
              }
              final key = event.logicalKey;
              double? value;
              if (key == LogicalKeyboardKey.home) value = widget.min;
              if (key == LogicalKeyboardKey.end) value = widget.max;
              if (key == LogicalKeyboardKey.arrowUp) value = _next(1);
              if (key == LogicalKeyboardKey.arrowDown) value = _next(-1);
              if (key == LogicalKeyboardKey.arrowRight) {
                value = _next(direction == TextDirection.rtl ? -1 : 1);
              }
              if (key == LogicalKeyboardKey.arrowLeft) {
                value = _next(direction == TextDirection.rtl ? 1 : -1);
              }
              if (value == null) return KeyEventResult.ignored;
              _nudge(value);
              return KeyEventResult.handled;
            },
            child: MouseRegion(
              cursor: _enabled
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _enabled
                    ? (event) {
                        if (_pointer != null || event.buttons != 1) return;
                        _focus.requestFocus();
                        setState(() => _pointer = event.pointer);
                        widget.onChangeStart?.call(widget.value);
                        changeAt(event.localPosition);
                      }
                    : null,
                onPointerMove: _enabled
                    ? (event) {
                        if (event.pointer == _pointer) {
                          changeAt(event.localPosition);
                        }
                      }
                    : null,
                onPointerUp: (event) {
                  if (event.pointer == _pointer) {
                    setState(() => _pointer = null);
                    widget.onChangeEnd?.call(widget.value);
                  }
                },
                onPointerCancel: (event) {
                  if (event.pointer == _pointer) {
                    setState(() => _pointer = null);
                    widget.onChangeEnd?.call(widget.value);
                  }
                },
                child: SizedBox(
                  width: width,
                  height: 48,
                  child: CustomPaint(
                    painter: _SliderPaint(
                      fraction: widget.max == widget.min
                          ? 0
                          : (widget.value - widget.min) /
                                (widget.max - widget.min),
                      padding: padding,
                      rtl: direction == TextDirection.rtl,
                      active: _enabled ? active : active.withAlpha(80),
                      inactive: inactive,
                      radius: radius,
                      thickness: theme.trackHeight ?? 3,
                      highlight: _pointer != null || _focus.hasFocus,
                      divisions: widget.divisions,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SliderPaint extends CustomPainter {
  const _SliderPaint({
    required this.fraction,
    required this.padding,
    required this.rtl,
    required this.active,
    required this.inactive,
    required this.radius,
    required this.thickness,
    required this.highlight,
    this.divisions,
  });
  final double fraction, radius, thickness;
  final EdgeInsets padding;
  final bool rtl, highlight;
  final Color active, inactive;
  final int? divisions;
  @override
  void paint(Canvas canvas, Size size) {
    final left = padding.left;
    final right = size.width - padding.right;
    final y = size.height / 2;
    final x = left + (right - left) * (rtl ? 1 - fraction : fraction);
    final paint = Paint()
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(left, y), Offset(right, y), paint..color = inactive);
    canvas.drawLine(
      Offset(rtl ? right : left, y),
      Offset(x, y),
      paint..color = active,
    );
    if (divisions != null && divisions! <= 20) {
      for (var i = 0; i <= divisions!; i++) {
        canvas.drawCircle(
          Offset(left + (right - left) * i / divisions!, y),
          1,
          Paint()..color = active,
        );
      }
    }
    if (highlight) {
      canvas.drawCircle(
        Offset(x, y),
        radius + 5,
        Paint()..color = active.withAlpha(35),
      );
    }
    canvas.drawCircle(Offset(x, y), radius, Paint()..color = active);
  }

  @override
  bool shouldRepaint(covariant _SliderPaint old) =>
      fraction != old.fraction ||
      padding != old.padding ||
      rtl != old.rtl ||
      active != old.active ||
      inactive != old.inactive ||
      radius != old.radius ||
      thickness != old.thickness ||
      highlight != old.highlight ||
      divisions != old.divisions;
}
