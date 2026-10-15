import 'dart:async';

import 'package:media_kit/media_kit.dart';

/// Keep native mpv instances alive across routes. Destroying a native player
/// waits for decoder threads and can block the UI during Escape navigation.
class StudioAudioPlayers {
  StudioAudioPlayers._();

  static Player? _pool;
  static Player? _editor;
  static String? poolSource;
  static String? editorSource;
  static Player get pool => _pool ??= Player();
  static Player get editor => _editor ??= Player();

  static void warmUp() {
    Timer(const Duration(milliseconds: 300), () {
      pool;
      editor;
    });
  }
}
