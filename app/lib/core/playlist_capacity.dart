import 'playlist_plan.dart';

class PlaylistCapacityViolation {
  const PlaylistCapacityViolation(
    this.radio,
    this.type,
    this.count,
    this.limit,
  );
  final String radio;
  final String? type;
  final int count, limit;
  String get key => '$radio|${type ?? 'bank'}';
  String get description =>
      '$radio ${type == null
          ? '跨场景合计'
          : type == 'Event'
          ? '比赛'
          : '漫游'}：$count / $limit 首';
}

List<String> describeCapacityViolations(
  List<PlaylistCapacityViolation> issues,
) => [
  for (final issue in issues)
    if (issue.type != null ||
        !issues.any(
          (other) => other.radio == issue.radio && other.type != null,
        ))
      issue.description,
];

class PlaylistCapacityException implements Exception {
  PlaylistCapacityException(this.issues);
  final List<PlaylistCapacityViolation> issues;
  @override
  String toString() =>
      '当前未开启电台扩容，此操作会超出容量：${describeCapacityViolations(issues).join('；')}。请先开启电台扩容，或减少歌曲数量。';
}

/// Shared by settings, all playlist mutations, history restoration and persistence.
class PlaylistCapacityPolicy {
  PlaylistCapacityPolicy(Map<String, Map<String, int>> limits)
    : limits = Map.unmodifiable({
        for (final entry in limits.entries)
          entry.key: Map<String, int>.unmodifiable(entry.value),
      });
  final Map<String, Map<String, int>> limits;
  List<PlaylistCapacityViolation> violations(
    PlaylistPlan plan, {
    Map<String, Map<String, int>> fallbackCounts = const {},
  }) {
    final issues = <PlaylistCapacityViolation>[];
    for (final entry in limits.entries) {
      final sources = <String>{};
      var bankLimit = 0;
      for (final type in ['FreeRoam', 'Event']) {
        final limit = entry.value[type]!;
        if (limit > bankLimit) bankLimit = limit;
        final assigned = plan.assignmentsForRadio(entry.key, type);
        sources.addAll(
          assigned.map((a) => PlaylistAssignment.keyForPath(a.source)),
        );
        final count = plan.hasBuiltinOverride(entry.key, type)
            ? 0
            : assigned.isNotEmpty
            ? assigned.length
            : fallbackCounts[entry.key]?[type] ?? 0;
        if (count > limit) {
          issues.add(PlaylistCapacityViolation(entry.key, type, count, limit));
        }
      }
      if (sources.length > bankLimit) {
        issues.add(
          PlaylistCapacityViolation(entry.key, null, sources.length, bankLimit),
        );
      }
    }
    return issues;
  }

  void requireTransition(
    PlaylistPlan before,
    PlaylistPlan after, {
    bool allowExistingOverflow = true,
  }) {
    final previous = {
      for (final issue in violations(before)) issue.key: issue.count,
    };
    final rejected = violations(after)
        .where(
          (issue) =>
              !allowExistingOverflow ||
              issue.count > (previous[issue.key] ?? issue.limit),
        )
        .toList();
    if (rejected.isNotEmpty) throw PlaylistCapacityException(rejected);
  }
}
