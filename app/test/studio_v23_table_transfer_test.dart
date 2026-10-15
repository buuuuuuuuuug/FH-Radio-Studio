import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fh_radio_studio/state/library_columns.dart';
import 'package:fh_radio_studio/state/editor_shortcuts.dart';
import 'package:fh_radio_studio/state/custom_pool_tracks.dart';
import 'package:fh_radio_studio/screens/custom_pool.dart';
import 'package:fh_radio_studio/screens/playlist/radio_column.dart';
import 'package:fh_radio_studio/domain/radio_library.dart';
import 'package:fh_radio_studio/widgets/rm_button.dart';
import 'package:fh_radio_studio/widgets/timing_match_modes.dart';
import 'editor_playlist_upgrade_test.dart' as fixture;
import 'studio_v21_workflow_test.dart' as helpers;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  test(
    'restore default migrates Home once and respects newer custom choices',
    () async {
      SharedPreferences.setMockInitialValues({
        'editor.shortcuts.version': 2,
        'editor.shortcuts.v1':
            '{"restoreSaved":{"key":${LogicalKeyboardKey.home.keyId},"ctrl":true}}',
      });
      final prefs = await SharedPreferences.getInstance();
      final ctl = EditorShortcutController(prefs);
      expect(ctl.state[EditorAction.restoreSaved]!.label, 'Ctrl + H');
      ctl.save({
        ...ctl.state,
        EditorAction.restoreSaved: const EditorChord(
          LogicalKeyboardKey.home,
          ctrl: true,
        ),
      });
      final restored = EditorShortcutController(prefs);
      expect(restored.state[EditorAction.restoreSaved]!.label, 'Ctrl + Home');
      restored.dispose();
      ctl.dispose();
      expect(
        timingCsvTemplate.split('\n').first,
        'Filename,TD,PD,TL-A,TL-B,PL-A,PL-B',
      );
    },
  );
  test(
    'column fitting and dragging respect minima, total width and saved settings',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final ctl = LibraryColumnsController(prefs);
      const specs = [
        LibraryColumnSpec('song', 100, 300),
        LibraryColumnSpec('preview', 144, 160),
        LibraryColumnSpec('actions', 80, 100),
      ];
      final widths = fitLibraryColumns(650, specs, {});
      ctl.resize(specs, widths, 0, -10000);
      expect(ctl.state['song'], 100);
      expect(ctl.state.values.reduce((a, b) => a + b), closeTo(650, .001));
      ctl.flush();
      final loaded = LibraryColumnsController(prefs);
      expect(loaded.state, ctl.state);
      final fit = fitLibraryColumns(400, specs, loaded.state);
      expect(fit.values.reduce((a, b) => a + b), closeTo(400, .001));
      for (final s in specs) {
        expect(fit[s.id], greaterThanOrEqualTo(s.minimum));
      }
      loaded.dispose();
      ctl.reset();
      ctl.dispose();
    },
  );
  testWidgets(
    'library header dragging resizes rows, export appears and narrow layout fits',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1500, 1050);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final previousError = FlutterError.onError;
      FlutterError.onError = (details) {
        FlutterError.dumpErrorToConsole(details);
        previousError?.call(details);
      };
      addTearDown(() => FlutterError.onError = previousError);
      final f = await fixture.fixture();
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: helpers.app(const CustomPoolScreen()),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('导出时间点'), findsOneWidget);
      final grip = find.byKey(const ValueKey('pool-column-grip-song'));
      await Scrollable.ensureVisible(t.element(grip));
      await t.pumpAndSettle();
      final before = t.getSize(find.text('Song').first).width;
      await t.drag(grip, const Offset(-80, 0));
      await t.pumpAndSettle();
      await t.pump(const Duration(milliseconds: 300));
      expect(f.container.read(libraryColumnsProvider), isNotEmpty);
      expect(t.getSize(find.text('Song').first).width, lessThan(before));
      for (final width in [960.0, 720.0, 420.0]) {
        t.view.physicalSize = Size(width, 1050);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      }
    },
  );
  testWidgets(
    'radio list creates visible cards only and preview stop icon stays centered',
    (t) async {
      var count = 0;
      await t.pumpWidget(
        helpers.app(
          Center(
            child: SizedBox(
              width: 300,
              height: 420,
              child: PlaylistColumn.radioBuilder(
                radio: kRadios.first,
                isCustom: true,
                count: 1000,
                itemCount: 1000,
                itemBuilder: (_, i) {
                  count++;
                  return SizedBox(height: 52, child: Text('Track $i'));
                },
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(count, lessThan(25));
      await t.pumpWidget(
        helpers.app(
          Center(
            child: SizedBox(
              width: 36,
              child: RmButton(
                onPressed: () {},
                size: RmButtonSize.sm,
                horizontalPadding: 3,
                foregroundColor: Colors.grey,
                leading: const Icon(Icons.stop, size: 10),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        (t.getCenter(find.byIcon(Icons.stop)) -
                t.getCenter(find.byType(RmButton)))
            .distance,
        lessThan(.6),
      );
      expect(t.takeException(), isNull);
    },
  );
  test('source date includes hours and minutes', () {
    final dir = Directory.systemTemp.createTempSync('timing-date-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}/song.wav')..writeAsStringSync('test');
    f.setLastModifiedSync(DateTime(2026, 10, 15, 9, 7));
    expect(modifiedLabel(f), '2026-10-15 09:07');
  });
}
