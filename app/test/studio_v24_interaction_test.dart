import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fh_radio_studio/state/editor_shortcuts.dart';
import 'package:fh_radio_studio/state/library_columns.dart';
import 'package:fh_radio_studio/state/layout_options.dart';
import 'package:fh_radio_studio/screens/custom_pool.dart';
import 'package:fh_radio_studio/screens/playlist/radio_column.dart';
import 'package:fh_radio_studio/screens/playlist/playlist_state.dart';
import 'package:fh_radio_studio/screens/replace_editor/replace_editor.dart';
import 'package:fh_radio_studio/screens/replace_editor/replace_state.dart';
import 'package:fh_radio_studio/screens/replace_editor/manual_focus_waveform.dart';
import 'package:fh_radio_studio/screens/replace_editor/waveform_card.dart';
import 'package:fh_radio_studio/screens/replace_editor/waveform_painter.dart';
import 'package:fh_radio_studio/domain/replacement_models.dart';
import 'package:fh_radio_studio/domain/radio_library.dart';
import 'package:fh_radio_studio/core/playlist_plan.dart';
import 'editor_playlist_upgrade_test.dart' as fixture;
import 'playlist_double_edit_test.dart' as routing;
import 'studio_v21_workflow_test.dart' as helpers;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  test(
    'old Alt bindings migrate; companions follow the one modifier and base keys',
    () async {
      SharedPreferences.setMockInitialValues({
        'editor.shortcuts.version': 3,
        'editor.shortcuts.v1': jsonEncode({
          'beatForward': const EditorChord(LogicalKeyboardKey.keyK).toJson(),
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final ctl = EditorShortcutController(prefs);
      expect(ctl.state[EditorAction.loopBeatForward]!.label, 'Alt + K');
      ctl.save({
        ...ctl.state,
        EditorAction.loopTenForward: const EditorChord(
          LogicalKeyboardKey.keyL,
          ctrl: true,
        ),
      });
      final restored = EditorShortcutController(prefs);
      expect(
        restored.state[EditorAction.loopTenForward]!.label,
        'Alt + Shift + →',
      );
      expect(restored.state[EditorAction.tenForward]!.label, 'Shift + →');
      expect(
        shortcutConflict({
          ...restored.state,
          EditorAction.play: restored.state[EditorAction.loopTenForward]!,
        }),
        isNotNull,
      );
      restored.dispose();
      ctl.dispose();
    },
  );
  testWidgets(
    'column divider follows the pointer across frames and has no trailing action grip',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1500, 1050);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final f = await fixture.fixture();
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: helpers.app(const CustomPoolScreen()),
        ),
      );
      await t.pumpAndSettle();
      final grip = find.byKey(const ValueKey('pool-column-grip-song'));
      await Scrollable.ensureVisible(t.element(grip));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('pool-column-grip-actions')),
        findsNothing,
      );
      final initial = t.getCenter(grip);
      final gesture = await t.startGesture(initial);
      for (final dx in [-45.0, -85.0, -110.0, -55.0]) {
        await gesture.moveTo(initial + Offset(dx, 0));
        await t.pump();
        expect(t.getCenter(grip).dx, closeTo(initial.dx + dx, 1.0));
      }
      await gesture.up();
      await t.pumpAndSettle();
      expect(f.container.read(libraryColumnsProvider), isNotEmpty);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'waveform toggles control real painter layers; unused spectrum and chord entries are gone',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1200, 700);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final f = await fixture.fixture();
      final state = f.container.read(replaceEditorProvider('p1'));
      await t.pumpWidget(
        helpers.app(
          WaveformCard(
            state: state,
            aiPending: false,
            onSeek: (_) {},
            onZoomIn: () {},
            onZoomOut: () {},
          ),
        ),
      );
      WaveformPainter painter() => t
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<WaveformPainter>()
          .single;
      expect(find.text('频谱'), findsNothing);
      expect(find.text('和弦'), findsNothing);
      expect(painter().showWaveform, isTrue);
      await t.tap(find.byKey(const ValueKey('waveform-toggle-波形')));
      await t.pumpAndSettle();
      expect(painter().showWaveform, isFalse);
      await t.tap(find.byKey(const ValueKey('waveform-toggle-节拍')));
      await t.pumpAndSettle();
      expect(painter().beats, isEmpty);
      await t.tap(find.byKey(const ValueKey('waveform-toggle-段落')));
      await t.pumpAndSettle();
      expect(painter().segments, isEmpty);
      await t.tap(find.byKey(const ValueKey('waveform-toggle-段落')));
      await t.pumpAndSettle();
      expect(painter().segments, state.ai.segments);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'custom loop shortcut shifts both endpoints and appears as shortcut cards',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1800, 1150);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final f = await fixture.fixture();
      final c = f.container;
      final shortcuts = c.read(editorShortcutsProvider.notifier);
      shortcuts.save({
        ...shortcuts.state,
        EditorAction.tenForward: const EditorChord(
          LogicalKeyboardKey.keyL,
          ctrl: true,
        ),
      });
      final n = c.read(replaceEditorProvider('p1').notifier);
      n.applyManualLoop(GroupKind.tl, 10, 60, confirm: false);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: helpers.app(
            const ReplaceEditorScreen(trackId: 'p1', enableAudio: false),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('两端同移组合键'), findsOneWidget);
      expect(find.text('Alt'), findsOneWidget);
      expect(find.text('两端同移 10ms'), findsNothing);
      final manual = find.byKey(const ValueKey('editor-manual-refine-tl'));
      await Scrollable.ensureVisible(t.element(manual), alignment: .5);
      await t.pump();
      await t.tap(manual);
      await t.pumpAndSettle();
      List<double> times() => t
          .widget<ManualFocusWaveform>(find.byType(ManualFocusWaveform))
          .handles
          .map((h) => h.t)
          .toList();
      await helpers.keyCombo(t, LogicalKeyboardKey.keyL, ctrl: true, alt: true);
      expect(times()[0], closeTo(10.01, 1e-8));
      expect(times()[1], closeTo(60.01, 1e-8));
      expect(n.state.tl.start, 10);
      expect(n.state.tl.end, 60);
      await helpers.keyCombo(t, LogicalKeyboardKey.keyZ, ctrl: true);
      expect(times(), [10, 60]);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'width drag reuses radio and pool content; height reaches 1200 and persists after debounce',
    (t) async {
      final f = await routing.setupPlaylist(t);
      final before = t
          .widgetList<PlaylistColumn>(find.byType(PlaylistColumn))
          .toList();
      final ctl = f.container.read(layoutOptionsProvider.notifier);
      ctl.setWidth(1500);
      await t.pump();
      final after = t
          .widgetList<PlaylistColumn>(find.byType(PlaylistColumn))
          .toList();
      expect(after.length, before.length);
      expect(after.every((w) => before.contains(w)), isTrue);
      ctl.setRadioHeight(1500);
      await t.pump();
      expect(ctl.state.radioHeight, 1200);
      ctl.setRadioHeight(1199.5);
      await t.pump(const Duration(milliseconds: 300));
      expect(ctl.state.radioHeight, 1199.5);
      expect(t.takeException(), isNull);
    },
  );
  test(
    'large pool resolves identical canonical assignments without a scan for every song',
    () {
      final pool = [
        for (var i = 0; i < 1200; i++)
          PoolTrack(
            id: 'p$i',
            title: 'Song $i',
            artist: 'Test',
            source: 'D:/music/song$i.wav',
            durationSec: 180,
            bpm: 120,
            key: '',
            configured: true,
            confirmed: 4,
            added: '',
          ),
      ];
      var plan = const PlaylistPlan.empty();
      for (var i = 0; i < 1200; i++) {
        plan = plan.assign(
          source: pool[i].source,
          radioCode: 'R${i % 9 + 1}',
          playlistType: 'FreeRoam',
          slot: i ~/ 9 + 1,
        );
      }
      const mode = PlaylistMode.freeroam;
      final state = PlaylistState(
        pool: pool,
        mode: mode,
        search: '',
        splitPlaylistTypes: false,
      );
      final watch = Stopwatch()..start();
      final display = state.poolForDisplay(plan);
      watch.stop();
      expect(display.length, 1200);
      expect(display.every((t) => t.assignedTo != null), isTrue);
      for (final t in [display.first, display[600], display.last]) {
        final expected = plan.assignmentForPath(t.source)!;
        expect(t.assignedTo, expected.radioCode);
        expect(t.slot, expected.slot);
      }
      debugPrint(
        '1200-song pool assignment index: ${watch.elapsedMilliseconds} ms',
      );
    },
  );
}
