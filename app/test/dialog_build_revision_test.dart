import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fh_radio_studio/theme/app_theme.dart';
import 'package:fh_radio_studio/theme/accents.dart';
import 'package:fh_radio_studio/widgets/song_metadata_button.dart';
import 'package:fh_radio_studio/widgets/package_publication_recovery.dart';
import 'package:fh_radio_studio/widgets/timing_dialog_frame.dart';

Widget app(Widget child) => MaterialApp(
  theme: buildAppTheme(brightness: Brightness.light, accent: AppAccent.lime),
  home: Scaffold(body: child),
);

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  testWidgets('metadata dialog closes on outside click without saving', (
    t,
  ) async {
    var saves = 0;
    await t.pumpWidget(
      app(
        SongMetadataButton(
          title: 'Title',
          artist: 'Artist',
          onSave: (_, _) async {
            saves++;
            return true;
          },
        ),
      ),
    );
    await t.tap(find.text('编辑歌曲信息'));
    await t.pumpAndSettle();
    expect(find.byType(TimingDialogFrame), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('游戏使用自己的字体'), findsNothing);
    await t.enterText(find.byType(TextField).first, 'Unsaved title');
    await t.tapAt(const Offset(8, 8));
    await t.pumpAndSettle();
    expect(find.byType(TimingDialogFrame), findsNothing);
    expect(saves, 0);
  });

  testWidgets('metadata dialog cannot dismiss while saving', (t) async {
    final saved = Completer<bool>();
    await t.pumpWidget(
      app(
        SongMetadataButton(
          title: 'Title',
          artist: 'Artist',
          onSave: (_, _) => saved.future,
        ),
      ),
    );
    await t.tap(find.text('编辑歌曲信息'));
    await t.pumpAndSettle();
    await t.tap(find.text('保存歌曲信息'));
    await t.pump();
    await t.tapAt(const Offset(8, 8));
    await t.pumpAndSettle();
    expect(find.byType(TimingDialogFrame), findsOneWidget);
    saved.complete(true);
    await t.pumpAndSettle();
    expect(find.byType(TimingDialogFrame), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'publication confirmation uses app dialog and supports outside dismissal',
    (t) async {
      await t.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showPackagePublicationDialog(context),
              child: const Text('打开确认'),
            ),
          ),
        ),
      );
      await t.tap(find.text('打开确认'));
      await t.pumpAndSettle();
      expect(find.byType(TimingDialogFrame), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('重试替换'), findsOneWidget);
      await t.tapAt(const Offset(8, 8));
      await t.pumpAndSettle();
      expect(find.byType(TimingDialogFrame), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
}
