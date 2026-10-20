import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fh_radio_studio/core/fh_radio_studio_cli.dart';
import 'package:fh_radio_studio/core/project_workspace.dart';
import 'package:fh_radio_studio/core/siren_audio_cache.dart';
import 'package:fh_radio_studio/core/siren_catalog.dart';
import 'package:fh_radio_studio/state/app_state.dart';
import 'package:fh_radio_studio/state/audio_analysis_state.dart';
import 'package:fh_radio_studio/state/siren_import_queue_state.dart';
import 'package:fh_radio_studio/state/studio_state.dart';

const _track = SirenTrack(
  cid: 'test-song',
  name: 'Test song',
  albumCid: 'test-album',
  albumName: 'Test album',
  coverUrl: '',
  artists: ['Test artist'],
  albumIsOst: false,
);
const _detail = SirenSongDetail(
  cid: 'test-song',
  name: 'Test song',
  albumCid: 'test-album',
  sourceUrl: 'https://example.invalid/test.wav',
  lyricUrl: null,
  mvUrl: null,
  mvCoverUrl: null,
  artists: ['Test artist'],
);

class _Studio extends StudioController {
  _Studio(super.prefs);
  final importedProjects = <String>[];
  void switchProject(String dir) => state = state.copyWith(projectDir: dir);
  void setOperation(String mode) => state = state.copyWith(
    busy: mode == 'busy',
    refreshingPanels: mode == 'scan' ? const {'fileIntegrity'} : const {},
    projectPathMigrationRunning: mode == 'migration',
  );
  @override
  Future<String?> importSirenTrack({
    required SirenTrack track,
    required SirenSongDetail detail,
    required String cachedAudioPath,
    String? coverImagePath,
  }) async {
    importedProjects.add(state.projectDir);
    return '$cachedAudioPath-imported';
  }
}

class _Catalog extends Fake implements SirenCatalogClient {
  @override
  Future<SirenSongDetail> fetchSongDetail(String cid) async => _detail;
}

class _Cache extends SirenAudioCache {
  _Cache(String path) : super(rootPath: path);
  final started = Completer<void>();
  final result = Completer<File>();
  @override
  Future<File> cacheAudio(SirenSongDetail detail, {SirenTrack? track}) {
    started.complete();
    return result.future;
  }
}

CliRunResult _analysisResult(String path, {bool cancelled = false}) =>
    CliRunResult(
      exitCode: cancelled ? -1 : 0,
      stdout: jsonEncode({'source': path, 'duration_sec': 8, 'candidates': {}}),
      stderr: '',
      commandLine: 'fixture',
      cancelled: cancelled,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SharedPreferences prefs;
  late _Studio studio;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('studio-state-lifecycle-');
    for (final name in ['one', 'two']) {
      FhRadioStudioProject.ensure('${root.path}/$name');
    }
    SharedPreferences.setMockInitialValues({
      'rm.studio.projectDir': '${root.path}/one',
      'rm.studio.repoRoot': root.path,
    });
    prefs = await SharedPreferences.getInstance();
    studio = _Studio(prefs);
    addTearDown(() => root.deleteSync(recursive: true));
  });

  ProviderContainer container({AudioAnalysisCliRunner? runner, _Cache? cache}) {
    final result = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        studioProvider.overrideWith((ref) => studio),
        if (runner != null)
          audioAnalysisCliRunnerProvider.overrideWithValue(runner),
        if (cache != null) ...[
          sirenAudioCacheProvider.overrideWithValue(cache),
          sirenCatalogClientProvider.overrideWithValue(_Catalog()),
        ],
      ],
    );
    addTearDown(result.dispose);
    return result;
  }

  for (final mode in ['busy', 'scan', 'migration']) {
    test('project and game directories stay fixed during $mode', () {
      final c = container();
      final before = c.read(studioProvider);
      studio.setOperation(mode);
      studio.setProjectDir('${root.path}/two');
      studio.updateRecentProjectPath(before.projectDir, '${root.path}/two');
      studio.removeRecentProject(before.projectDir);
      studio.setGameDir('${root.path}/other-game');
      expect(c.read(studioProvider).projectDir, before.projectDir);
      expect(c.read(studioProvider).gameDir, before.gameDir);
      expect(c.read(studioProvider).hasProject, isTrue);
      expect(prefs.getString('rm.studio.projectDir'), before.projectDir);
      studio.setOperation('none');
      studio.setProjectDir('${root.path}/two');
      expect(
        Directory(c.read(studioProvider).projectDir).absolute.path,
        Directory('${root.path}/two').absolute.path,
      );
    });
  }

  test(
    'analysis launch failure clears busy and permits another analysis',
    () async {
      var calls = 0;
      final c = container(
        runner: (root, args, {cancellationToken, onStdout, onStderr}) async {
          if (calls++ == 0) {
            throw const ProcessException('fixture', [], 'missing tool');
          }
          return _analysisResult(args[1]);
        },
      );
      final controller = c.read(audioAnalysisProvider.notifier);
      expect(await controller.analyze('first.wav'), isNull);
      expect(c.read(audioAnalysisProvider).busy, isFalse);
      expect(c.read(audioAnalysisProvider).error, contains('missing tool'));
      expect(await controller.analyze('second.wav'), isNotNull);
      expect(c.read(audioAnalysisProvider).path, 'second.wav');
    },
  );

  test(
    'rapid analysis requests keep only the latest pending request',
    () async {
      final pending = <String, Completer<CliRunResult>>{};
      final c = container(
        runner: (root, args, {cancellationToken, onStdout, onStderr}) {
          final result = Completer<CliRunResult>();
          pending[args[1]] = result;
          return result.future;
        },
      );
      final controller = c.read(audioAnalysisProvider.notifier);
      final first = controller.analyze('first.wav');
      final second = controller.analyze('second.wav');
      final latest = controller.analyze('latest.wav');
      await Future<void>.delayed(Duration.zero);
      expect(pending.keys, ['first.wav', 'latest.wav']);
      pending['latest.wav']!.complete(_analysisResult('latest.wav'));
      expect(await latest, isNotNull);
      pending['first.wav']!.complete(_analysisResult('first.wav'));
      expect(await first, isNull);
      expect(await second, isNull);
      expect(c.read(audioAnalysisProvider).result!.path, 'latest.wav');
    },
  );

  test('project switch cancels analysis and ignores its late result', () async {
    final finish = Completer<CliRunResult>();
    CliCancellationToken? active;
    final c = container(
      runner: (root, args, {cancellationToken, onStdout, onStderr}) {
        active = cancellationToken;
        return finish.future;
      },
    );
    final work = c.read(audioAnalysisProvider.notifier).analyze('old.wav');
    studio.switchProject('${root.path}/two');
    expect(active!.isCancelled, isTrue);
    expect(c.read(audioAnalysisProvider).busy, isFalse);
    expect(c.read(audioAnalysisProvider).path, isNull);
    finish.complete(_analysisResult('old.wav'));
    expect(await work, isNull);
    expect(c.read(audioAnalysisProvider).result, isNull);
  });

  test(
    'cancelled CLI result clears busy even without token cancellation',
    () async {
      final c = container(
        runner: (root, args, {cancellationToken, onStdout, onStderr}) async =>
            _analysisResult(args[1], cancelled: true),
      );
      expect(
        await c.read(audioAnalysisProvider.notifier).analyze('song.wav'),
        isNull,
      );
      expect(c.read(audioAnalysisProvider).busy, isFalse);
    },
  );

  test('disposing pending analysis ignores its late result', () async {
    final finish = Completer<CliRunResult>();
    final c = container(
      runner: (root, args, {cancellationToken, onStdout, onStderr}) =>
          finish.future,
    );
    final work = c.read(audioAnalysisProvider.notifier).analyze('song.wav');
    c.dispose();
    finish.complete(_analysisResult('song.wav'));
    expect(await work, isNull);
  });

  test(
    'Siren download completion never imports into a newly selected project',
    () async {
      final cache = _Cache(root.path);
      final c = container(cache: cache);
      final controller = c.read(sirenImportQueueProvider.notifier);
      controller.queue([_track.cid]);
      final work = controller.importQueuedTracks([_track]);
      await cache.started.future;
      studio.switchProject('${root.path}/two');
      controller.queue(['new-project-song']);
      cache.result.complete(File('${root.path}/cached.wav'));
      await work;
      expect(studio.importedProjects, isEmpty);
      expect(c.read(sirenImportQueueProvider).queuedCids, {'new-project-song'});
      expect(c.read(sirenImportQueueProvider).lastBatchTotal, 0);
      expect(c.read(sirenImportQueueProvider).trackErrors, isEmpty);
    },
  );

  test('Siren imported preview identities are scoped to the project', () {
    final c = container(cache: _Cache(root.path));
    final controller = c.read(sirenImportQueueProvider.notifier);
    controller.markImported(_track.cid);
    studio.switchProject('${root.path}/two');
    controller.queue([_track.cid]);
    expect(c.read(sirenImportQueueProvider).queuedCids, {_track.cid});
    expect(c.read(sirenImportQueueProvider).importedPreviewCids, isEmpty);
  });

  test(
    'disposing Siren queue during download does not publish after disposal',
    () async {
      final cache = _Cache(root.path);
      final c = container(cache: cache);
      final controller = c.read(sirenImportQueueProvider.notifier);
      controller.queue([_track.cid]);
      final work = controller.importQueuedTracks([_track]);
      await cache.started.future;
      c.dispose();
      cache.result.completeError(
        const FileSystemException('cancelled fixture'),
      );
      await expectLater(work, completes);
      expect(studio.importedProjects, isEmpty);
    },
  );
}
