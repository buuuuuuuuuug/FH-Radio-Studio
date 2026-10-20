import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fh_radio_studio/state/layout_options.dart';
import 'package:fh_radio_studio/widgets/waveform_zoom_gesture.dart';

void main() {
  test(
    'grid options persist independently and auto heights follow row count',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = LayoutOptionsController(prefs);
      c.setRadioColumns(3);
      c.setHeightMode(RadioHeightMode.allStations);
      c.setWidth(-1);
      expect(c.state.heightFor(720, 9, 3), 232);
      expect(c.state.heightFor(720, 9, 2), 180);
      expect(c.state.heightFor(100, 9, 2), 180);
      c.setHeightMode(RadioHeightMode.oneRow);
      expect(c.state.heightFor(720, 9, 3), 720);
      c.setRadioColumns(6);
      expect(c.state.canvasWidth(300), 300);
      expect(c.state.columnsFor(300), 1);
      c.setRadioHeight(140);
      expect(c.state.heightMode, RadioHeightMode.manual);
      c.dispose(); // Flush the intentionally buffered slider preferences.
      final loaded = LayoutOptionsController(prefs);
      expect(loaded.state.radioHeight, 160);
      expect(loaded.state.radioColumns, 6);
      expect(loaded.state.width, -1);
      expect(loaded.state.heightMode, RadioHeightMode.manual);
      loaded.dispose();
    },
  );

  testWidgets(
    'Ctrl wheel zooms without moving page, normal wheel scrolls page',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final factors = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  WaveformZoomGesture(
                    onZoom: factors.add,
                    child: const SizedBox(
                      key: ValueKey('wave'),
                      height: 250,
                      width: 600,
                    ),
                  ),
                  const SizedBox(height: 2000),
                ],
              ),
            ),
          ),
        ),
      );
      final position = tester.getCenter(find.byKey(const ValueKey('wave')));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: position,
          scrollDelta: const Offset(0, -120),
        ),
      );
      await tester.pump();
      expect(factors.single, lessThan(1));
      expect(scroll.offset, 0);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: position,
          scrollDelta: const Offset(0, 120),
        ),
      );
      await tester.pump();
      expect(factors.last, greaterThan(1));
      expect(scroll.offset, 0);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: position,
          scrollDelta: const Offset(0, 100),
        ),
      );
      await tester.pump();
      expect(factors.length, 2);
      expect(scroll.offset, greaterThan(0));
    },
  );
}
