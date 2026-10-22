import 'dart:io';

import 'package:fh_radio_studio/core/project_workspace.dart';
import 'package:fh_radio_studio/core/track_metadata_cache.dart';
import 'package:fh_radio_studio/core/siren_imports.dart';
import 'package:fh_radio_studio/state/custom_pool_tracks.dart';
import 'package:fh_radio_studio/state/studio_state.dart';
import 'package:fh_radio_studio/widgets/package_publication_recovery.dart';
import 'package:fh_radio_studio/widgets/song_metadata_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'studio_v21_workflow_test.dart' as helpers;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  test(
    'explicit display edits override imported Siren labels without moving the source',
    () {
      final root = Directory.systemTemp.createTempSync('metadata_siren_');
      addTearDown(() => root.deleteSync(recursive: true));
      final source = File(p.join(root.path, 'song.wav'))..writeAsBytesSync([0]);
      final imported = SirenImportEntry(
        cid: 'demo',
        title: 'Imported title',
        albumCid: 'album',
        albumName: 'Album',
        artist: 'Imported artist',
        artists: const ['Imported artist'],
        coverUrl: '',
        lyricUrl: null,
        path: source.path,
        importedAt: DateTime.now(),
      );
      final track = poolTrackFromFile(
        source,
        sirenImport: imported,
        metadata: const TrackMetadata(
          title: 'Edited title',
          artist: 'Edited artist',
          fromTags: false,
          displayEdited: true,
        ),
      );
      expect(track.title, 'Edited title');
      expect(track.artist, 'Edited artist');
      expect(track.source, source.path);
    },
  );

  test(
    'new project rejects non-ASCII parent paths without creating project files',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = StudioController(prefs);
      addTearDown(controller.dispose);
      final root = Directory.systemTemp.createTempSync('project_path_');
      addTearDown(() => root.deleteSync(recursive: true));
      final path = p.join(root.path, '中文', 'EnglishProject');
      expect(() => controller.setProjectDir(path), throwsFormatException);
      expect(Directory(path).existsSync(), isFalse);
      expect(
        FhRadioStudioProject.newProjectPathError(
          p.join(root.path, 'English Project'),
        ),
        isNull,
      );
      // Existing project files remain openable, even with historical Chinese paths.
      FhRadioStudioProject.ensure(path);
      controller.setProjectDir(path);
      expect(controller.state.projectDir, path);
    },
  );

  testWidgets('metadata dialog validates and submits editable names', (
    t,
  ) async {
    final saved = <String>[];
    await t.pumpWidget(
      helpers.app(
        SongMetadataButton(
          title: 'Old title',
          artist: 'Old artist',
          onSave: (title, artist) async {
            saved.addAll([title, artist]);
            return true;
          },
        ),
      ),
    );
    await t.tap(find.text('编辑歌曲信息'));
    await t.pumpAndSettle();
    expect(find.textContaining('游戏使用自己的字体'), findsNothing);
    await t.enterText(find.byType(TextField).first, '');
    await t.tap(find.text('保存歌曲信息'));
    await t.pumpAndSettle();
    expect(saved, isEmpty);
    await t.enterText(find.byType(TextField).first, 'New title');
    await t.enterText(find.byType(TextField).last, 'New artist');
    await t.tap(find.text('保存歌曲信息'));
    await t.pumpAndSettle();
    expect(saved, ['New title', 'New artist']);
    expect(find.byType(TextField), findsNothing);
    expect(t.takeException(), isNull);
  });

  test(
    'recoverable completed output is discovered after reopening the project',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final project = Directory.systemTemp.createTempSync('publication_ui_');
      addTearDown(() => project.deleteSync(recursive: true));
      final controller = StudioController(prefs)..setProjectDir(project.path);
      final container = ProviderContainer(
        overrides: [studioProvider.overrideWith((ref) => controller)],
      );
      addTearDown(container.dispose);
      Directory(
        p.join(project.path, 'packages', '.current-building-incomplete'),
      ).createSync();
      final ready = Directory(
        p.join(project.path, 'packages', '.current-building-complete'),
      )..createSync();
      File(p.join(ready.path, '.publish-ready.json')).writeAsStringSync('{}');
      final candidates = container.read(completedPackageProvider);
      expect(candidates, hasLength(1));
      expect(candidates.single.ready, ready.path);
      expect(
        candidates.single.target,
        p.join(project.path, 'packages', 'current'),
      );
    },
  );
}
