import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fh_radio_studio/core/fh_radio_studio_cli.dart';
import 'package:fh_radio_studio/domain/radio_library.dart';
import 'package:fh_radio_studio/state/playlist_catalog_state.dart';
import 'package:fh_radio_studio/state/playlist_plan_state.dart';
import 'package:fh_radio_studio/widgets/rm_select.dart';
import 'package:fh_radio_studio/widgets/timing_export_dialog.dart';
import 'package:fh_radio_studio/widgets/timing_import_dialog.dart';
import 'package:fh_radio_studio/widgets/timing_match_modes.dart';
import 'editor_playlist_upgrade_test.dart' as fixture;
import 'studio_v21_workflow_test.dart' as helpers;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
    'file sample import sends units and invalidates an existing preview',
    (t) async {
      t.view.physicalSize = const Size(1200, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final f = await fixture.fixture();
      final calls = <List<String>>[];
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: ProviderScope(
            overrides: [
              timingImportFilePickerProvider.overrideWithValue(
                () async => "C:/fixtures/points.csv",
              ),
              timingImportRunnerProvider.overrideWithValue((
                root,
                args,
                input,
              ) async {
                calls.add([...args]);
                return CliRunResult(
                  exitCode: 0,
                  commandLine: 'test',
                  stderr: '',
                  stdout: jsonEncode({
                    'snapshot_hash': 's',
                    'input_hash': 'i',
                    'ready_count': 1,
                    'rows': [],
                  }),
                );
              }),
            ],
            child: helpers.app(const TimingImportDialog()),
          ),
        ),
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.text('使用粘贴文本'), findsNothing);
      await t.tap(find.byKey(const ValueKey('timing-import-file')));
      await t.pumpAndSettle();
      expect(find.text('points.csv'), findsOneWidget);
      await t.pump();
      await t.tap(find.text('预览匹配'));
      await t.pumpAndSettle();
      expect(find.textContaining('可导入 1 首'), findsOneWidget);
      final select = t.widget<RmSelect<String>>(
        find.byKey(const ValueKey('timing-import-time-unit')),
      );
      select.onChanged!('samples');
      await t.pumpAndSettle();
      expect(find.textContaining('可导入 1 首'), findsNothing);
      expect(
        find.text(timingCsvTemplateFor(timeUnit: 'samples')),
        findsOneWidget,
      );
      await t.tap(find.text('预览匹配'));
      await t.pumpAndSettle();
      expect(calls.last[calls.last.indexOf('--time-unit') + 1], 'samples');
      expect(
        calls.last[calls.last.indexOf('--input') + 1],
        'C:/fixtures/points.csv',
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'RadioInfo file selects sample input and offers optional station assignment',
    (t) async {
      t.view.physicalSize = const Size(1000, 950);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final f = await fixture.fixture();
      final calls = <List<String>>[];
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: ProviderScope(
            overrides: [
              timingImportFilePickerProvider.overrideWithValue(
                () async => "C:/fixtures/RadioInfo_CN.xml",
              ),
              playlistCatalogProvider.overrideWithValue(
                PlaylistCatalog(
                  origin: PlaylistCatalogOrigin.package,
                  sourcePath: 'fixture.xml',
                  radios: [kRadios.first],
                  modes: const {'R1': StationMode.custom},
                  freeRoamTracks: const {},
                  eventTracks: const {},
                ),
              ),
              timingImportRunnerProvider.overrideWithValue((
                root,
                args,
                input,
              ) async {
                calls.add([...args]);
                return CliRunResult(
                  exitCode: 0,
                  commandLine: 'test',
                  stderr: '',
                  stdout: jsonEncode({
                    'ready_count': 1,
                    'source_format': 'radio-info',
                    'snapshot_hash': 's',
                    'input_hash': 'i',
                    'applied_count': 1,
                    'rows': [
                      {
                        'row': 1,
                        'status': 'ready',
                        'source': f.dir.uri
                            .resolve('sources/song.wav')
                            .toFilePath(),
                        'radio_stations': ['R1'],
                      },
                    ],
                  }),
                );
              }),
            ],
            child: helpers.app(const TimingImportDialog()),
          ),
        ),
      );
      await t.tap(find.byKey(const ValueKey('timing-import-file')));
      await t.pumpAndSettle();
      expect(find.textContaining('仅读取赛事（Event）'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('timing-import-match-mode')),
        findsNothing,
      );
      expect(find.text('按 XML 电台归属分配'), findsOneWidget);
      await t.tap(find.text('预览匹配'));
      await t.pumpAndSettle();
      expect(calls.last, containsAll(['--time-unit', 'samples']));
      expect(calls.last, isNot(contains('--assign-radio')));
      await t.tap(find.text('按 XML 电台归属分配'));
      await t.pumpAndSettle();
      await t.tap(find.text('预览匹配'));
      await t.pumpAndSettle();
      expect(calls.last, contains('--assign-radio'));
      final roaming = f.container
          .read(playlistPlanProvider)
          .assignmentsForRadio('R1', 'FreeRoam')
          .map((a) => a.source)
          .toList();
      await t.tap(find.text('导入 1 首'));
      await t.pumpAndSettle();
      final plan = f.container.read(playlistPlanProvider);
      expect(plan.assignmentsForRadio('R1', 'Event'), hasLength(1));
      expect(
        plan
            .assignmentsForRadio('R1', 'FreeRoam')
            .map((a) => a.source)
            .toList(),
        roaming,
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'sample export sends fixed units and updates the column explanation',
    (t) async {
      final f = await fixture.fixture();
      List<String>? call;
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: ProviderScope(
            overrides: [
              playlistCatalogProvider.overrideWithValue(
                PlaylistCatalog(
                  origin: PlaylistCatalogOrigin.package,
                  sourcePath: 'fixture.xml',
                  radios: [kRadios.first],
                  modes: const {'R1': StationMode.custom},
                  freeRoamTracks: const {},
                  eventTracks: const {},
                ),
              ),
              timingImportRunnerProvider.overrideWithValue((
                root,
                args,
                input,
              ) async {
                call = args;
                return const CliRunResult(
                  exitCode: 1,
                  commandLine: 'test',
                  stderr: 'controlled stop',
                  stdout: '',
                );
              }),
            ],
            child: helpers.app(const TimingExportDialog()),
          ),
        ),
      );
      t
          .widget<RmSelect<String>>(
            find.byKey(const ValueKey('timing-export-time-unit')),
          )
          .onChanged!('samples');
      await t.pumpAndSettle();
      expect(
        find.textContaining('Filename,TD,PD,TL-A,TL-B,PL-A,PL-B'),
        findsOneWidget,
      );
      expect(find.textContaining('SampleRate'), findsNothing);
      await t.tap(find.text('导出 CSV'));
      await t.pumpAndSettle();
      expect(call, containsAll(['export-timings', '--time-unit', 'samples']));
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'match mode updates the CSV example and radio and unit choices compose',
    (t) async {
      t.view.physicalSize = const Size(1200, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final f = await fixture.fixture();
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: helpers.app(const TimingImportDialog()),
        ),
      );
      for (final entry in {
        'filename': '示例歌曲.wav',
        'title': '示例歌曲',
        'title-artist': '示例歌曲_示例歌手',
        'artist-title': '示例歌手_示例歌曲',
      }.entries) {
        t
            .widget<RmSelect<String>>(
              find.byKey(const ValueKey('timing-import-match-mode')),
            )
            .onChanged!(entry.key);
        await t.pumpAndSettle();
        expect(
          find.text(timingCsvTemplateFor(matchMode: entry.key)),
          findsOneWidget,
        );
        expect(
          timingCsvTemplateFor(
            matchMode: entry.key,
          ).split('\n')[1].split(',').first,
          entry.value,
        );
      }
      t
          .widget<RmSelect<String>>(
            find.byKey(const ValueKey('timing-import-time-unit')),
          )
          .onChanged!('samples');
      await t.tap(find.text('使用 Radio_station 列分配电台'));
      await t.pumpAndSettle();
      expect(
        find.text(
          timingCsvTemplateFor(
            matchMode: 'artist-title',
            timeUnit: 'samples',
            includeRadio: true,
          ),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('SampleRate'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'canceling file replacement keeps the preview and choosing a new file invalidates it',
    (t) async {
      t.view.physicalSize = const Size(1200, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final f = await fixture.fixture();
      final choices = <String?>[
        'C:/fixtures/points.csv',
        null,
        'C:/fixtures/RadioInfo_CN.xml',
      ];
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: ProviderScope(
            overrides: [
              timingImportFilePickerProvider.overrideWithValue(
                () async => choices.removeAt(0),
              ),
              timingImportRunnerProvider.overrideWithValue((
                root,
                args,
                input,
              ) async {
                expect(input, isNull);
                return const CliRunResult(
                  exitCode: 0,
                  commandLine: 'test',
                  stderr: '',
                  stdout:
                      '{"snapshot_hash":"s","input_hash":"i","ready_count":1,"rows":[]}',
                );
              }),
            ],
            child: helpers.app(const TimingImportDialog()),
          ),
        ),
      );
      await t.tap(find.byKey(const ValueKey('timing-import-file')));
      await t.pumpAndSettle();
      await t.tap(find.text('预览匹配'));
      await t.pumpAndSettle();
      expect(find.textContaining('可导入 1 首'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('timing-import-file')));
      await t.pumpAndSettle();
      expect(find.textContaining('可导入 1 首'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('timing-import-file')));
      await t.pumpAndSettle();
      expect(find.textContaining('可导入 1 首'), findsNothing);
      expect(find.text('RadioInfo_CN.xml'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('timing-import-match-mode')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('timing-import-time-unit')),
        findsNothing,
      );
      expect(find.text('CSV 模板'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('transfer dialogs render at a narrow viewport with semantics', (
    t,
  ) async {
    t.view.physicalSize = const Size(640, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final semantics = t.ensureSemantics();
    final f = await fixture.fixture();
    try {
      for (final dialog in [
        const TimingImportDialog(),
        const TimingExportDialog(),
      ]) {
        await t.pumpWidget(
          UncontrolledProviderScope(
            container: f.container,
            child: helpers.app(dialog),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      }
    } finally {
      semantics.dispose();
    }
  });
}
