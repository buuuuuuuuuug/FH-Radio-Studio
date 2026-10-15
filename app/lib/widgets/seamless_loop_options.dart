import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/editor_options.dart';
import '../state/studio_state.dart';
import '../theme/app_theme.dart';
import '../theme/text_styles.dart';
import 'rm_button.dart';

class SeamlessLoopOptions extends ConsumerWidget {
  const SeamlessLoopOptions({super.key});
  static const projectUrl = 'https://github.com/CPUrising/seamless-loop-music';
  Future<void> _openProject(BuildContext context) async {
    try {
      if (Platform.isWindows) {
        await Process.start('rundll32.exe', [
          'url.dll,FileProtocolHandler',
          projectUrl,
        ], mode: ProcessStartMode.detached);
      } else {
        await Process.start(Platform.isMacOS ? 'open' : 'xdg-open', [
          projectUrl,
        ], mode: ProcessStartMode.detached);
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开浏览器，请访问 $projectUrl')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rm = context.rm;
    final enabled = ref.watch(editorOptionsProvider).slmEnabled;
    return Column(
      children: [
        Divider(height: 1, color: rm.border),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final description = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SeamlessLoopMusic · 实验功能',
                    style: RmText.sans(
                      12.5,
                      color: rm.fg,
                      weight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '自动寻找衔接自然的 TL / PL 循环起止点，替换原循环分析；无 AI 模式也可用。',
                    style: RmText.sans(11.5, color: rm.fg3),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '来源：CPUrising / SeamlessLoopMusic 的 loopfinder 引擎（PyMusicLooper 的 C++ 重写）。',
                    style: RmText.sans(11.5, color: rm.fg3),
                  ),
                ],
              );
              final controls = Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  RmButton(
                    size: RmButtonSize.sm,
                    label: '原项目 GitHub',
                    leading: const Icon(Icons.open_in_new, size: 12),
                    tooltip: '查看 SeamlessLoopMusic 的源代码、说明与许可',
                    onPressed: () => _openProject(context),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 40,
                    height: 24,
                    child: FittedBox(
                      child: Switch(
                        value: enabled,
                        activeThumbColor: rm.panel,
                        activeTrackColor: rm.accent.base,
                        inactiveThumbColor: rm.fg4,
                        inactiveTrackColor: rm.raised,
                        trackOutlineColor: WidgetStateProperty.all(rm.border),
                        onChanged: ref.watch(studioProvider).busy
                            ? null
                            : (v) => ref
                                  .read(editorOptionsProvider.notifier)
                                  .update(slmEnabled: v),
                      ),
                    ),
                  ),
                ],
              );
              if (constraints.maxWidth < 620) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    description,
                    const SizedBox(height: 10),
                    Align(alignment: Alignment.centerRight, child: controls),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: description),
                  const SizedBox(width: 18),
                  controls,
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
