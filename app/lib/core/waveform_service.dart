import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'fh_radio_studio_cli.dart';
import 'waveform_cache.dart';

class WaveformService {
  static final _active = <String, Future<void>>{};
  static Future<Map<String, dynamic>> load({
    required String project,
    required String repoRoot,
    required String source,
    CliCancellationToken? token,
  }) {
    final key = '$project|$source';
    final previous = _active[key];
    final result = () async {
      // Serialize readers of the same source. A batch cancellation must not
      // cancel an editor's request, nor race its atomic cache write.
      if (previous != null) await previous;
      if (token?.isCancelled ?? false) throw const FormatException('已取消波形分析');
      return _load(
        project: project,
        repoRoot: repoRoot,
        source: source,
        token: token,
      );
    }();
    final gate = result.then<void>((_) {}, onError: (Object _) {});
    _active[key] = gate;
    unawaited(
      gate.then((_) {
        if (identical(_active[key], gate)) _active.remove(key);
      }),
    );
    return result;
  }

  static Future<Map<String, dynamic>> _load({
    required String project,
    required String repoRoot,
    required String source,
    CliCancellationToken? token,
  }) async {
    final cached = await WaveformCache.read(project, source);
    if (cached != null) return cached;
    final cli = FhRadioStudioCli(repoRoot: repoRoot);
    final ffmpeg = '${cli.uvRuntime.audioToolsDir}/ffmpeg/ffmpeg.exe';
    final result = await cli.runBase([
      'waveform-audio',
      source,
      '--cache-dir',
      '$project/analysis/waveforms',
      if (File(ffmpeg).existsSync()) ...['--ffmpeg', ffmpeg],
    ], cancellationToken: token);
    if (token?.isCancelled ?? false) throw const FormatException('已取消波形分析');
    if (!result.ok) throw FormatException('波形读取失败：${result.stderr}');
    final payload = jsonDecode(result.stdout) as Map<String, dynamic>;
    try {
      await WaveformCache.write(project, source, payload);
    } on Object {
      // Editing remains available even if the optional view cache cannot be saved.
    }
    return payload;
  }
}
