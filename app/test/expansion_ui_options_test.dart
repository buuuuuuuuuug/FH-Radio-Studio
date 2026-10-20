import 'dart:ui' as ui;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fh_radio_studio/core/game_deployment_target.dart';
import 'package:fh_radio_studio/domain/radio_library.dart';
import 'package:fh_radio_studio/screens/dashboard.dart';
import 'package:fh_radio_studio/screens/playlist/radio_column.dart';
import 'package:fh_radio_studio/state/studio_state.dart';
import 'package:fh_radio_studio/theme/accents.dart';
import 'package:fh_radio_studio/theme/app_theme.dart';

void main() {
  for (final cancelMethod in ['close-icon', 'cancel-button', 'escape']) {
    testWidgets('typed deployment dialog closes safely via $cancelMethod', (
      tester,
    ) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      SharedPreferences.setMockInitialValues({
        'rm.studio.projectDir': 'deployment-close-fixture',
      });
      final prefs = await SharedPreferences.getInstance();
      final controller = StudioController(prefs);
      addTearDown(controller.dispose);
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var returns = 0;
      GameDeploymentTarget? result = GameDeploymentTarget.media;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(
            brightness: Brightness.light,
            accent: AppAccent.lime,
          ),
          home: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) => Scaffold(
                body: Column(
                  children: [
                    const Text('Project overview remains visible'),
                    TextButton(
                      onPressed: () async {
                        result = await showDialog<GameDeploymentTarget>(
                          context: context,
                          builder: (_) =>
                              deploymentDialogForTesting(controller.state),
                        );
                        returns++;
                      },
                      child: const Text('Open write dialog'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.tap(find.text('Open write dialog'));
        await tester.pumpAndSettle();
        expect(find.text('写入游戏前请确认'), findsOneWidget);
        switch (cancelMethod) {
          case 'close-icon':
            await tester.tap(find.byTooltip('关闭'));
          case 'cancel-button':
            await tester.tap(find.text('取消'));
          case 'escape':
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(result, isNull);
        expect(returns, attempt + 1);
        expect(find.byType(Dialog), findsNothing);
        expect(find.text('Project overview remains visible'), findsOneWidget);
      }
    });
  }
  testWidgets('deployment offers both paths with mediapc selected initially', (
    tester,
  ) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({
      'rm.studio.projectDir': 'deployment-fixture',
    });
    final prefs = await SharedPreferences.getInstance();
    final controller = StudioController(prefs);
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(
          brightness: Brightness.light,
          accent: AppAccent.lime,
        ),
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: deploymentDialogForTesting(controller.state),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final finder = find.byKey(const ValueKey('deploy-choice-mediapc'));
    expect(tester.widget<Semantics>(finder).properties.selected, isTrue);
    expect(find.text('media（覆盖原文件）'), findsOneWidget);
    expect(find.text('mediapc（默认）'), findsOneWidget);
    await tester.tap(find.text('media（覆盖原文件）'));
    await tester.pumpAndSettle();
    expect(tester.widget<Semantics>(finder).properties.selected, isFalse);
    expect(
      tester
          .widget<Semantics>(find.byKey(const ValueKey('deploy-choice-media')))
          .properties
          .selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
    if (Platform.environment['CAPTURE_EXPANSION_OPTIONS'] == '1') {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/visual_qa/deployment_options.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });

  testWidgets('expanded radio displays baseline song count at narrow width', (
    tester,
  ) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    const radio = RadioStation(
      code: 'R9',
      name: 'Horizon Opus',
      hue: 'violet',
      genre: 'Classical',
      slot: 24,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(
          brightness: Brightness.light,
          accent: AppAccent.lime,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 205,
              height: 480,
              child: PlaylistColumn.radio(
                radio: radio,
                isCustom: true,
                count: 24,
                capacity: 4096,
                originalCount: 22,
                children: const [],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('24 首 · 原有 22 首 · 扩容'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
