import 'package:fh_radio_studio/screens/playlist/radio_column.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fh_radio_studio/core/fh_radio_studio_cli.dart';
import 'package:fh_radio_studio/core/playlist_plan.dart';
import 'package:fh_radio_studio/domain/radio_library.dart';
import 'package:fh_radio_studio/screens/playlist/track_card.dart';
import 'package:fh_radio_studio/state/app_state.dart';
import 'package:fh_radio_studio/state/game_playlist_membership.dart';
import 'package:fh_radio_studio/state/playlist_catalog_state.dart';
import 'package:fh_radio_studio/state/studio_state.dart';
import 'package:fh_radio_studio/theme/app_theme.dart';
import 'package:fh_radio_studio/theme/accents.dart';
import 'playlist_double_edit_test.dart' show doubleClick;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  testWidgets('locked cards cannot edit even if a caller provides a callback', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(
          brightness: Brightness.light,
          accent: AppAccent.lime,
        ),
        home: Scaffold(
          body: TrackCard.fromPoolTrack(
            kCustomPool.first,
            locked: true,
            onOpenEditor: () => opened++,
          ),
        ),
      ),
    );
    final card = find.byType(TrackCard);
    await doubleClick(tester, card);
    expect(opened, 0);
    expect(find.byTooltip('双击进入编辑；拖动可调整排序'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test(
    'membership loads all game lists independently of builtin mode and draft',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var calls = 0;
      final catalog = PlaylistCatalog(
        origin: PlaylistCatalogOrigin.game,
        sourcePath: 'game/RadioInfo_CN.xml',
        radios: kRadios,
        modes: const {},
        freeRoamTracks: const {},
        eventTracks: const {},
      );
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          studioProvider.overrideWith((ref) => _Studio(prefs)),
          gamePlaylistCatalogProvider.overrideWithValue(catalog),
          playlistMembershipRunnerProvider.overrideWithValue((
            root,
            args,
          ) async {
            calls++;
            expect(args, contains('playlist-membership'));
            expect(args.last, catalog.sourcePath);
            return CliRunResult(
              exitCode: 0,
              stdout: jsonEncode({
                'schema_version': 2,
                'assignments': [
                  {
                    'source': 'C:/music/source.wav',
                    'radio_code': 'R9',
                    'playlist_type': 'Event',
                    'slot': 39,
                  },
                ],
                'builtin_targets': [],
                'uncertain_sources': ['C:/music/duplicate.wav'],
              }),
              stderr: '',
              commandLine: 'fixture',
            );
          }),
        ],
      );
      addTearDown(c.dispose);
      final membership = await c.read(gamePlaylistMembershipProvider.future);
      expect(catalog.modeOf('R9'), StationMode.builtin);
      expect(
        membership.plan.assignmentForPath('C:/music/source.wav')?.slot,
        39,
      );
      expect(
        membership.uncertainSources,
        contains(PlaylistAssignment.keyForPath('C:/music/duplicate.wav')),
      );
      expect(calls, 1);
    },
  );
  test(
    'game expansion is based on distinct tracks shared across both scenes',
    () {
      PlaylistCatalog catalog(List<int> free, List<int> event) =>
          PlaylistCatalog(
            origin: PlaylistCatalogOrigin.game,
            sourcePath: 'fixture',
            radios: const [
              RadioStation(
                code: 'R9',
                name: 'Opus',
                hue: 'cyan',
                genre: 'R9',
                slot: 22,
              ),
            ],
            modes: const {},
            freeRoamTracks: {
              'R9': [
                for (final i in free)
                  TrackRef(
                    id: '$i',
                    title: 'Song $i',
                    artist: 'Artist',
                    durationSec: 10,
                    soundName: 'S$i',
                  ),
              ],
            },
            eventTracks: {
              'R9': [
                for (final i in event)
                  TrackRef(
                    id: '$i',
                    title: 'Song $i',
                    artist: 'Artist',
                    durationSec: 10,
                    soundName: 'S$i',
                  ),
              ],
            },
          );
      final original = List.generate(22, (i) => i);
      final baseline = catalog(original, original);
      expect(baseline.hasExpandedBank('R9', baseline), isFalse);
      expect(
        catalog(
          original,
          List.generate(39, (i) => i),
        ).hasExpandedBank('R9', baseline),
        isTrue,
      );
      expect(
        catalog(
          original,
          List.generate(22, (i) => i + 22),
        ).hasExpandedBank('R9', baseline),
        isTrue,
      );
      expect(catalog(original, original).hasExpandedBank('R9', null), isFalse);
    },
  );
  testWidgets('game expanded label shows actual count and original capacity', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(
          brightness: Brightness.light,
          accent: AppAccent.lime,
        ),
        home: Scaffold(
          body: SizedBox(
            width: 280,
            height: 480,
            child: PlaylistColumn.radio(
              radio: const RadioStation(
                code: 'R9',
                name: 'Opus',
                hue: 'cyan',
                genre: 'R9',
                slot: 22,
              ),
              isCustom: true,
              count: 39,
              capacity: 39,
              originalCount: 22,
              expanded: true,
              children: const [],
            ),
          ),
        ),
      ),
    );
    expect(find.text('39 首 · 原有 22 首 · 扩容'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _Studio extends StudioController {
  _Studio(super.prefs);
  @override
  Future<void> refreshStatus({bool verifyFiles = false}) async {}
}
