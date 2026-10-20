import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fh_radio_studio/state/unsaved_edits.dart';
import 'package:fh_radio_studio/widgets/rm_button.dart';
import 'package:fh_radio_studio/theme/app_theme.dart';
import 'package:fh_radio_studio/theme/accents.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fh_radio_studio/core/playlist_plan.dart';
import 'package:fh_radio_studio/core/playlist_capacity.dart';
import 'package:fh_radio_studio/core/playback_window.dart';
import 'package:fh_radio_studio/state/editor_options.dart';
import 'package:fh_radio_studio/state/playlist_plan_state.dart';
import 'studio_v18_workflow_test.dart' as fixtures;

PlaylistPlan radioPlan(
  int count, {
  String type = 'FreeRoam',
  String prefix = 'song',
}) {
  var plan = const PlaylistPlan.empty();
  for (var i = 0; i < count; i++) {
    plan = plan.assign(
      source: 'C:/test/$prefix$i.wav',
      radioCode: 'R9',
      playlistType: type,
      slot: i + 1,
    );
  }
  return plan;
}

void main() {
  test(
    'undo and redo cannot cross current capacity; rejected history is retained',
    () async {
      final c = await fixtures.fixture(
        capacityLimits: {
          'R9': {'FreeRoam': 22, 'Event': 22},
        },
      );
      final h = c.read(playlistPlanProvider.notifier);
      final opts = c.read(editorOptionsProvider.notifier);
      opts.update(expansionEnabled: true);
      final large = radioPlan(39), small = radioPlan(22);
      h.replaceWith(large);
      h.replaceWith(small);
      expect(opts.update(expansionEnabled: false), isTrue);
      final before = h.state.encodeForCli();
      expect(h.undo, throwsA(isA<PlaylistCapacityException>()));
      expect(h.state.encodeForCli(), before);
      expect(h.canUndo, isTrue);
      expect(h.canRedo, isFalse);
      opts.update(expansionEnabled: true);
      h.undo();
      expect(h.state.assignmentsForRadio('R9', 'FreeRoam'), hasLength(39));
      h.redo();
      expect(h.state.assignmentsForRadio('R9', 'FreeRoam'), hasLength(22));
      h.replaceWith(large);
      h.undo();
      opts.update(expansionEnabled: false);
      expect(h.redo, throwsA(isA<PlaylistCapacityException>()));
      expect(h.state.assignmentsForRadio('R9', 'FreeRoam'), hasLength(22));
      opts.update(expansionEnabled: true);
      h.redo();
      expect(h.state.assignmentsForRadio('R9', 'FreeRoam'), hasLength(39));
    },
  );
  test(
    'same constraint applies to direct mutations, persistence and transaction rollback',
    () async {
      final c = await fixtures.fixture(
        capacityLimits: {
          'R9': {'FreeRoam': 22, 'Event': 22},
        },
      );
      final h = c.read(playlistPlanProvider.notifier);
      final small = radioPlan(22), large = radioPlan(39);
      h.replaceWith(small);
      expect(
        () => h.replaceWith(large),
        throwsA(isA<PlaylistCapacityException>()),
      );
      final before = h.state.encodeForCli();
      expect(
        () => h.transaction(() {
          h.replaceWith(radioPlan(10));
          h.replaceWith(large);
        }),
        throwsA(isA<PlaylistCapacityException>()),
      );
      expect(h.state.encodeForCli(), before);
      c.read(editorOptionsProvider.notifier).update(expansionEnabled: true);
      h.replaceWith(large);
      expect(
        c.read(editorOptionsProvider.notifier).update(expansionEnabled: false),
        isFalse,
      );
      final policy = PlaylistCapacityPolicy({
        'R9': {'FreeRoam': 22, 'Event': 22},
      });
      expect(
        () => policy.requireTransition(large, radioPlan(38)),
        returnsNormally,
      );
      expect(
        () => policy.requireTransition(radioPlan(38), large),
        throwsA(isA<PlaylistCapacityException>()),
      );
      expect(
        () => policy.requireTransition(
          large,
          large,
          allowExistingOverflow: false,
        ),
        throwsA(isA<PlaylistCapacityException>()),
      );
    },
  );
  test(
    'shared bank union is constrained even if both scenes individually fit',
    () {
      final a = radioPlan(2, prefix: 'a');
      var combined = a;
      for (final b in radioPlan(
        2,
        type: 'Event',
        prefix: 'b',
      ).assignments.values) {
        combined = combined.assign(
          source: b.source,
          radioCode: b.radioCode,
          playlistType: b.playlistType,
          slot: b.slot,
        );
      }
      final policy = PlaylistCapacityPolicy({
        'R9': {'FreeRoam': 3, 'Event': 3},
      });
      final violations = policy.violations(combined);
      expect(violations, hasLength(1));
      expect(violations.single.type, isNull);
      expect(violations.single.count, 4);
    },
  );
  test(
    'page trigger and landing have equal margins and stationary frames do not bounce',
    () {
      var view = (start: 40.0, end: 60.0);
      final forward = pagedPlaybackWindow(
        duration: 200,
        start: view.start,
        end: view.end,
        playhead: 58.01,
      );
      expect(
        (58.01 - forward.start) / (forward.end - forward.start),
        closeTo(.1, 1e-10),
      );
      for (var i = 0; i < 10; i++) {
        expect(
          pagedPlaybackWindow(
            duration: 200,
            start: forward.start,
            end: forward.end,
            playhead: 58.01,
          ),
          forward,
        );
      }
      final backward = pagedPlaybackWindow(
        duration: 200,
        start: 40,
        end: 60,
        playhead: 41.99,
      );
      expect(
        (41.99 - backward.start) / (backward.end - backward.start),
        closeTo(.9, 1e-10),
      );
      expect(
        pagedPlaybackWindow(
          duration: 200,
          start: backward.start,
          end: backward.end,
          playhead: 41.99,
        ),
        backward,
      );
      expect(
        pagedPlaybackWindow(duration: 200, start: 40, end: 60, playhead: 58),
        view,
      );
      expect(
        pagedPlaybackWindow(duration: 200, start: 40, end: 60, playhead: 42),
        view,
      );
    },
  );
  test(
    'discard and save use the same constraint as history restoration',
    () async {
      final c = await fixtures.fixture(
        capacityLimits: {
          'R9': {'FreeRoam': 22, 'Event': 22},
        },
      );
      final h = c.read(playlistPlanProvider.notifier);
      final options = c.read(editorOptionsProvider.notifier);
      options.update(expansionEnabled: true);
      h.replaceWith(radioPlan(39));
      h.save();
      h.replaceWith(radioPlan(22));
      expect(options.update(expansionEnabled: false), isTrue);
      expect(h.discard, throwsA(isA<PlaylistCapacityException>()));
      expect(h.state.assignmentsForRadio('R9', 'FreeRoam'), hasLength(22));
      expect(h.save, returnsNormally);
      expect(h.dirty, isFalse);
      expect(h.discard, returnsNormally);
      expect(h.state.assignmentsForRadio('R9', 'FreeRoam'), hasLength(22));
    },
  );
  testWidgets(
    'exit explains saved overflow before discard and saves the current smaller draft',
    (tester) async {
      final c = await fixtures.fixture(
        capacityLimits: {
          'R9': {'FreeRoam': 22, 'Event': 22},
        },
      );
      final history = c.read(playlistPlanProvider.notifier);
      final options = c.read(editorOptionsProvider.notifier);
      options.update(expansionEnabled: true);
      history.replaceWith(radioPlan(39));
      history.save();
      history.replaceWith(radioPlan(22));
      options.update(expansionEnabled: false);
      late BuildContext screen;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: buildAppTheme(
              brightness: Brightness.light,
              accent: AppAccent.lime,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  screen = context;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      final closing = c
          .read(unsavedEditsProvider)
          .confirm(screen, exiting: true);
      await tester.pumpAndSettle();
      expect(find.text('关闭前保存修改？'), findsOneWidget);
      expect(find.textContaining('已保存的旧播放列表仍超出原始容量'), findsOneWidget);
      final discard = tester.widget<RmButton>(
        find.widgetWithText(RmButton, '放弃更改'),
      );
      expect(discard.onPressed, isNull);
      await tester.tap(find.text('保存并关闭'));
      await tester.pumpAndSettle();
      expect(await closing, isTrue);
      expect(history.dirty, isFalse);
      expect(
        history.state.assignmentsForRadio('R9', 'FreeRoam'),
        hasLength(22),
      );
      expect(history.discard, returnsNormally);
      expect(tester.takeException(), isNull);
    },
  );
}
