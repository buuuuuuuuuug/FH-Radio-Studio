import '../state/audition_preferences.dart';

enum AuditionPhase { before, after, finished }

enum AuditionEvent { none, joined, finished }

class LoopAuditionSession {
  LoopAuditionSession({
    required this.start,
    required this.end,
    required this.options,
  });
  final double start;
  final double end;
  final AuditionPreferences options;
  AuditionPhase phase = AuditionPhase.before;
  int completed = 0;
  double? _previous;
  double get auditionStart =>
      (end - options.before).clamp(start, end).toDouble();
  double get afterEnd => (start + options.after).clamp(start, end).toDouble();
  AuditionEvent observe(double position) {
    final previous = _previous;
    _previous = position;
    if (phase == AuditionPhase.before &&
        previous != null &&
        previous >= auditionStart - .3 &&
        position < previous - .3 &&
        position <= afterEnd + .3) {
      phase = AuditionPhase.after;
      return AuditionEvent.joined;
    }
    if (phase == AuditionPhase.after && position >= afterEnd - .025) {
      return completeCycle();
    }
    return AuditionEvent.none;
  }

  void join() {
    phase = AuditionPhase.after;
    _previous = start;
  }

  AuditionEvent completeCycle() {
    if (phase != AuditionPhase.after) return AuditionEvent.none;
    completed++;
    phase = AuditionPhase.finished;
    return AuditionEvent.finished;
  }

  void restart() {
    phase = AuditionPhase.before;
    _previous = null;
  }
}
