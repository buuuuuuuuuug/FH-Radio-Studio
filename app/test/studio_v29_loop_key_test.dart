import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fh_radio_studio/state/editor_shortcuts.dart';
import 'package:fh_radio_studio/widgets/editor_shortcuts_dialog.dart';
import 'package:fh_radio_studio/screens/replace_editor/replace_editor.dart';
import 'package:fh_radio_studio/screens/replace_editor/manual_focus_waveform.dart';
import 'editor_playlist_upgrade_test.dart' as fixture;
import 'studio_v21_workflow_test.dart' as helpers;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  test(
    'letters and function keys persist as one loop combination key',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final ctl = EditorShortcutController(prefs);
      expect(loopCombinationLabel(ctl.state), 'Alt');
      for (final key in [LogicalKeyboardKey.keyK, LogicalKeyboardKey.f8]) {
        ctl.setLoopModifier(loopModifierForKey(key));
        final loaded = EditorShortcutController(prefs);
        for (final action in loopNudgeActions) {
          final chord = loaded.state[action]!;
          expect(chord.extraKey, key);
          final event = KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.arrowRight,
            logicalKey: chord.key,
            timeStamp: Duration.zero,
          );
          expect(
            chord.matches(
              event,
              ctrl: chord.ctrl,
              shift: chord.shift,
              alt: chord.alt,
              meta: chord.meta,
              pressedKeys: {key},
            ),
            isTrue,
          );
          expect(
            chord.matches(
              event,
              ctrl: chord.ctrl,
              shift: chord.shift,
              alt: chord.alt,
              meta: chord.meta,
              pressedKeys: {},
            ),
            isFalse,
          );
          expect(EditorChord.fromJson(chord.toJson())!.token, chord.token);
        }
        expect(loopCombinationLabel(loaded.state), EditorChord(key).label);
        expect(shortcutConflict(loaded.state), isNull);
        loaded.dispose();
      }
      ctl.dispose();
    },
  );
  test(
    'invalid and conflicting combination keys preserve saved settings',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final ctl = EditorShortcutController(prefs);
      ctl.setLoopModifier(loopModifierForKey(LogicalKeyboardKey.keyK));
      final saved = prefs.getString('editor.shortcuts.v1');
      final modifier = prefs.getString('editor.loopModifier');
      for (final key in [
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.escape,
        LogicalKeyboardKey.shiftLeft,
      ]) {
        expect(
          () => ctl.setLoopModifier(loopModifierForKey(key)),
          throwsFormatException,
        );
        expect(prefs.getString('editor.shortcuts.v1'), saved);
        expect(prefs.getString('editor.loopModifier'), modifier);
      }
      ctl.dispose();
    },
  );
  testWidgets('settings record one key and can cancel re-recording', (t) async {
    final f = await fixture.fixture();
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: f.container,
        child: helpers.app(const EditorShortcutsButton()),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('修改快捷键'));
    await t.pumpAndSettle();
    final button = find.byKey(const ValueKey('shortcut-loop-modifier'));
    expect(find.text('两端同移组合键'), findsOneWidget);
    expect(find.text('Alt'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('shortcut-loopBeatForward')),
      findsNothing,
    );
    await t.tap(button);
    await t.sendKeyEvent(LogicalKeyboardKey.keyK);
    await t.pumpAndSettle();
    expect(find.text('K'), findsOneWidget);
    await t.tap(find.text('保存'));
    await t.pumpAndSettle();
    expect(
      loopCombinationLabel(f.container.read(editorShortcutsProvider)),
      'K',
    );
    await t.tap(find.text('修改快捷键'));
    await t.pumpAndSettle();
    expect(find.text('K'), findsOneWidget);
    await t.tap(button);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('K'), findsOneWidget);
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'custom combination moves both endpoints and release stops repeats',
    (t) async {
      t.view.physicalSize = const Size(1600, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final f = await fixture.fixture();
      f.container
          .read(editorShortcutsProvider.notifier)
          .setLoopModifier(loopModifierForKey(LogicalKeyboardKey.keyK));
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: helpers.app(
            const ReplaceEditorScreen(trackId: 'p1', enableAudio: false),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('两端同移组合键'), findsOneWidget);
      expect(find.text('两端同移 1 拍'), findsNothing);
      expect(find.text('两端同移 10ms'), findsNothing);
      final open = find.byKey(const ValueKey('editor-manual-refine-tl'));
      await Scrollable.ensureVisible(t.element(open), alignment: .5);
      await t.pumpAndSettle();
      await t.tap(open);
      await t.pumpAndSettle();
      List<double> times() => t
          .widget<ManualFocusWaveform>(find.byType(ManualFocusWaveform))
          .handles
          .map((h) => h.t)
          .toList();
      final before = times();
      await t.sendKeyDownEvent(LogicalKeyboardKey.keyK);
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await t.pump(const Duration(milliseconds: 650));
      expect(times()[0], greaterThan(before[0]));
      expect(times()[1] - times()[0], closeTo(before[1] - before[0], 1e-6));
      await t.sendKeyUpEvent(LogicalKeyboardKey.keyK);
      await t.pump();
      final stopped = times();
      await t.pump(const Duration(milliseconds: 750));
      expect(times(), stopped);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await t.pump(const Duration(milliseconds: 350));
      expect(times(), stopped);
      await t.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();
      expect(times()[0], greaterThan(stopped[0]));
      expect(times()[1], stopped[1]);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );
}
