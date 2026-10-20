import 'package:fh_radio_studio/core/playlist_capacity.dart';
import 'package:fh_radio_studio/state/playlist_capacity.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fh_radio_studio/core/project_workspace.dart';
import 'package:fh_radio_studio/core/song_selection.dart';
import 'package:fh_radio_studio/core/loop_audition_session.dart';
import 'package:fh_radio_studio/domain/radio_library.dart';
import 'package:fh_radio_studio/state/app_state.dart';
import 'package:fh_radio_studio/state/audition_preferences.dart';
import 'package:fh_radio_studio/state/editor_navigation.dart';
import 'package:fh_radio_studio/state/custom_pool_tracks.dart';
import 'package:fh_radio_studio/state/studio_state.dart';
import 'package:fh_radio_studio/state/playlist_plan_state.dart';
import 'package:fh_radio_studio/state/playlist_catalog_state.dart';
import 'package:fh_radio_studio/state/unsaved_edits.dart';
import 'package:fh_radio_studio/screens/playlist/playlist_state.dart';
import 'package:fh_radio_studio/screens/playlist/track_card.dart';
import 'package:fh_radio_studio/screens/replace_editor/replace_editor.dart';
import 'package:fh_radio_studio/widgets/rm_button.dart';
import 'package:fh_radio_studio/widgets/audition_settings_button.dart';
import 'package:fh_radio_studio/theme/app_theme.dart';
import 'package:fh_radio_studio/theme/accents.dart';
import 'playlist_double_edit_test.dart' as routing;

Future<ProviderContainer> fixture({
  Map<String, Map<String, int>>? capacityLimits,
}) async {
  final dir = Directory.systemTemp.createTempSync('studio-v18-');
  addTearDown(() => dir.deleteSync(recursive: true));
  FhRadioStudioProject.ensure(dir.path);
  final baseline = File(
    '${dir.path}/backups/baseline-current/baseline_manifest.json',
  );
  baseline.parent.createSync(recursive: true);
  baseline.writeAsStringSync(
    '{"kind":"game_baseline","state":"current","files":[]}',
  );
  SharedPreferences.setMockInitialValues({'rm.studio.projectDir': dir.path});
  final prefs = await SharedPreferences.getInstance();
  final catalog = PlaylistCatalog(
    origin: PlaylistCatalogOrigin.package,
    sourcePath: 'fixture',
    radios: kRadios,
    modes: const {},
    freeRoamTracks: const {},
    eventTracks: const {},
  );
  final container = ProviderContainer(
    overrides: [
      if (capacityLimits != null)
        playlistCapacityPolicyProvider.overrideWithValue(
          PlaylistCapacityPolicy(capacityLimits),
        ),
      sharedPreferencesProvider.overrideWithValue(prefs),
      studioProvider.overrideWith((ref) => _FixtureController(prefs)),
      realPoolTracksProvider.overrideWithValue(kCustomPool),
      playlistCatalogProvider.overrideWithValue(catalog),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

class _FixtureController extends StudioController {
  _FixtureController(super.prefs);
  @override
  Future<void> refreshStatus({bool verifyFiles = false}) async {}
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  test(
    'batch allocation is atomic, skips duplicates, and undo/redo restores both scenes',
    () async {
      final c = await fixture();
      final songs = c.read(playlistProvider.notifier);
      final history = c.read(playlistPlanProvider.notifier);
      final ids = kCustomPool.take(3).map((t) => t.id).toList();
      expect(
        songs.assignManyToRadio(ids, 'R1', 'FreeRoam', maxSlots: 2),
        isFalse,
      );
      expect(c.read(effectivePlaylistPlanProvider).assignments, isEmpty);
      expect(history.canUndo, isFalse);
      expect(
        songs.assignManyToRadio(
          ids.take(2).toList(),
          'R1',
          'FreeRoam',
          maxSlots: 2,
        ),
        isTrue,
      );
      final complete = c.read(effectivePlaylistPlanProvider).encodeForCli();
      expect(
        c
            .read(effectivePlaylistPlanProvider)
            .assignmentsForRadio('R1', 'Event')
            .length,
        2,
      );
      history.undo();
      expect(c.read(effectivePlaylistPlanProvider).assignments, isEmpty);
      expect(
        c
            .read(playlistProvider)
            .poolForDisplay(c.read(effectivePlaylistPlanProvider))
            .where((t) => t.assignedTo != null),
        isEmpty,
      );
      expect(history.canUndo, isFalse);
      expect(history.canRedo, isTrue);
      history.redo();
      expect(c.read(effectivePlaylistPlanProvider).encodeForCli(), complete);
      expect(
        songs.assignManyToRadio(
          ids.take(2).toList(),
          'R1',
          'FreeRoam',
          maxSlots: 2,
        ),
        isTrue,
      );
      expect(
        c
            .read(effectivePlaylistPlanProvider)
            .assignmentsForRadio('R1', 'FreeRoam')
            .length,
        2,
      );
      history.undo();
      expect(c.read(effectivePlaylistPlanProvider).assignments, isEmpty);
    },
  );
  test(
    'saved baseline, reorder and move-back each have a single reversible action',
    () async {
      final c = await fixture();
      final songs = c.read(playlistProvider.notifier);
      final history = c.read(playlistPlanProvider.notifier);
      songs.assignManyToRadio(
        kCustomPool.take(2).map((t) => t.id).toList(),
        'R1',
        'FreeRoam',
        maxSlots: 3,
      );
      history.save();
      expect(history.dirty, isFalse);
      songs.reorder(
        kCustomPool[1].source,
        kCustomPool[0].source,
        'R1',
        'FreeRoam',
      );
      expect(
        c
            .read(effectivePlaylistPlanProvider)
            .assignmentsForRadio('R1', 'FreeRoam')
            .first
            .source,
        kCustomPool[1].source,
      );
      history.undo();
      expect(history.dirty, isFalse);
      history.redo();
      songs.unassign(
        kCustomPool[0].id,
        radioCode: 'R1',
        playlistType: 'FreeRoam',
      );
      expect(
        c
            .read(effectivePlaylistPlanProvider)
            .assignmentsForRadio('R1', 'Event')
            .length,
        1,
      );
      history.undo();
      expect(
        c
            .read(effectivePlaylistPlanProvider)
            .assignmentsForRadio('R1', 'Event')
            .length,
        2,
      );
      expect(
        c
            .read(effectivePlaylistPlanProvider)
            .assignmentsForRadio('R1', 'Event')
            .first
            .source,
        kCustomPool[1].source,
      );
      history.undo();
      expect(history.dirty, isFalse);
      expect(
        songs.assignToRadio(kCustomPool[2].id, 'R2', 'FreeRoam', maxSlots: 3),
        isTrue,
      );
      expect(history.canRedo, isFalse);
      history.discard();
      expect(history.canUndo, isFalse);
      expect(history.canRedo, isFalse);
    },
  );
  test(
    'restoring builtin and deleting a source cannot leave dangling undo references',
    () async {
      final c = await fixture();
      final songs = c.read(playlistProvider.notifier);
      final history = c.read(playlistPlanProvider.notifier);
      songs.assignManyToRadio(
        kCustomPool.take(2).map((t) => t.id).toList(),
        'R1',
        'FreeRoam',
        maxSlots: 3,
      );
      songs.restoreBuiltin('R1', 'FreeRoam');
      expect(
        c.read(effectivePlaylistPlanProvider).hasBuiltinOverride('R1', 'Event'),
        isTrue,
      );
      history.undo();
      expect(
        c
            .read(effectivePlaylistPlanProvider)
            .assignmentsForRadio('R1', 'Event')
            .length,
        2,
      );
      history.removeDeletedSource(kCustomPool.first.source);
      expect(history.canRedo, isFalse);
      expect(history.canUndo, isFalse);
      expect(
        c
            .read(effectivePlaylistPlanProvider)
            .assignmentForPath(kCustomPool.first.source),
        isNull,
      );
    },
  );
  test(
    'selection supports toggle and shift range in the displayed descending order',
    () {
      const order = ['d', 'c', 'b', 'a'];
      var selection = SongSelection().click('c', order);
      selection = selection.click('a', order, range: true);
      expect(selection.ids, {'c', 'b', 'a'});
      selection = selection.click('b', order);
      expect(selection.ids, {'c', 'a'});
      selection = selection.click('d', ['d', 'c'], range: true);
      expect(selection.ids.contains('d'), isTrue);
    },
  );
  test(
    'finite loop audition only plays before B and after A, and counts exact joins',
    () {
      final session = LoopAuditionSession(
        start: 20,
        end: 80,
        options: const AuditionPreferences(before: 3, after: 4, repetitions: 2),
      );
      expect(session.auditionStart, 77);
      expect(session.afterEnd, 24);
      expect(session.observe(77), AuditionEvent.none);
      expect(session.observe(79.8), AuditionEvent.none);
      expect(session.observe(20.1), AuditionEvent.joined);
      expect(session.observe(23.9), AuditionEvent.none);
      expect(session.observe(24), AuditionEvent.repeat);
      expect(session.completeCycle(), AuditionEvent.none);
      session.restart();
      session.observe(77);
      session.observe(79.8);
      session.observe(20.1);
      expect(session.observe(24), AuditionEvent.finished);
      expect(session.completed, 2);
    },
  );
  test(
    'continuous audition is bounded to short loops and settings survive reload',
    () async {
      final s = LoopAuditionSession(
        start: 10,
        end: 11,
        options: const AuditionPreferences(before: 4, after: 5, repetitions: 0),
      );
      expect(s.auditionStart, 10);
      expect(s.afterEnd, 11);
      for (var i = 0; i < 12; i++) {
        s.join();
        expect(s.completeCycle(), AuditionEvent.repeat);
        s.restart();
      }
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      c
          .read(auditionPreferencesProvider.notifier)
          .update(before: 6, after: 3, repetitions: 5, volume: 45);
      c.dispose();
      final c2 = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(c2.dispose);
      final options = c2.read(auditionPreferencesProvider);
      expect(options.before, 6);
      expect(options.after, 3);
      expect(options.repetitions, 5);
      expect(options.volume, 45);
    },
  );
  testWidgets(
    'continuous editor navigation respects ordered queue, unsaved cancel and return origin',
    (tester) async {
      final f = await routing.setupPlaylist(tester);
      final pool = find.descendant(
        of: find.byKey(const ValueKey('playlist-pool-side-panel')),
        matching: find.byType(TrackCard),
      );
      final titles = pool
          .evaluate()
          .map((e) => (e.widget as TrackCard).title)
          .toList();
      final ids = titles
          .map((title) => kCustomPool.firstWhere((t) => t.title == title).id)
          .toList();
      await routing.doubleClick(tester, pool.first);
      await tester.pumpAndSettle();
      expect(f.container.read(editorSongQueueProvider).ids, ids);
      var dirty = true;
      f.container.read(unsavedEditsProvider).entries['editor'] = PendingEdit(
        label: '未保存歌曲',
        dirty: () => dirty,
        save: () => dirty = false,
        discard: () => dirty = false,
      );
      await tester.tap(find.byKey(const ValueKey('editor-next-song')));
      await tester.pumpAndSettle();
      expect(find.text('切换歌曲前保存修改？'), findsOneWidget);
      await tester.tap(find.text('取消切换'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ReplaceEditorScreen>(find.byType(ReplaceEditorScreen))
            .trackId,
        ids[0],
      );
      await tester.tap(find.byKey(const ValueKey('editor-next-song')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('放弃更改'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ReplaceEditorScreen>(find.byType(ReplaceEditorScreen))
            .trackId,
        ids[1],
      );
      await tester.tap(find.byKey(const ValueKey('editor-previous-song')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ReplaceEditorScreen>(find.byType(ReplaceEditorScreen))
            .trackId,
        ids[0],
      );
      expect(
        tester
            .widget<RmButton>(
              find.byKey(const ValueKey('editor-previous-song')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('playlist-pool-side-panel')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('pool supports control selection, shift range and batch dialog', (
    tester,
  ) async {
    final f = await routing.setupPlaylist(tester);
    final pool = find.descendant(
      of: find.byKey(const ValueKey('playlist-pool-side-panel')),
      matching: find.byType(TrackCard),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(pool.at(0));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(pool.at(2));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(find.text('已选 3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('playlist-batch-assign')));
    await tester.pumpAndSettle();
    expect(find.text('分配 3 首歌曲'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(f.container.read(effectivePlaylistPlanProvider), f.plan);
    tester.view.physicalSize = const Size(1000, 700);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'audition settings fit narrow windows and persist changed volume',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      tester.view.physicalSize = const Size(520, 680);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            theme: buildAppTheme(
              brightness: Brightness.light,
              accent: AppAccent.lime,
            ),
            home: const Scaffold(body: AuditionSettingsButton()),
          ),
        ),
      );
      await tester.tap(find.text('试听设置'));
      await tester.pumpAndSettle();
      expect(find.text('循环试听设置'), findsOneWidget);
      final slider = find.byType(Slider).last;
      await tester.tapAt(tester.getCenter(slider));
      await tester.pumpAndSettle();
      expect(prefs.getDouble('rm.audition.volume'), lessThan(100));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
    },
  );
}
