import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fh_radio_studio/core/fh_radio_studio_cli.dart';
import 'package:fh_radio_studio/core/track_timing_config.dart';
import 'package:fh_radio_studio/core/waveform_cache.dart';
import 'package:fh_radio_studio/domain/replacement_models.dart';
import 'package:fh_radio_studio/screens/replace_editor/replace_editor.dart';
import 'package:fh_radio_studio/screens/replace_editor/replace_state.dart';
import 'package:fh_radio_studio/screens/replace_editor/time_group_card.dart';
import 'package:fh_radio_studio/state/app_state.dart';
import 'package:fh_radio_studio/state/audio_analysis_state.dart';
import 'package:fh_radio_studio/state/custom_pool_tracks.dart';
import 'package:fh_radio_studio/state/editor_options.dart';
import 'package:fh_radio_studio/state/seamless_loop_state.dart';
import 'package:fh_radio_studio/theme/accents.dart';
import 'package:fh_radio_studio/theme/app_theme.dart';
import 'editor_playlist_upgrade_test.dart' as upgrade;

const suggested = LoopCandidate(
  start: 14.123456,
  end: 112.987654,
  score: .97,
  bars: 0,
  why: 'SeamlessLoopMusic · 衔接匹配',
);
const markers = <String, double>{
  'TrackDrop': 10,
  'PostDrop': 100,
  'TrackLoopStart': 20,
  'TrackLoopEnd': 90,
  'PostRaceLoopStart': 25,
  'PostRaceLoopEnd': 105,
};

Future<(ProviderContainer, String)> setup({
  bool manual = true,
  SeamlessLoopLoader? loader,
}) async {
  final f = await upgrade.fixture();
  final source = '${f.dir.path}/sources/song.wav';
  TrackTimingStore.save(
    f.dir.path,
    TrackTimingConfig(
      source: source,
      bpm: 120,
      markersSec: markers,
      confirmed: const {'td': true, 'pd': true, 'tl': true, 'pl': true},
      updatedAt: DateTime.utc(2026),
    ),
  );
  await WaveformCache.write(f.dir.path, source, {
    'duration_sec': 180,
    'sample_rate': 48000,
    'waveform': {
      'bins': [
        {'norm_peak': .5, 'norm_rms': .4},
      ],
    },
  });
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(
        f.container.read(sharedPreferencesProvider),
      ),
      seamlessLoopLoaderProvider.overrideWithValue(
        loader ?? (root, project, source, token, force) async => [suggested],
      ),
      audioAnalysisCliRunnerProvider.overrideWithValue((
        root,
        args, {
        cancellationToken,
        onStdout,
        onStderr,
      }) async {
        expect(args, containsAll(['--loop-engine', 'seamless', '--slm-dll']));
        return CliRunResult(
          exitCode: 0,
          commandLine: 'fake',
          stderr: '',
          stdout: jsonEncode({
            'source': source,
            'duration_sec': 180,
            'sample_rate': 48000,
            'waveform': {
              'bins': [
                {'norm_peak': .5, 'norm_rms': .4},
              ],
            },
            'candidates': {
              'tl': [
                {
                  'start': suggested.start,
                  'end': suggested.end,
                  'score': .97,
                  'why': suggested.why,
                },
              ],
              'pl': [
                {
                  'start': suggested.start,
                  'end': suggested.end,
                  'score': .97,
                  'why': suggested.why,
                },
              ],
              'td': [
                {'t': 11, 'score': .8},
              ],
              'pd': [
                {'t': 95, 'score': .8},
              ],
            },
          }),
        );
      }),
    ],
  );
  addTearDown(c.dispose);
  c
      .read(editorOptionsProvider.notifier)
      .update(manualOnly: manual, slmEnabled: true);
  return (c, realTrackIdForPath(source));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  for (final manual in [true, false]) {
    test(
      'native suggestions preserve saved markers in ${manual ? 'manual' : 'AI'} mode',
      () async {
        final (c, id) = await setup(manual: manual);
        final provider = replaceEditorProvider(id);
        final sub = c.listen(provider, (_, _) {});
        addTearDown(sub.close);
        final before = c.read(provider);
        await c.read(provider.notifier).analyze();
        final after = c.read(provider);
        expect(after.markerSeconds, before.markerSeconds);
        expect(after.confirmedGroups, before.confirmedGroups);
        expect(
          after.ai.tl.any(
            (v) => v.start == suggested.start && v.end == suggested.end,
          ),
          isTrue,
        );
        expect(
          after.ai.pl.any(
            (v) => v.start == suggested.start && v.end == suggested.end,
          ),
          isTrue,
        );
        expect(after.error, isNull);
        expect(after.analyzing, isFalse);
        expect(after.dirty, isFalse);
        expect(after.saved, isTrue);
      },
    );
  }
  testWidgets(
    'manual native mode hides outer candidates and displays refinement suggestions',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (c, id) = (await tester.runAsync(() => setup()))!;
      await tester.runAsync(
        () => c.read(replaceEditorProvider(id).notifier).analyze(),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: buildAppTheme(
              brightness: Brightness.light,
              accent: AppAccent.lime,
            ),
            home: Scaffold(
              body: ReplaceEditorScreen(trackId: id, enableAudio: false),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final cards = tester.widgetList<TimeGroupCard>(
        find.byType(TimeGroupCard),
      );
      expect(
        cards.where((v) => v.kind.isLoop).every((v) => v.manualOnly),
        isTrue,
      );
      final n = c.read(replaceEditorProvider(id).notifier);
      n.setConfirmed(GroupKind.tl, false);
      await tester.pump();
      final manual = find.byKey(const ValueKey('editor-manual-refine-tl'));
      await Scrollable.ensureVisible(tester.element(manual), alignment: .5);
      await tester.pump();
      await tester.tap(manual);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));
      expect(find.text('套用循环建议'), findsOneWidget);
      expect(find.text('套用 AI 建议'), findsNothing);
      expect(
        find.byKey(const ValueKey('manual-refine-ai-apply-1')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'saved seams identical to native suggestions are not duplicated',
    () async {
      final (c, id) = await setup(
        loader: (root, project, source, token, force) async => [
          const LoopCandidate(
            start: 20,
            end: 90,
            score: .9,
            bars: 0,
            why: 'SeamlessLoopMusic',
          ),
          suggested,
        ],
      );
      final sub = c.listen(replaceEditorProvider(id), (_, _) {});
      addTearDown(sub.close);
      final before = c.read(replaceEditorProvider(id)).markerSeconds;
      await c.read(replaceEditorProvider(id).notifier).analyzeSeamless();
      final after = c.read(replaceEditorProvider(id));
      expect(after.ai.tl.length, 2);
      expect(
        after.ai.tl.where((item) => item.start == 20 && item.end == 90).length,
        1,
      );
      expect(after.markerSeconds, before);
      expect(after.tlConfirmed, isTrue);
    },
  );

  test(
    'disposing editor cancels native request and late result cannot overwrite state',
    () async {
      final started = Completer<CliCancellationToken>();
      final finished = Completer<List<LoopCandidate>>();
      final (c, id) = await setup(
        loader: (r, p, s, token, force) {
          started.complete(token);
          return finished.future;
        },
      );
      final subscription = c.listen(replaceEditorProvider(id), (_, _) {});
      final work = c.read(replaceEditorProvider(id).notifier).analyzeSeamless();
      final token = await started.future;
      subscription.close();
      await Future<void>.delayed(Duration.zero);
      expect(token.isCancelled, isTrue);
      finished.complete([suggested]);
      await work;
    },
  );
}
