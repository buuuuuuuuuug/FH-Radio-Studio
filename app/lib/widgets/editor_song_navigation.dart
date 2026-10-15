import '../state/editor_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/editor_navigation.dart';
import '../state/custom_pool_tracks.dart';
import '../state/studio_state.dart';
import '../theme/app_theme.dart';
import '../theme/text_styles.dart';
import 'rm_button.dart';
import 'rm_icon.dart';

class EditorSongNavigation extends ConsumerWidget {
  const EditorSongNavigation({
    super.key,
    required this.trackId,
    required this.returnToPlaylist,
  });
  final String trackId;
  final bool returnToPlaylist;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(editorSongQueueProvider);
    final shortcuts = ref.watch(editorShortcutsProvider);
    final all = ref.watch(realPoolTracksProvider).map((t) => t.id).toList();
    final project = ref.watch(studioProvider.select((s) => s.projectDir));
    final ids = queue.projectDir == project && queue.ids.contains(trackId)
        ? queue.ids.where(all.contains).toList()
        : all;
    final index = ids.indexOf(trackId);
    void move(int step) => openAdjacentEditorSong(
      context,
      trackId: trackId,
      step: step,
      returnToPlaylist: returnToPlaylist,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RmButton(
          key: const ValueKey('editor-previous-song'),
          size: RmButtonSize.sm,
          label: '上一首',
          leading: const Icon(Icons.chevron_left, size: 13),
          tooltip: '上一首 · ${shortcuts[EditorAction.previous]!.label}（循环切换）',
          onPressed: index >= 0 && ids.length > 1 ? () => move(-1) : null,
        ),
        const SizedBox(width: 8),
        Text(
          '${index < 0 ? 0 : index + 1} / ${ids.length}',
          style: RmText.mono(10.5, color: context.rm.fg3),
        ),
        const SizedBox(width: 8),
        RmButton(
          key: const ValueKey('editor-next-song'),
          size: RmButtonSize.sm,
          label: '下一首',
          trailing: const RmIcon('arrow-right', size: 11),
          tooltip: '下一首 · ${shortcuts[EditorAction.next]!.label}（循环切换）',
          onPressed: index >= 0 && ids.length > 1 ? () => move(1) : null,
        ),
      ],
    );
  }
}
