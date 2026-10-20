import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:fh_radio_studio/domain/radio_library.dart';
import 'package:fh_radio_studio/screens/playlist.dart';
import 'package:fh_radio_studio/state/app_state.dart';
import 'package:fh_radio_studio/state/layout_options.dart';
import 'package:fh_radio_studio/state/custom_pool_tracks.dart';
import 'package:fh_radio_studio/state/playlist_catalog_state.dart';
import 'package:fh_radio_studio/theme/accents.dart';
import 'package:fh_radio_studio/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('auto height keeps songs visible in a short narrow window', (
    tester,
  ) async {
    await _pumpPlaylist(tester, const Size(840, 820));
    final scope = ProviderScope.containerOf(
      tester.element(find.byType(PlaylistScreen)),
    );
    final options = scope.read(layoutOptionsProvider.notifier);
    options.setRadioColumns(2);
    options.setHeightMode(RadioHeightMode.allStations);
    await tester.pump();
    final station = find.byKey(const ValueKey('playlist-radio-column-R1'));
    final songs = find.descendant(of: station, matching: find.byType(ListView));
    expect(tester.getSize(songs).height, greaterThanOrEqualTo(60));
    final board = tester.widget<GridView>(
      find.byKey(const ValueKey('playlist-radio-board')),
    );
    expect(board.controller!.position.maxScrollExtent, greaterThan(0));
    board.controller!.jumpTo(board.controller!.position.maxScrollExtent);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('playlist-radio-column-R9')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('very narrow board stacks pool without violating station width', (
    tester,
  ) async {
    await _pumpPlaylist(tester, const Size(364, 1100));
    final scope = ProviderScope.containerOf(
      tester.element(find.byType(PlaylistScreen)),
    );
    scope.read(layoutOptionsProvider.notifier).setRadioColumns(6);
    await tester.pump();
    final first = find.byKey(const ValueKey('playlist-radio-column-R1'));
    final pool = find.byKey(const ValueKey('playlist-pool-side-panel'));
    expect(tester.getSize(first).width, greaterThanOrEqualTo(205));
    expect(tester.getBottomRight(first).dx, lessThanOrEqualTo(324));
    expect(
      tester.getTopLeft(pool).dy,
      greaterThan(tester.getTopLeft(first).dy),
    );
    expect(
      tester
          .widget<Slider>(find.byKey(const ValueKey('radio-columns-slider')))
          .onChanged,
      isNull,
    );
    expect(tester.getSize(find.text('播放列表')).height, lessThan(60));
    expect(
      tester.getTopLeft(first).dy,
      lessThan(tester.view.physicalSize.height - 200),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'playlist search text and filtering survive leaving and returning',
    (tester) async {
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      await _pumpPlaylist(tester, const Size(1365, 900), visible: visible);
      final search = find.byKey(const ValueKey('playlist-search'));
      await tester.enterText(search, 'unmatched song');
      await tester.pump();
      visible.value = false;
      await tester.pump();
      visible.value = true;
      await tester.pump();
      expect(
        tester.widget<TextField>(search).controller!.text,
        'unmatched song',
      );
      await tester.tap(find.byTooltip('清空搜索'));
      await tester.pump();
      expect(tester.widget<TextField>(search).controller!.text, '');
      expect(find.byTooltip('清空搜索'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'inline grid controls resize auto heights and protect six narrow columns',
    (tester) async {
      await _pumpPlaylist(tester, const Size(1900, 1100));
      final scope = ProviderScope.containerOf(
        tester.element(find.byType(PlaylistScreen)),
      );
      final ctl = scope.read(layoutOptionsProvider.notifier);
      ctl.setWidth(-1);
      ctl.setRadioColumns(3);
      ctl.setHeightMode(RadioHeightMode.allStations);
      await tester.pump();
      final first = find.byKey(const ValueKey('playlist-radio-column-R1'));
      final ninth = find.byKey(const ValueKey('playlist-radio-column-R9'));
      final pool = find.byKey(const ValueKey('playlist-pool-side-panel'));
      expect(
        tester.getBottomRight(ninth).dy,
        lessThanOrEqualTo(tester.getBottomRight(pool).dy + 1),
      );
      final height = tester.getSize(first).height;
      tester.view.physicalSize = const Size(1900, 950);
      await tester.pump();
      expect(tester.getSize(first).height, lessThan(height));
      ctl.setHeightMode(RadioHeightMode.oneRow);
      await tester.pump();
      expect(
        tester.getSize(first).height,
        closeTo(tester.getSize(pool).height, 1),
      );
      ctl.setRadioColumns(6);
      tester.view.physicalSize = const Size(960, 950);
      await tester.pump();
      expect(tester.getSize(first).width, greaterThanOrEqualTo(205));
      final second = find.byKey(const ValueKey('playlist-radio-column-R2'));
      final third = find.byKey(const ValueKey('playlist-radio-column-R3'));
      expect(
        tester.getBottomRight(second).dx,
        lessThanOrEqualTo(tester.getTopLeft(pool).dx - 12 + .01),
      );
      final firstY = tester.getTopLeft(first).dy;
      final grid = find.byKey(const ValueKey('playlist-radio-board'));
      tester
          .widget<GridView>(grid)
          .controller!
          .jumpTo(
            (tester.getSize(first).height + 12).clamp(
              0,
              tester
                  .widget<GridView>(grid)
                  .controller!
                  .position
                  .maxScrollExtent,
            ),
          );
      await tester.pump();
      expect(
        tester.getTopLeft(third).dy +
            tester.widget<GridView>(grid).controller!.offset,
        greaterThan(firstY),
      );
      expect(
        tester
            .widget<Slider>(find.byKey(const ValueKey('radio-columns-slider')))
            .max,
        1,
      );
      expect(tester.getBottomRight(pool).dx, lessThanOrEqualTo(920));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'expanded page width stays inside window and list height is independent',
    (tester) async {
      await _pumpPlaylist(tester, const Size(1900, 1000));
      final scope = ProviderScope.containerOf(
        tester.element(find.byType(PlaylistScreen)),
      );
      scope.read(layoutOptionsProvider.notifier).setWidth(-1);
      scope.read(layoutOptionsProvider.notifier).setRadioHeight(720);
      await tester.pump();
      final first = find.byKey(const ValueKey('playlist-radio-column-R1'));
      final pool = find.byKey(const ValueKey('playlist-pool-side-panel'));
      expect(tester.getTopLeft(first).dx, greaterThanOrEqualTo(40));
      expect(tester.getBottomRight(pool).dx, lessThanOrEqualTo(1860));
      expect(tester.getSize(first).height, 720);
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(960, 900);
      await tester.pump();
      expect(tester.getBottomRight(pool).dx, lessThanOrEqualTo(920));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('package playlist keeps the pool in a right side panel', (
    tester,
  ) async {
    await _pumpPlaylist(tester, const Size(1365, 900));

    final poolPanel = find.byKey(const ValueKey('playlist-pool-side-panel'));
    final firstRadio = find.byKey(const ValueKey('playlist-radio-column-R1'));

    expect(poolPanel, findsOneWidget);
    expect(firstRadio, findsOneWidget);
    expect(
      tester.getTopLeft(poolPanel).dx,
      greaterThan(tester.getTopLeft(firstRadio).dx),
    );
    expect(tester.getTopLeft(poolPanel).dy, tester.getTopLeft(firstRadio).dy);
    expect(
      tester.getSize(poolPanel).height,
      greaterThan(tester.getSize(firstRadio).height),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow package playlist keeps pool visible beside radios', (
    tester,
  ) async {
    await _pumpPlaylist(tester, const Size(720, 900));

    final poolPanel = find.byKey(const ValueKey('playlist-pool-side-panel'));
    final firstRadio = find.byKey(const ValueKey('playlist-radio-column-R1'));
    final secondRadio = find.byKey(const ValueKey('playlist-radio-column-R2'));

    expect(poolPanel, findsOneWidget);
    expect(firstRadio, findsOneWidget);
    final firstTop = tester.getTopLeft(firstRadio);
    final firstWidth = tester.getSize(firstRadio).width;
    final grid = find.byKey(const ValueKey('playlist-radio-board'));
    tester
        .widget<GridView>(grid)
        .controller!
        .jumpTo(
          (tester.getSize(firstRadio).height + 12).clamp(
            0,
            tester.widget<GridView>(grid).controller!.position.maxScrollExtent,
          ),
        );
    await tester.pump();
    expect(secondRadio, findsOneWidget);
    expect(tester.getTopLeft(poolPanel).dy, firstTop.dy);
    expect(tester.getTopLeft(poolPanel).dx, greaterThan(firstTop.dx));
    // Auto columns preserve the minimum width, so narrow windows stack radios.
    expect(
      tester.getTopLeft(secondRadio).dy +
          tester.widget<GridView>(grid).controller!.offset,
      greaterThan(firstTop.dy),
    );
    expect(firstWidth, greaterThanOrEqualTo(LayoutOptions.minColumnWidth));
    expect(tester.takeException(), isNull);
  });

  testWidgets('playlist count uses bank-derived slot capacity', (tester) async {
    final temp = Directory.systemTemp.createTempSync(
      'fh-radio-studio-playlist-count-widget-',
    );
    addTearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final catalog = _bankSlotCatalog(temp);

    await _pumpPlaylist(tester, const Size(960, 900), catalog: catalog);

    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.text('3 / 4'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'builtin columns allow direct scrolling with or without control',
    (tester) async {
      await _pumpPlaylist(tester, const Size(1365, 900));

      final builtinList = find.descendant(
        of: find.byKey(const ValueKey('playlist-radio-column-R2')),
        matching: find.byType(ListView),
      );

      expect(builtinList, findsOneWidget);
      expect(
        tester.widget<ListView>(builtinList).physics,
        isA<ClampingScrollPhysics>(),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(
        tester.widget<ListView>(builtinList).physics,
        isA<ClampingScrollPhysics>(),
      );

      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pumpPlaylist(
  WidgetTester tester,
  Size size, {
  PlaylistCatalog? catalog,
  ValueNotifier<bool>? visible,
}) async {
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;

  final tempRoot = Directory.systemTemp.createTempSync(
    'fh-radio-studio-playlist-layout-',
  );
  addTearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });
  final projectDir = p.join(tempRoot.path, 'project');
  SharedPreferences.setMockInitialValues({'rm.studio.projectDir': projectDir});
  final prefs = await SharedPreferences.getInstance();

  final effectiveCatalog =
      catalog ??
      const PlaylistCatalog(
        origin: PlaylistCatalogOrigin.package,
        sourcePath: 'test-radio-info.xml',
        radios: [
          ...kRadios,
          RadioStation(
            code: 'R9',
            name: 'Horizon Opus',
            hue: 'cyan',
            genre: 'Classical',
            slot: 22,
          ),
        ],
        modes: kStationModes,
        freeRoamTracks: kTracks,
        eventTracks: kTracks,
      );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        realPoolTracksProvider.overrideWithValue(kCustomPool),
        playlistCatalogProvider.overrideWithValue(effectiveCatalog),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(
          brightness: Brightness.light,
          accent: AppAccent.lime,
        ),
        home: Scaffold(
          body: visible == null
              ? const PlaylistScreen()
              : ValueListenableBuilder<bool>(
                  valueListenable: visible,
                  builder: (_, show, _) =>
                      show ? const PlaylistScreen() : const SizedBox(),
                ),
        ),
      ),
    ),
  );
  await tester.pump();
}

PlaylistCatalog _bankSlotCatalog(Directory temp) {
  final gameDir = Directory(p.join(temp.path, 'ForzaHorizon6'));
  final audioDir = Directory(p.join(gameDir.path, 'media', 'audio'))
    ..createSync(recursive: true);
  Directory(p.join(audioDir.path, 'FMODBanks')).createSync();
  _writeFsb5Bank(
    File(p.join(audioDir.path, 'FMODBanks', 'R1_Tracks_CU1.assets.bank')),
    samples: 3,
  );
  File(p.join(audioDir.path, 'RadioInfo_CN.xml')).writeAsStringSync('''
<RadioInfo Language="CN">
  <RadioStations>
    <RadioStation Number="1" Name="Horizon Pulse">
      <Banks>
        <Bank Name="R1_Tracks_CU1" />
      </Banks>
      <SampleList Type="Track">
        <Sample SoundName="HZ6_R1_SLOT_01" SampleLength="48000" SampleRate="48000" DisplayName="One" Artist="Forza" />
        <Sample SoundName="HZ6_R1_SLOT_02" SampleLength="48000" SampleRate="48000" DisplayName="Two" Artist="Forza" />
        <Sample SoundName="HZ6_R1_SLOT_03" SampleLength="48000" SampleRate="48000" DisplayName="Three" Artist="Forza" />
        <Sample SoundName="HZ6_R1_XML_ONLY" SampleLength="48000" SampleRate="48000" DisplayName="XML Only" Artist="Forza" />
      </SampleList>
      <PlayList Type="FreeRoam">
        <Entry Name="HZ6_R1_SLOT_01" />
        <Entry Name="HZ6_R1_SLOT_02" />
        <Entry Name="HZ6_R1_SLOT_03" />
      </PlayList>
      <PlayList Type="Event">
        <Entry Name="HZ6_R1_SLOT_01" />
        <Entry Name="HZ6_R1_SLOT_02" />
        <Entry Name="HZ6_R1_SLOT_03" />
      </PlayList>
    </RadioStation>
  </RadioStations>
</RadioInfo>
''', encoding: utf8);

  return loadPlaylistCatalog(
    packageDir: null,
    gameDir: gameDir.path,
    sourceLang: 'CN',
    targetLang: 'EN',
  );
}

void _writeFsb5Bank(File file, {required int samples}) {
  file.createSync(recursive: true);
  final header = Uint8List(60);
  header.setAll(0, 'FSB5'.codeUnits);
  final view = ByteData.sublistView(header);
  view.setUint32(4, 1, Endian.little);
  view.setUint32(8, samples, Endian.little);
  file.writeAsBytesSync(header);
}
