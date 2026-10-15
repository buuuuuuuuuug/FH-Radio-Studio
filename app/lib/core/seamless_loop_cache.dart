import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'atomic_file.dart';

/// Caches structured CLI output; source, engine and candidate count all invalidate it.
class SeamlessLoopCache {
  static final _memory = <String, Map<String, dynamic>>{};
  static final _engineHashes = <String, String>{};
  static void clearMemory() {
    _memory.clear();
    _engineHashes.clear();
  }

  static Future<(File, String)> _entry(
    String project,
    String source,
    String dll,
  ) async {
    final sourceStat = await File(source).stat();
    final engineStat = await File(dll).stat();
    if (sourceStat.type != FileSystemEntityType.file ||
        engineStat.type != FileSystemEntityType.file) {
      throw const FormatException('音频或循环分析组件不存在');
    }
    final engineKey =
        '${File(dll).absolute.path}:${engineStat.size}:${engineStat.modified.microsecondsSinceEpoch}';
    final hash =
        _engineHashes[engineKey] ??
        sha256.convert(await File(dll).readAsBytes()).toString();
    _engineHashes[engineKey] = hash;
    while (_engineHashes.length > 4) {
      _engineHashes.remove(_engineHashes.keys.first);
    }
    final key = sha256
        .convert(utf8.encode('${File(source).absolute.path}|$hash'))
        .toString();
    return (
      File('$project/analysis/seamless-loops/view-$key.json'),
      'v2:10:${sourceStat.size}:${sourceStat.modified.microsecondsSinceEpoch}:$hash',
    );
  }

  static Future<Map<String, dynamic>?> read(
    String project,
    String source,
    String dll,
  ) async {
    try {
      final (file, stamp) = await _entry(project, source, dll);
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
    String dll,
    Map<String, dynamic> payload,
  ) async {
    final (file, stamp) = await _entry(project, source, dll);
    final record = <String, dynamic>{'stamp': stamp, 'payload': payload};
    await writeTextAtomically(file, jsonEncode(record));
    _remember(file.path, record);
  }

  static void _remember(String key, Map<String, dynamic> record) {
    _memory.remove(key);
    _memory[key] = record;
    while (_memory.length > 16) {
      _memory.remove(_memory.keys.first);
    }
  }
}
