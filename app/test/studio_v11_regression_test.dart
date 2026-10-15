import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fh_radio_studio/domain/waveform_envelope.dart';
import 'package:fh_radio_studio/widgets/accent_color_wheel.dart';
import 'package:fh_radio_studio/widgets/custom_accent_dialog.dart';
import 'package:fh_radio_studio/theme/app_theme.dart';
import 'package:fh_radio_studio/theme/accents.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  test(
    'original density is retained without flattening detailed cached audio',
    () {
      final old = List.generate(512, (i) => i / 512);
      expect(waveformEnvelope(old, duration: 240), old);
      final detailed = [for (final v in old) ...List.filled(16, v)];
      expect(waveformEnvelope(detailed, duration: 240), old);
      expect(
        waveformEnvelope(List.filled(8192, .35), duration: 240),
        everyElement(closeTo(.35, 1e-12)),
      );
      final zoom = waveformEnvelope(
        detailed,
        duration: 240,
        windowStart: 60,
        windowEnd: 120,
      );
      expect(zoom.length, 512);
      expect(zoom.first, closeTo(.25, .001));
      expect(zoom.last, closeTo(.5, .003));
      expect(waveformEnvelope([], duration: 10), isEmpty);
      expect(waveformEnvelope([.4], duration: 10), [.4]);
    },
  );
  testWidgets('color wheel drag clamps saturation and retains brightness', (
    tester,
  ) async {
    HSVColor? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AccentColorWheel(
              value: const HSVColor.fromAHSV(1, 120, .5, .6),
              onChanged: (v) => chosen = v,
            ),
          ),
        ),
      ),
    );
    final center = tester.getCenter(find.byType(AccentColorWheel));
    await tester.tapAt(center + const Offset(60, 0));
    expect(chosen!.hue, closeTo(0, .01));
    expect(chosen!.saturation, closeTo(60 / 81, .01));
    expect(chosen!.value, .6);
    final gesture = await tester.startGesture(center);
    await gesture.moveTo(center + const Offset(0, 140));
    await gesture.up();
    expect(chosen!.hue, closeTo(90, .01));
    expect(chosen!.saturation, 1);
  });
  testWidgets('wheel, hex entry and apply stay synchronized in short windows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Color? applied;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(
          brightness: Brightness.light,
          accent: AppAccent.lime,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('open'),
              onPressed: () async {
                applied = await showDialog<Color>(
                  context: context,
                  builder: (_) =>
                      const CustomAccentDialog(initial: Colors.green),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final wheel = find.byKey(const ValueKey('custom-accent-wheel'));
    await tester.tapAt(tester.getCenter(wheel) + const Offset(81, 0));
    await tester.pump();
    final hex = find.byKey(const ValueKey('custom-accent-hex'));
    expect(tester.widget<TextField>(hex).controller!.text, startsWith('#'));
    await tester.enterText(hex, '#123ABC');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(
      tester.widget<AccentColorWheel>(wheel).value.toColor(),
      const Color(0xFF123ABC),
    );
    await tester.tap(find.text('应用颜色'));
    await tester.pumpAndSettle();
    expect(applied, const Color(0xFF123ABC));
    expect(tester.takeException(), isNull);
  });
}
