import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fh_radio_studio/state/unsaved_edits.dart';
import 'package:fh_radio_studio/theme/accents.dart';
import 'package:fh_radio_studio/theme/app_theme.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
    'a queued window close checks playlist edits after the track prompt',
    (tester) async {
      final edits = UnsavedEdits();
      final dirty = {'track': true, 'playlist': true};
      final saved = <String>[];
      for (final key in dirty.keys) {
        edits.entries[key] = PendingEdit(
          label: key,
          dirty: () => dirty[key]!,
          save: () {
            saved.add(key);
            dirty[key] = false;
          },
          discard: () => dirty[key] = false,
        );
      }
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(
            brightness: Brightness.light,
            accent: AppAccent.lime,
          ),
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                context = ctx;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      final trackPrompt = edits.confirm(context, key: 'track', switching: true);
      await tester.pumpAndSettle();
      final closing = edits.confirm(context, exiting: true);
      await tester.tap(find.text('保存并切换'));
      await tester.pumpAndSettle();
      expect(await trackPrompt, isTrue);
      expect(saved, ['track']);
      expect(find.text('关闭前保存修改？'), findsOneWidget);
      await tester.tap(find.text('保存并关闭'));
      await tester.pumpAndSettle();
      expect(await closing, isTrue);
      expect(saved, ['track', 'playlist']);
      expect(edits.isDirty, isFalse);
    },
  );
}
