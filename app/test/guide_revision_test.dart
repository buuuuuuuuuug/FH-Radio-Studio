import 'package:fh_radio_studio/state/studio_state.dart';
import 'dart:io';

import 'package:fh_radio_studio/core/demo_song.dart';
import 'package:fh_radio_studio/core/project_workspace.dart';
import 'package:fh_radio_studio/domain/replacement_models.dart';
import 'package:fh_radio_studio/domain/radio_library.dart';
import 'package:fh_radio_studio/state/custom_pool_tracks.dart';
import 'package:fh_radio_studio/screens/replace_editor/progress_strip.dart';
import 'package:fh_radio_studio/screens/replace_editor/replace_editor.dart';
import 'package:fh_radio_studio/screens/replace_editor/replace_state.dart';
import 'package:fh_radio_studio/state/app_state.dart';
import 'package:fh_radio_studio/state/audition_preferences.dart';
import 'package:fh_radio_studio/state/editor_options.dart';
import 'package:fh_radio_studio/theme/accents.dart';
import 'package:fh_radio_studio/theme/app_theme.dart';
import 'package:fh_radio_studio/widgets/feature_tour.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'editor_playlist_upgrade_test.dart' as fixture;
import 'studio_v21_workflow_test.dart' as helpers;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  test(
    'TD and PD durations persist independently and clamp to valid ranges',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(c.dispose);
      final n = c.read(auditionPreferencesProvider.notifier);
      expect(n.state.tdDuration, 6);
      expect(n.state.pdDuration, 6);
      n.update(tdDuration: 9, pdDuration: 14, before: 3);
      await Future<void>.delayed(Duration.zero);
      c.invalidate(auditionPreferencesProvider);
      final restored = c.read(auditionPreferencesProvider);
      expect(restored.pointDuration(false), 9);
      expect(restored.pointDuration(true), 14);
      expect(restored.before, 3);
      c
          .read(auditionPreferencesProvider.notifier)
          .update(tdDuration: -1, pdDuration: 99);
      expect(c.read(auditionPreferencesProvider).tdDuration, 1);
      expect(c.read(auditionPreferencesProvider).pdDuration, 30);
      expect(
        pointPreviewWindowForTesting(
          timeSec: 10,
          durationSec: 180,
          previewDuration: restored.tdDuration,
        ),
        (start: 10.0, end: 19.0),
      );
      expect(
        pointPreviewWindowForTesting(
          timeSec: 175,
          durationSec: 180,
          previewDuration: restored.pdDuration,
        ),
        (start: 175.0, end: 180.0),
      );
    },
  );

  test(
    'loop engine defaults on but preserves an explicitly disabled project',
    () async {
      final f = await fixture.fixture();
      expect(f.container.read(editorOptionsProvider).slmEnabled, isFalse);
      final fresh = Directory.systemTemp.createTempSync('guide_defaults_');
      addTearDown(() => fresh.deleteSync(recursive: true));
      FhRadioStudioProject.ensure(fresh.path);
      // Use the same load path as a newly opened project, with no stored option.
      f.container.read(studioProvider.notifier).setProjectDir(fresh.path);
      expect(f.container.read(editorOptionsProvider).slmEnabled, isTrue);
      f.container
          .read(editorOptionsProvider.notifier)
          .update(slmEnabled: false);
      f.container.invalidate(editorOptionsProvider);
      expect(f.container.read(editorOptionsProvider).slmEnabled, isFalse);
      final settings = FhRadioStudioProject.readSettings(fresh.path);
      expect(settings['seamless_loop_music'], isFalse);
      expect(const EditorOptions().slmEnabled, isTrue);
    },
  );

  test(
    'demo installs through importer once and records a portable reference',
    () async {
      final dir = Directory.systemTemp.createTempSync('guide_demo_');
      addTearDown(() => dir.deleteSync(recursive: true));
      FhRadioStudioProject.ensure(dir.path);
      String? tempInput;
      var calls = 0;
      Future<List<String>> importer(String input) async {
        calls++;
        tempInput = input;
        final bytes = await File(input).readAsBytes();
        expect(String.fromCharCodes(bytes.take(4)), 'RIFF');
        final target = p.join(dir.path, 'sources', DemoSong.fileName);
        await File(input).copy(target);
        return [target];
      }

      await DemoSong.install(dir.path, importer);
      final source = DemoSong.sourceFor(dir.path);
      expect(source, p.join(dir.path, 'sources', DemoSong.fileName));
      expect(DemoSong.matches(dir.path, source!), isTrue);
      if (Platform.isWindows) {
        expect(
          DemoSong.matches(
            dir.path,
            source.toUpperCase().replaceAll('\\', '/'),
          ),
          isTrue,
        );
      }
      expect(File(tempInput!).existsSync(), isFalse);
      await DemoSong.install(dir.path, importer);
      expect(calls, 1);
      File(source).deleteSync();
      expect(DemoSong.sourceFor(dir.path), isNull);
    },
  );

  testWidgets(
    'queued save prompt rechecks saved and unconfirmed state before opening',
    (t) async {
      final f = await fixture.fixture();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            f.container.read(sharedPreferencesProvider),
          ),
          realPoolTracksProvider.overrideWithValue([
            PoolTrack(
              id: 'p1',
              title: 'Queued save',
              artist: 'Test',
              source: p.join(f.dir.path, 'sources', 'song.wav'),
              durationSec: 180,
              bpm: 120,
              key: '',
              configured: false,
              confirmed: 0,
              added: '',
            ),
          ]),
        ],
      );
      addTearDown(c.dispose);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: helpers.app(
            const ReplaceEditorScreen(trackId: 'p1', enableAudio: false),
          ),
        ),
      );
      await t.pumpAndSettle();
      final n = c.read(replaceEditorProvider('p1').notifier);
      for (final kind in GroupKind.values) {
        n.setConfirmed(kind, true);
      }
      n.saveToProject();
      await t.pumpAndSettle();
      expect(find.text('保存这首歌的配置？'), findsNothing);
      n.setConfirmed(GroupKind.pl, false);
      n.editTime(GroupKind.pl, FineTarget.loopStart, 10);
      n.setConfirmed(GroupKind.pl, true);
      n.setConfirmed(GroupKind.pl, false);
      await t.pumpAndSettle();
      expect(find.text('保存这首歌的配置？'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  test(
    'failed demo import cleans temporary audio and does not mark success',
    () async {
      final dir = Directory.systemTemp.createTempSync('guide_demo_fail_');
      addTearDown(() => dir.deleteSync(recursive: true));
      FhRadioStudioProject.ensure(dir.path);
      String? input;
      await expectLater(
        DemoSong.install(dir.path, (path) async {
          input = path;
          throw StateError('import failed');
        }),
        throwsStateError,
      );
      expect(File(input!).existsSync(), isFalse);
      expect(DemoSong.sourceFor(dir.path), isNull);
    },
  );

  test('guide cards sit 12px from targets including a full-height board', () {
    const viewport = Size(1200, 850), card = Size(380, 200);
    for (final target in [
      const Rect.fromLTWH(100, 50, 1000, 150),
      const Rect.fromLTWH(100, 700, 1000, 100),
      const Rect.fromLTWH(20, 20, 1160, 1200),
    ]) {
      final visible = featureTourVisibleTarget(
        viewport,
        target.intersect(Offset.zero & viewport),
        card,
      )!;
      final pos = featureTourCardOffset(viewport, visible, card);
      final tooltip = pos & card;
      expect(tooltip.overlaps(visible), isFalse);
      final gap = tooltip.top >= visible.bottom
          ? tooltip.top - visible.bottom
          : visible.top - tooltip.bottom;
      expect(gap, 12);
    }
  });

  testWidgets(
    'progress cards order, hover-only highlight, Ctrl-click and double-click',
    (t) async {
      final f = await fixture.fixture();
      final s = f.container.read(replaceEditorProvider('p1'));
      GroupKind? selected, preview, refine;
      await t.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(
            brightness: Brightness.light,
            accent: AppAccent.lime,
          ),
          home: Scaffold(
            body: ProgressStrip(
              state: s,
              onSelect: (g) => selected = g,
              onPreview: (g) => preview = g,
              onManualRefine: (g) => refine = g,
            ),
          ),
        ),
      );
      final td = find.byKey(const ValueKey('editor-progress-TD'));
      final tl = find.byKey(const ValueKey('editor-progress-TL'));
      final pd = find.byKey(const ValueKey('editor-progress-PD'));
      expect(t.getTopLeft(td).dx, lessThan(t.getTopLeft(tl).dx));
      expect(t.getTopLeft(tl).dx, lessThan(t.getTopLeft(pd).dx));
      await t.tap(td);
      await t.pump(const Duration(milliseconds: 350));
      await t.pumpAndSettle();
      expect(selected, GroupKind.td);
      Container box() => t
          .widgetList<Container>(
            find.descendant(of: td, matching: find.byType(Container)),
          )
          .first;
      expect((box().decoration! as BoxDecoration).gradient, isNull);
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(790, 590));
      await mouse.moveTo(t.getCenter(td));
      await t.pumpAndSettle();
      expect((box().decoration! as BoxDecoration).gradient, isNotNull);
      await mouse.moveTo(const Offset(790, 590));
      await t.pumpAndSettle();
      expect((box().decoration! as BoxDecoration).gradient, isNull);
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.tap(pd);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pump(const Duration(milliseconds: 350));
      await t.pumpAndSettle();
      expect(preview, GroupKind.pd);
      expect(selected, GroupKind.td);
      await t.tap(tl);
      await t.pump(const Duration(milliseconds: 60));
      await t.tap(tl);
      await t.pumpAndSettle();
      expect(refine, GroupKind.tl);
      await mouse.removePointer();
    },
  );
}
