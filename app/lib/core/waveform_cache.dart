import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'atomic_file.dart';

/// A small, versioned view cache of CLI waveform output. Audio decoding and
/// waveform analysis remain entirely in the CLI. Changed sources invalidate it.
class WaveformCache {
  static final _memory = <String, Map<String, dynamic>>{};
  static final _writes = <String, Future<void>>{};
  static void clearMemory() => _memory.clear();
  static Future<(File, String)> _entry(String project, String source) async {
    final stat = await File(source).stat();
    final identity = '$project|${File(source).absolute.path}';
    final key = sha256.convert(utf8.encode(identity)).toString();
    return (
      File('$project/analysis/waveforms/view-$key.json'),
      'v3:${stat.size}:${stat.modified.microsecondsSinceEpoch}',
    );
  }

  static Future<Map<String, dynamic>?> read(
    String project,
    String source,
  ) async {
    try {
      final (file, stamp) = await _entry(project, source);
      final record =
          _memory[file.path] ??
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (record['stamp'] != stamp || record['payload'] is! Map) return null;
      _remember(file.path, record);
      return Map<String, dynamic>.from(record['payload'] as Map);
    } on Object {
      return null;
    }
  }

  static Future<void> write(
    String project,
    String source,
    Map<String, dynamic> payload,
  ) async {
    final key = '$project|${File(source).absolute.path}';
    final previous = _writes[key];
    final result = () async {
      if (previous != null) await previous;
      await _write(project, source, payload);
    }();
    final gate = result.then<void>((_) {}, onError: (Object _) {});
    _writes[key] = gate;
    unawaited(
      gate.then((_) {
        if (identical(_writes[key], gate)) _writes.remove(key);
      }),
    );
    return result;
  }

  static Future<void> _write(
    String project,
    String source,
    Map<String, dynamic> payload,
  ) async {
    final (file, stamp) = await _entry(project, source);
    final existing = await read(project, source);
    final next = Map<String, dynamic>.from(payload);
    final oldWave = existing?['waveform'];
    final newWave = payload['waveform'];
    if (oldWave is Map &&
        newWave is Map &&
        oldWave['bins'] is List &&
        newWave['bins'] is List &&
        (oldWave['bins'] as List).length > (newWave['bins'] as List).length) {
      next['waveform'] = oldWave;
    }
    final record = <String, dynamic>{'stamp': stamp, 'payload': next};
    await writeTextAtomically(file, jsonEncode(record));
    _remember(file.path, record);
  }

  static void _remember(String key, Map<String, dynamic> value) {
    _memory.remove(key);
    _memory[key] = value;
    while (_memory.length > 8) {
      _memory.remove(_memory.keys.first);
    }
  }
}
