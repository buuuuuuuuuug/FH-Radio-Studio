import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fh_radio_studio/domain/replacement_models.dart';
import 'package:fh_radio_studio/screens/playlist/track_card.dart';
import 'package:fh_radio_studio/screens/playlist/radio_column.dart';
import 'package:fh_radio_studio/screens/replace_editor/replace_editor.dart';
import 'package:fh_radio_studio/screens/replace_editor/replace_state.dart';
import 'package:fh_radio_studio/screens/replace_editor/manual_focus_waveform.dart';
import 'package:fh_radio_studio/state/editor_options.dart';
import 'package:fh_radio_studio/state/layout_options.dart';
import 'package:fh_radio_studio/theme/app_theme.dart';
import 'package:fh_radio_studio/theme/accents.dart';
import 'package:fh_radio_studio/widgets/package_quality_panel.dart';
import 'editor_playlist_upgrade_test.dart' as upgrade;
import 'playlist_double_edit_test.dart' as routing;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  testWidgets('selection is immediate and does not rebuild station columns', (
    tester,
  ) async {
    await routing.setupPlaylist(tester);
    await tester.tap(find.byKey(const ValueKey('playlist-multiselect-toggle')));
    await tester.pump();
    final stationBefore = tester
        .widgetList<PlaylistColumn>(find.byType(PlaylistColumn))
        .first;
    final pool = find.descendant(
      of: find.byKey(const ValueKey('playlist-pool-side-panel')),
      matching: find.byType(TrackCard),
    );
    await tester.tap(pool.at(0));
    await tester
        .pump(); // No double-tap timeout is allowed before showing selection.
    expect(find.text('已选 1'), findsOneWidget);
    expect(
      identical(
        stationBefore,
        tester.widgetList<PlaylistColumn>(find.byType(PlaylistColumn)).first,
      ),
      isTrue,
    );
    await tester.tap(pool.at(1));
    await tester.pump();
    expect(find.text('已选 2'), findsOneWidget);
    await tester.tap(pool.at(0));
    await tester.pump();
    expect(find.text('已选 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test(
    'PL pause is session local, resume copies TL confirmation, one-shot is undoable',
    () async {
      final f = await upgrade.fixture();
      final c = f.container;
      final provider = replaceEditorProvider('p1');
      final subscription = c.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final n = c.read(provider.notifier);
      c.read(editorOptionsProvider.notifier).update(syncPostLoop: true);
      n.applyManualLoop(GroupKind.tl, 10, 50, confirm: true);
      expect(n.state.pl.start, 10);
      expect(n.state.plConfirmed, isTrue);
      n.setPostLoopSyncPaused(true);
      n.applyManualLoop(GroupKind.tl, 15, 55, confirm: false);
      expect(n.state.pl.start, 10);
      expect(c.read(editorOptionsProvider).syncPostLoop, isTrue);
      n.setPostLoopSyncPaused(false);
      expect(n.state.pl.start, 15);
      expect(n.state.pl.end, 55);
      expect(n.state.plConfirmed, isFalse);
      c.read(editorOptionsProvider.notifier).update(syncPostLoop: false);
      n.applyManualLoop(GroupKind.tl, 20, 60, confirm: false);
      n.syncPostLoopFromTrackLoop();
      expect(n.state.pl.start, 20);
      n.undo();
      expect(n.state.pl.start, 15);
      expect(n.state.dirty, isTrue);
      expect(c.read(editorOptionsProvider).syncPostLoop, isFalse);
    },
  );
  test('manual window preference persists', () async {
    SharedPreferences.setMockInitialValues({});
    final p = await SharedPreferences.getInstance();
    final first = LayoutOptionsController(p)..setManualRefineWidth(1560);
    first.dispose();
    final second = LayoutOptionsController(p);
    expect(second.state.manualRefineWidth, 1560);
    second.dispose();
  });
  testWidgets(
    'Alt with all three steps shifts both endpoints; width expands only waveform',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1800, 1100);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = await upgrade.fixture();
      final c = f.container;
      final n = c.read(replaceEditorProvider('p1').notifier);
      n.applyManualLoop(GroupKind.tl, 10, 60, confirm: false);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: buildAppTheme(
              brightness: Brightness.light,
              accent: AppAccent.lime,
            ),
            home: const Scaffold(
              body: ReplaceEditorScreen(trackId: 'p1', enableAudio: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final manual = find.byKey(const ValueKey('editor-manual-refine-tl'));
      await Scrollable.ensureVisible(tester.element(manual), alignment: .5);
      await tester.pump();
      await tester.tap(manual);
      await tester.pumpAndSettle();
      final main = find.byKey(const ValueKey('manual-refine-main-editor'));
      final right = find.byKey(const ValueKey('manual-refine-ai-panel'));
      final originalMain = tester.getSize(main).width;
      final originalRight = tester.getSize(right).width;
      c.read(layoutOptionsProvider.notifier).setManualRefineWidth(1550);
      await tester.pumpAndSettle();
      expect(tester.getSize(main).width, greaterThan(originalMain + 400));
      expect(tester.getSize(right).width, originalRight);
      List<double> times() => tester
          .widget<ManualFocusWaveform>(find.byType(ManualFocusWaveform))
          .handles
          .map((h) => h.t)
          .toList();
      for (final modifier in [
        null,
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.controlLeft,
      ]) {
        final before = times();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        if (modifier != null) await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        final after = times();
        final step = modifier == LogicalKeyboardKey.shiftLeft
            ? .010
            : modifier == LogicalKeyboardKey.controlLeft
            ? .001
            : 60 / n.state.ai.bpm;
        expect(after[0] - before[0], closeTo(step, 1e-8));
        expect(after[1] - before[1], closeTo(step, 1e-8));
        expect(after[1] - after[0], closeTo(50, 1e-8));
        if (modifier != null) await tester.sendKeyUpEvent(modifier);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      }
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      final stopped = times();
      await tester.pump(const Duration(milliseconds: 700));
      expect(times(), stopped);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      // Repeated whole-loop movement clamps the common delta at zero, preserving length.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      for (var i = 0; i < 35; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
      }
      expect(times()[0], closeTo(0, 1e-8));
      expect(times()[1], closeTo(50, 1e-8));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'quality defaults to 50, changes estimates and warns before bank overflow at wide and narrow sizes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 950);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var selected = 50;
      final data = <String, dynamic>{
        'files': [
          {
            'name': 'media/audio/FMODBanks/R1.assets.bank',
            'sizes': List.generate(100, (i) => (i + 1) * 30000000),
            'upper_sizes': List.generate(100, (i) => (i + 1) * 40000000),
            'limit_bytes': 2147483648,
            'rebuilt': true,
          },
        ],
        'total_sizes': List.generate(100, (i) => (i + 1) * 30000000),
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(
            brightness: Brightness.light,
            accent: AppAccent.lime,
          ),
          home: Scaffold(
            body: PackageBuildDialogFrame(
              estimate: Future.value(data),
              onQualityChanged: (v) => selected = v,
              child: const SizedBox(height: 360, child: Text('构建配置')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('50'), findsOneWidget);
      final totalBefore = tester
          .widget<Text>(find.byKey(const ValueKey('package-total-estimate')))
          .data;
      tester
          .widget<Slider>(find.byKey(const ValueKey('package-quality-slider')))
          .onChanged!(100);
      await tester.pump();
      expect(selected, 100);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('package-total-estimate')))
            .data,
        isNot(totalBefore),
      );
      expect(
        find.byKey(const ValueKey('package-size-warning')),
        findsOneWidget,
      );
      tester.view.physicalSize = const Size(760, 680);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
