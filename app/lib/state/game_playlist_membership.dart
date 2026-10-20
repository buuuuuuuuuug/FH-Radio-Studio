import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/fh_radio_studio_cli.dart';
import '../core/playlist_plan.dart';
import 'playlist_catalog_state.dart';
import 'studio_state.dart';

class GamePlaylistMembership {
  const GamePlaylistMembership(this.plan, {this.uncertainSources = const {}});
  final PlaylistPlan plan;
  final Set<String> uncertainSources;
}

typedef PlaylistMembershipRunner =
    Future<CliRunResult> Function(String root, List<String> args);

final playlistMembershipRunnerProvider = Provider<PlaylistMembershipRunner>(
  (ref) =>
      (root, args) => FhRadioStudioCli(repoRoot: root).runBase(args),
);

// A draft only contains changed stations. Game membership must include unchanged
// builtin stations too, and must never come from the current editable draft.
final gamePlaylistMembershipProvider = FutureProvider<GamePlaylistMembership>((
  ref,
) async {
  final catalog = ref.watch(gamePlaylistCatalogProvider);
  final state = ref.watch(
    studioProvider.select(
      (s) => (
        project: s.projectDir,
        root: s.repoRoot,
        inputs: s.musicPaths,
        revision: s.projectPathMigrationRevision,
      ),
    ),
  );
  final runner = ref.watch(playlistMembershipRunnerProvider);
  if (catalog.failed || catalog.sourcePath == null) {
    throw StateError('无法读取游戏内 RadioInfo');
  }
  final result = await runner(state.root, [
    'playlist-membership',
    '--project-dir',
    state.project,
    '--radio-info',
    catalog.sourcePath!,
  ]);
  if (!result.ok) throw StateError(result.stderr.trim());
  final payload = jsonDecode(result.stdout) as Map<String, dynamic>;
  return GamePlaylistMembership(
    PlaylistPlanCodec.fromDecoded(payload, projectDir: state.project),
    uncertainSources: {
      for (final source in (payload['uncertain_sources'] as List? ?? const []))
        PlaylistAssignment.keyForPath('$source'),
    },
  );
});
