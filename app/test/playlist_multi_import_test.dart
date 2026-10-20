import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fh_radio_studio/core/playlist_plan.dart';
import 'package:fh_radio_studio/core/timing_radio_assignments.dart';
import 'package:fh_radio_studio/domain/radio_library.dart';
import 'package:fh_radio_studio/screens/playlist.dart';
import 'package:fh_radio_studio/screens/playlist/playlist_state.dart';
import 'package:fh_radio_studio/screens/playlist/track_card.dart';
import 'package:fh_radio_studio/state/playlist_plan_state.dart';
import 'package:fh_radio_studio/widgets/timing_import_dialog.dart';
import 'package:fh_radio_studio/core/fh_radio_studio_cli.dart';
import 'dart:convert';
import 'studio_v18_workflow_test.dart' as fixtures;
import 'studio_v21_workflow_test.dart' as helpers;

Finder cards(String column) => find.descendant(
  of: find.byKey(ValueKey(column)),
  matching: find.byType(TrackCard),
);
Future<void> dragTo(WidgetTester t, Finder from, Finder target) async {
  final gesture = await t.startGesture(t.getCenter(from));
  await gesture.moveBy(const Offset(24, 0));
  await t.pump();
  expect(find.text('移动 2 首歌曲'), findsOneWidget);
  await gesture.moveTo(t.getCenter(target));
  await t.pump(const Duration(milliseconds: 50));
  await gesture.up();
  await t.pumpAndSettle();
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  test(
    'whole batch moves, over-capacity rollback, sorting and removal each undo once',
    () async {
      final c = await fixtures.fixture();
      final ctl = c.read(playlistProvider.notifier);
      final history = c.read(playlistPlanProvider.notifier);
      final tracks = kCustomPool.take(4).toList();
      ctl.assignManyToRadio(
        tracks.map((t) => t.id).toList(),
        'R1',
        'FreeRoam',
        maxSlots: 4,
      );
      final initial = c.read(playlistPlanProvider).encodeForCli();
      expect(
        ctl.assignManyToRadio(
          tracks.take(2).map((t) => t.id).toList(),
          'R2',
          'FreeRoam',
          maxSlots: 1,
          originRadioCode: 'R1',
          originPlaylistType: 'FreeRoam',
        ),
        isFalse,
      );
      expect(c.read(playlistPlanProvider).encodeForCli(), initial);
      expect(
        ctl.assignManyToRadio(
          tracks.take(2).map((t) => t.id).toList(),
          'R2',
          'FreeRoam',
          maxSlots: 2,
          originRadioCode: 'R1',
          originPlaylistType: 'FreeRoam',
        ),
        isTrue,
      );
      expect(
        c.read(playlistPlanProvider).assignmentsForRadio('R1', 'FreeRoam'),
        hasLength(2),
      );
      expect(
        c.read(playlistPlanProvider).assignmentsForRadio('R2', 'Event'),
        hasLength(2),
      );
      history.undo();
      expect(c.read(playlistPlanProvider).encodeForCli(), initial);
      ctl.reorderMany(
        [tracks[0].source, tracks[2].source],
        '',
        'R1',
        'FreeRoam',
      );
      expect(
        c
            .read(playlistPlanProvider)
            .assignmentsForRadio('R1', 'FreeRoam')
            .map((a) => a.source),
        [
          tracks[1].source,
          tracks[3].source,
          tracks[0].source,
          tracks[2].source,
        ],
      );
      history.undo();
      expect(c.read(playlistPlanProvider).encodeForCli(), initial);
      ctl.unassignMany(
        tracks.take(2).map((t) => t.id).toList(),
        radioCode: 'R1',
        playlistType: 'FreeRoam',
      );
      expect(
        c.read(playlistPlanProvider).assignmentsForRadio('R1', 'Event'),
        hasLength(2),
      );
      history.undo();
      expect(c.read(playlistPlanProvider).encodeForCli(), initial);
    },
  );
  for (final fromPool in [true, false]) {
    testWidgets(
      fromPool
          ? 'pool multi-selection drags together'
          : 'radio Ctrl multi-selection drags together',
      (t) async {
        t.view.physicalSize = const Size(1800, 1100);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final c = await fixtures.fixture();
        final ctl = c.read(playlistProvider.notifier);
        ctl.assignManyToRadio(
          kCustomPool.take(3).map((t) => t.id).toList(),
          'R1',
          'FreeRoam',
          maxSlots: 10,
        );
        ctl.assignManyToRadio(
          [kCustomPool[3].id],
          'R2',
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
        final scope = fromPool
            ? 'playlist-pool-side-panel'
            : 'playlist-radio-column-R1';
        if (fromPool) {
          await t.tap(
            find.byKey(const ValueKey('playlist-multiselect-toggle')),
          );
          await t.pump();
        } else {
          await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        }
        await t.tap(cards(scope).at(0));
        await t.pump();
        await t.tap(cards(scope).at(1));
        await t.pump();
        if (!fromPool) await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await dragTo(
          t,
          cards(scope).at(0),
          cards('playlist-radio-column-R2').first,
        );
        expect(
          c.read(playlistPlanProvider).assignmentsForRadio('R2', 'FreeRoam'),
          hasLength(3),
        );
        expect(
          c.read(playlistPlanProvider).assignmentsForRadio('R1', 'FreeRoam'),
          hasLength(fromPool ? 3 : 1),
        );
        c.read(playlistPlanProvider.notifier).undo();
        expect(c.read(playlistPlanProvider).encodeForCli(), before);
        expect(t.takeException(), isNull);
      },
    );
  }
  test(
    'XML baseline clears 39 custom assignments and restores both unified lists',
    () {
      var plan = const PlaylistPlan.empty();
      for (var i = 0; i < 39; i++) {
        for (final type in ['FreeRoam', 'Event']) {
          plan = plan.assign(
            source: 'C:/song$i.wav',
            radioCode: 'R9',
            playlistType: type,
            slot: i + 1,
          );
        }
      }
      final args = [
        <String, dynamic>{
          'radio_code': 'R9',
          'count': 22,
          'mode': 'builtin',
          'sources': <String>[],
        },
      ];
      final restored = previewXmlRadioLayouts(
        plan: plan,
        layouts: args,
        capacities: {'R9': 22},
        splitTypes: false,
      );
      expect(restored.hasBuiltinOverride('R9', 'Event'), isTrue);
      expect(restored.hasBuiltinOverride('R9', 'FreeRoam'), isTrue);
      expect(restored.assignmentsForRadio('R9', 'Event'), isEmpty);
      final split = previewXmlRadioLayouts(
        plan: plan,
        layouts: args,
        capacities: {'R9': 22},
        splitTypes: true,
      );
      expect(split.assignmentsForRadio('R9', 'FreeRoam'), hasLength(39));
      expect(split.hasBuiltinOverride('R9', 'Event'), isTrue);
    },
  );
  testWidgets(
    'pasted text reaches CLI stdin and re-preview uses current content',
    (t) async {
      t.view.physicalSize = const Size(1200, 1200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final c = await fixtures.fixture();
      String? received;
      List<String>? call;
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: ProviderScope(
            overrides: [
              timingImportRunnerProvider.overrideWithValue((
                root,
                args,
                input,
              ) async {
                received = input;
                call = args;
                return CliRunResult(
                  exitCode: 0,
                  commandLine: 'fixture',
                  stderr: '',
                  stdout: jsonEncode({
                    'ready_count': 1,
                    'rows': [],
                    'snapshot_hash': 's',
                    'input_hash': 'i',
                  }),
                );
              }),
            ],
            child: helpers.app(const TimingImportDialog()),
          ),
        ),
      );
      await t.tap(find.text('粘贴文本'));
      await t.pump();
      const csv = 'Filename,TD,TL-A,TL-B\nSong.wav,1,2,9';
      await t.enterText(find.byKey(const ValueKey('timing-import-text')), csv);
      await t.pump();
      await t.tap(find.text('预览匹配'));
      await t.pumpAndSettle();
      expect(received, csv);
      expect(call![call!.indexOf('--input') + 1], '-');
      expect(find.textContaining('可导入 1 首'), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('timing-import-text')),
        '$csv\nSecond.wav,1,3,8',
      );
      await t.pump();
      expect(find.textContaining('可导入 1 首'), findsNothing);
      await t.tap(find.text('预览匹配'));
      await t.pumpAndSettle();
      expect(received, contains('Second.wav'));
      expect(t.takeException(), isNull);
    },
  );
}
