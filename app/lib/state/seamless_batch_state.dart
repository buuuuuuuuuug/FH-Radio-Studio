import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/fh_radio_studio_cli.dart';
import '../core/seamless_loop_cache.dart';
import 'seamless_loop_state.dart';
import '../domain/radio_library.dart';
import 'studio_state.dart';

typedef BatchLoopLoader =
    Future<void> Function(
      String project,
      String repoRoot,
      String source,
      CliCancellationToken token,
    );
final batchLoopLoaderProvider = Provider<BatchLoopLoader>(
  (ref) => (project, repoRoot, source, token) async {
    await ref.read(seamlessLoopLoaderProvider)(
      repoRoot,
      project,
      source,
      token,
      false,
    );
  },
);

class SeamlessBatchState {
  const SeamlessBatchState({
    this.running = false,
    this.total = 0,
    this.done = 0,
    this.cached = 0,
    this.current = '',
    this.errors = const {},
    this.cancelled = false,
  });
  final bool running, cancelled;
  final int total, done, cached;
  final String current;
  final Map<String, String> errors;
}

class SeamlessBatchController extends StateNotifier<SeamlessBatchState> {
  SeamlessBatchController(this.ref) : super(const SeamlessBatchState()) {
    ref.listen<String>(studioProvider.select((s) => s.projectDir), (_, _) {
      cancel();
      _generation++;
      state = const SeamlessBatchState();
    });
  }
  final Ref ref;
  CliCancellationToken? _token;
  int _generation = 0;
  bool _cancelled = false;
  void cancel() {
    _cancelled = true;
    if (mounted && state.running) {
      state = SeamlessBatchState(
        running: true,
        cancelled: true,
        total: state.total,
        done: state.done,
        cached: state.cached,
        current: state.current,
        errors: state.errors,
      );
    }
    if (_token != null) unawaited(_token!.cancel());
  }

  Future<void> start(List<PoolTrack> tracks) async {
    if (state.running) return;
    final studio = ref.read(studioProvider);
    final project = studio.projectDir, repoRoot = studio.repoRoot;
    final dll = ref.read(seamlessEnginePathProvider);
    final unique = {for (final t in tracks) t.source: t}.values.toList();
    final generation = ++_generation;
    _cancelled = false;
    var done = 0, cached = 0;
    final errors = <String, String>{};
    void publish(bool running, String current) {
      if (mounted && generation == _generation) {
        state = SeamlessBatchState(
          running: running,
          total: unique.length,
          done: done,
          cached: cached,
          current: current,
          errors: Map.unmodifiable(errors),
          cancelled: _cancelled,
        );
      }
    }

    publish(true, '');
    try {
      for (final track in unique) {
        if (_cancelled || generation != _generation) break;
        publish(true, track.title);
        final token = _token = CliCancellationToken();
        try {
          if (await SeamlessLoopCache.read(project, track.source, dll) !=
              null) {
            cached++;
          } else {
            await ref.read(batchLoopLoaderProvider)(
              project,
              repoRoot,
              track.source,
              token,
            );
          }
        } on Object catch (error) {
          if (_cancelled || generation != _generation) break;
          errors[track.source] = '${track.title}：$error';
        }
        if (_cancelled || generation != _generation) break;
        done++;
        publish(true, track.title);
      }
    } finally {
      if (generation == _generation) _token = null;
      publish(false, '');
    }
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }
}

final seamlessBatchProvider =
    StateNotifierProvider<SeamlessBatchController, SeamlessBatchState>(
      (ref) => SeamlessBatchController(ref),
    );
