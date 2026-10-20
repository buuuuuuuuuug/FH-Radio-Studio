import 'timing_dialog_frame.dart';
import 'dart:convert';
import 'dart:io';
import 'rm_segmented.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../core/fh_radio_studio_cli.dart';
import '../core/playlist_plan.dart';
import '../core/timing_radio_assignments.dart';
import '../screens/playlist/playlist_state.dart';
import '../state/studio_state.dart';
import '../state/track_timing_state.dart';
import '../state/playlist_catalog_state.dart';
import '../state/playlist_plan_state.dart';
import '../theme/app_theme.dart';
import '../theme/text_styles.dart';
import 'rm_button.dart';
import 'rm_select.dart';
import 'quick_assign_dialog.dart';
import 'timing_match_modes.dart';

typedef TimingImportRunner =
    Future<CliRunResult> Function(
      String root,
      List<String> args,
      String? input,
    );
final timingImportRunnerProvider = Provider<TimingImportRunner>(
  (ref) =>
      (root, args, input) =>
          FhRadioStudioCli(repoRoot: root).runBase(args, stdinInput: input),
);

final timingImportFilePickerProvider = Provider<Future<String?> Function()>(
  (ref) => () async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'tsv', 'txt', 'json', 'xlsx', 'xml'],
      dialogTitle: '选择时间点文件',
    );
    return result?.files.firstOrNull?.path;
  },
);

class TimingImportButton extends ConsumerWidget {
  const TimingImportButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(studioProvider);
    return RmButton(
      label: '导入时间点',
      size: RmButtonSize.sm,
      tooltip: '导入时间或 48000 Hz 采样点，支持 CSV、JSON、XLSX、RadioInfo XML；导入前自动备份',
      onPressed: state.busy || state.projectPathMigrationActive
          ? null
          : () => showDialog<void>(
              context: context,
              builder: (_) => const TimingImportDialog(),
            ),
    );
  }
}

class TimingImportDialog extends ConsumerStatefulWidget {
  const TimingImportDialog({super.key});
  @override
  ConsumerState<TimingImportDialog> createState() => _TimingImportDialogState();
}

class _TimingImportDialogState extends ConsumerState<TimingImportDialog> {
  String? file, error, previewProject, radioSignature;
  final pastedText = TextEditingController();
  bool pasteMode = false;
  bool get hasInput =>
      pasteMode ? pastedText.text.trim().isNotEmpty : file != null;
  @override
  void dispose() {
    pastedText.dispose();
    super.dispose();
  }

  String matchMode = 'auto';
  String timeUnit = 'time';
  bool eventOnlyAssignment = false;
  bool get xmlInput =>
      !pasteMode && file?.toLowerCase().endsWith('.xml') == true;
  bool overwrite = false,
      confirm = false,
      assignRadio = false,
      busy = false,
      applied = false;
  Map<String, dynamic>? preview;
  PlaylistPlan? assignmentPreview;
  void invalidate() {
    preview = null;
    applied = false;
    error = null;
    assignmentPreview = null;
    radioSignature = null;
    eventOnlyAssignment = false;
  }

  Map<String, int> capacities() => {
    for (final radio in ref.read(playlistCatalogProvider).radios)
      if (RegExp(r'^R[1-9]$').hasMatch(radio.code))
        radio.code: assignmentLimit(
          ref,
          radio,
          eventOnlyAssignment ||
                  ref.read(playlistProvider).mode == PlaylistMode.event
              ? 'Event'
              : 'FreeRoam',
        ),
  };
  String currentRadioSignature() => jsonEncode([
    editableAssignmentPlan(ref).encodeForCli(),
    capacities(),
    ref.read(playlistProvider).splitPlaylistTypes,
    ref.read(playlistProvider).mode.name,
  ]);
  Future<void> chooseFile() async {
    try {
      final selected = await ref.read(timingImportFilePickerProvider)();
      if (!mounted || selected == null) return;
      setState(() {
        file = selected;
        invalidate();
      });
    } on Object catch (e) {
      if (mounted) setState(() => error = '无法选择文件：$e');
    }
  }

  Future<void> run({bool apply = false}) async {
    if (busy || !hasInput) return;
    if (pasteMode && pastedText.text.trimLeft().startsWith('<')) {
      setState(() => error = 'RadioInfo XML 请通过“选择文件”导入。');
      return;
    }
    final studio = ref.read(studioProvider);
    if (studio.projectEditingLocked) {
      setState(() => error = '项目当前不可编辑。');
      return;
    }
    if (apply &&
        (previewProject != studio.projectDir ||
            assignRadio && radioSignature != currentRadioSignature())) {
      setState(() {
        invalidate();
        error = '项目、播放列表或容量设置已改变，请重新预览。';
      });
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (apply && assignRadio && assignmentPreview != null) {
        final backup = File(
          p.join(
            studio.projectDir,
            'analysis',
            'timing-import-backups',
            '${DateTime.now().toUtc().microsecondsSinceEpoch}-playlist.json',
          ),
        );
        backup.parent.createSync(recursive: true);
        backup.writeAsStringSync(editableAssignmentPlan(ref).encodeForCli());
      }
      final result = await ref.read(timingImportRunnerProvider)(
        studio.repoRoot,
        [
          'import-timings',
          '--project-dir',
          studio.projectDir,
          '--input',
          pasteMode ? '-' : file!,
          '--match-mode',
          matchMode,
          '--time-unit',
          xmlInput ? 'samples' : timeUnit,
          if (overwrite) '--overwrite',
          if (confirm) '--confirm',
          if (assignRadio) '--assign-radio',
          if (apply) ...[
            '--apply',
            '--expected-snapshot',
            '${preview!['snapshot_hash']}',
            '--expected-input',
            '${preview!['input_hash']}',
          ],
        ],
        pasteMode ? pastedText.text : null,
      );
      if (!result.ok) throw FormatException(result.stderr.trim());
      final payload = jsonDecode(result.stdout) as Map<String, dynamic>;
      if (!mounted) return;
      if (ref.read(studioProvider).projectDir != studio.projectDir) {
        throw const FormatException('项目已改变，请重新预览。');
      }
      if (apply) {
        ref.read(trackTimingProvider.notifier).reload();
        if (assignRadio && assignmentPreview != null) {
          if (radioSignature != currentRadioSignature()) {
            throw const FormatException('时间点已导入；播放列表刚刚改变，电台分配未应用，请重新预览。');
          }
          ref
              .read(playlistPlanProvider.notifier)
              .replaceWith(assignmentPreview!);
        }
      } else if (assignRadio) {
        eventOnlyAssignment = payload['source_format'] == 'radio-info';
        radioSignature = currentRadioSignature();
        final state = ref.read(playlistProvider);
        final layouts = (payload['radio_layouts'] as List? ?? const [])
            .cast<Map>();
        assignmentPreview = eventOnlyAssignment && layouts.isNotEmpty
            ? previewXmlRadioLayouts(
                plan: editableAssignmentPlan(ref),
                layouts: layouts,
                capacities: capacities(),
                splitTypes: state.splitPlaylistTypes,
                projectDir: studio.projectDir,
              )
            : previewTimingRadioAssignments(
                plan: editableAssignmentPlan(ref),
                rows: (payload['rows'] as List).cast<Map>(),
                capacities: capacities(),
                playlistType:
                    eventOnlyAssignment || state.mode == PlaylistMode.event
                    ? 'Event'
                    : 'FreeRoam',
                splitTypes: eventOnlyAssignment || state.splitPlaylistTypes,
                projectDir: studio.projectDir,
              );
      }
      setState(() {
        preview = payload;
        previewProject = studio.projectDir;
        applied = apply;
      });
    } on Object catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rm = context.rm;
    final rows = (preview?['rows'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    final count = (preview?['ready_count'] as num?)?.toInt() ?? 0;
    final layouts = (preview?['radio_layouts'] as List? ?? const [])
        .cast<Map>();
    final layoutAvailable =
        assignRadio &&
        layouts.any((l) => l['mode'] == 'builtin' || l['mode'] == 'custom');
    final template = timingCsvTemplateFor(
      includeRadio: assignRadio,
      timeUnit: timeUnit,
      matchMode: matchMode,
    );
    Widget selectField(String label, Widget select) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: RmText.sans(11.5, color: rm.fg2)),
        const SizedBox(height: 5),
        select,
      ],
    );
    return TimingDialogFrame(
      title: '批量导入时间点',
      busy: busy,
      width: 820,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: RmSegmented<bool>(
              value: pasteMode,
              options: const [
                RmSegmentedOption(value: false, label: '选择文件'),
                RmSegmentedOption(value: true, label: '粘贴文本'),
              ],
              onChanged: (v) {
                if (!busy) {
                  setState(() {
                    pasteMode = v;
                    invalidate();
                  });
                }
              },
            ),
          ),
          const SizedBox(height: 12),
          if (pasteMode) ...[
            TextField(
              key: const ValueKey('timing-import-text'),
              controller: pastedText,
              enabled: !busy,
              minLines: 4,
              maxLines: 7,
              style: RmText.mono(11.5, color: rm.fg),
              decoration: const InputDecoration(
                hintText: '在此粘贴 CSV、表格文本或 JSON',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(invalidate),
            ),
            const SizedBox(height: 6),
            Text(
              '可直接粘贴表格单元格；RadioInfo XML 请切换到文件导入。',
              style: RmText.sans(11, color: rm.fg3),
            ),
          ] else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: rm.raised,
                border: Border.all(color: rm.border),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.insert_drive_file_outlined,
                    size: 20,
                    color: rm.fg3,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file == null ? '选择要导入的文件' : p.basename(file!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: RmText.sans(12, color: rm.fg),
                        ),
                        const SizedBox(height: 3),
                        Tooltip(
                          message: file ?? '',
                          child: Text(
                            file ?? 'CSV、Excel、JSON、TXT 或 RadioInfo XML',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: RmText.sans(11, color: rm.fg3),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  RmButton(
                    key: const ValueKey('timing-import-file'),
                    label: file == null ? '选择文件' : '更换文件',
                    onPressed: busy ? null : chooseFile,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          if (xmlInput &&
              file!.replaceAll('\\', '/').contains('/packages/')) ...[
            Text(
              '此文件来自准备包，将按其中的排布导入；恢复较早排布请选择对应备份。',
              style: RmText.sans(11.5, color: rm.warn),
            ),
            const SizedBox(height: 8),
          ],
          if (xmlInput)
            Text(
              '仅读取赛事（Event），按歌曲名和歌手自动匹配；采样率须为 48000 Hz。',
              style: RmText.sans(11.5, color: rm.fg2),
            )
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final fields = [
                  selectField(
                    'Filename 列的匹配方式',
                    RmSelect<String>(
                      key: const ValueKey('timing-import-match-mode'),
                      value: matchMode,
                      items: timingMatchModes,
                      onChanged: busy
                          ? null
                          : (v) => setState(() {
                              matchMode = v;
                              invalidate();
                            }),
                    ),
                  ),
                  selectField(
                    '数据中的时间点形式',
                    RmSelect<String>(
                      key: const ValueKey('timing-import-time-unit'),
                      value: timeUnit,
                      items: timingTimeUnits,
                      onChanged: busy
                          ? null
                          : (v) => setState(() {
                              timeUnit = v;
                              invalidate();
                            }),
                    ),
                  ),
                ];
                return constraints.maxWidth < 560
                    ? Column(
                        children: [
                          fields[0],
                          const SizedBox(height: 10),
                          fields[1],
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: fields[0]),
                          const SizedBox(width: 12),
                          Expanded(child: fields[1]),
                        ],
                      );
              },
            ),
            const SizedBox(height: 6),
            Text(
              '${matchMode == 'auto' ? '仅接受唯一匹配；重名时建议用文件名。' : 'Filename 按“${timingMatchModes[matchMode]}”填写。'} '
              '${timeUnit == 'samples' ? '采样点须为非负整数，固定按 48000 Hz 换算。' : '时间可填 分:秒.毫秒 或 秒数。'}',
              style: RmText.sans(11, color: rm.fg3),
            ),
          ],
          const SizedBox(height: 8),
          _check(
            context,
            xmlInput ? '按 XML 电台归属分配' : '使用 Radio_station 列分配电台',
            assignRadio,
            busy
                ? null
                : (v) => setState(() {
                    assignRadio = v;
                    invalidate();
                  }),
          ),
          if (assignRadio)
            Text(
              xmlInput
                  ? '按文件重建列表；匹配到本地歌曲时保持可编辑。未分场景时同步漫游，分场景时只更新赛事。'
                  : '填写 R1–R9，多个电台用分号分隔；空白不改分配。先检查容量，再更新播放列表草稿。',
              style: RmText.sans(11, color: rm.fg3),
            ),
          Wrap(
            spacing: 10,
            runSpacing: 2,
            children: [
              _check(
                context,
                '允许覆盖已有时间组',
                overwrite,
                busy
                    ? null
                    : (v) => setState(() {
                        overwrite = v;
                        invalidate();
                      }),
              ),
              _check(
                context,
                '将完整时间组标记为已确认',
                confirm,
                busy
                    ? null
                    : (v) => setState(() {
                        confirm = v;
                        invalidate();
                      }),
              ),
            ],
          ),
          Text(
            overwrite
                ? '空白节点会清除原值，未包含的列保留。导入前自动备份。'
                : '默认跳过已有时间组，未完成组保持待配置。导入前自动备份。',
            style: RmText.sans(11, color: rm.fg3),
          ),
          if (!xmlInput) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: rm.raised,
                border: Border.all(color: rm.border),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'CSV 模板',
                          style: RmText.sans(
                            12,
                            weight: FontWeight.w600,
                            color: rm.fg2,
                          ),
                        ),
                      ),
                      RmButton(
                        label: '复制 CSV 模板',
                        size: RmButtonSize.sm,
                        onPressed: () =>
                            Clipboard.setData(ClipboardData(text: template)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SelectableText(
                      template,
                      style: RmText.mono(11, color: rm.fg),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'TL-A / PL-A 为起点，TL-B / PL-B 为终点；节点可留空。',
                    style: RmText.sans(11, color: rm.fg3),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(error!, style: RmText.sans(11.5, color: rm.warn)),
            ),
          if (busy) const LinearProgressIndicator(minHeight: 2),
          if (preview != null) ...[
            Text(
              applied
                  ? (count == 0 && layoutAvailable
                        ? '已更新电台列表，歌曲时间点未变。原播放列表已备份。'
                        : '已导入 ${preview!['applied_count']} 首，原点位已自动备份。${assignRadio ? '电台分配已更新至播放列表草稿。' : ''}')
                  : '可导入 $count 首；其余行已跳过或需修正。',
              style: RmText.sans(12, color: applied ? rm.accent.base : rm.fg2),
            ),
            if (assignRadio)
              for (final layout in layouts)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${layout['radio_code']} · ${layout['message']}',
                    style: RmText.sans(
                      12,
                      color: layout['mode'] == 'blocked'
                          ? rm.warn
                          : rm.accent.base,
                    ),
                  ),
                ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 230),
              decoration: BoxDecoration(
                border: Border.all(color: rm.border),
                borderRadius: BorderRadius.circular(6),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: rows.length,
                separatorBuilder: (_, i) =>
                    Divider(height: 1, color: rm.border),
                itemBuilder: (context, i) {
                  final row = rows[i];
                  return Padding(
                    padding: const EdgeInsets.all(9),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 32,
                          child: Text(
                            '${row['row']}',
                            style: RmText.mono(11, color: rm.fg3),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${row['title'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: RmText.sans(12, color: rm.fg),
                              ),
                              Text(
                                '${row['message']}',
                                style: RmText.sans(
                                  11,
                                  color: row['status'] == 'error'
                                      ? rm.warn
                                      : rm.fg3,
                                ),
                              ),
                              if (row['markers_sec'] is Map)
                                Text(
                                  (row['markers_sec'] as Map).entries
                                      .map(
                                        (e) =>
                                            '${_markerLabel(e.key)} ${_time(e.value)}',
                                      )
                                      .join(' · '),
                                  style: RmText.mono(10, color: rm.fg3),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          row['status'] == 'builtin'
                              ? '原版'
                              : row['status'] == 'ready'
                              ? '可导入'
                              : row['status'] == 'error'
                              ? '需修正'
                              : '已跳过',
                          style: RmText.sans(
                            11,
                            color: row['status'] == 'ready'
                                ? rm.accent.base
                                : rm.fg3,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
      actions: [
        RmButton(
          label: applied ? '完成' : '取消',
          onPressed: busy ? null : () => Navigator.pop(context),
        ),
        if (!applied)
          RmButton(
            label: preview == null ? '预览匹配' : '重新预览',
            variant: preview == null
                ? RmButtonVariant.primary
                : RmButtonVariant.defaultBtn,
            onPressed: busy || !hasInput ? null : () => run(),
          ),
        if (preview != null && !applied)
          RmButton(
            label: count == 0 && layoutAvailable ? '应用电台列表' : '导入 $count 首',
            variant: RmButtonVariant.primary,
            onPressed:
                busy ||
                    applied ||
                    (count == 0 && !layoutAvailable) ||
                    error != null
                ? null
                : () => run(apply: true),
          ),
      ],
    );
  }

  String _markerLabel(Object key) =>
      const {
        'TrackDrop': 'TD',
        'PostDrop': 'PD',
        'TrackLoopStart': 'TL-A',
        'TrackLoopEnd': 'TL-B',
        'PostRaceLoopStart': 'PL-A',
        'PostRaceLoopEnd': 'PL-B',
      }[key] ??
      '$key';
  String _time(Object? value) {
    if (value is! num) return '—';
    final ms = (value * 1000).round();
    return '${ms ~/ 60000}:${((ms ~/ 1000) % 60).toString().padLeft(2, "0")}.${(ms % 1000).toString().padLeft(3, "0")}';
  }

  Widget _check(
    BuildContext context,
    String label,
    bool value,
    ValueChanged<bool>? change,
  ) => InkWell(
    onTap: change == null ? null : () => change(!value),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: value,
          onChanged: change == null ? null : (v) => change(v == true),
          visualDensity: VisualDensity.compact,
        ),
        Text(label, style: RmText.sans(11.5, color: context.rm.fg2)),
      ],
    ),
  );
}
