import '../theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/audition_preferences.dart';
import '../theme/app_theme.dart';
import '../theme/text_styles.dart';
import 'rm_button.dart';
import 'rm_icon.dart';

class AuditionSettingsButton extends StatelessWidget {
  const AuditionSettingsButton({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) {
    void open() => showDialog<void>(
      context: context,
      builder: (_) => const _AuditionSettingsDialog(),
    );
    if (compact) {
      return RmButton.icon(
        icon: const RmIcon('settings', size: 12),
        tooltip: '循环试听设置',
        onPressed: open,
      );
    }
    return RmButton(
      size: RmButtonSize.sm,
      label: '试听设置',
      leading: const RmIcon('settings', size: 12),
      onPressed: open,
    );
  }
}

class _AuditionSettingsDialog extends ConsumerWidget {
  const _AuditionSettingsDialog();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(auditionPreferencesProvider);
    final controller = ref.read(auditionPreferencesProvider.notifier);
    final rm = context.rm;
    Widget slider(
      String title,
      double value,
      double min,
      double max,
      int divisions,
      String unit,
      ValueChanged<double> change,
    ) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: RmText.sans(12, color: rm.fg2)),
            ),
            Text(
              '${value.toStringAsFixed(unit == '%' ? 0 : 1)} $unit',
              style: RmText.mono(11.5, color: rm.fg),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: change,
        ),
      ],
    );
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(context).colorScheme.copyWith(
          primary: rm.accent.base,
          onPrimary: rm.accent.onAccent,
          surface: rm.panel,
        ),
      ),
      child: AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RmTokens.rLg),
          side: BorderSide(color: rm.border),
        ),
        backgroundColor: rm.panel,
        surfaceTintColor: Colors.transparent,
        title: Text(
          '循环试听设置',
          style: RmText.sans(15, weight: FontWeight.w600, color: rm.fg),
        ),
        content: SizedBox(
          width: 350,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '试听 B → A 的衔接；时间和次数应用于下一次试听，不改变歌曲点位。',
                  style: RmText.sans(11.5, color: rm.fg3),
                ),
                const SizedBox(height: 16),
                slider(
                  '衔接前（B 前）',
                  options.before,
                  .5,
                  10,
                  19,
                  '秒',
                  (v) => controller.update(before: v),
                ),
                slider(
                  '衔接后（A 后）',
                  options.after,
                  .5,
                  10,
                  19,
                  '秒',
                  (v) => controller.update(after: v),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '重复次数',
                        style: RmText.sans(12, color: rm.fg2),
                      ),
                    ),
                    DropdownButton<int>(
                      value: options.repetitions,
                      items: [
                        for (final n in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
                          DropdownMenuItem(
                            value: n,
                            child: Text(
                              n == 0 ? '持续试听' : '$n 次',
                              style: RmText.sans(12, color: rm.fg),
                            ),
                          ),
                      ],
                      onChanged: (n) {
                        if (n != null) controller.update(repetitions: n);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                slider(
                  '试听音量',
                  options.volume,
                  0,
                  100,
                  20,
                  '%',
                  (v) => controller.update(volume: v),
                ),
              ],
            ),
          ),
        ),
        actions: [
          RmButton(
            label: '完成',
            variant: RmButtonVariant.primary,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}
