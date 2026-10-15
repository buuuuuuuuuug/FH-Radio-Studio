import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fh_radio_studio/domain/replacement_models.dart';
import 'package:fh_radio_studio/state/app_state.dart';
import 'package:fh_radio_studio/theme/app_theme.dart';
import 'package:fh_radio_studio/theme/accents.dart';
import 'package:fh_radio_studio/widgets/custom_accent_dialog.dart';
import 'package:fh_radio_studio/widgets/smooth_scroll_to_top.dart';
import 'package:fh_radio_studio/screens/playlist/radio_column.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  testWidgets(
    'playlist pool offers its own return without moving other stations',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(
            brightness: Brightness.light,
            accent: AppAccent.lime,
          ),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 280,
                height: 500,
                child: PlaylistColumn.poolBuilder(
                  count: 229,
                  itemCount: 229,
                  itemBuilder: (_, i) =>
                      SizedBox(height: 60, child: Text('track $i')),
                ),
              ),
            ),
          ),
        ),
      );
      final list = tester.widget<ListView>(find.byType(ListView));
      list.controller!.jumpTo(4000);
      await tester.pumpAndSettle();
      expect(find.text('回到顶部'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('scroll-to-top-button')));
      await tester.pumpAndSettle();
      expect(list.controller!.offset, 0);
      expect(find.text('池子'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'quiet audio and dynamics remain proportional rather than stretched to full height',
    () {
      final input = [0.0, .08, .12, .24, .36, .48, .52, .6, .65];
      expect(WaveformBars.fromValues(input).values, input);
      expect(
        WaveformBars.fromValues(
          List.filled(8192, .35),
        ).values.every((v) => v == .35),
        isTrue,
      );
    },
  );
  test(
    'custom colors persist and preset reset leaves no stale override',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final n = CustomAccentNotifier(prefs);
      n.set(const Color(0xFF123ABC));
      final loaded = CustomAccentNotifier(prefs);
      expect(loaded.state, const Color(0xFF123ABC));
      expect(
        accentColors(
          AppAccent.lime,
          Brightness.light,
          customColor: loaded.state,
        ).base,
        loaded.state,
      );
      expect(
        accentColors(
          AppAccent.lime,
          Brightness.light,
          customColor: Colors.yellow,
        ).onAccent,
        const Color(0xFF0A0A0B),
      );
      n.set(null);
      expect(CustomAccentNotifier(prefs).state, isNull);
      n.dispose();
      loaded.dispose();
    },
  );
  testWidgets('hex picker accepts arbitrary color and rejects invalid input', (
    tester,
  ) async {
    Color? chosen;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(
          brightness: Brightness.light,
          accent: AppAccent.lime,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                chosen = await showDialog<Color>(
                  context: context,
                  builder: (_) =>
                      const CustomAccentDialog(initial: Colors.green),
                );
              },
              child: const Text('pick'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('custom-accent-hex'));
    await tester.enterText(field, 'invalid');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('请输入六位颜色，例如 #23A136'), findsOneWidget);
    await tester.enterText(field, '#12AB34');
    await tester.tap(find.text('应用颜色'));
    await tester.pumpAndSettle();
    expect(chosen, const Color(0xFF12AB34));
  });
  testWidgets(
    'deep scroll return avoids building intervening thousands of rows',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final visited = <int>{};
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(
            brightness: Brightness.light,
            accent: AppAccent.lime,
          ),
          home: Scaffold(
            body: SmoothScrollToTop(
              controller: scroll,
              child: ListView.builder(
                controller: scroll,
                itemCount: 5000,
                itemExtent: 70,
                itemBuilder: (_, i) {
                  visited.add(i);
                  return Text('song $i');
                },
              ),
            ),
          ),
        ),
      );
      scroll.jumpTo(200000);
      await tester.pump();
      visited.clear();
      await tester.tap(find.byKey(const ValueKey('scroll-to-top-button')));
      for (var i = 0; i < 24; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      expect(visited.length, lessThan(50));
      expect(find.text('回到顶部'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
