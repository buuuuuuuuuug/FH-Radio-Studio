import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:fh_radio_studio/core/playlist_plan.dart';
import 'package:fh_radio_studio/core/project_refs.dart';
import 'package:fh_radio_studio/domain/radio_library.dart';
import 'package:fh_radio_studio/screens/playlist/playlist_state.dart';

void main() {
  test(
    'durable-key station lookup matches the old scan after reorder and pool removal',
    () {
      final pool = [
        for (var i = 0; i < 1200; i++)
          PoolTrack(
            id: 'p$i',
            title: 'Song $i',
            artist: 'Test',
            source: 'D:/lookup/sources/song$i.wav',
            durationSec: 180,
            bpm: 120,
            key: '',
            configured: true,
            confirmed: 4,
            added: '',
          ),
      ];
      final assignments = <String, PlaylistAssignment>{};
      for (var i = 0; i < pool.length; i++) {
        final item = PlaylistAssignment(
          trackKey: trackKeyForProjectPath('D:/lookup', pool[i].source)!,
          source: pool[i].source,
          radioCode: 'R${i % 9 + 1}',
          playlistType: 'FreeRoam',
          slot: i ~/ 9 + 1,
        );
        assignments[item.assignmentKey] = item;
      }
      final state = PlaylistState(
        pool: pool,
        mode: PlaylistMode.freeroam,
        search: '',
        splitPlaylistTypes: false,
      );
      final plan = PlaylistPlan(assignments: assignments);
      final oldResults = <List<PoolTrack>>[];
      final old = Stopwatch()..start();
      for (var r = 1; r <= 9; r++) {
        final index = {
          for (final t in pool) PlaylistAssignment.keyForPath(t.source): t,
        };
        oldResults.add([
          for (final a in plan.assignmentsForRadio('R$r', 'FreeRoam'))
            (index[a.trackKey] ??
                    pool.firstWhere(
                      (t) =>
                          PlaylistAssignment.keyForPath(t.source) ==
                          PlaylistAssignment.keyForPath(a.source),
                    ))
                .copyWith(assignedTo: a.radioCode, slot: a.slot),
        ]);
      }
      old.stop();
      final fast = Stopwatch()..start();
      for (var r = 1; r <= 9; r++) {
        final actual = state.tracksOfRadio('R$r', 'FreeRoam', plan);
        expect(actual.map((t) => t.id), oldResults[r - 1].map((t) => t.id));
        expect(actual.map((t) => t.slot), oldResults[r - 1].map((t) => t.slot));
      }
      fast.stop();
      var changed = plan.moveBefore(
        source: pool[0].source,
        beforeSource: '',
        radioCode: 'R1',
        playlistType: 'FreeRoam',
      );
      expect(state.tracksOfRadio('R1', 'FreeRoam', changed).last.id, 'p0');
      changed = changed.unassign(pool[0].source, projectDir: 'D:/lookup');
      expect(
        state.tracksOfRadio('R1', 'FreeRoam', changed).any((t) => t.id == 'p0'),
        isFalse,
      );
      debugPrint(
        '1200 songs / 9 station lookups: previous ${old.elapsedMilliseconds}ms, indexed ${fast.elapsedMilliseconds}ms',
      );
    },
  );
}
