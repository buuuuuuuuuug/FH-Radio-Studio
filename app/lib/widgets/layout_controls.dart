import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/app_state.dart';
import '../state/layout_options.dart';
import '../theme/app_theme.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.dart';
import 'rm_button.dart';

class PageWidthControl extends ConsumerWidget {
  const PageWidthControl({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(layoutOptionsProvider);
    final ctl = ref.read(layoutOptionsProvider.notifier);
    final sidebar = ref.watch(navStyleProvider) == NavStyle.rail
        ? RmTokens.sidebarWidth
        : 0;
    final available = math.max(
      320.0,
      MediaQuery.sizeOf(context).width - sidebar,
    );
    final minimum = math.min(1120.0, available);
    final value = options.width <= 0
        ? math.min(1240.0, available)
        : options.width.clamp(minimum, available);
    final rm = context.rm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) => Row(
            children: [
              Expanded(
                child: Text(
                  options.width == 0
                      ? '原始宽度'
                      : options.width < 0
                      ? '适应窗口'
                      : '${value.round()} px',
                  style: RmText.sans(11.5, color: rm.fg2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              RmButton(
                size: RmButtonSize.sm,
                label: c.maxWidth < 240 ? '原始' : '原始宽度',
                tooltip: '原始宽度',
                horizontalPadding: 6,
                onPressed: () => ctl.setWidth(0),
              ),
              const SizedBox(width: 6),
              RmButton(
                size: RmButtonSize.sm,
                label: c.maxWidth < 240 ? '适应' : '适应窗口',
                tooltip: '适应窗口',
                horizontalPadding: 6,
                onPressed: () => ctl.setWidth(-1),
              ),
            ],
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
          ),
          child: Slider(
            value: value,
            min: minimum,
            max: math.max(minimum, available),
            activeColor: rm.accent.base,
            onChanged: available <= minimum ? null : ctl.setWidth,
          ),
        ),
      ],
    );
  }
}

class RadioHeightDialog extends ConsumerWidget {
  const RadioHeightDialog({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rm = context.rm;
    final height = ref.watch(layoutOptionsProvider).radioHeight;
    return AlertDialog(
      backgroundColor: rm.panel,
      title: Text(
        '电台列表显示长度',
        style: RmText.sans(16, weight: FontWeight.w600, color: rm.fg),
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '每个电台高度 ${height.round()} px',
              style: RmText.sans(12, color: rm.fg2),
            ),
            Slider(
              value: height,
              min: 160,
              max: 1200,
              divisions: 52,
              activeColor: rm.accent.base,
              onChanged: ref
                  .read(layoutOptionsProvider.notifier)
                  .setRadioHeight,
            ),
            Text(
              '仅改变可见长度，歌曲数量与顺序保持不变。',
              style: RmText.sans(11.5, color: rm.fg3),
            ),
          ],
        ),
      ),
      actions: [
        RmButton(
          label: '恢复默认',
          onPressed: () =>
              ref.read(layoutOptionsProvider.notifier).setRadioHeight(480),
        ),
        RmButton(label: '完成', onPressed: () => Navigator.pop(context)),
      ],
    );
  }
}

/// This preference expands the waveform side only; the suggestions stay 300 px wide.
class ManualRefineWidthControl extends ConsumerWidget {
  const ManualRefineWidthControl({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rm = context.rm;
    final options = ref.watch(layoutOptionsProvider);
    final ctl = ref.read(layoutOptionsProvider.notifier);
    final sidebar = ref.watch(navStyleProvider) == NavStyle.rail
        ? RmTokens.sidebarWidth
        : 0;
    final available = math.max(
      0.0,
      MediaQuery.sizeOf(context).width - sidebar - 48,
    );
    final minimum = math.min(860.0, available);
    final value = options.manualRefineWidth.clamp(minimum, available);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${value.round()} px',
                style: RmText.sans(11.5, color: rm.fg2),
              ),
            ),
            RmButton(
              size: RmButtonSize.sm,
              label: '恢复默认',
              onPressed: () => ctl.setManualRefineWidth(1080),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
          ),
          child: Slider(
            key: const ValueKey('manual-refine-width-slider'),
            value: value,
            min: minimum,
            max: available,
            activeColor: rm.accent.base,
            onChanged: available <= minimum ? null : ctl.setManualRefineWidth,
          ),
        ),
      ],
    );
  }
}
