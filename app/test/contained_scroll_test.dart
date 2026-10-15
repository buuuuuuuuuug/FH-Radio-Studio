import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fh_radio_studio/widgets/contained_scroll.dart';

void main() {
  testWidgets(
    'inner wheel remains contained at both ends; margin scrolls outer',
    (tester) async {
      final outer = ScrollController();
      final inner = ScrollController();
      addTearDown(outer.dispose);
      addTearDown(inner.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContainedScroll(
              controller: outer,
              child: SingleChildScrollView(
                controller: outer,
                child: Column(
                  children: [
                    SizedBox(
                      height: 300,
                      child: Row(
                        children: [
                          const SizedBox(width: 60),
                          SizedBox(
                            width: 220,
                            child: ContainedScroll(
                              controller: inner,
                              child: ListView(
                                controller: inner,
                                children: List.generate(
                                  20,
                                  (i) => SizedBox(
                                    height: 40,
                                    child: Text('song $i'),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 1600),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      Future<void> wheel(Offset position, double delta) async {
        tester.binding.handlePointerEvent(
          PointerScrollEvent(position: position, scrollDelta: Offset(0, delta)),
        );
        await tester.pump();
      }

      await wheel(const Offset(150, 150), -100);
      expect(outer.offset, 0);
      await wheel(const Offset(150, 150), 900);
      expect(inner.offset, inner.position.maxScrollExtent);
      expect(outer.offset, 0);
      await wheel(const Offset(150, 150), 100);
      expect(outer.offset, 0);
      await wheel(const Offset(20, 150), 100);
      expect(outer.offset, 100);
      expect(tester.takeException(), isNull);
    },
  );
}
