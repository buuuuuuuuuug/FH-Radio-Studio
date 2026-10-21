import 'dart:io';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'project_refs.dart';
import 'project_workspace.dart';
import 'path_keys.dart';

/// Only used when the user explicitly creates a new project. Metadata and audio
/// normalization still go through the normal CLI import pipeline.
class DemoSong {
  static const asset = 'assets/audio/looplab_demo.wav';
  static const fileName = 'LoopLab - 功能演示.wav';
  static File _marker(String root) =>
      File(p.join(FhRadioStudioProject.metadataDir(root), 'tutorial-demo.ref'));

  static bool matches(String root, String source) {
    final demo = sourceFor(root);
    return demo != null && canonicalPathKey(demo) == canonicalPathKey(source);
  }

  static String? sourceFor(String root) {
    try {
      final marker = _marker(root);
      if (!marker.existsSync()) return null;
      final value = marker.readAsStringSync(encoding: utf8).trim();
      if (!isProjectRef(value)) return null;
      final source = resolveProjectRef(root, value);
      return File(source).existsSync() ? source : null;
    } on Object {
      return null;
    }
  }

  static Future<void> install(
    String root,
    Future<List<String>> Function(String path) importAudio,
  ) async {
    if (sourceFor(root) != null) return;
    final temp = await Directory.systemTemp.createTemp('looplab_demo_');
    try {
      final bytes = await rootBundle.load(asset);
      final input = File(p.join(temp.path, fileName));
      await input.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      final imported = await importAudio(input.path);
      if (imported.length != 1) throw const FormatException('演示歌曲未能导入');
      final ref = projectRefForPath(root, imported.single);
      if (ref == null) throw const FormatException('演示歌曲不在当前工程内');
      await _marker(root).writeAsString('$ref\n', encoding: utf8);
    } finally {
      // This directory was allocated by createTemp and contains only our asset.
      await temp.delete(recursive: true);
    }
  }
}
