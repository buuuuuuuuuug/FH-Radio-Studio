import 'timing_dialog_frame.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class TimingImportButton extends ConsumerWidget {
  const TimingImportButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(studioProvider);
    return RmButton(
      label: '导入时间点',
      size: RmButtonSize.sm,
      tooltip: '预览并批量导入文本、CSV、JSON 或 XLSX；导入前自动备份',
      onPressed: state.busy || state.projectPathMigrationActive
          ? null
          : () => showDialog<void>(
              context: context,
              barrierDismissible: false,
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
  final text = TextEditingController();
  String? file, error, previewProject, radioSignature;
  String matchMode = 'auto';
  bool overwrite = false,
      confirm = false,
      assignRadio = false,
      busy = false,
      applied = false;
  Map<String, dynamic>? preview;
  PlaylistPlan? assignmentPreview;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  void invalidate() {
    preview = null;
    applied = false;
    error = null;
    assignmentPreview = null;
    radioSignature = null;
  }

  Map<String, int> capacities() => {
    for (final radio in ref.read(playlistCatalogProvider).radios)
      if (RegExp(r'^R[1-9]$').hasMatch(radio.code))
        radio.code: assignmentLimit(
          ref,
          radio,
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
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'tsv', 'txt', 'json', 'xlsx'],
      dialogTitle: '选择时间点数据',
    );
    if (!mounted || result == null || result.files.isEmpty) return;
    setState(() {
      file = result.files.first.path;
      invalidate();
    });
  }

  Future<void> run({bool apply = false}) async {
    if (busy) return;
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
      final result = await ref.read(timingImportRunnerProvider)(
        studio.repoRoot,
        [
          'import-timings',
          '--project-dir',
          studio.projectDir,
          '--input',
          file ?? '-',
          '--match-mode',
          matchMode,
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
        file == null ? text.text : null,
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
        radioSignature = currentRadioSignature();
        final state = ref.read(playlistProvider);
        assignmentPreview = previewTimingRadioAssignments(
          plan: editableAssignmentPlan(ref),
          rows: (payload['rows'] as List).cast<Map>(),
          capacities: capacities(),
          playlistType: state.mode == PlaylistMode.event ? 'Event' : 'FreeRoam',
          splitTypes: state.splitPlaylistTypes,
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
    final template = timingCsvTemplateFor(includeRadio: assignRadio);
    return TimingDialogFrame(
      title: '批量导入时间点',
      busy: busy,
      width: 820,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '自动模式只接受唯一匹配；空白时间点可以导入，未完成组不会标记为已确认。已有时间组默认跳过。',
            style: RmText.sans(11.5, color: rm.fg3),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              RmButton(label: '选择文件', onPressed: busy ? null : chooseFile),
              RmButton(
                label: '使用粘贴文本',
                onPressed: busy
                    ? null
                    : () => setState(() {
                        file = null;
                        invalidate();
                      }),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('Filename 列的匹配方式', style: RmText.sans(11.5, color: rm.fg2)),
          const SizedBox(height: 5),
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
          const SizedBox(height: 8),
          _check(
            context,
            '使用 Radio_station 列分配电台',
            assignRadio,
            busy
                ? null
                : (v) => setState(() {
                    assignRadio = v;
                    invalidate();
                  }),
          ),
          Text(
            assignRadio
                ? 'Radio_station 放在 Filename 后，填写 R1–R9 或 1–9；多个电台用分号分隔，空白不改变分配。先检查容量，再更新播放列表草稿；可在播放列表保存或撤销。分场景编辑时只分配当前场景。'
                : '电台分配已关闭：即使文件含有 Radio_station 列，也会忽略该列。',
            style: RmText.sans(11, color: rm.fg3),
          ),
          const SizedBox(height: 8),
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
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'TL-A / PL-A 是循环起点，TL-B / PL-B 是终点。支持分:秒.毫秒或秒数；允许只填部分节点。勾选“允许覆盖”后，文件中明确留空的节点会清除原值；未包含的列保留。',
            style: RmText.sans(11, color: rm.fg3),
          ),
          const SizedBox(height: 8),
          if (file != null)
            Text(
              file!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: RmText.sans(11.5, color: rm.fg2),
            )
          else
            TextField(
              key: const ValueKey('timing-import-text'),
              controller: text,
              minLines: 3,
              maxLines: 5,
              enabled: !busy,
              style: RmText.mono(11.5, color: rm.fg),
              onChanged: (_) => setState(invalidate),
              decoration: InputDecoration(
                hintText: '粘贴带表头的 CSV / Excel 制表符文本，或 JSON…',
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: rm.border),
                ),
              ),
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
                '导入的完整时间组标记为已确认',
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
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(error!, style: RmText.sans(11.5, color: rm.warn)),
            ),
          if (busy) const LinearProgressIndicator(minHeight: 2),
          if (preview != null) ...[
            Text(
              applied
                  ? '已导入 ${preview!['applied_count']} 首，原点位已自动备份。${assignRadio ? '电台分配已更新至播放列表草稿。' : ''}'
                  : '可导入 $count 首；其余行已跳过或需修正。',
              style: RmText.sans(12, color: applied ? rm.accent.base : rm.fg2),
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
                          row['status'] == 'ready'
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
        RmButton(
          label: '预览匹配',
          onPressed: busy || file == null && text.text.trim().isEmpty
              ? null
              : () => run(),
        ),
        RmButton(
          label: '导入 $count 首',
          variant: RmButtonVariant.primary,
          onPressed: busy || applied || count == 0 || error != null
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
