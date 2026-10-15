import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.dart';

InputDecoration rmFieldDecoration(
  BuildContext context, {
  String? hint,
  String? error,
  Widget? prefix,
}) {
  final rm = context.rm;
  OutlineInputBorder border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(RmTokens.rSm),
    borderSide: BorderSide(color: color),
  );
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: rm.raised,
    hintText: hint,
    hintStyle: RmText.sans(12, color: rm.fg4),
    errorText: error,
    errorStyle: RmText.sans(11, color: rm.danger),
    prefixIcon: prefix,
    prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 30),
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    border: border(rm.border),
    enabledBorder: border(rm.border),
    focusedBorder: border(rm.accent.base),
    errorBorder: border(rm.danger),
    focusedErrorBorder: border(rm.danger),
  );
}
