import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fh_radio_studio/domain/radio_library.dart';
import 'package:fh_radio_studio/domain/replacement_models.dart';
import 'package:fh_radio_studio/screens/replace_editor/replace_editor.dart';
import 'package:fh_radio_studio/screens/replace_editor/replace_state.dart';
import 'package:fh_radio_studio/screens/replace_editor/manual_focus_waveform.dart';
import 'package:fh_radio_studio/state/app_state.dart';
import 'package:fh_radio_studio/state/custom_pool_tracks.dart';
import 'package:fh_radio_studio/state/playlist_plan_state.dart';
import 'package:fh_radio_studio/core/playlist_plan.dart';
import 'package:fh_radio_studio/widgets/open_package_folder_button.dart';
import 'package:fh_radio_studio/widgets/rm_button.dart';
import 'editor_playlist_upgrade_test.dart' as fixture;
import 'studio_v21_workflow_test.dart' as helpers;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  void viewport(WidgetTester t) {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1365, 900);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
  }

  Future<ProviderContainer> setup() async {
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
            configured: false,
            confirmed: 0,
            added: 'today',
          ),
        ]),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<void> pump(WidgetTester t, ProviderContainer c) async {
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: helpers.app(
          const ReplaceEditorScreen(trackId: 'p1', enableAudio: false),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets(
    'confirmed groups remain unchanged after double click, Escape, close and unchanged confirm',
    (t) async {
      viewport(t);
      final c = await setup();
      final n = c.read(replaceEditorProvider('p1').notifier);
      for (final g in GroupKind.values) {
        n.setConfirmed(g, true);
      }
      n.saveToProject();
      await pump(t, c);
      final markers = {...n.state.markerSeconds};
      for (final kind in GroupKind.values) {
        final cell = find.byKey(ValueKey('editor-progress-${kind.code}'));
        await t.tap(cell);
        await t.pump(const Duration(milliseconds: 70));
        await t.tap(cell);
        await t.pumpAndSettle();
        expect(n.state.confirmedOf(kind), isTrue);
        expect(n.state.dirty, isFalse);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pumpAndSettle();
        expect(n.state.allConfirmed, isTrue);
        expect(n.state.dirty, isFalse);
        await t.tap(cell);
        await t.pump(const Duration(milliseconds: 70));
        await t.tap(cell);
        await t.pumpAndSettle();
        await t.tap(find.byTooltip('取消人工选点'));
        await t.pumpAndSettle();
        expect(n.state.allConfirmed, isTrue);
        expect(n.state.markerSeconds, markers);
        expect(n.state.dirty, isFalse);
      }
      await helpers.keyCombo(t, LogicalKeyboardKey.digit3, ctrl: true);
      await t.tap(find.text('确认选点'));
      await t.pumpAndSettle();
      expect(n.state.dirty, isFalse);
      expect(find.textContaining('配置 6 个时间点'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('discarded manual changes keep original confirmed markers', (
    t,
  ) async {
    viewport(t);
    final c = await setup();
    final n = c.read(replaceEditorProvider('p1').notifier);
    n.setConfirmed(GroupKind.tl, true);
    n.saveToProject();
    final markers = {...n.state.markerSeconds};
    await pump(t, c);
    await helpers.keyCombo(t, LogicalKeyboardKey.digit3, ctrl: true);
    await helpers.keyCombo(t, LogicalKeyboardKey.arrowRight, ctrl: true);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(n.state.tlConfirmed, isTrue);
    expect(n.state.markerSeconds, markers);
    expect(n.state.dirty, isFalse);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'Ctrl plus mouse right click confirms current groups without changing points',
    (t) async {
      viewport(t);
      final c = await setup();
      final n = c.read(replaceEditorProvider('p1').notifier);
      for (final kind in GroupKind.values) {
        n.setConfirmed(kind, false);
      }
      await pump(t, c);
      final points = {...n.state.markerSeconds};
      await t.tap(find.byKey(const ValueKey('editor-progress-PD')), buttons: 2);
      await t.pumpAndSettle();
      expect(n.state.pdConfirmed, isFalse);
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.tap(find.byKey(const ValueKey('editor-progress-PD')), buttons: 2);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pumpAndSettle();
      expect(n.state.pdConfirmed, isTrue);
      await helpers.keyCombo(t, LogicalKeyboardKey.digit3, ctrl: true);
      final wave = find.byType(ManualFocusWaveform);
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.tap(wave, buttons: 2);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pumpAndSettle();
      expect(find.byType(ManualFocusWaveform), findsNothing);
      expect(n.state.tlConfirmed, isTrue);
      expect(n.state.markerSeconds, points);
      expect(t.takeException(), isNull);
    },
  );
  for (final assigned in [false, true]) {
    testWidgets(
      'completed configuration only offers assignment when missing: assigned=$assigned',
      (t) async {
        viewport(t);
        final c = await setup();
        final n = c.read(replaceEditorProvider('p1').notifier);
        if (assigned) {
          c
              .read(playlistPlanProvider.notifier)
              .replaceWith(
                const PlaylistPlan.empty().assign(
                  source: n.state.track.source,
                  radioCode: 'R1',
                  playlistType: 'Event',
                  slot: 1,
                ),
              );
        }
        for (final g in GroupKind.values) {
          n.setConfirmed(g, false);
        }
        await pump(t, c);
        for (final g in GroupKind.values) {
          n.setConfirmed(g, true);
        }
        await t.pumpAndSettle();
        expect(find.text('时间点已全部确认'), findsOneWidget);
        expect(find.text('保存并分配电台'), assigned ? findsNothing : findsOneWidget);
        await t.tap(find.text('暂不保存'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'open package folder requires an existing folder and opens exactly that directory',
    (t) async {
      final dir = Directory.systemTemp.createTempSync('package_folder_');
      addTearDown(() => dir.deleteSync(recursive: true));
      String? opened;
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            packageFolderOpenerProvider.overrideWithValue(
              (path) async => opened = path,
            ),
          ],
          child: helpers.app(OpenPackageFolderButton(path: dir.path)),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('open-built-package-folder')));
      await t.pumpAndSettle();
      expect(opened, dir.absolute.path);
      await t.pumpWidget(
        ProviderScope(
          key: const ValueKey('missing-folder-scope'),
          child: helpers.app(
            OpenPackageFolderButton(path: '${dir.path}/missing'),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        t
            .widget<RmButton>(
              find.byKey(const ValueKey('open-built-package-folder')),
            )
            .onPressed,
        isNull,
      );
      expect(t.takeException(), isNull);
    },
  );
}
