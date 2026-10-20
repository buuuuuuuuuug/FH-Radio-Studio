import 'package:flutter/material.dart';
import '../domain/radio_library.dart';
import '../theme/app_theme.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.dart';

/// Shared station row for single-song and batch assignment.
class AssignmentRadioChoice extends StatelessWidget {
  const AssignmentRadioChoice({
    super.key,
    required this.radio,
    required this.summary,
    required this.selected,
    required this.onTap,
    this.choiceKey,
    this.summaryColor,
  });
  final RadioStation radio;
  final String summary;
  final bool selected;
  final VoidCallback onTap;
  final Key? choiceKey;
  final Color? summaryColor;

  @override
  Widget build(BuildContext context) {
    final rm = context.rm;
    final color = summaryColor ?? (selected ? rm.accent.base : rm.fg2);
    return Semantics(
      button: true,
      selected: selected,
      label: '${radio.code} ${radio.name}，$summary',
      child: Material(
        color: selected ? rm.accent.bg : rm.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RmTokens.rSm),
          side: BorderSide(color: selected ? rm.accent.ring : rm.border),
        ),
        child: InkWell(
          key: choiceKey,
          borderRadius: BorderRadius.circular(RmTokens.rSm),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: rm.panel,
                    border: Border.all(color: rm.border),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    radio.code,
                    style: RmText.mono(
                      10.5,
                      weight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    radio.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RmText.sans(
                      12,
                      weight: FontWeight.w500,
                      color: rm.fg,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(summary, style: RmText.mono(10.5, color: color)),
                if (selected) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.check, size: 15, color: color),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
