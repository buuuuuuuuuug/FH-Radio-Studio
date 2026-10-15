import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fh_radio_studio/core/playlist_plan.dart';
import 'package:fh_radio_studio/core/project_workspace.dart';
import 'package:fh_radio_studio/core/track_metadata_cache.dart';

void main() {
  test('measure real project reference resolution', () {
    final project = Platform.environment['FH_STUDIO_PERFORMANCE_PROJECT']!;
    final decoded =
        jsonDecode(
              File(
                '$project/analysis/expansion_plan_full.json',
              ).readAsStringSync(),
            )
            as Map;
    final records = decoded['assignments'] as List;
    final migration = Stopwatch()..start();
    final required = FhRadioStudioProject.needsPathMigration(project);
    migration.stop();
    final watch = Stopwatch()..start();
    for (final raw in records) {
      final assignment = PlaylistAssignment.fromJson(
        Map<String, dynamic>.from(raw as Map),
        projectDir: project,
      );
      expect(assignment.source, isNotEmpty);
    }
    watch.stop();
    expect(
      TrackMetadataCache.assetIndex(project).length,
      greaterThanOrEqualTo(229),
    );
    // ignore: avoid_print
    print(
      'PERFORMANCE records=${records.length} migration_ms=${migration.elapsedMilliseconds} '
      'resolve_ms=${watch.elapsedMilliseconds} migration_required=$required',
    );
  }, skip: Platform.environment['FH_STUDIO_PERFORMANCE_PROJECT'] == null);
}
