import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fh_radio_studio/core/playlist_plan.dart';
import 'package:fh_radio_studio/core/fh_radio_studio_cli.dart';
import 'package:fh_radio_studio/domain/replacement_models.dart';
import 'package:fh_radio_studio/domain/radio_library.dart';
import 'package:fh_radio_studio/screens/replace_editor/replace_editor.dart';
import 'package:fh_radio_studio/screens/replace_editor/manual_focus_waveform.dart';
import 'package:fh_radio_studio/screens/replace_editor/replace_state.dart';
import 'package:fh_radio_studio/screens/playlist/radio_column.dart';
import 'package:fh_radio_studio/screens/playlist/track_card.dart';
import 'package:fh_radio_studio/state/editor_shortcuts.dart';
import 'package:fh_radio_studio/state/editor_options.dart';
import 'package:fh_radio_studio/state/editor_navigation.dart';
import 'package:fh_radio_studio/state/layout_options.dart';
import 'package:fh_radio_studio/state/playlist_plan_state.dart';
import 'package:fh_radio_studio/theme/app_theme.dart';
import 'package:fh_radio_studio/theme/accents.dart';
import 'package:fh_radio_studio/widgets/timing_import_dialog.dart';
import 'package:fh_radio_studio/widgets/editor_shortcuts_dialog.dart';
import 'package:fh_radio_studio/widgets/time_input_field.dart';
import 'editor_playlist_upgrade_test.dart' as upgrade;
import 'studio_v18_workflow_test.dart' as history;
import 'playlist_double_edit_test.dart' as routing;

Widget app(Widget body) => MaterialApp(
  theme: buildAppTheme(brightness: Brightness.light, accent: AppAccent.lime),
  home: Scaffold(body: body),
);
Future<void> keyCombo(
  WidgetTester t,
  LogicalKeyboardKey key, {
  bool ctrl = false,
  bool shift = false,
  bool alt = false,
}) async {
  if (ctrl) await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  if (alt) await t.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await t.sendKeyEvent(key);
  if (alt) await t.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (ctrl) await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await t.pumpAndSettle();
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  test(
    'shortcut defaults are conflict free and customization survives reload',
    () async {
      SharedPreferences.setMockInitialValues({});
      final p = await SharedPreferences.getInstance();
      final c = EditorShortcutController(p);
      expect(c.state[EditorAction.previous]!.label, 'Shift + ↑');
      expect(shortcutConflict(c.state), isNull);
      final bad = {
        ...c.state,
        EditorAction.next: c.state[EditorAction.previous]!,
      };
      expect(shortcutConflict(bad), isNotNull);
      final valid = {
        ...c.state,
        EditorAction.previous: const EditorChord(
          LogicalKeyboardKey.keyP,
          ctrl: true,
          shift: true,
        ),
      };
      c.save(valid);
      final restored = EditorShortcutController(p);
      expect(restored.state[EditorAction.previous]!.label, 'Ctrl + Shift + P');
      c.dispose();
      restored.dispose();
    },
  );
  test(
    'expansion cannot turn off while a draft exceeds baseline capacity',
    () async {
      final c = await history.fixture();
      final options = c.read(editorOptionsProvider.notifier);
      options.update(expansionEnabled: true);
      final capacity = kRadios.firstWhere((r) => r.code == 'R1').slot;
      var plan = const PlaylistPlan.empty();
      for (var i = 0; i <= capacity; i++) {
        plan = plan.assign(
          source: 'C:/test/song$i.wav',
          radioCode: 'R1',
          playlistType: 'FreeRoam',
          slot: i + 1,
        );
      }
      c.read(playlistPlanProvider.notifier).replaceWith(plan);
      expect(options.update(expansionEnabled: false), isFalse);
      expect(c.read(editorOptionsProvider).expansionEnabled, isTrue);
      expect(options.expansionOverflow().join(), contains('${capacity + 1}'));
      c
          .read(playlistPlanProvider.notifier)
          .replaceWith(
            plan.unassign(
              'C:/test/song$capacity.wav',
              radioCode: 'R1',
              playlistType: 'FreeRoam',
            ),
          );
      expect(options.update(expansionEnabled: false), isTrue);
      expect(c.read(editorOptionsProvider).expansionEnabled, isFalse);
    },
  );
  testWidgets(
    'layout drag reuses station widgets and heights move without 20px jumps',
    (t) async {
      final f = await routing.setupPlaylist(t);
      final before = t
          .widgetList<PlaylistColumn>(find.byType(PlaylistColumn))
          .first;
      final ctl = f.container.read(layoutOptionsProvider.notifier);
      ctl.setRadioHeight(481);
      await t.pump();
      expect(
        identical(
          before,
          t.widgetList<PlaylistColumn>(find.byType(PlaylistColumn)).first,
        ),
        isTrue,
      );
      expect(
        t
            .getSize(find.byKey(const ValueKey('playlist-radio-column-R1')))
            .height,
        481,
      );
      ctl.setRadioHeight(482);
      await t.pump();
      expect(
        t
            .getSize(find.byKey(const ValueKey('playlist-radio-column-R1')))
            .height,
        482,
      );
      await t.pump(const Duration(milliseconds: 300));
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('previous and next shortcuts wrap the originating queue', (
    t,
  ) async {
    final f = await routing.setupPlaylist(t);
    final pool = find.descendant(
      of: find.byKey(const ValueKey('playlist-pool-side-panel')),
      matching: find.byType(TrackCard),
    );
    await routing.doubleClick(t, pool.first);
    await t.pumpAndSettle();
    var current = t
        .widget<ReplaceEditorScreen>(find.byType(ReplaceEditorScreen))
        .trackId;
    final queue = f.container.read(editorSongQueueProvider).ids;
    expect(current, queue.first);
    await keyCombo(t, LogicalKeyboardKey.arrowUp, shift: true);
    current = t
        .widget<ReplaceEditorScreen>(find.byType(ReplaceEditorScreen))
        .trackId;
    expect(current, queue.last);
    await keyCombo(t, LogicalKeyboardKey.arrowDown, shift: true);
    expect(
      t.widget<ReplaceEditorScreen>(find.byType(ReplaceEditorScreen)).trackId,
      queue.first,
    );
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'manual undo restores nudges and text input without touching main editor history',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1800, 1100);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final f = await upgrade.fixture();
      final c = f.container;
      final n = c.read(replaceEditorProvider('p1').notifier);
      n.applyManualLoop(GroupKind.tl, 10, 60, confirm: false);
      n.editTime(GroupKind.td, FineTarget.point, 2.5);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: app(
            const ReplaceEditorScreen(trackId: 'p1', enableAudio: false),
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
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
      expect(times()[0], greaterThan(10));
      await keyCombo(t, LogicalKeyboardKey.keyZ, ctrl: true);
      expect(times(), [10, 60]);
      expect(n.state.td.t, 2.5);
      await keyCombo(t, LogicalKeyboardKey.keyZ, ctrl: true);
      expect(
        n.state.td.t,
        2.5,
      ); // Empty local history must never undo main edits.
      final input = find.descendant(
        of: find.byKey(const ValueKey('manual-time-loopStart')),
        matching: find.byType(TextField),
      );
      await t.enterText(input, '0:15.250');
      TimeInputValidation.flush();
      await t.pump();
      expect(times()[0], 15.250);
      await keyCombo(t, LogicalKeyboardKey.keyZ, ctrl: true);
      expect(times(), [10, 60]);
      expect(n.state.td.t, 2.5);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      await t.pump(const Duration(milliseconds: 300));
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'shortcut dialog rejects conflicts, saves valid chords and fits small windows',
    (t) async {
      final f = await upgrade.fixture();
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: app(const EditorShortcutsButton()),
        ),
      );
      await t.tap(find.text('修改快捷键'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('shortcut-previous')),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await Scrollable.ensureVisible(
        t.element(find.byKey(const ValueKey('shortcut-previous'))),
        alignment: .5,
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('shortcut-previous')));
      await t.pump();
      await keyCombo(t, LogicalKeyboardKey.space);
      expect(find.textContaining('冲突'), findsOneWidget);
      await keyCombo(t, LogicalKeyboardKey.keyP, ctrl: true, shift: true);
      await t.tap(find.text('保存'));
      await t.pumpAndSettle();
      expect(
        f.container.read(editorShortcutsProvider)[EditorAction.previous]!.label,
        'Ctrl + Shift + P',
      );
      await t.pump(const Duration(milliseconds: 300));
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'timing import previews first and only writes after explicit confirmation',
    (t) async {
      final f = await upgrade.fixture();
      final calls = <List<String>>[];
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: ProviderScope(
            overrides: [
              timingImportFilePickerProvider.overrideWithValue(
                () async => "C:/fixtures/points.csv",
              ),
              timingImportRunnerProvider.overrideWithValue((
                root,
                args,
                input,
              ) async {
                calls.add([...args]);
                expect(input, isNull);
                expect(args, contains('C:/fixtures/points.csv'));
                return CliRunResult(
                  commandLine: 'test import',
                  exitCode: 0,
                  stderr: '',
                  stdout: jsonEncode({
                    'snapshot_hash': 's',
                    'input_hash': 'i',
                    'ready_count': 1,
                    'rows': [
                      {
                        'row': 1,
                        'title': 'Artist - Song',
                        'status': 'ready',
                        'message': '导入 TL',
                        'markers_sec': {'TrackLoopStart': 2.123},
                      },
                    ],
                    if (args.contains('--apply')) 'applied_count': 1,
                  }),
                );
              }),
            ],
            child: app(const TimingImportDialog()),
          ),
        ),
      );
      await t.tap(find.byKey(const ValueKey('timing-import-file')));
      await t.pump();
      await t.tap(find.text('预览匹配'));
      await t.pumpAndSettle();
      expect(calls.length, 1);
      expect(calls.first, isNot(contains('--apply')));
      expect(find.textContaining('可导入 1 首'), findsOneWidget);
      await t.tap(find.text('导入 1 首'));
      await t.pumpAndSettle();
      expect(
        calls.last,
        containsAll(['--apply', '--expected-snapshot', '--expected-input']),
      );
      expect(find.textContaining('已导入 1 首'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 300));
      expect(t.takeException(), isNull);
    },
  );
}
