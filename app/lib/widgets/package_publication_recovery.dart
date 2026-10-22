import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/project_workspace.dart';
import '../state/studio_state.dart';
import 'rm_banner.dart';
import 'rm_button.dart';
import 'timing_dialog_frame.dart';
import '../theme/text_styles.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

final completedPackageProvider =
    Provider<List<({String target, String ready})>>((ref) {
      final state = ref.watch(
        studioProvider.select((s) => (s.projectDir, s.busy, s.log.length)),
      );
      final packages = Directory(FhRadioStudioProject.packagesDir(state.$1));
      try {
        if (!packages.existsSync()) return const [];
        final candidates =
            packages
                .listSync(followLinks: false)
                .whereType<Directory>()
                .where(
                  (d) =>
                      File(p.join(d.path, '.publish-ready.json')).existsSync(),
                )
                .toList()
              ..sort(
                (a, b) =>
                    b.statSync().modified.compareTo(a.statSync().modified),
              );
        final result = <({String target, String ready})>[];
        for (final name in ['current', 'pending']) {
          final stage = candidates
              .where((d) => p.basename(d.path).startsWith('.$name-building-'))
              .firstOrNull;
          if (stage != null) {
            result.add((
              target: p.join(packages.path, name),
              ready: stage.path,
            ));
          }
        }
        return result;
      } on FileSystemException {
        return const [];
      }
    });

class PackagePublicationRecovery extends ConsumerWidget {
  const PackagePublicationRecovery({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completed = ref.watch(completedPackageProvider);
    final cli = ref.watch(studioProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final package in completed)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const RmBanner(
                  kind: RmBannerKind.warn,
                  title: '新准备包已构建，等待替换。',
                  body:
                      '可直接重试，无需重新编码。若具体文件仍被独占，请先关闭使用该文件的程序。重试使用已完成的版本，不包含之后的编辑。',
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: RmButton(
                    label: '重试替换',
                    onPressed: cli.busy || cli.projectEditingLocked
                        ? null
                        : () async {
                            final confirm = await showPackagePublicationDialog(
                              context,
                            );
                            if (confirm != true ||
                                !context.mounted ||
                                ref.read(studioProvider).projectDir !=
                                    cli.projectDir) {
                              return;
                            }
                            await ref
                                .read(studioProvider.notifier)
                                .retryPackagePublication(
                                  package.target,
                                  package.ready,
                                );
                            ref.invalidate(completedPackageProvider);
                          },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

Future<bool?> showPackagePublicationDialog(BuildContext context) =>
    showDialog<bool>(
      context: context,
      barrierColor: RmTokens.modalBackdrop,
      builder: (dialog) => TimingDialogFrame(
        title: '替换为已完成的准备包？',
        icon: 'refresh',
        description: '使用上次已完成的构建',
        width: 520,
        busy: false,
        body: Text(
          '这会发布上次已完成的构建，不会重新编码，也不包含之后修改的歌曲信息或播放列表。',
          style: RmText.body(color: dialog.rm.fg2),
        ),
        actions: [
          RmButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            label: '取消',
          ),
          RmButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            label: '重试替换',
            variant: RmButtonVariant.primary,
          ),
        ],
      ),
    );
