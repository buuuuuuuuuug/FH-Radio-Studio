import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import 'rm_button.dart';
import 'rm_icon.dart';

final packageFolderOpenerProvider = Provider<Future<void> Function(String)>(
  (ref) => (path) async {
    final executable = Platform.isWindows
        ? 'explorer'
        : Platform.isMacOS
        ? 'open'
        : Platform.isLinux
        ? 'xdg-open'
        : null;
    if (executable == null) throw UnsupportedError('当前平台不支持打开文件夹');
    await Process.start(executable, [path]);
  },
);

class OpenPackageFolderButton extends ConsumerWidget {
  const OpenPackageFolderButton({super.key, required this.path});
  final String? path;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folder = path == null || path!.trim().isEmpty
        ? null
        : Directory(path!);
    final available = folder?.existsSync() ?? false;
    return RmButton(
      key: const ValueKey('open-built-package-folder'),
      label: '打开准备包文件夹',
      leading: RmIcon('folder', size: 12, color: context.rm.fg2),
      tooltip: available ? folder!.path : '尚无已构建的准备包目录',
      onPressed: !available
          ? null
          : () async {
              try {
                await ref.read(packageFolderOpenerProvider)(
                  folder!.absolute.path,
                );
              } on Object catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('无法打开准备包目录：$error')));
                }
              }
            },
    );
  }
}
