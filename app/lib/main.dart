import 'widgets/feature_tour.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'state/app_state.dart';
import 'core/studio_audio_players.dart';
import 'core/studio_http_proxy.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StudioHttpProxy.install();
  MediaKit.ensureInitialized();
  // Isolate preferences from the user's existing modified Studio installation.
  final uiTest = Platform.environment['FH_RADIO_STUDIO_UI_TEST_PROJECT'];
  SharedPreferences.setPrefix(
    uiTest == null ? 'fh_loop_lab.' : 'fh_loop_lab_ui_test.',
  );
  final prefs = await SharedPreferences.getInstance();
  if (uiTest != null) await prefs.setString('rm.studio.projectDir', uiTest);

  runApp(
    ProviderScope(
      overrides: [
        automaticFeatureToursProvider.overrideWithValue(true),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const FhRadioStudioApp(),
    ),
  );
  StudioAudioPlayers.warmUp();
}
