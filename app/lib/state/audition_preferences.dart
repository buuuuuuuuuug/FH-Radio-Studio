import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_state.dart';

class AuditionPreferences {
  const AuditionPreferences({
    this.before = 2,
    this.after = 2,
    this.repetitions = 1,
    this.volume = 100,
  });
  final double before;
  final double after;
  final int repetitions;
  final double volume;
  AuditionPreferences copyWith({
    double? before,
    double? after,
    int? repetitions,
    double? volume,
  }) => AuditionPreferences(
    before: (before ?? this.before).clamp(.5, 10).toDouble(),
    after: (after ?? this.after).clamp(.5, 10).toDouble(),
    repetitions: (repetitions ?? this.repetitions).clamp(0, 10),
    volume: (volume ?? this.volume).clamp(0, 100).toDouble(),
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
    );
  }
  final Ref ref;
  void update({
    double? before,
    double? after,
    int? repetitions,
    double? volume,
  }) {
    state = state.copyWith(
      before: before,
      after: after,
      repetitions: repetitions,
      volume: volume,
    );
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setDouble('rm.audition.before', state.before);
    prefs.setDouble('rm.audition.after', state.after);
    prefs.setInt('rm.audition.repetitions', state.repetitions);
    prefs.setDouble('rm.audition.volume', state.volume);
  }
}

final auditionPreferencesProvider =
    StateNotifierProvider<AuditionPreferencesController, AuditionPreferences>(
      (ref) => AuditionPreferencesController(ref),
    );
