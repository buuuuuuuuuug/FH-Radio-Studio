import 'dart:ui' show SemanticsAction;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fh_radio_studio/widgets/rm_slider.dart';

void main() {
  testWidgets(
    'Windows slider drags, clamps, snaps and accepts keyboard input',
    (t) async {
      double value = 5;
      final starts = <double>[];
      final ends = <double>[];
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => Center(
                child: SizedBox(
                  width: 300,
                  child: RmSlider(
                    value: value,
                    min: 0,
                    max: 10,
                    divisions: 10,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    onChanged: (v) => update(() => value = v),
                    onChangeStart: starts.add,
                    onChangeEnd: ends.add,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final rect = t.getRect(find.byType(RmSlider));
      final drag = await t.startGesture(Offset(rect.left + 72, rect.center.dy));
      await t.pump();
      expect(value, 2);
      await drag.moveTo(Offset(rect.right + 50, rect.center.dy));
      await t.pump();
      expect(value, 10);
      await drag.up();
      await t.pump();
      expect(starts, [5]);
      expect(ends, [10]);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pump();
      expect(value, 9);
      await t.sendKeyEvent(LogicalKeyboardKey.home);
      await t.pump();
      expect(value, 0);
      await t.sendKeyEvent(LogicalKeyboardKey.end);
      await t.pump();
      expect(value, 10);
      expect(t.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'Windows slider exposes functional accessible increment and decrement',
    (t) async {
      final semantics = t.ensureSemantics();
      try {
        double value = 50;
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, update) => RmSlider(
                  label: 'Quality',
                  value: value,
                  min: 0,
                  max: 100,
                  divisions: 100,
                  semanticFormatterCallback: (v) => v.round().toString(),
                  onChanged: (v) => update(() => value = v),
                ),
              ),
            ),
          ),
        );
        final node = t.getSemantics(find.bySemanticsLabel('Quality'));
        expect(node.getSemanticsData().value, '50');
        node.owner!.performAction(node.id, SemanticsAction.increase);
        await t.pump();
        expect(value, 51);
        node.owner!.performAction(node.id, SemanticsAction.decrease);
        await t.pump();
        expect(value, 50);
        expect(t.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'disabled Windows slider ignores input and dialog disposal keeps semantics valid',
    (t) async {
      final semantics = t.ensureSemantics();
      try {
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    const RmSlider(value: 0, min: 0, max: 0, onChanged: null),
                    TextButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          content: SizedBox(
                            width: 300,
                            child: RmSlider(
                              value: 50,
                              min: 1,
                              max: 100,
                              divisions: 99,
                              onChanged: (_) {},
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      ),
                      child: const Text('Open'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await t.tap(find.byType(RmSlider));
        await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await t.pump();
        expect(
          t
              .getSemantics(find.byType(RmSlider))
              .getSemanticsData()
              .hasAction(SemanticsAction.increase),
          isFalse,
        );
        await t.tap(find.text('Open'));
        await t.pumpAndSettle();
        await t.tap(find.text('Close'));
        await t.pumpAndSettle();
        expect(find.byType(RmSlider), findsOneWidget);
        expect(t.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
