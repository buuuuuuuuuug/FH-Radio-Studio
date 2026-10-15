import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fh_radio_studio/core/atomic_file.dart';
import 'package:fh_radio_studio/core/playlist_plan.dart';
import 'package:fh_radio_studio/core/timing_radio_assignments.dart';
import 'package:fh_radio_studio/core/project_json_guard.dart';
import 'package:fh_radio_studio/core/project_workspace.dart';
import 'package:fh_radio_studio/core/track_timing_config.dart';
import 'package:fh_radio_studio/core/waveform_cache.dart';
import 'package:fh_radio_studio/state/library_columns.dart';
import 'package:fh_radio_studio/state/layout_options.dart';

void main() {
  late Directory temp;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('studio-persistence-');
    WaveformCache.clearMemory();
  });
  tearDown(() {
    WaveformCache.clearMemory();
    temp.deleteSync(recursive: true);
  });
  test(
    'atomic save replaces full UTF-8 content and cleans private files',
    () async {
      final file = File('${temp.path}/analysis/state.json');
      writeTextAtomicallySync(file, '{"name":"原内容"}');
      await Future.wait(
        List.generate(
          12,
          (i) => writeTextAtomically(
            file,
            jsonEncode({'name': '歌曲$i', 'values': List.filled(1024, i)}),
          ),
        ),
      );
      final saved = jsonDecode(file.readAsStringSync()) as Map;
      final values = saved['values'] as List;
      expect(values, hasLength(1024));
      expect(values.toSet(), hasLength(1));
      expect(file.parent.listSync().whereType<Directory>(), isEmpty);
    },
  );
  test('serialization failure cannot truncate the old project JSON', () {
    final file = File('${temp.path}/analysis/state.json');
    file.createSync(recursive: true);
    file.writeAsStringSync('{"preserve":true}');
    expect(
      () => writeProjectJsonSync(
        projectDir: temp.path,
        file: file,
        payload: {'bad': Object()},
      ),
      throwsA(isA<JsonUnsupportedObjectError>()),
    );
    expect(file.readAsStringSync(), '{"preserve":true}');
    expect(file.parent.listSync(), hasLength(1));
  });
  test(
    'failed final rename leaves the old target and no temporary files',
    () async {
      final target = Directory('${temp.path}/target')..createSync();
      File('${target.path}/keep').writeAsStringSync('keep');
      expect(
        () => writeTextAtomicallySync(File(target.path), 'replacement'),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        writeTextAtomically(File(target.path), 'replacement'),
        throwsA(isA<FileSystemException>()),
      );
      expect(File('${target.path}/keep').readAsStringSync(), 'keep');
      expect(temp.listSync(), hasLength(1));
    },
  );
  for (final raw in [
    '{"tracks":',
    '{"tracks":{}}',
    '{"tracks":[null]}',
    '{"tracks":[{"track_key":"missing"}]}',
  ]) {
    test('saving or removing refuses invalid timing data: $raw', () {
      FhRadioStudioProject.ensure(temp.path);
      final file = File(TrackTimingStore.configPath(temp.path))
        ..writeAsStringSync(raw);
      final config = TrackTimingConfig(
        source: '${temp.path}/sources/new.wav',
        bpm: 120,
        markersSec: const {},
        confirmed: const {},
        updatedAt: DateTime.utc(2026),
      );
      expect(
        () => TrackTimingStore.save(temp.path, config),
        throwsFormatException,
      );
      expect(
        () => TrackTimingStore.remove(temp.path, config.source),
        throwsFormatException,
      );
      expect(file.readAsStringSync(), raw);
    });
  }
  test('invalid project settings are preserved rather than replaced', () {
    FhRadioStudioProject.ensure(temp.path);
    final file = File(FhRadioStudioProject.manifestPath(temp.path));
    for (final raw in ['{"settings":', '[]', '{"settings":17}']) {
      file.writeAsStringSync(raw);
      expect(
        () => FhRadioStudioProject.writeSettings(temp.path, manualOnly: true),
        throwsFormatException,
      );
      expect(file.readAsStringSync(), raw);
    }
  });
  test('invalid saved playlists cannot be overwritten by an empty draft', () {
    FhRadioStudioProject.ensure(temp.path);
    final file = File(PlaylistPlanStore.configPath(temp.path));
    for (final raw in [
      '{"assignments":',
      '[]',
      '{"assignments":{}}',
      '{"assignments":[null]}',
    ]) {
      file.writeAsStringSync(raw);
      expect(
        () => PlaylistPlanStore.write(temp.path, const PlaylistPlan.empty()),
        throwsFormatException,
      );
      expect(file.readAsStringSync(), raw);
    }
  });
  test(
    'overlapping waveform cache writers produce complete readable output',
    () async {
      final source = File('${temp.path}/source.wav')
        ..writeAsStringSync('audio');
      await Future.wait(
        List.generate(
          10,
          (i) => WaveformCache.write(temp.path, source.path, {
            'waveform': {'bins': List.filled(128, i)},
            'writer': i,
          }),
        ),
      );
      WaveformCache.clearMemory();
      final saved = await WaveformCache.read(temp.path, source.path);
      expect(saved, isNotNull);
      expect(
        ((saved!['waveform'] as Map)['bins'] as List).toSet(),
        hasLength(1),
      );
      expect(
        Directory('${temp.path}/analysis/waveforms').listSync(),
        hasLength(1),
      );
    },
  );
  test(
    'concurrent lower-detail cache writes cannot erase the detailed waveform',
    () async {
      final source = File('${temp.path}/source.wav')
        ..writeAsStringSync('audio');
      await Future.wait([
        for (final count in [8192, 512, 1024, 256])
          WaveformCache.write(temp.path, source.path, {
            'waveform': {'bins': List.filled(count, .5)},
          }),
      ]);
      WaveformCache.clearMemory();
      final saved = await WaveformCache.read(temp.path, source.path);
      expect((saved!['waveform'] as Map)['bins'], hasLength(8192));
    },
  );
  test('radio capacity counts unique sources across both scenarios', () {
    final plan = const PlaylistPlan.empty()
        .assign(
          source: 'C:/music/a.wav',
          radioCode: 'R1',
          playlistType: 'FreeRoam',
          slot: 1,
        )
        .assign(
          source: 'C:/music/b.wav',
          radioCode: 'R1',
          playlistType: 'Event',
          slot: 1,
        );
    expect(plan.canFitRadioSources('R1', ['C:/music/a.wav'], 2), isTrue);
    expect(plan.canFitRadioSources('R1', ['C:/music/c.wav'], 2), isFalse);
    expect(
      () => previewTimingRadioAssignments(
        plan: plan,
        rows: [
          {
            'status': 'ready',
            'source': 'C:/music/c.wav',
            'radio_stations': ['R1'],
          },
        ],
        capacities: {'R1': 2},
        playlistType: 'Event',
        splitTypes: true,
      ),
      throwsFormatException,
    );
    expect(plan.assignments, hasLength(2));
  });
  test('disposing a pending column resize flushes the final widths', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = LibraryColumnsController(prefs);
    const specs = [
      LibraryColumnSpec('a', 100, 150),
      LibraryColumnSpec('b', 100, 150),
    ];
    controller.resize(specs, {'a': 150, 'b': 150}, 0, 25);
    controller.dispose();
    final loaded = LibraryColumnsController(prefs);
    expect(loaded.state, {'a': 175, 'b': 125});
    loaded.dispose();
  });
  test('non-finite radio heights do not change the layout', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = LayoutOptionsController(prefs);
    for (final value in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      controller.setRadioHeight(value);
      expect(controller.state.radioHeight, 480);
    }
    controller.dispose();
  });
}
