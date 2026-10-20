import 'playlist_plan.dart';

/// Validate the entire import against a copy of the current draft before any write.
/// Song identities and sources come only from the CLI matching result.
PlaylistPlan previewTimingRadioAssignments({
  required PlaylistPlan plan,
  required List<Map> rows,
  required Map<String, int> capacities,
  required String playlistType,
  required bool splitTypes,
  String? projectDir,
}) {
  var next = splitTypes ? plan : plan.syncPlaylistTypesFrom(playlistType);
  for (final row in rows.where((row) => row['status'] == 'ready')) {
    final stations = (row['radio_stations'] as List? ?? const [])
        .cast<String>();
    final source = row['source'] as String? ?? '';
    if (stations.isNotEmpty && source.isEmpty) {
      throw const FormatException('导入歌曲来源无效，请重新预览。');
    }
    for (final radio in stations) {
      final capacity = capacities[radio];
      if (capacity == null) {
        throw FormatException('$radio 电台不可用，请修正 Radio_station。');
      }
      if (next.assignmentFor(
            source: source,
            radioCode: radio,
            playlistType: playlistType,
          ) !=
          null) {
        continue;
      }
      final count = next.assignmentsForRadio(radio, playlistType).length;
      if (count >= capacity ||
          !next.canFitRadioSources(radio, [source], capacity)) {
        throw FormatException(
          '$radio 容量不足（当前场景 $count / $capacity；跨场景共享容量），请调整 Radio_station 或开启电台扩容后重新预览。',
        );
      }
      next = next.assign(
        source: source,
        radioCode: radio,
        playlistType: playlistType,
        slot: count + 1,
        projectDir: projectDir,
      );
    }
  }
  return splitTypes ? next : next.syncPlaylistTypesFrom(playlistType);
}

/// Replace only the CLI-validated Event layouts; never guess original tracks here.
PlaylistPlan previewXmlRadioLayouts({
  required PlaylistPlan plan,
  required List<Map> layouts,
  required Map<String, int> capacities,
  required bool splitTypes,
  String? projectDir,
}) {
  var next = plan;
  for (final layout in layouts) {
    final mode = layout['mode'];
    if (mode != 'builtin' && mode != 'custom') continue;
    final radio = layout['radio_code'] as String;
    if (!capacities.containsKey(radio)) throw FormatException('$radio 电台不可用。');
    next = next.restoreBuiltin(radioCode: radio, playlistType: 'Event');
    if (!splitTypes) {
      next = next.restoreBuiltin(radioCode: radio, playlistType: 'FreeRoam');
    }
    if (mode == 'builtin') continue;
    final sources = (layout['sources'] as List).cast<String>();
    final capacity = capacities[radio]!;
    if (sources.length > capacity ||
        !next.canFitRadioSources(radio, sources, capacity)) {
      throw FormatException('$radio 容量不足，请先开启电台扩容。');
    }
    for (var i = 0; i < sources.length; i++) {
      next = next.assign(
        source: sources[i],
        radioCode: radio,
        playlistType: 'Event',
        slot: i + 1,
        projectDir: projectDir,
      );
    }
  }
  return splitTypes ? next : next.syncPlaylistTypesFrom('Event');
}
