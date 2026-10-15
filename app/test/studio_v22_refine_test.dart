import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fh_radio_studio/state/audition_preferences.dart';
import 'package:fh_radio_studio/state/editor_shortcuts.dart';
import 'package:fh_radio_studio/state/custom_pool_tracks.dart';
import 'package:fh_radio_studio/state/app_state.dart';
import 'package:fh_radio_studio/domain/radio_library.dart';
import 'package:fh_radio_studio/screens/replace_editor/replace_editor.dart';
import 'package:fh_radio_studio/screens/replace_editor/replace_state.dart';
import 'package:fh_radio_studio/screens/replace_editor/manual_focus_waveform.dart';
import 'package:fh_radio_studio/domain/replacement_models.dart';
import 'editor_playlist_upgrade_test.dart' as fixture;
import 'studio_v21_workflow_test.dart' as helpers;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  test(
    'new defaults and old navigation migrate without retaining segment shortcuts',
    () async {
      SharedPreferences.setMockInitialValues({
        'editor.shortcuts.v1': jsonEncode({
          'previous': const EditorChord(
            LogicalKeyboardKey.arrowUp,
            alt: true,
            shift: true,
          ).toJson(),
          'next': const EditorChord(
            LogicalKeyboardKey.arrowDown,
            alt: true,
            shift: true,
          ).toJson(),
          'play': const EditorChord(
            LogicalKeyboardKey.keyP,
            ctrl: true,
          ).toJson(),
          'segment1': const EditorChord(LogicalKeyboardKey.digit1).toJson(),
        }),
      });
      final ctl = EditorShortcutController(
        await SharedPreferences.getInstance(),
      );
      expect(ctl.state[EditorAction.previous]!.label, 'Ctrl + Shift + ↑');
      expect(ctl.state[EditorAction.next]!.label, 'Ctrl + Shift + ↓');
      expect(ctl.state[EditorAction.play]!.label, 'Ctrl + P');
      expect(ctl.state[EditorAction.suggestionPrevious]!.label, 'Ctrl + ↑');
      expect(ctl.state[EditorAction.restoreSaved]!.label, 'Ctrl + H');
      expect(shortcutConflict(ctl.state), isNull);
      expect(ctl.state.keys.any((a) => a.name.startsWith('segment')), isFalse);
      expect(
        ctl.state.values.any((c) => c.key == LogicalKeyboardKey.digit1),
        isFalse,
      );
      ctl.save({
        ...ctl.state,
        EditorAction.previous: const EditorChord(
          LogicalKeyboardKey.arrowUp,
          alt: true,
          shift: true,
        ),
      });
      final reloaded = EditorShortcutController(
        await SharedPreferences.getInstance(),
      );
      expect(reloaded.state[EditorAction.previous]!.label, 'Alt + Shift + ↑');
      reloaded.dispose();
      ctl.dispose();
    },
  );
  test(
    'audition defaults to one repetition and two seconds on each side',
    () async {
      final f = await fixture.fixture();
      final prefs = f.container.read(auditionPreferencesProvider);
      expect(prefs.repetitions, 1);
      expect(prefs.before, 2);
      expect(prefs.after, 2);
      f.container
          .read(auditionPreferencesProvider.notifier)
          .update(repetitions: 4);
      f.container.invalidate(auditionPreferencesProvider);
      expect(f.container.read(auditionPreferencesProvider).repetitions, 4);
    },
  );
  testWidgets(
    'manual suggestion keys cycle, restore saved disk values and undo locally',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1800, 1150);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final f = await fixture.fixture();
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
              configured: true,
              confirmed: 0,
              added: 'today',
            ),
          ]),
        ],
      );
      addTearDown(c.dispose);
      const id = 'p1';
      final n = c.read(replaceEditorProvider(id).notifier);
      n.applyManualLoop(GroupKind.tl, 10, 60, confirm: false);
      n.saveToProject();
      final disk = File('${f.dir.path}/analysis/track_timing.json');
      final savedBytes = disk.readAsBytesSync();
      n.applyManualLoop(GroupKind.tl, 20, 80, confirm: false);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: helpers.app(
            ReplaceEditorScreen(trackId: id, enableAudio: false),
          ),
        ),
      );
      await t.pumpAndSettle();
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
      final candidates = n.state.ai.tl;
      expect(candidates.length, greaterThan(1));
      await helpers.keyCombo(t, LogicalKeyboardKey.arrowDown, ctrl: true);
      expect(times(), [candidates.first.start, candidates.first.end]);
      await helpers.keyCombo(t, LogicalKeyboardKey.arrowDown, ctrl: true);
      expect(times(), [candidates[1].start, candidates[1].end]);
      await helpers.keyCombo(t, LogicalKeyboardKey.arrowUp, ctrl: true);
      expect(times(), [candidates.first.start, candidates.first.end]);
      await helpers.keyCombo(t, LogicalKeyboardKey.arrowUp, ctrl: true);
      expect(times(), [candidates.last.start, candidates.last.end]);
      final beforeRestore = times();
      await helpers.keyCombo(t, LogicalKeyboardKey.keyH, ctrl: true);
      expect(times(), [10, 60]);
      expect(n.state.tl.start, 20);
      expect(n.state.tl.end, 80);
      expect(disk.readAsBytesSync(), savedBytes);
      await helpers.keyCombo(t, LogicalKeyboardKey.keyZ, ctrl: true);
      expect(times(), beforeRestore);
      final input = find.descendant(
        of: find.byKey(const ValueKey('manual-time-loopStart')),
        matching: find.byType(TextField),
      );
      await t.enterText(input, '0:25.125');
      await helpers.keyCombo(t, LogicalKeyboardKey.keyH, ctrl: true);
      expect(times(), [10, 60]);
      await helpers.keyCombo(t, LogicalKeyboardKey.keyZ, ctrl: true);
      expect(times()[0], 25.125);
      expect(disk.readAsBytesSync(), savedBytes);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );
}
