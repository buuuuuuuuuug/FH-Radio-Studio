import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.dart';

class RmSelect<T> extends StatelessWidget {
  const RmSelect({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final T value;
  final Map<T, String> items;
  final ValueChanged<T>? onChanged;
  @override
  Widget build(BuildContext context) {
    final rm = context.rm;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: rm.raised,
        border: Border.all(color: rm.border),
        borderRadius: BorderRadius.circular(RmTokens.rSm),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          dropdownColor: rm.panel,
          borderRadius: BorderRadius.circular(RmTokens.rSm),
          style: RmText.sans(12, color: rm.fg),
          icon: Icon(Icons.expand_more, size: 14, color: rm.fg3),
          items: [
            for (final e in items.entries)
              DropdownMenuItem(
                value: e.key,
                child: Text(
                  e.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: onChanged == null
              ? null
              : (v) {
                  if (v != null) onChanged!(v);
                },
        ),
      ),
    );
  }
}
