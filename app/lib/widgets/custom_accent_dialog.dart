import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/text_styles.dart';
import 'rm_button.dart';
import 'accent_color_wheel.dart';
import 'rm_field.dart';

class CustomAccentDialog extends StatefulWidget {
  const CustomAccentDialog({super.key, required this.initial});
  final Color initial;
  @override
  State<CustomAccentDialog> createState() => _CustomAccentDialogState();
}

class _CustomAccentDialogState extends State<CustomAccentDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late final _text = TextEditingController(text: _hex(_hsv.toColor()));
  final _focus = FocusNode();
  String? _error;
  String _hex(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  void _change(HSVColor color) => setState(() {
    _hsv = color;
    _error = null;
    _text.text = _hex(color.toColor());
  });
  bool _parse() {
    final value = _text.text.trim().replaceFirst(
      RegExp(r'^(#|0x)', caseSensitive: false),
      '',
    );
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(value)) {
      setState(() => _error = '请输入六位颜色，例如 #23A136');
      return false;
    }
    _change(
      HSVColor.fromColor(Color(0xFF000000 | int.parse(value, radix: 16))),
    );
    return true;
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rm = context.rm;
    Widget control(
      String label,
      double value,
      double max,
      ValueChanged<double> change,
    ) => Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(label, style: RmText.sans(12, color: rm.fg2)),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: 0,
            max: max,
            activeColor: rm.accent.base,
            onChanged: change,
          ),
        ),
      ],
    );
    return AlertDialog(
      backgroundColor: rm.panel,
      title: Text(
        '自选强调色',
        style: RmText.sans(16, weight: FontWeight.w600, color: rm.fg),
      ),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AccentColorWheel(
                key: const ValueKey('custom-accent-wheel'),
                value: _hsv,
                onChanged: _change,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _hsv.toColor(),
                      border: Border.all(color: rm.border),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('custom-accent-hex'),
                      controller: _text,
                      focusNode: _focus,
                      style: RmText.mono(12.5, color: rm.fg),
                      decoration: rmFieldDecoration(
                        context,
                        hint: '#23A136',
                        error: _error,
                      ),
                      onSubmitted: (_) => _parse(),
                      onTapOutside: (_) {
                        if (_focus.hasFocus) {
                          _parse();
                          _focus.unfocus();
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              control('色相', _hsv.hue, 360, (v) => _change(_hsv.withHue(v))),
              control(
                '饱和度',
                _hsv.saturation,
                1,
                (v) => _change(_hsv.withSaturation(v)),
              ),
              control('明度', _hsv.value, 1, (v) => _change(_hsv.withValue(v))),
            ],
          ),
        ),
      ),
      actions: [
        RmButton(label: '取消', onPressed: () => Navigator.pop(context)),
        RmButton(
          label: '应用颜色',
          variant: RmButtonVariant.primary,
          onPressed: () {
            if (_parse()) Navigator.pop(context, _hsv.toColor());
          },
        ),
      ],
    );
  }
}
