import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fh_radio_studio/core/fh_radio_studio_cli.dart';
import 'package:fh_radio_studio/core/seamless_loop_cache.dart';
import 'package:fh_radio_studio/state/app_state.dart';
import 'package:fh_radio_studio/state/custom_pool_tracks.dart';
import 'package:fh_radio_studio/state/seamless_loop_state.dart';
import 'package:fh_radio_studio/state/seamless_batch_state.dart';
import 'editor_playlist_upgrade_test.dart' as fixtures;

Map<String, dynamic> payload() => {
  'loop_engine': 'seamless-loop-music',
  'duration_sec': 180,
  'candidates': {
    'tl': List.generate(
      10,
      (i) => {
        'start': i + 10,
        'end': i + 90,
        'score': .99 - i / 100,
        'why': 'SeamlessLoopMusic',
      },
    ),
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(SeamlessLoopCache.clearMemory);
  test(
    'cached ten candidates load without launching CLI and invalidate after audio/engine changes',
    () async {
      final f = await fixtures.fixture();
      final song = '${f.dir.path}/sources/song.wav';
      final dll = File('${f.dir.path}/loopfinder.dll')..writeAsBytesSync([1]);
      await SeamlessLoopCache.write(f.dir.path, song, dll.path, payload());
      SeamlessLoopCache.clearMemory();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            f.container.read(sharedPreferencesProvider),
          ),
          seamlessEnginePathProvider.overrideWithValue(dll.path),
        ],
      );
      addTearDown(c.dispose);
      final list = await c.read(seamlessLoopLoaderProvider)(
        'no-native-process',
        f.dir.path,
        song,
        CliCancellationToken(),
        false,
      );
      expect(list.length, 10);
      expect(list.first.start, 10);
      await File(song).writeAsBytes([1, 2]);
      expect(await SeamlessLoopCache.read(f.dir.path, song, dll.path), isNull);
      await SeamlessLoopCache.write(f.dir.path, song, dll.path, payload());
      await dll.writeAsBytes([2, 3]);
      expect(await SeamlessLoopCache.read(f.dir.path, song, dll.path), isNull);
    },
  );
  test(
    'batch continues on failure, reuses cached entries and never updates markers',
    () async {
      final f = await fixtures.fixture();
      final dll = File('${f.dir.path}/loopfinder.dll')..writeAsBytesSync([1]);
      var calls = 0;
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            f.container.read(sharedPreferencesProvider),
          ),
          seamlessEnginePathProvider.overrideWithValue(dll.path),
          batchLoopLoaderProvider.overrideWithValue((
            project,
            root,
            source,
            token,
          ) async {
            calls++;
            if (source.endsWith('a.wav')) {
              throw const FormatException('bad audio');
            }
            await SeamlessLoopCache.write(project, source, dll.path, payload());
          }),
        ],
      );
      addTearDown(c.dispose);
      for (final name in ['a', 'b', 'c', 'other']) {
        File('${f.dir.path}/sources/$name.wav').writeAsBytesSync([1]);
      }
      final tracks = c.read(realPoolTracksProvider);
      for (final t in tracks) {
        if (!File(t.source).existsSync()) File(t.source).writeAsBytesSync([1]);
      }
      final markers = File('${f.dir.path}/track_timing.json');
      final existed = markers.existsSync();
      await c.read(seamlessBatchProvider.notifier).start(tracks);
      expect(c.read(seamlessBatchProvider).done, tracks.length);
      expect(c.read(seamlessBatchProvider).errors.length, 1);
      expect(c.read(seamlessBatchProvider).running, isFalse);
      expect(calls, tracks.length);
      calls = 0;
      await c.read(seamlessBatchProvider.notifier).start(tracks);
      expect(calls, 1);
      expect(c.read(seamlessBatchProvider).cached, tracks.length - 1);
      expect(markers.existsSync(), existed);
    },
  );
  test(
    'cancelling a batch stops before the next song and ignores a late result',
    () async {
      final f = await fixtures.fixture();
      final started = Completer<CliCancellationToken>();
      final finish = Completer<void>();
      var calls = 0;
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            f.container.read(sharedPreferencesProvider),
          ),
          batchLoopLoaderProvider.overrideWithValue((
            project,
            root,
            source,
            token,
          ) {
            calls++;
            started.complete(token);
            return finish.future;
          }),
        ],
      );
      addTearDown(c.dispose);
      final work = c
          .read(seamlessBatchProvider.notifier)
          .start(c.read(realPoolTracksProvider));
      final token = await started.future;
      c.read(seamlessBatchProvider.notifier).cancel();
      expect(token.isCancelled, isTrue);
      finish.complete();
      await work;
      expect(calls, 1);
      expect(c.read(seamlessBatchProvider).done, 0);
      expect(c.read(seamlessBatchProvider).cancelled, isTrue);
      expect(c.read(seamlessBatchProvider).running, isFalse);
    },
  );
}
