import 'timing_dialog_frame.dart';
import '../core/atomic_file.dart';
import 'rm_select.dart';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/studio_state.dart';
import '../theme/app_theme.dart';
import '../theme/text_styles.dart';
import 'rm_button.dart';
import 'timing_import_dialog.dart';
import 'timing_match_modes.dart';

class TimingExportButton extends ConsumerWidget {
  const TimingExportButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(studioProvider);
    return RmButton(
      label: '导出时间点',
      size: RmButtonSize.sm,
      tooltip: '导出项目中已保存的时间点为 CSV',
      onPressed: state.busy || state.projectPathMigrationActive
          ? null
          : () => showDialog<void>(
              context: context,
              builder: (_) => const TimingExportDialog(),
            ),
    );
  }
}

class TimingExportDialog extends ConsumerStatefulWidget {
  const TimingExportDialog({super.key});
  @override
  ConsumerState<TimingExportDialog> createState() => _TimingExportDialogState();
}

class _TimingExportDialogState extends ConsumerState<TimingExportDialog> {
  String identity = 'filename';
  bool busy = false;
  bool includeRadio = false;
  String? message;
  Future<void> export() async {
    final studio = ref.read(studioProvider);
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final result =
          await ref.read(timingImportRunnerProvider)(studio.repoRoot, [
            'export-timings',
            '--project-dir',
            studio.projectDir,
            '--identity',
            identity,
            if (includeRadio) '--include-radio',
          ], null);
      if (!result.ok) {
        throw FormatException(result.stderr.trim());
      }
      final data = jsonDecode(result.stdout) as Map<String, dynamic>;
      if ((data['count'] as num? ?? 0) == 0) {
        throw const FormatException('项目中没有可导出的歌曲。');
      }
      if (!mounted) {
        return;
      }
      final path = await FilePicker.saveFile(
        dialogTitle: '导出时间点 CSV',
        fileName: 'track_timing.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (path == null || !mounted) {
        return;
      }
      if (ref.read(studioProvider).projectDir != studio.projectDir) {
        throw const FormatException('项目已改变，请重新导出。');
      }
      final file = path.toLowerCase().endsWith('.csv') ? path : '$path.csv';
      await writeTextAtomically(File(file), '\uFEFF${data['csv']}');
      if (mounted) {
        setState(
          () => message =
              '已导出 ${data['count']} 首：$file\n${data['warning'] ?? ''}',
        );
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => message = '$e');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rm = context.rm;
    return TimingDialogFrame(
      title: '导出时间点',
      busy: busy,
      width: 520,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '导出全部歌曲的已保存时间点，未配置节点留空。未保存的编辑请先保存；此操作不修改项目。',
            style: RmText.sans(12, color: rm.fg2),
          ),
          const SizedBox(height: 12),
          Text('Filename 列使用的歌曲标识', style: RmText.sans(11.5, color: rm.fg2)),
          const SizedBox(height: 5),
          RmSelect<String>(
            value: identity,
            items: {
              for (final e in timingMatchModes.entries)
                if (e.key != 'auto') e.key: e.value,
            },
            onChanged: busy ? null : (v) => setState(() => identity = v),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              '包含 Radio_station 电台列',
              style: RmText.sans(12, color: rm.fg2),
            ),
            value: includeRadio,
            onChanged: busy
                ? null
                : (v) => setState(() => includeRadio = v == true),
          ),
          if (includeRadio)
            Text(
              '导出已保存播放列表中的 R1–R9 分配，多个电台用分号分隔。未保存的播放列表草稿不包含在内。',
              style: RmText.sans(11, color: rm.fg3),
            ),
          const SizedBox(height: 12),
          Text(
            '${includeRadio ? 'Filename,Radio_station,TD,PD,TL-A,TL-B,PL-A,PL-B' : 'Filename,TD,PD,TL-A,TL-B,PL-A,PL-B'}\nTL-A / PL-A 为起点，TL-B / PL-B 为终点；空白表示该时间点未配置。',
            style: RmText.sans(11.5, color: rm.fg3),
          ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SelectableText(
                message!,
                style: RmText.sans(12, color: rm.fg),
              ),
            ),
        ],
      ),
      actions: [
        RmButton(
          label: '关闭',
          onPressed: busy ? null : () => Navigator.pop(context),
        ),
        RmButton(
          label: busy ? '正在导出…' : '导出 CSV',
          variant: RmButtonVariant.primary,
          onPressed: busy ? null : export,
        ),
      ],
    );
  }
}
