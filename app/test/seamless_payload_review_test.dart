import 'package:flutter_test/flutter_test.dart';
import 'package:fh_radio_studio/state/seamless_loop_state.dart';

void main() {
  test('loop suggestions skip damaged entries and retain valid intervals', () {
    final result = seamlessCandidatesFromPayload({
      'duration_sec': 120,
      'candidates': {
        'tl': [
          null,
          {'start': 'bad', 'end': 80, 'score': .9},
          {'start': 10, 'end': 80, 'score': double.nan},
          {'start': 10, 'end': 130, 'score': .9},
          {'start': 80, 'end': 10, 'score': .9},
          {'start': 10, 'end': 80, 'score': .9, 'why': 'valid'},
        ],
      },
    });
    expect(result, hasLength(1));
    expect(result.single.start, 10);
    expect(result.single.end, 80);
    expect(result.single.score, .9);
  });

  for (final duration in [null, '120', 0, -1, double.nan, double.infinity]) {
    test('loop suggestions reject invalid duration $duration', () {
      expect(
        () => seamlessCandidatesFromPayload({
          'duration_sec': duration,
          'candidates': {
            'tl': [
              {'start': 10, 'end': 20, 'score': .9},
            ],
          },
        }),
        throwsFormatException,
      );
    });
  }

  test('loop suggestions reject missing candidates with a readable error', () {
    expect(
      () => seamlessCandidatesFromPayload({'duration_sec': 120}),
      throwsFormatException,
    );
  });
}
