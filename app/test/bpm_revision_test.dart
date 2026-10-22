import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fh_radio_studio/core/project_workspace.dart';
import 'package:fh_radio_studio/core/project_refs.dart';
import 'package:fh_radio_studio/core/track_metadata_cache.dart';
import 'package:fh_radio_studio/core/fh_radio_studio_cli.dart';
import 'package:fh_radio_studio/core/waveform_service.dart';
import 'package:fh_radio_studio/core/track_timing_config.dart';
import 'package:fh_radio_studio/screens/replace_editor/replace_state.dart';
import 'package:fh_radio_studio/state/app_state.dart';
import 'package:fh_radio_studio/state/audio_analysis_state.dart';
import 'package:fh_radio_studio/state/custom_pool_tracks.dart';
import 'package:fh_radio_studio/widgets/bpm_edit_button.dart';
import 'package:fh_radio_studio/widgets/package_build_notice_dialog.dart';
import 'package:fh_radio_studio/theme/app_theme.dart';
import 'package:fh_radio_studio/theme/accents.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  test(
    'manual BPM updates grid, preserves markers and confirmations, undoes and persists',
    () async {
      final root = Directory.systemTemp.createTempSync('bpm_edit_');
      addTearDown(() => root.deleteSync(recursive: true));
      FhRadioStudioProject.ensure(root.path);
      FhRadioStudioProject.writeSettings(root.path, slmEnabled: false);
      final source = File(p.join(root.path, 'sources', 'demo.wav'))
        ..writeAsBytesSync([0]);
      final sourceRef = projectRefForPath(root.path, source.path)!;
      File(TrackMetadataCache.configPath(root.path)).writeAsStringSync(
        jsonEncode({
          'schema_version': 2,
          'tracks': [
            {
              'track_key': trackKeyForSourceRef(sourceRef),
              'source_ref': sourceRef,
            },
          ],
        }),
      );
      final config = TrackTimingConfig(
        source: source.path,
        bpm: 120,
        markersSec: const {
          'TrackDrop': 1,
          'PostDrop': 2,
          'TrackLoopStart': 3,
          'TrackLoopEnd': 6,
          'PostRaceLoopStart': 3,
          'PostRaceLoopEnd': 6,
        },
        confirmed: const {'td': true, 'tl': false, 'pd': true, 'pl': false},
        updatedAt: DateTime.now(),
      );
      TrackTimingStore.save(root.path, config);
      SharedPreferences.setMockInitialValues({
        'rm.studio.projectDir': root.path,
      });
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          audioAnalysisCliRunnerProvider.overrideWithValue(
            (repoRoot, args, {cancellationToken, onStdout, onStderr}) async =>
                CliRunResult(
                  exitCode: 0,
                  stderr: '',
                  commandLine: 'test analysis',
                  stdout: jsonEncode({
                    'source': source.path,
                    'duration_sec': 16,
                    'bpm': 90,
                    'beats': [0.1, .7667, 1.4333],
                    'waveform': {
                      'bins': List.filled(WaveformService.detailedBins, {
                        'norm_peak': .4,
                        'norm_rms': .2,
                      }),
                    },
                  }),
                ),
          ),
        ],
      );
      addTearDown(c.dispose);
      final provider = replaceEditorProvider(realTrackIdForPath(source.path));
      final sub = c.listen(provider, (_, _) {});
      addTearDown(sub.close);
      final n = c.read(provider.notifier);
      final before = c.read(provider);
      n.setBpm(150);
      final edited = c.read(provider);
      expect(edited.ai.bpm, 150);
      expect(edited.bpmManual, isTrue);
      expect(edited.ai.beats[1] - edited.ai.beats[0], closeTo(.4, 1e-8));
      expect(edited.markerSeconds, before.markerSeconds);
      expect(edited.confirmedGroups, before.confirmedGroups);
      expect(edited.dirty, isTrue);
      n.undo();
      expect(c.read(provider).ai.bpm, 120);
      expect(c.read(provider).bpmManual, isFalse);
      for (final invalid in [double.nan, double.infinity, 0.0, 401.0]) {
        expect(() => n.setBpm(invalid), throwsFormatException);
      }
      n.setBpm(150);
      n.saveToProject();
      final saved = TrackTimingStore.readAll(root.path).values.single;
      expect(saved.bpm, 150);
      expect(saved.bpmManual, isTrue);
      c.invalidate(provider);
      final reopened = c.read(provider);
      expect(reopened.bpmManual, isTrue);
      expect(reopened.ai.bpm, 150);
      expect(reopened.ai.beats[1] - reopened.ai.beats[0], closeTo(.4, 1e-8));
      expect(reopened.markerSeconds, edited.markerSeconds);
      expect(reopened.confirmedGroups, edited.confirmedGroups);
      await c.read(provider.notifier).analyze(force: true);
      final reanalyzed = c.read(provider);
      expect(reanalyzed.ai.bpm, 150);
      expect(reanalyzed.bpmManual, isTrue);
      expect(
        reanalyzed.ai.beats[1] - reanalyzed.ai.beats[0],
        closeTo(.4, 1e-8),
      );
      expect(reanalyzed.markerSeconds, edited.markerSeconds);
      expect(reanalyzed.confirmedGroups, edited.confirmedGroups);
    },
  );

  testWidgets('BPM input rejects invalid values and supports doubling', (
    tester,
  ) async {
    double? applied;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(
          brightness: Brightness.light,
          accent: AppAccent.lime,
        ),
        home: Scaffold(
          body: BpmEditButton(
            bpm: 75,
            manual: false,
            onApply: (v) => applied = v,
          ),
        ),
      ),
    );
    await tester.tap(find.text('BPM 75.0'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'NaN');
    await tester.tap(find.text('应用 BPM'));
    await tester.pump();
    expect(applied, isNull);
    expect(find.textContaining('请输入 20'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '75');
    await tester.tap(find.text('加倍'));
    await tester.tap(find.text('应用 BPM'));
    await tester.pumpAndSettle();
    expect(applied, 150);
    expect(tester.takeException(), isNull);
  });

  testWidgets('build success action navigates to Overview without deploying', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/playlist',
      routes: [
        GoRoute(
          path: '/playlist',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => showPackageBuildSuccessDialog(
                context,
                detail: '完成',
                trackPreview: '试听曲',
              ),
              child: const Text('结果'),
            ),
          ),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (_, _) => const Scaffold(body: Text('概览测试页')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        theme: buildAppTheme(
          brightness: Brightness.light,
          accent: AppAccent.lime,
        ),
      ),
    );
    await tester.tap(find.text('结果'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('前往概览写入游戏'));
    await tester.pumpAndSettle();
    expect(find.text('概览测试页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
