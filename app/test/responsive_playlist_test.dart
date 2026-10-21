import 'package:fh_radio_studio/state/custom_pool_tracks.dart';
import 'package:fh_radio_studio/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fh_radio_studio/core/playlist_plan.dart';
import 'package:fh_radio_studio/domain/radio_library.dart';
import 'package:fh_radio_studio/domain/replacement_models.dart';
import 'package:fh_radio_studio/screens/playlist.dart';
import 'package:fh_radio_studio/screens/playlist/playlist_state.dart';
import 'package:fh_radio_studio/screens/playlist/playlist_drag_preview.dart';
import 'package:fh_radio_studio/screens/playlist/track_card.dart';
import 'package:fh_radio_studio/screens/replace_editor/replace_editor.dart';
import 'package:fh_radio_studio/screens/replace_editor/replace_state.dart';
import 'package:fh_radio_studio/screens/replace_editor/progress_strip.dart';
import 'package:fh_radio_studio/state/playlist_plan_state.dart';
import 'package:fh_radio_studio/state/playlist_catalog_state.dart';
import 'package:fh_radio_studio/state/editor_shortcuts.dart';
import 'package:fh_radio_studio/widgets/layout_controls.dart';
import 'package:fh_radio_studio/widgets/song_browse_controls.dart';
import 'package:fh_radio_studio/widgets/rm_button.dart';
import 'editor_playlist_upgrade_test.dart' as editor;
import 'studio_v18_workflow_test.dart' as playlist;
import 'studio_v21_workflow_test.dart' as helpers;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  void viewport(WidgetTester t, Size size) {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = size;
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
  }

  test(
    'plan owns immutable inputs and cached indexes cannot be mutated by callers',
    () {
      final assignment = PlaylistAssignment(
        trackKey: 'song',
        source: 'C:/song.wav',
        radioCode: 'R1',
        playlistType: 'FreeRoam',
        slot: 1,
      );
      final input = {assignment.assignmentKey: assignment};
      final targets = <String>{'R2|Event'};
      final plan = PlaylistPlan(assignments: input, builtinTargets: targets);
      final encoded = plan.encodeForCli();
      input.clear();
      targets.clear();
      expect(plan.assignments, hasLength(1));
      expect(plan.builtinTargets, hasLength(1));
      plan.assignmentsForRadio('R1', 'FreeRoam').clear();
      expect(plan.assignmentsForRadio('R1', 'FreeRoam'), hasLength(1));
      expect(plan.encodeForCli(), encoded);
      expect(identical(plan.encodeForCli(), encoded), isTrue);
      expect(() => plan.assignments.clear(), throwsUnsupportedError);
      final moved = plan.moveBefore(
        source: assignment.source,
        beforeSource: '',
        radioCode: 'R1',
        playlistType: 'FreeRoam',
      );
      expect(moved.assignmentsForRadio('R1', 'FreeRoam').single.slot, 1);
    },
  );
  for (final width in [680.0, 900.0, 1200.0]) {
    testWidgets('song header fits $width and does not keep a click highlight', (
      t,
    ) async {
      viewport(t, Size(width, 1000));
      final f = await editor.fixture();
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: helpers.app(
            const ReplaceEditorScreen(trackId: 'p1', enableAudio: false),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('来源文件'), findsNothing);
      expect(find.text('导出此曲配置'), findsNothing);
      expect(find.byKey(const ValueKey('waveform-toggle-段落')), findsNothing);
      expect(find.text('双击人工精修'), findsOneWidget);
      final gradients = find.descendant(
        of: find.byType(ProgressStrip),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).gradient != null,
        ),
      );
      expect(gradients, findsNothing);
      final save = t.getRect(find.byKey(const ValueKey('editor-save')));
      final chip = t.getRect(
        find.byKey(const ValueKey('editor-assignment-status')),
      );
      expect(chip.overlaps(save), isFalse);
      expect(save.right, lessThanOrEqualTo(width));
      await t.tap(find.byKey(const ValueKey('editor-progress-PD')));
      await t.pump(const Duration(milliseconds: 350));
      await t.pumpAndSettle();
      expect(gradients, findsNothing);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('Ctrl S uses the same save as the song toolbar', (t) async {
    viewport(t, const Size(1365, 1000));
    final f = await editor.fixture();
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          f.container.read(sharedPreferencesProvider),
        ),
        realPoolTracksProvider.overrideWithValue([
          PoolTrack(
            id: 'p1',
            title: 'Song',
            artist: 'Test',
            source: '${f.dir.path}/sources/song.wav',
            durationSec: 180,
            bpm: 120,
            key: '',
            configured: false,
            confirmed: 0,
            added: 'today',
          ),
        ]),
      ],
    );
    addTearDown(c.dispose);
    final n = c.read(replaceEditorProvider('p1').notifier);
    for (final g in GroupKind.values) {
      n.setConfirmed(g, true);
    }
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: helpers.app(
          const ReplaceEditorScreen(trackId: 'p1', enableAudio: false),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(defaultEditorShortcuts()[EditorAction.save]!.label, 'Ctrl + S');
    await helpers.keyCombo(t, LogicalKeyboardKey.keyS, ctrl: true);
    await t.pumpAndSettle();
    expect(n.state.dirty, isFalse);
    expect(n.state.saved, isTrue);
    expect(find.textContaining('已保存配置：'), findsOneWidget);
  });
  testWidgets('width slider controls shrink to their contents', (t) async {
    viewport(t, const Size(1365, 900));
    final c = await playlist.fixture();
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: helpers.app(
          const Center(
            child: SizedBox(
              width: 210,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [PageWidthControl(), ManualRefineWidthControl()],
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(
      t.getSize(find.byType(PageWidthControl)).height,
      lessThanOrEqualTo(65),
    );
    expect(
      t.getSize(find.byType(ManualRefineWidthControl)).height,
      lessThanOrEqualTo(65),
    );
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'playlist keys preserve text undo, exit selection and undo redo save a draft',
    (t) async {
      viewport(t, const Size(1800, 1100));
      final c = await playlist.fixture();
      final ctl = c.read(playlistProvider.notifier);
      ctl.assignManyToRadio(
        kCustomPool.take(3).map((t) => t.id).toList(),
        'R1',
        'FreeRoam',
        maxSlots: 10,
      );
      final before = c.read(playlistPlanProvider).encodeForCli();
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: helpers.app(const PlaylistScreen()),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('radio-multiselect-R1')), findsNothing);
      final toggle = find.byKey(const ValueKey('playlist-multiselect-toggle'));
      expect(
        t.getTopLeft(toggle).dy,
        greaterThan(t.getBottomLeft(find.byType(SongBrowseControls)).dy),
      );
      await t.tap(toggle);
      await t.pump();
      expect(find.text('退出多选'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      expect(find.text('退出多选'), findsNothing);
      await helpers.keyCombo(t, LogicalKeyboardKey.keyZ, ctrl: true);
      await t.pump();
      expect(c.read(playlistPlanProvider).assignments, isEmpty);
      await helpers.keyCombo(t, LogicalKeyboardKey.keyY, ctrl: true);
      await t.pump();
      expect(c.read(playlistPlanProvider).encodeForCli(), before);
      // Empty plan can be saved in this fixture without external source files.
      await helpers.keyCombo(t, LogicalKeyboardKey.keyZ, ctrl: true);
      await t.pump();
      await helpers.keyCombo(t, LogicalKeyboardKey.keyS, ctrl: true);
      await t.pump();
      expect(c.read(playlistPlanProvider.notifier).dirty, isFalse);
      expect(find.text('歌曲分配与顺序已保存。'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'copying game layout needs confirmation and cancel preserves draft',
    (t) async {
      viewport(t, const Size(1800, 1100));
      final base = await playlist.fixture();
      final c = ProviderContainer(
        parent: base,
        overrides: [
          gamePlaylistCatalogProvider.overrideWithValue(
            base.read(playlistCatalogProvider),
          ),
        ],
      );
      addTearDown(c.dispose);
      c
          .read(playlistProvider.notifier)
          .assignManyToRadio(
            [kCustomPool.first.id],
            'R1',
            'FreeRoam',
            maxSlots: 10,
          );
      final before = c.read(playlistPlanProvider).encodeForCli();
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: helpers.app(const PlaylistScreen()),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(RmButton, '复制游戏内排布'));
      await t.pumpAndSettle();
      expect(find.text('复制游戏内排布？'), findsOneWidget);
      expect(c.read(playlistPlanProvider).encodeForCli(), before);
      await t.tap(find.widgetWithText(RmButton, '取消'));
      await t.pumpAndSettle();
      expect(c.read(playlistPlanProvider).encodeForCli(), before);
    },
  );
  testWidgets('drag feedback shows each of three selected song cards', (
    t,
  ) async {
    viewport(t, const Size(1365, 900));
    await t.pumpWidget(
      helpers.app(
        Center(
          child: PlaylistDragPreview(tracks: kCustomPool.take(3).toList()),
        ),
      ),
    );
    expect(find.byType(TrackCard), findsNWidgets(3));
    expect(find.text('移动 3 首歌曲'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
