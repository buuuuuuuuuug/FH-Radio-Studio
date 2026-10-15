import 'package:flutter_test/flutter_test.dart';
import 'package:fh_radio_studio/core/playlist_plan.dart';
import 'package:fh_radio_studio/domain/radio_library.dart';
import 'package:fh_radio_studio/screens/playlist/playlist_state.dart';
import 'package:fh_radio_studio/state/playlist_catalog_state.dart';
import 'package:fh_radio_studio/state/playlist_plan_state.dart';
import 'editor_playlist_upgrade_test.dart' as helpers;

void main() {
  test('failed cross-scenario assignments leave the draft unchanged', () async {
    final f = await helpers.fixture();
    final c = f.container;
    final notifier = c.read(playlistProvider.notifier);
    notifier.setSplitPlaylistTypes(true);
    final track = c.read(playlistProvider).pool.first;
    final plan = const PlaylistPlan.empty().assign(
      source: '${f.dir.path}/sources/other.wav',
      radioCode: 'R1',
      playlistType: 'Event',
      slot: 1,
    );
    c.read(playlistPlanProvider.notifier).replaceWith(plan);
    final before = c.read(playlistPlanProvider).encodeForCli();
    expect(
      notifier.assignToRadio(track.id, 'R1', 'FreeRoam', maxSlots: 1),
      isFalse,
    );
    expect(c.read(playlistPlanProvider).encodeForCli(), before);
    expect(
      notifier.assignManyToRadio([track.id], 'R1', 'FreeRoam', maxSlots: 1),
      isFalse,
    );
    expect(c.read(playlistPlanProvider).encodeForCli(), before);
  });

  test(
    'the same source in both scenarios consumes one physical slot',
    () async {
      final f = await helpers.fixture();
      final c = f.container;
      final notifier = c.read(playlistProvider.notifier);
      notifier.setSplitPlaylistTypes(true);
      final track = c.read(playlistProvider).pool.first;
      c
          .read(playlistPlanProvider.notifier)
          .replaceWith(
            const PlaylistPlan.empty().assign(
              source: track.source,
              radioCode: 'R1',
              playlistType: 'Event',
              slot: 1,
            ),
          );
      expect(
        notifier.assignToRadio(track.id, 'R1', 'FreeRoam', maxSlots: 1),
        isTrue,
      );
      expect(c.read(playlistPlanProvider).sourcesForRadio('R1'), hasLength(1));
      expect(
        c.read(playlistPlanProvider).assignmentsForRadio('R1', 'FreeRoam'),
        hasLength(1),
      );
      expect(
        c.read(playlistPlanProvider).assignmentsForRadio('R1', 'Event'),
        hasLength(1),
      );
    },
  );

  test(
    'matching title and artist cannot replace a missing source identity',
    () {
      const catalog = PlaylistCatalog(
        origin: PlaylistCatalogOrigin.game,
        sourcePath: null,
        radios: [
          RadioStation(
            code: 'R1',
            name: 'Radio',
            hue: 'cyan',
            genre: '',
            slot: 1,
          ),
        ],
        modes: {'R1': StationMode.custom},
        freeRoamTracks: {
          'R1': [
            TrackRef(
              id: 'unknown',
              title: 'Same',
              artist: 'Same',
              durationSec: 10,
              modded: true,
            ),
          ],
        },
        eventTracks: {},
      );
      const tracks = [
        PoolTrack(
          id: 'decoy',
          title: 'Same',
          artist: 'Same',
          source: 'C:/music/wrong.wav',
          durationSec: 10,
          bpm: 0,
          key: '',
          configured: true,
          confirmed: 4,
          added: '',
        ),
      ];
      expect(playlistPlanFromCatalog(catalog, tracks).assignments, isEmpty);
    },
  );
}
