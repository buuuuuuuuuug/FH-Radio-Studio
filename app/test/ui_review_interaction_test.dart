import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:fh_radio_studio/screens/project_picker.dart';
import 'package:fh_radio_studio/screens/replace_editor/replace_editor.dart';
import 'package:fh_radio_studio/screens/replace_editor/replace_state.dart';
import 'package:fh_radio_studio/state/app_state.dart';
import 'package:fh_radio_studio/state/studio_state.dart';
import 'package:fh_radio_studio/widgets/rm_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'editor_playlist_upgrade_test.dart' as fixture;
import 'studio_v21_workflow_test.dart' as helpers;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
    'buttons support keyboard focus, activation and disabled semantics',
    (t) async {
      final semantics = t.ensureSemantics();
      var calls = 0;
      var disabledCalls = 0;
      await t.pumpWidget(
        helpers.app(
          Row(
            children: [
              RmButton(label: 'Disabled', onPressed: null),
              RmButton(
                label: 'Blocked',
                disabled: true,
                onPressed: () => disabledCalls++,
              ),
              RmButton(label: 'Action', onPressed: () => calls++),
            ],
          ),
        ),
      );
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      expect(Focus.of(t.element(find.text('Action'))).hasFocus, isTrue);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pump();
      expect(calls, 2);
      await t.tap(find.text('Blocked'));
      await t.pump();
      expect(disabledCalls, 0);
      final data = t.getSemantics(find.text('Action')).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.isTrue);
      expect(t.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets('a repeating button stops immediately when disabled mid-press', (
    t,
  ) async {
    var enabled = true;
    var calls = 0;
    await t.pumpWidget(
      helpers.app(
        StatefulBuilder(
          builder: (_, update) => Center(
            child: RmButton(
              label: 'Nudge',
              repeat: true,
              onPressed: enabled
                  ? () {
                      calls++;
                      update(() => enabled = false);
                    }
                  : null,
            ),
          ),
        ),
      ),
    );
    final press = await t.startGesture(t.getCenter(find.text('Nudge')));
    await t.pump(const Duration(milliseconds: 510));
    await t.pump(const Duration(seconds: 1));
    await press.up();
    await t.pump();
    expect(calls, 1);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'editor page shortcuts retain initial Space and Enter ownership',
    (t) async {
      final f = await fixture.fixture();
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: helpers.app(
            const ReplaceEditorScreen(trackId: 'p1', enableAudio: false),
          ),
        ),
      );
      await t.pumpAndSettle();
      final notifier = f.container.read(replaceEditorProvider('p1').notifier);
      expect(notifier.state.playing, isFalse);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'replace-editor-hotkeys',
      );
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'replace-editor-hotkeys',
      );
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(notifier.state.playing, isFalse);
      expect(notifier.state.tdConfirmed, isTrue);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'page shortcuts keep Space and Enter after mouse button actions',
    (t) async {
      var pageShortcuts = 0, buttonCalls = 0;
      await t.pumpWidget(
        helpers.app(
          Focus(
            autofocus: true,
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent &&
                  (event.logicalKey == LogicalKeyboardKey.space ||
                      event.logicalKey == LogicalKeyboardKey.enter)) {
                pageShortcuts++;
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Center(
              child: RmButton(label: 'Action', onPressed: () => buttonCalls++),
            ),
          ),
        ),
      );
      await t.pump();
      await t.tap(find.text('Action'));
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(buttonCalls, 1);
      expect(pageShortcuts, 2);
      expect(t.takeException(), isNull);
    },
  );

  const pickerChannel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
  for (final relocate in [false, true]) {
    testWidgets(
      'pending ${relocate ? 'relocation' : 'project selection'} ignores a disposed page',
      (t) async {
        final pending = Completer<String?>();
        var pickerCalls = 0;
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          pickerChannel,
          (call) {
            expect(call.method, 'dir');
            pickerCalls++;
            return pending.future;
          },
        );
        addTearDown(
          () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            pickerChannel,
            null,
          ),
        );
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final controller = _PickerController(prefs);
        if (relocate) {
          controller.showMissingRecent();
        }
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            studioProvider.overrideWith((_) => controller),
          ],
        );
        addTearDown(container.dispose);
        await t.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: helpers.app(const ProjectPickerScreen()),
          ),
        );
        if (relocate) {
          await t.tap(find.text(_PickerController.missingProject));
          await t.pumpAndSettle();
          await t.tap(find.text('重新定位'));
        } else {
          await t.tap(find.text('新建工程'));
          await t.pump();
          await t.tap(find.text('打开项目目录'));
        }
        await t.pump();
        expect(pickerCalls, 1);
        await t.pumpWidget(const SizedBox.shrink());
        pending.complete('D:/unused-selected-project');
        await t.pumpAndSettle();
        expect(controller.opens, 0);
        expect(controller.relocations, 0);
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets('native directory picker errors show a message and allow retry', (
    t,
  ) async {
    var calls = 0;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(pickerChannel, (
      call,
    ) async {
      calls++;
      if (calls == 1) {
        throw MissingPluginException('directory picker unavailable');
      }
      return null;
    });
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        pickerChannel,
        null,
      ),
    );
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          studioProvider.overrideWith((_) => _PickerController(prefs)),
        ],
        child: helpers.app(const ProjectPickerScreen()),
      ),
    );
    await t.tap(find.text('新建工程'));
    await t.pumpAndSettle();
    expect(find.textContaining('无法选择项目目录'), findsOneWidget);
    await t.tap(find.text('打开项目目录'));
    await t.pumpAndSettle();
    expect(calls, 2);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'project operations block selection before and after native dialog',
    (t) async {
      final pending = <Completer<String?>>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(pickerChannel, (
        call,
      ) {
        final result = Completer<String?>();
        pending.add(result);
        return result.future;
      });
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          pickerChannel,
          null,
        ),
      );
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = _PickerController(prefs);
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            studioProvider.overrideWith((_) => controller),
          ],
          child: helpers.app(const ProjectPickerScreen()),
        ),
      );
      for (final mode in ['busy', 'scan', 'migration']) {
        controller.setOperation(mode);
        await t.pump();
        await t.tap(find.text('新建工程'));
        await t.pump();
        final count = pending.length;
        controller.setOperation(null);
        await t.pump();
        await t.tap(find.text('新建工程'));
        await t.pump();
        expect(pending.length, count + 1);
        controller.setOperation(mode);
        await t.pump();
        pending.last.complete('D:/unused-selected-project');
        await t.pumpAndSettle();
        expect(controller.opens, 0);
      }
      expect(pending.length, 3);
      expect(t.takeException(), isNull);
    },
  );
}

class _PickerController extends StudioController {
  _PickerController(super.prefs);
  static const missingProject = 'Z:/missing-review-project';
  int opens = 0, relocations = 0;

  void showMissingRecent() {
    state = state.copyWith(recentProjectDirs: [missingProject]);
  }

  void setOperation(String? mode) {
    state = state.copyWith(
      busy: mode == 'busy',
      refreshingPanels: mode == 'scan' ? {'fileIntegrity'} : {},
      projectPathMigrationRunning: mode == 'migration',
    );
  }

  @override
  void setProjectDirAndStartFullScan(String value) => opens++;

  @override
  void updateRecentProjectPath(String oldPath, String newPath) => relocations++;
}
