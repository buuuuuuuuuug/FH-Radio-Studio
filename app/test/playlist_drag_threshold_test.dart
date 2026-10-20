import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fh_radio_studio/domain/radio_library.dart';
import 'package:fh_radio_studio/screens/playlist.dart';
import 'package:fh_radio_studio/screens/playlist/playlist_state.dart';
import 'package:fh_radio_studio/screens/playlist/track_card.dart';
import 'package:fh_radio_studio/screens/playlist/playlist_draggable.dart';
import 'package:fh_radio_studio/screens/playlist/playlist_drag_preview.dart';
import 'package:fh_radio_studio/state/playlist_plan_state.dart';
import 'studio_v18_workflow_test.dart' as fixtures;
import 'studio_v21_workflow_test.dart' as helpers;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  testWidgets('a sole drag recognizer waits for movement, not a timer', (
    t,
  ) async {
    await t.pumpWidget(
      helpers.app(
        Center(
          child: PlaylistDraggable<String>(
            data: 'song',
            feedback: const Text('floating'),
            child: const SizedBox(width: 180, height: 60, child: Text('song')),
          ),
        ),
      ),
    );
    final gesture = await t.startGesture(
      t.getCenter(find.text('song')),
      kind: PointerDeviceKind.mouse,
    );
    await t.pump(const Duration(seconds: 1));
    expect(find.text('floating'), findsNothing);
    await gesture.moveBy(const Offset(8, 0));
    await t.pump();
    expect(find.text('floating'), findsNothing);
    await gesture.moveBy(const Offset(3, 0));
    await t.pump();
    expect(find.text('floating'), findsOneWidget);
    await gesture.cancel();
    await t.pump();
    expect(find.text('floating'), findsNothing);
    expect(t.takeException(), isNull);
  });
  for (final pool in [true, false]) {
    testWidgets(
      '${pool ? 'pool' : 'station'} clicks select immediately and only movement floats the selected group',
      (t) async {
        t.view.physicalSize = const Size(1800, 1100);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final c = await fixtures.fixture();
        c
            .read(playlistProvider.notifier)
            .assignManyToRadio(
              kCustomPool.take(4).map((s) => s.id).toList(),
              'R1',
              'FreeRoam',
              maxSlots: 10,
            );
        final before = c.read(playlistPlanProvider).encodeForCli();
        await t.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: helpers.app(const PlaylistScreen()),
          ),
        );
        await t.pumpAndSettle();
        if (pool) {
          await t.tap(
            find.byKey(const ValueKey('playlist-multiselect-toggle')),
          );
          await t.pump();
        } else {
          await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        }
        Finder cards() => find.descendant(
          of: find.byKey(
            ValueKey(
              pool ? 'playlist-pool-side-panel' : 'playlist-radio-column-R1',
            ),
          ),
          matching: find.byType(TrackCard),
        );
        for (var i = 0; i < 3; i++) {
          final gesture = await t.startGesture(
            t.getCenter(cards().at(i)),
            kind: PointerDeviceKind.mouse,
          );
          await t.pump(const Duration(milliseconds: 500));
          expect(find.byType(PlaylistDragPreview), findsNothing);
          await gesture.moveBy(const Offset(5, 0));
          await t.pump();
          expect(find.byType(PlaylistDragPreview), findsNothing);
          await gesture.up();
          await t.pump();
          expect(
            t.widgetList<TrackCard>(cards()).where((s) => s.selected),
            hasLength(i + 1),
          );
          expect(find.byType(PlaylistDragPreview), findsNothing);
        }
        if (!pool) await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        // Clicking an already-selected card toggles selection without floating it.
        final click = await t.startGesture(
          t.getCenter(cards().first),
          kind: PointerDeviceKind.mouse,
        );
        await t.pump();
        expect(find.byType(PlaylistDragPreview), findsNothing);
        await click.up();
        await t.pump();
        expect(
          t.widgetList<TrackCard>(cards()).where((s) => s.selected),
          hasLength(2),
        );
        await t.tap(cards().first);
        await t.pump();
        expect(
          t.widgetList<TrackCard>(cards()).where((s) => s.selected),
          hasLength(3),
        );
        final drag = await t.startGesture(
          t.getCenter(cards().first),
          kind: PointerDeviceKind.mouse,
        );
        await t.pump();
        expect(find.byType(PlaylistDragPreview), findsNothing);
        await drag.moveBy(const Offset(8, 0));
        await t.pump();
        expect(find.byType(PlaylistDragPreview), findsNothing);
        await drag.moveBy(const Offset(12, 0));
        await t.pump();
        expect(
          t
              .widget<PlaylistDragPreview>(find.byType(PlaylistDragPreview))
              .tracks,
          hasLength(3),
        );
        await drag.cancel();
        await t.pumpAndSettle();
        expect(find.byType(PlaylistDragPreview), findsNothing);
        expect(
          t.widgetList<TrackCard>(cards()).where((s) => s.selected),
          hasLength(3),
        );
        expect(c.read(playlistPlanProvider).encodeForCli(), before);
        expect(t.takeException(), isNull);
      },
    );
  }
}
