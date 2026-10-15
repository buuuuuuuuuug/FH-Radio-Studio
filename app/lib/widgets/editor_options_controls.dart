import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/editor_options.dart';
import '../theme/app_theme.dart';
import '../theme/text_styles.dart';

class EditorOptionsControls extends ConsumerWidget {
  const EditorOptionsControls({super.key, this.analysisControl});
  final Widget? analysisControl;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(editorOptionsProvider);
    final controller = ref.read(editorOptionsProvider.notifier);
    final rm = context.rm;
    Widget option(
      String title,
      String description,
      bool value,
      ValueChanged<bool> change,
    ) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: RmText.sans(
                      12.5,
                      weight: FontWeight.w500,
                      color: rm.fg,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(description, style: RmText.sans(11.5, color: rm.fg3)),
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 40,
              height: 24,
              child: FittedBox(
                child: Switch(
                  value: value,
                  onChanged: change,
                  activeThumbColor: rm.panel,
                  activeTrackColor: rm.accent.base,
                  inactiveThumbColor: rm.fg4,
                  inactiveTrackColor: rm.raised,
                  trackOutlineColor: WidgetStateProperty.all(rm.border),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Divider(height: 1, color: rm.border),
        LayoutBuilder(
          builder: (context, constraints) {
            final sync = option(
              'PL 自动同步 TL',
              '同步起止时间与确认状态',
              options.syncPostLoop,
              (v) => controller.update(syncPostLoop: v),
            );
            final manual =
                (analysisControl == null
                    ? null
                    : Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        child: analysisControl,
                      )) ??
                option(
                  '无 AI 处理模式',
                  '只加载波形，使用手动精调',
                  options.manualOnly,
                  (v) => controller.update(manualOnly: v),
                );
            final expansion = option(
              '电台扩容',
              '允许超过原版曲目数量',
              options.expansionEnabled,
              (v) {
                if (!controller.update(expansionEnabled: v)) {
                  showDialog<void>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      backgroundColor: rm.panel,
                      title: Text(
                        '暂时不能关闭电台扩容',
                        style: RmText.sans(16, color: rm.fg),
                      ),
                      content: Text(
                        '请先把以下电台减少到原版容量以内：\n\n${controller.expansionOverflow().join("\n")}\n\n现有歌曲与顺序不会自动删除。',
                        style: RmText.sans(12, color: rm.fg2),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('知道了'),
                        ),
                      ],
                    ),
                  );
                }
              },
            );
            if (constraints.maxWidth < 900) {
              return Column(
                children: [
                  manual,
                  Divider(height: 1, color: rm.border),
                  if (constraints.maxWidth < 600) ...[
                    sync,
                    Divider(height: 1, color: rm.border),
                    expansion,
                  ] else
                    Row(
                      children: [
                        Expanded(child: sync),
                        Container(width: 1, height: 64, color: rm.border),
                        Expanded(child: expansion),
                      ],
                    ),
                ],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 2, child: manual),
                  VerticalDivider(width: 1, color: rm.border),
                  Expanded(child: sync),
                  VerticalDivider(width: 1, color: rm.border),
                  Expanded(child: expansion),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
