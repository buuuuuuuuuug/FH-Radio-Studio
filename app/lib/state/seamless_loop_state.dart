import '../core/seamless_loop_cache.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/fh_radio_studio_cli.dart';
import '../domain/replacement_models.dart';
import 'studio_state.dart';

final seamlessEnginePathProvider = Provider<String>((ref) {
  final root = ref.watch(studioProvider.select((s) => s.repoRoot));
  return '${FhRadioStudioCli(repoRoot: root).uvRuntime.audioToolsDir}/seamless/loopfinder.dll';
});

typedef SeamlessLoopLoader =
    Future<List<LoopCandidate>> Function(
      String repoRoot,
      String project,
      String source,
      CliCancellationToken token,
      bool force,
    );

final seamlessLoopLoaderProvider = Provider<SeamlessLoopLoader>(
  (ref) => (repoRoot, project, source, token, force) async {
    final cli = FhRadioStudioCli(repoRoot: repoRoot);
    final tools = cli.uvRuntime.audioToolsDir;
    final dll = ref.read(seamlessEnginePathProvider);
    final cached = force
        ? null
        : await SeamlessLoopCache.read(project, source, dll);
    if (token.isCancelled) throw const FormatException('循环分析已取消');
    if (cached != null) {
      try {
        return seamlessCandidatesFromPayload(cached);
      } on FormatException {
        // The view cache is optional; regenerate a damaged entry through CLI.
      }
    }
    final result = await cli.runBase([
      'analyze-seamless-loops',
      source,
      '--slm-dll',
      dll,
      '--cache-dir',
      '$project/analysis/seamless-loops',
      if (force) '--force',
      if (File('$tools/ffmpeg/ffmpeg.exe').existsSync()) ...[
        '--ffmpeg',
        '$tools/ffmpeg/ffmpeg.exe',
      ],
    ], cancellationToken: token);
    if (token.isCancelled) throw const FormatException('循环分析已取消');
    if (!result.ok) throw FormatException('循环分析失败：${result.stderr}');
    final data = jsonDecode(result.stdout) as Map<String, dynamic>;
    final loops = seamlessCandidatesFromPayload(data);
    try {
      await SeamlessLoopCache.write(project, source, dll, data);
    } on Object {
      /* cache is optional */
    }
    return loops;
  },
);

List<LoopCandidate> seamlessCandidatesFromPayload(Map<String, dynamic> data) {
  final duration = data['duration_sec'];
  final candidates = data['candidates'];
  final raw = candidates is Map ? candidates['tl'] : null;
  if (duration is! num || !duration.isFinite || duration <= 0 || raw is! List) {
    throw const FormatException('循环分析结果格式无效，可重新分析或手动精调。');
  }
  final loops = <LoopCandidate>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final start = item['start'], end = item['end'], score = item['score'];
    if (start is! num || end is! num || score is! num) continue;
    final a = start.toDouble(), b = end.toDouble();
    if (!a.isFinite ||
        !b.isFinite ||
        !score.isFinite ||
        a < 0 ||
        b <= a ||
        b > duration) {
      continue;
    }
    loops.add(
      LoopCandidate(
        start: a,
        end: b,
        score: score.toDouble().clamp(0, 1),
        bars: 0,
        why: '${item['why']}',
      ),
    );
  }
  if (loops.isEmpty) throw const FormatException('没有有效循环建议，可继续手动精调。');
  return loops;
}
