import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:fh_radio_studio/domain/waveform_envelope.dart';

void main() {
  test(
    'waveform fills its background while retaining dynamics and input data',
    () {
      final raw = [0.0, .1, .2, .4, .6, .35];
      final saved = [...raw];
      final display = waveformDisplayEnvelope(raw, duration: 180);
      expect(display.reduce(math.max), closeTo(.92, 1e-12));
      expect(display[1] / display[4], closeTo(1 / 6, 1e-12));
      expect(display[2] / display[3], closeTo(.5, 1e-12));
      expect(display.where((v) => v >= .919).length, 1);
      expect(display.first, 0);
      expect(raw, saved);
      for (final height in [130.0, 180.0]) {
        expect(
          display.reduce(math.max) * (height - 8) / height,
          greaterThan(.85),
        );
        expect(display.reduce(math.max) * (height - 8) / height, lessThan(.9));
      }
      expect(
        waveformDisplayEnvelope([for (final v in raw) v * .2], duration: 180),
        pairwiseCompare(
          display,
          (double a, double b) => (a - b).abs() < 1e-12,
          'same shape at different levels',
        ),
      );
    },
  );
  test(
    'silence remains silent and detailed zoom does not flatten distinct peaks',
    () {
      expect(
        waveformDisplayEnvelope(List.filled(8192, 0), duration: 180),
        List.filled(512, 0),
      );
      expect(waveformDisplayEnvelope([], duration: 180), isEmpty);
      final detailed = List.generate(8192, (i) => .1 + (i % 127) / 500);
      final display = waveformDisplayEnvelope(
        detailed,
        duration: 180,
        windowStart: 30,
        windowEnd: 90,
      );
      expect(display.length, 512);
      expect(display.reduce(math.max), closeTo(.92, 1e-12));
      expect(display.toSet().length, greaterThan(100));
      expect(display.every((v) => v >= 0 && v <= .92), isTrue);
    },
  );
}
