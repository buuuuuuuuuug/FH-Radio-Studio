import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/audition_preferences.dart';
import '../theme/app_theme.dart';
import '../theme/text_styles.dart';
import 'rm_button.dart';
import 'rm_icon.dart';
import 'rm_panel.dart';
import 'rm_select.dart';
import 'rm_slider.dart';
import 'timing_dialog_frame.dart';

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
        tooltip: '试听设置',
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
        RmSlider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: change,
        ),
      ],
    );
    return TimingDialogFrame(
      title: '试听设置',
      busy: false,
      width: 500,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '应用于下一次快速试听，不改变歌曲时间点。普通播放仅使用音量设置。',
            style: RmText.sans(11.5, color: rm.fg3),
          ),
          const SizedBox(height: 16),
          RmPanel(
            title: '播放起点 · TD / PD',
            child: Column(
              children: [
                slider(
                  'TD 比赛开始 · 试听时长',
                  options.tdDuration,
                  1,
                  30,
                  29,
                  '秒',
                  (v) => controller.update(tdDuration: v),
                ),
                slider(
                  'PD 冲线之后 · 试听时长',
                  options.pdDuration,
                  1,
                  30,
                  29,
                  '秒',
                  (v) => controller.update(pdDuration: v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          RmPanel(
            title: '循环拼接 · TL / PL',
            child: Column(
              children: [
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
                    SizedBox(
                      width: 124,
                      child: RmSelect<int>(
                        value: options.repetitions,
                        items: {
                          for (final n in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
                            n: n == 0 ? '持续试听' : '$n 次',
                        },
                        onChanged: (n) => controller.update(repetitions: n),
                      ),
                    ),
                  ],
                ),
              ],
            ),
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
      actions: [
        RmButton(
          label: '完成',
          variant: RmButtonVariant.primary,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
