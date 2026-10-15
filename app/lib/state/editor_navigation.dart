import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'studio_state.dart';
import 'custom_pool_tracks.dart';
import 'unsaved_edits.dart';
import 'router.dart';

class EditorSongQueue {
  const EditorSongQueue({this.projectDir = '', this.ids = const []});
  final String projectDir;
  final List<String> ids;
}

class EditorSongQueueController extends StateNotifier<EditorSongQueue> {
  EditorSongQueueController() : super(const EditorSongQueue());
  bool navigating = false;
  void begin(String projectDir, Iterable<String> ids) {
    state = EditorSongQueue(
      projectDir: projectDir,
      ids: List.unmodifiable(ids.toSet()),
    );
  }
}

final editorSongQueueProvider =
    StateNotifierProvider<EditorSongQueueController, EditorSongQueue>(
      (ref) => EditorSongQueueController(),
    );

List<String> editorSongIds(Ref ref, String currentId) {
  final project = ref.read(studioProvider).projectDir;
  final available = ref.read(realPoolTracksProvider).map((t) => t.id).toList();
  final queue = ref.read(editorSongQueueProvider);
  if (queue.projectDir == project && queue.ids.contains(currentId)) {
    final live = available.toSet();
    return queue.ids.where(live.contains).toList();
  }
  return available;
}

Future<void> openAdjacentEditorSong(
  BuildContext context, {
  required String trackId,
  required int step,
  required bool returnToPlaylist,
}) async {
  final container = ProviderScope.containerOf(context);
  final controller = container.read(editorSongQueueProvider.notifier);
  if (controller.navigating) return;
  final queue = container.read(editorSongQueueProvider);
  final available = container
      .read(realPoolTracksProvider)
      .map((t) => t.id)
      .toList();
  final ids =
      queue.projectDir == container.read(studioProvider).projectDir &&
          queue.ids.contains(trackId)
      ? queue.ids.where(available.contains).toList()
      : available;
  final index = ids.indexOf(trackId);
  if (index < 0 || ids.length < 2) return;
  final target = (index + step) % ids.length;
  controller.navigating = true;
  try {
    final projectBefore = container.read(studioProvider).projectDir;
    final allowed = await container
        .read(unsavedEditsProvider)
        .confirm(context, key: 'editor', switching: true);
    if (!allowed || !context.mounted) return;
    if (container.read(studioProvider).projectDir != projectBefore ||
        !container
            .read(realPoolTracksProvider)
            .any((t) => t.id == ids[target])) {
      return;
    }
    unawaitedEditorReplace(context, ids[target], returnToPlaylist);
  } finally {
    controller.navigating = false;
  }
}

void unawaitedEditorReplace(
  BuildContext context,
  String id,
  bool fromPlaylist,
) {
  context.replace(RmRoutes.editor(id, fromPlaylist: fromPlaylist));
}
