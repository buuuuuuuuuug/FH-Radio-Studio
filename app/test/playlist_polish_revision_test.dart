import 'package:fh_radio_studio/core/playlist_plan.dart';
import 'package:fh_radio_studio/state/studio_state.dart';
import 'package:fh_radio_studio/theme/rainbow_border.dart';
import 'package:fh_radio_studio/widgets/cross_radio_assignment_notice.dart';
import 'package:fh_radio_studio/widgets/package_loudness_dialog.dart';
import 'package:fh_radio_studio/widgets/rm_select.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'studio_v21_workflow_test.dart' as helpers;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  const source = r'C:\project\sources\song.wav';
  PlaylistPlan oneRadio() => const PlaylistPlan.empty()
      .assign(
        source: source,
        radioCode: 'R1',
        playlistType: 'FreeRoam',
        slot: 1,
      )
      .assign(source: source, radioCode: 'R1', playlistType: 'Event', slot: 1);
  PlaylistPlan multipleRadios() => oneRadio().assign(
    source: source.toUpperCase(),
    radioCode: 'R2',
    playlistType: 'FreeRoam',
    slot: 1,
  );

  test(
    'cross-radio notices distinguish scenes, path casing and removed assignments',
    () {
      expect(oneRadio().crossRadioAssignments, isEmpty);
      final multi = multipleRadios();
      expect(multi.crossRadioAssignments.length, 1);
      expect(multi.crossRadioAssignments.values.single.length, 3);
      final restored = PlaylistPlanCodec.decodeJson(multi.encodeForCli());
      expect(restored.crossRadioAssignments.length, 1);
      expect(
        multi
            .restoreBuiltin(radioCode: 'R2', playlistType: 'FreeRoam')
            .crossRadioAssignments,
        isEmpty,
      );
    },
  );

  testWidgets('playlist and pre-build notice names every affected station', (
    t,
  ) async {
    await t.pumpWidget(
      helpers.app(
        CrossRadioAssignmentNotice(
          plan: multipleRadios(),
          titleForSource: (_) => '演示曲',
        ),
      ),
    );
    expect(
      find.textContaining('1 首歌曲分配到多个电台', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('演示曲：R1 / R2', findRichText: true),
      findsOneWidget,
    );
    await t.pumpWidget(
      helpers.app(
        PackageLoudnessDialog(
          referenceMedianLufs: -18,
          initialOffsetLu: 3,
          previewInputLufs: -18,
          assignmentPlan: multipleRadios(),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('cross-radio-assignment-notice')),
      findsOneWidget,
    );
    expect(find.text('响度战争'), findsNothing);
    expect(find.text('响度调整'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('loudness song selection preserves selected output loudness', (
    t,
  ) async {
    const previews = [
      PackageBuildLoudnessPreview(
        referenceMedianLufs: -18,
        initialOffsetLu: 3,
        previewInputLufs: -22,
        previewInputLufsHeuristic: false,
        source: 'not-present-a.wav',
        previewTitle: 'First',
      ),
      PackageBuildLoudnessPreview(
        referenceMedianLufs: -18,
        initialOffsetLu: 3,
        previewInputLufs: -14,
        previewInputLufsHeuristic: false,
        source: 'not-present-b.wav',
        previewTitle: 'Second',
      ),
    ];
    await t.pumpWidget(
      helpers.app(
        const PackageLoudnessDialog(
          referenceMedianLufs: -18,
          initialOffsetLu: 3,
          previewInputLufs: -22,
          previewTracks: previews,
        ),
      ),
    );
    await t.pumpAndSettle();
    final selector = find.byKey(const ValueKey('loudness-preview-track'));
    t.widget<RmSelect<String>>(selector).onChanged!('not-present-b.wav');
    await t.pumpAndSettle();
    expect(t.widget<RmSelect<String>>(selector).value, 'not-present-b.wav');
    expect(find.text('+3 LU'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'global bottom notifications use a rainbow outline in the app theme',
    (t) async {
      late BuildContext context;
      await t.pumpWidget(
        helpers.app(
          Builder(
            builder: (value) {
              context = value;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(Theme.of(context).snackBarTheme.shape, isA<RainbowBorder>());
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已保存')));
      await t.pumpAndSettle();
      expect(find.text('已保存'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
