import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/waveform_batch_state.dart';
import '../theme/app_theme.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.dart';
import 'rm_button.dart';

class WaveformBatchProgress extends ConsumerWidget {
  const WaveformBatchProgress({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(waveformBatchProvider);
    if (s.total == 0) return const SizedBox.shrink();
    final rm = context.rm;
    final title = s.running
        ? '正在分析波形 ${s.done}/${s.total}'
        : s.cancelled
        ? '波形分析已取消 · 已完成 ${s.done}/${s.total}'
        : '波形缓存完成 · 成功 ${s.done - s.errors.length}/${s.total}';
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: rm.panel,
        border: Border.all(color: rm.border),
        borderRadius: BorderRadius.circular(RmTokens.rSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$title · 复用缓存 ${s.cached}',
                  style: RmText.sans(12, color: rm.fg2),
                ),
              ),
              if (s.errors.isNotEmpty)
                Tooltip(
                  message: s.errors.values.join('\n'),
                  child: Text(
                    '失败 ${s.errors.length}',
                    style: RmText.sans(11.5, color: rm.danger),
                  ),
                ),
              if (s.running) ...[
                const SizedBox(width: 12),
                RmButton(
                  size: RmButtonSize.sm,
                  label: s.cancelled ? '取消中…' : '取消分析',
                  onPressed: s.cancelled
                      ? null
                      : () => ref.read(waveformBatchProvider.notifier).cancel(),
                ),
              ],
            ],
          ),
          if (s.running) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: s.done / s.total,
              minHeight: 3,
              color: rm.accent.base,
              backgroundColor: rm.raised,
            ),
            const SizedBox(height: 6),
            Text(
              s.current,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: RmText.sans(11.5, color: rm.fg3),
            ),
          ],
        ],
      ),
    );
  }
}
