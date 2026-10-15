import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/playlist_plan.dart';
import '../domain/radio_library.dart';
import '../screens/playlist/playlist_state.dart';
import '../state/editor_options.dart';
import '../state/playlist_catalog_state.dart';
import '../state/playlist_plan_state.dart';
import '../state/studio_state.dart';
import '../theme/app_theme.dart';
import '../theme/text_styles.dart';
import 'rm_button.dart';

PlaylistPlan editableAssignmentPlan(WidgetRef ref) {
  final plan = ref.read(effectivePlaylistPlanProvider);
  if (plan.hasDraft || ref.read(playlistPlanProvider.notifier).hasUserPlan) {
    return plan;
  }
  final catalog = ref.read(playlistCatalogProvider);
  return catalog.failed
      ? plan
      : playlistPlanFromCatalog(
          catalog,
          ref.read(playlistProvider).pool,
          projectDir: ref.read(studioProvider).projectDir,
          includeBuiltinTargets: false,
        );
}

int assignmentLimit(WidgetRef ref, RadioStation radio, String type) {
  if (ref.read(editorOptionsProvider).expansionEnabled) return 4096;
  final original =
      ref
          .read(baselinePlaylistCatalogProvider)
          ?.tracksOfRadio(radio.code, type)
          .length ??
      0;
  return original > 0 ? original : radio.slot;
}

Future<bool> showQuickAssign(BuildContext context, PoolTrack track) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => QuickAssignDialog(track: track),
    ) ??
    false;

class QuickAssignDialog extends ConsumerStatefulWidget {
  const QuickAssignDialog({super.key, required this.track});
  final PoolTrack track;
  @override
  ConsumerState<QuickAssignDialog> createState() => _QuickAssignDialogState();
}

class _QuickAssignDialogState extends ConsumerState<QuickAssignDialog> {
  final focus = FocusNode();
  late final project = ref.read(studioProvider).projectDir;
  String? error;
  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  void assign(RadioStation radio, String type) {
    if (ref.read(studioProvider).projectDir != project ||
        ref.read(studioProvider).projectEditingLocked) {
      setState(() => error = '项目状态已变化，请关闭后重试。');
      return;
    }
    final ok = ref
        .read(playlistProvider.notifier)
        .assignManyToRadio(
          [widget.track.id],
          radio.code,
          type,
          maxSlots: assignmentLimit(ref, radio, type),
        );
    if (!ok) {
      setState(() => error = '${radio.code} 已满或歌曲状态已变化，请选择其他电台。');
      return;
    }
    Navigator.pop(context, true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已分配到 ${radio.code}；可在播放列表保存或撤销。')));
  }

  @override
  Widget build(BuildContext context) {
    final rm = context.rm;
    final catalog = ref.watch(playlistCatalogProvider);
    ref.watch(effectivePlaylistPlanProvider);
    final state = ref.watch(playlistProvider);
    final type = state.mode == PlaylistMode.event ? 'Event' : 'FreeRoam';
    final plan = editableAssignmentPlan(ref);
    final radios =
        catalog.radios
            .where(
              (r) =>
                  RegExp(r'^R[1-9]$').hasMatch(r.code) &&
                  isUiSupportedRadio(name: r.name),
            )
            .toList()
          ..sort((a, b) => a.code.compareTo(b.code));
    return Focus(
      focusNode: focus,
      autofocus: true,
      onKeyEvent: (_, e) {
        if (e is! KeyDownEvent ||
            HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isAltPressed ||
            HardwareKeyboard.instance.isShiftPressed ||
            HardwareKeyboard.instance.isMetaPressed) {
          return KeyEventResult.ignored;
        }
        final digits = [
          LogicalKeyboardKey.digit1,
          LogicalKeyboardKey.digit2,
          LogicalKeyboardKey.digit3,
          LogicalKeyboardKey.digit4,
          LogicalKeyboardKey.digit5,
          LogicalKeyboardKey.digit6,
          LogicalKeyboardKey.digit7,
          LogicalKeyboardKey.digit8,
          LogicalKeyboardKey.digit9,
        ];
        final pads = [
          LogicalKeyboardKey.numpad1,
          LogicalKeyboardKey.numpad2,
          LogicalKeyboardKey.numpad3,
          LogicalKeyboardKey.numpad4,
          LogicalKeyboardKey.numpad5,
          LogicalKeyboardKey.numpad6,
          LogicalKeyboardKey.numpad7,
          LogicalKeyboardKey.numpad8,
          LogicalKeyboardKey.numpad9,
        ];
        var n = digits.indexOf(e.logicalKey);
        if (n < 0) n = pads.indexOf(e.logicalKey);
        final matches = radios.where((r) => r.code == 'R${n + 1}');
        if (n >= 0 && matches.isNotEmpty) {
          assign(matches.first, type);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AlertDialog(
        backgroundColor: rm.panel,
        title: Text('分配至电台', style: RmText.modalH2(color: rm.fg)),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.track.title,
                  style: RmText.sans(13, weight: FontWeight.w600, color: rm.fg),
                ),
                const SizedBox(height: 6),
                Text(
                  '按 1–9 立即选择电台，支持数字小键盘；Esc 取消。分配到播放列表草稿，重复歌曲不再追加。首次分配将电台切换为自建。',
                  style: RmText.sans(11.5, color: rm.fg3),
                ),
                if (!(state.pool
                            .where((t) => t.id == widget.track.id)
                            .firstOrNull ??
                        widget.track)
                    .configured)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '此曲节点未完成，可以先分配；完成并保存后才能构建。',
                      style: RmText.sans(11.5, color: rm.warn),
                    ),
                  ),
                const SizedBox(height: 12),
                if (catalog.failed)
                  Text(
                    '电台信息不可用，请先在概览刷新项目。',
                    style: RmText.sans(12, color: rm.warn),
                  ),
                for (final radio in radios)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: RmButton(
                      key: ValueKey('quick-assign-${radio.code}'),
                      onPressed: () => assign(radio, type),
                      label:
                          '${radio.code.substring(1)} · ${radio.name}  ${plan.assignmentsForRadio(radio.code, type).length} / ${assignmentLimit(ref, radio, type) == 4096 ? '扩容' : assignmentLimit(ref, radio, type)}',
                      tooltip: '选择 ${radio.code}',
                    ),
                  ),
                if (error != null)
                  Text(error!, style: RmText.sans(12, color: rm.danger)),
              ],
            ),
          ),
        ),
        actions: [
          RmButton(label: '取消', onPressed: () => Navigator.pop(context, false)),
        ],
      ),
    );
  }
}
