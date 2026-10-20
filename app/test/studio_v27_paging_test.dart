import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fh_radio_studio/core/playback_window.dart';
import 'package:fh_radio_studio/state/layout_options.dart';
import 'package:fh_radio_studio/screens/custom_pool.dart';
import 'package:fh_radio_studio/state/custom_pool_tracks.dart';
import 'package:fh_radio_studio/widgets/rm_button.dart';
import 'editor_playlist_upgrade_test.dart' as fixture;
import 'studio_v21_workflow_test.dart' as helpers;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  test(
    'playback pages only near edges, preserves overlap and clamps jumps',
    () {
      ({double start, double end}) view(
        double p, {
        double start = 40,
        double end = 60,
      }) => pagedPlaybackWindow(
        duration: 200,
        start: start,
        end: end,
        playhead: p,
      );
      for (final p in [43.0, 50.0, 57.9]) {
        expect(view(p), (start: 40.0, end: 60.0));
      }
      final next = view(58.1);
      expect(next, (start: 56.1, end: 76.1));
      expect(view(59, start: next.start, end: next.end), next);
      expect(view(41.9), (start: 23.9, end: 43.9));
      expect(view(150), (start: 148.0, end: 168.0));
      expect(view(0), (start: 0.0, end: 20.0));
      expect(view(200), (start: 180.0, end: 200.0));
      expect(view(50, start: 0, end: 200), (start: 0.0, end: 200.0));
    },
  );
  testWidgets(
    'dates shrink to content and action buttons follow their divider',
    (t) async {
      t.view.physicalSize = const Size(1800, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final f = await fixture.fixture();
      f.container.read(layoutOptionsProvider.notifier).setWidth(-1);
      final id = f.container.read(realPoolTracksProvider).first.id;
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: helpers.app(const CustomPoolScreen()),
        ),
      );
      await t.pumpAndSettle();
      Finder value(String column) =>
          find.byKey(ValueKey('pool-value-$column:$id')).first;
      Future<void> resize(String column, double delta) async {
        final grip = find.byKey(ValueKey('pool-column-grip-$column'));
        await Scrollable.ensureVisible(t.element(grip));
        await t.pumpAndSettle();
        await t.drag(grip, Offset(delta, 0));
        await t.pumpAndSettle();
      }

      await resize('added', -200);
      expect(t.getSize(value('added')).width, closeTo(112, .1));
      await resize('modified', -200);
      expect(t.getSize(value('modified')).width, closeTo(112, .1));
      Future<void> checkActions() async {
        final label = find.byKey(const ValueKey('pool-column-title-actions'));
        final grip = find.byKey(const ValueKey('pool-column-grip-preview'));
        final actions = value('actions');
        final firstButton = find
            .descendant(of: actions, matching: find.byType(RmButton))
            .first;
        expect(t.getTopLeft(label).dx, closeTo(t.getTopLeft(actions).dx, .1));
        expect(
          t.getTopLeft(firstButton).dx,
          closeTo(t.getTopLeft(label).dx, .1),
        );
        expect(t.getTopLeft(label).dx - t.getCenter(grip).dx, closeTo(8, .1));
      }

      await checkActions();
      await resize('preview', -30);
      await checkActions();
      await resize('preview', 60);
      await checkActions();
      expect(
        find.byKey(const ValueKey('pool-column-grip-actions')),
        findsNothing,
      );
      expect(t.takeException(), isNull);
    },
  );
}
