import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_state.dart';

class AuditionPreferences {
  const AuditionPreferences({
    this.before = 2,
    this.after = 2,
    this.repetitions = 1,
    this.volume = 100,
    this.tdDuration = 6,
    this.pdDuration = 6,
  });
  final double before;
  final double after;
  final int repetitions;
  final double volume;
  final double tdDuration;
  final double pdDuration;
  double pointDuration(bool postDrop) => postDrop ? pdDuration : tdDuration;
  AuditionPreferences copyWith({
    double? before,
    double? after,
    int? repetitions,
    double? volume,
    double? tdDuration,
    double? pdDuration,
  }) => AuditionPreferences(
    before: (before ?? this.before).clamp(.5, 10).toDouble(),
    after: (after ?? this.after).clamp(.5, 10).toDouble(),
    repetitions: (repetitions ?? this.repetitions).clamp(0, 10),
    volume: (volume ?? this.volume).clamp(0, 100).toDouble(),
    tdDuration: (tdDuration ?? this.tdDuration).clamp(1, 30).toDouble(),
    pdDuration: (pdDuration ?? this.pdDuration).clamp(1, 30).toDouble(),
  );
}

class AuditionPreferencesController extends StateNotifier<AuditionPreferences> {
  AuditionPreferencesController(this.ref) : super(const AuditionPreferences()) {
    final prefs = ref.read(sharedPreferencesProvider);
    state = state.copyWith(
      before: prefs.getDouble('rm.audition.before'),
      after: prefs.getDouble('rm.audition.after'),
      repetitions: prefs.getInt('rm.audition.repetitions'),
      volume: prefs.getDouble('rm.audition.volume'),
      tdDuration: prefs.getDouble('rm.audition.tdDuration'),
      pdDuration: prefs.getDouble('rm.audition.pdDuration'),
    );
  }
  final Ref ref;
  void update({
    double? before,
    double? after,
    int? repetitions,
    double? volume,
    double? tdDuration,
    double? pdDuration,
  }) {
    state = state.copyWith(
      before: before,
      after: after,
      repetitions: repetitions,
      volume: volume,
      tdDuration: tdDuration,
      pdDuration: pdDuration,
    );
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setDouble('rm.audition.before', state.before);
    prefs.setDouble('rm.audition.after', state.after);
    prefs.setInt('rm.audition.repetitions', state.repetitions);
    prefs.setDouble('rm.audition.volume', state.volume);
    prefs.setDouble('rm.audition.tdDuration', state.tdDuration);
    prefs.setDouble('rm.audition.pdDuration', state.pdDuration);
  }
}

final auditionPreferencesProvider =
    StateNotifierProvider<AuditionPreferencesController, AuditionPreferences>(
      (ref) => AuditionPreferencesController(ref),
    );
