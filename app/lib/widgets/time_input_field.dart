import 'package:flutter/material.dart';
import '../core/time_input.dart';
import '../theme/app_theme.dart';
import '../theme/text_styles.dart';
import 'rm_field.dart';

class TimeInputValidation {
  static final invalid = <Object>{};
  static final drafts = <Object, VoidCallback>{};
  static final focused = <Object>{};
  static void flush() {
    for (final commit in drafts.values.toList()) {
      commit();
    }
  }
}

class TimeInputField extends StatefulWidget {
  const TimeInputField({
    super.key,
    required this.seconds,
    required this.onCommit,
    this.fontSize = 12,
    this.fontWeight = FontWeight.w400,
    this.textAlign = TextAlign.left,
  });
  final double seconds;
  final ValueChanged<double>? onCommit;
  final double fontSize;
  final FontWeight fontWeight;
  final TextAlign textAlign;
  @override
  State<TimeInputField> createState() => _TimeInputFieldState();
}

class _TimeInputFieldState extends State<TimeInputField> {
  late final TextEditingController _text = TextEditingController(
    text: editableTime(widget.seconds),
  );
  final FocusNode _focus = FocusNode();
  String? _error;
  bool _changed = false;
  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        TimeInputValidation.focused.add(this);
      } else {
        TimeInputValidation.focused.remove(this);
        _commit();
      }
    });
  }

  @override
  void didUpdateWidget(TimeInputField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.seconds != old.seconds) {
      _text.text = editableTime(widget.seconds);
    }
  }

  void _commit() {
    if (!_changed) return;
    try {
      final seconds = parseTimeInput(_text.text);
      if ((seconds - widget.seconds).abs() > 1e-9) {
        widget.onCommit?.call(seconds);
      }
      _changed = false;
      TimeInputValidation.drafts.remove(this);
      TimeInputValidation.invalid.remove(this);
      if (mounted) setState(() => _error = null);
    } on FormatException catch (e) {
      TimeInputValidation.invalid.add(this);
      setState(() => _error = e.message);
    }
  }

  @override
  void dispose() {
    TimeInputValidation.invalid.remove(this);
    TimeInputValidation.drafts.remove(this);
    TimeInputValidation.focused.remove(this);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _text,
    focusNode: _focus,
    enabled: widget.onCommit != null,
    style: RmText.mono(
      widget.fontSize,
      weight: widget.fontWeight,
      color: context.rm.fg,
    ),
    textAlign: widget.textAlign,
    cursorColor: context.rm.accent.base,
    decoration: rmFieldDecoration(context, hint: '1:23.456', error: _error),
    onChanged: (_) {
      _changed = true;
      TimeInputValidation.drafts[this] = _commit;
      TimeInputValidation.invalid.remove(this);
      if (_error != null) setState(() => _error = null);
    },
    onSubmitted: (_) => _commit(),
    onTapOutside: (_) {
      if (_focus.hasFocus) {
        _commit();
        _focus.unfocus();
      }
    },
  );
}
