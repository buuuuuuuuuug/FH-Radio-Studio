import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fh_radio_studio/core/playlist_plan.dart';
import 'package:fh_radio_studio/state/app_state.dart';
import 'package:fh_radio_studio/state/playlist_plan_state.dart';
import 'package:fh_radio_studio/state/studio_state.dart';
import 'package:fh_radio_studio/state/unsaved_edits.dart';

import 'editor_playlist_upgrade_test.dart' as fixture;

class _SeededStudio extends StudioController {
  _SeededStudio(super.prefs, PackageArtifactSummary package) {
    state = state.copyWith(lastPackageSummary: package);
  }
}

void main() {
  test(
    'clearing an inherited package remains an unsaved intent through history and persistence',
    () async {
      final f = await fixture.fixture();
      final source = '${f.dir.path}/sources/song.wav';
      final prefs = f.container.read(sharedPreferencesProvider);
      final studio = _SeededStudio(
        prefs,
        PackageArtifactSummary(
          radio: 4,
          station: 'Horizon XS',
          bankName: 'R4_Tracks_CU1.assets.bank',
          musicCount: 1,
          bankSlots: 3,
          playlistMode: 'only',
          skipBank: true,
          runtimeVerified: false,
          sourceLang: 'CN',
          targetLang: 'EN',
          previewTracks: const ['Song'],
          assignments: [
            PackageTrackAssignment(source: source, radioLabel: 'R4', slot: 1),
          ],
        ),
      );
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          studioProvider.overrideWith((ref) => studio),
        ],
      );
      addTearDown(c.dispose);
      final history = c.read(playlistPlanProvider.notifier);
      expect(history.hasUserPlan, isFalse);
      expect(history.dirty, isFalse);
      expect(
        c.read(effectivePlaylistPlanProvider).assignmentsForPath(source),
        isNotEmpty,
      );

      history.unassign(source);
      expect(c.read(effectivePlaylistPlanProvider).assignments, isEmpty);
      expect(history.hasUserPlan, isTrue);
      expect(history.dirty, isTrue);
      expect(c.read(unsavedEditsProvider).isDirty, isTrue);
      history.undo();
      expect(history.hasUserPlan, isFalse);
      expect(history.dirty, isFalse);
      expect(
        c.read(effectivePlaylistPlanProvider).assignmentsForPath(source),
        isNotEmpty,
      );
      history.redo();
      expect(history.dirty, isTrue);
      expect(c.read(effectivePlaylistPlanProvider).assignments, isEmpty);

      history.discard();
      expect(history.hasUserPlan, isFalse);
      expect(history.dirty, isFalse);
      expect(
        c.read(effectivePlaylistPlanProvider).assignmentsForPath(source),
        isNotEmpty,
      );

      history.unassign(source);
      history.save();
      expect(history.dirty, isFalse);
      expect(
        File(PlaylistPlanStore.configPath(f.dir.path)).existsSync(),
        isTrue,
      );
      history.reload();
      expect(history.hasUserPlan, isTrue);
      expect(history.dirty, isFalse);
      expect(c.read(effectivePlaylistPlanProvider).assignments, isEmpty);
      history.discard();
      expect(history.hasUserPlan, isTrue);
      expect(c.read(effectivePlaylistPlanProvider).assignments, isEmpty);
    },
  );
}
