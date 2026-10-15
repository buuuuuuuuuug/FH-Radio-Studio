import 'dart:io';
import 'dart:async';
import 'package:media_kit/media_kit.dart';
import '../state/audition_preferences.dart';
import 'loop_audition_session.dart';

/// Keeps the B -> A transition in mpv's native A/B loop, then bounds A's tail.
class SeamAuditionPlayer {
  SeamAuditionPlayer({
    required this.player,
    required double start,
    required double end,
    required AuditionPreferences options,
    required this.isCurrent,
    required this.onDone,
    required this.onError,
    this.muted = false,
  }) : session = LoopAuditionSession(start: start, end: end, options: options);
  final Player player;
  final LoopAuditionSession session;
  final bool Function() isCurrent;
  final void Function() onDone;
  final void Function(Object) onError;
  final bool muted;
  StreamSubscription<Duration>? _position;
  StreamSubscription<bool>? _completed;
  Timer? _completionWatch;
  bool _closed = false;
  bool _busy = false;
  bool _nativeLoop = false;
  bool _armed = false;
  int _version = 0;
  bool get active => !_closed && session.phase != AuditionPhase.finished;
  bool get _valid => !_closed && isCurrent();

  Future<bool> _property(String name, String value) async {
    if (!_valid || player.platform is! NativePlayer) return false;
    try {
      await (player.platform as dynamic).setProperty(name, value);
      return _valid;
    } on Object {
      return false;
    }
  }

  Future<void> _seek(double position) async {
    if (!_valid) return;
    final native = player.platform;
    if (native is NativePlayer) {
      try {
        await (native as dynamic).command([
          'seek',
          position.toStringAsFixed(6),
          'absolute+exact',
        ]);
        native.state = native.state.copyWith(completed: false);
        return;
      } on Object {
        /* Fall back to the public player API. */
      }
    }
    if (_valid) {
      await player.seek(Duration(microseconds: (position * 1000000).round()));
    }
  }

  Future<void> start() async {
    // Some native players omit a second completed-stream edge after an end-bound seek.
    _completionWatch = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_valid || _busy || !_armed || !player.state.completed) return;
      if (session.phase == AuditionPhase.after) {
        _dispatch(session.completeCycle());
      } else if (session.phase == AuditionPhase.before) {
        unawaited(_joinFallback());
      }
    });
    _position = player.stream.position.listen(
      (p) => _observe(p.inMicroseconds / 1000000),
    );
    _completed = player.stream.completed.listen((done) {
      if (!done || !_valid || _busy || !_armed) return;
      if (session.phase == AuditionPhase.after) {
        _dispatch(session.completeCycle());
      } else if (session.phase == AuditionPhase.before) {
        unawaited(_joinFallback());
      }
    });
    await _restart();
  }

  Future<void> _restart() async {
    if (!_valid) return;
    _busy = true;
    _armed = false;
    final token = ++_version;
    try {
      await player.pause();
      await _property('end', 'none');
      await _property('ab-loop-a', 'no');
      await _property('ab-loop-b', 'no');
      _nativeLoop = await _property(
        'ab-loop-a',
        session.start.toStringAsFixed(6),
      );
      _nativeLoop =
          await _property('ab-loop-b', session.end.toStringAsFixed(6)) &&
          _nativeLoop;
      if (!_valid || token != _version) return;
      if (session.completed == 0) {
        await player.setVolume(muted ? 0 : session.options.volume);
      }
      await _seek(session.auditionStart);
      if (!_valid || token != _version) return;
      session.restart();
      if (Platform.environment['FH_RADIO_STUDIO_PREVIEW_DIAGNOSTICS'] == '1') {
        stderr.writeln(
          'SEAM_AUDITION start=${session.auditionStart} A=${session.start} B=${session.end} after=${session.afterEnd} completed=${session.completed}',
        );
      }
      _busy = false;
      await player.play();
    } on Object catch (e) {
      if (_valid) onError(e);
      await cancel();
    } finally {
      if (token == _version) _busy = false;
    }
  }

  void _observe(double seconds) {
    if (!_valid || _busy || !player.state.playing) return;
    if (!_armed) {
      if (seconds < session.auditionStart - .3 || seconds > session.end + .3) {
        return;
      }
      _armed = true;
    }
    final event = session.observe(seconds);
    if (event == AuditionEvent.joined) {
      if (Platform.environment['FH_RADIO_STUDIO_PREVIEW_DIAGNOSTICS'] == '1') {
        stderr.writeln(
          'SEAM_AUDITION joined position=$seconds completed=${session.completed}',
        );
      }
      unawaited(_boundTail());
    } else if (event != AuditionEvent.none) {
      _dispatch(event);
    } else if (!_nativeLoop &&
        session.phase == AuditionPhase.before &&
        seconds >= session.end - .025) {
      unawaited(_joinFallback());
    }
  }

  Future<void> _boundTail() async {
    if (!_valid || session.phase != AuditionPhase.after) return;
    final token = _version;
    await _property('ab-loop-a', 'no');
    if (token != _version || session.phase != AuditionPhase.after) return;
    await _property('ab-loop-b', 'no');
    if (token != _version || session.phase != AuditionPhase.after) return;
    await _property('end', session.afterEnd.toStringAsFixed(6));
  }

  Future<void> _joinFallback() async {
    if (!_valid || _busy || session.phase != AuditionPhase.before) return;
    _busy = true;
    try {
      session.join();
      await _seek(session.start);
      await _boundTail();
      if (_valid) await player.play();
    } on Object catch (e) {
      if (_valid) onError(e);
    } finally {
      _busy = false;
    }
  }

  void _dispatch(AuditionEvent event) {
    if (event == AuditionEvent.repeat) {
      unawaited(_restart());
    } else if (event == AuditionEvent.finished) {
      unawaited(_finish());
    }
  }

  Future<void> _finish() async {
    if (!_valid) return;
    await player.pause();
    if (!_valid) return;
    if (Platform.environment['FH_RADIO_STUDIO_PREVIEW_DIAGNOSTICS'] == '1') {
      stderr.writeln('SEAM_AUDITION finished completed=${session.completed}');
    }
    await cancel();
    if (isCurrent()) onDone();
  }

  Future<void> cancel() async {
    if (_closed) return;
    _closed = true;
    _version++;
    _completionWatch?.cancel();
    await _position?.cancel();
    await _completed?.cancel();
    if (!isCurrent() || player.platform is! NativePlayer) return;
    try {
      await (player.platform as dynamic).setProperty('end', 'none');
      if (!isCurrent()) return;
      await (player.platform as dynamic).setProperty('ab-loop-a', 'no');
      if (!isCurrent()) return;
      await (player.platform as dynamic).setProperty('ab-loop-b', 'no');
    } on Object {
      /* Playback owner also clears bounds when starting other modes. */
    }
  }
}
