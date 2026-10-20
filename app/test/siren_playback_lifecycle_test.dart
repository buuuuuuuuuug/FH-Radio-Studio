import 'dart:async';
import 'dart:io';

import 'package:fh_radio_studio/core/project_workspace.dart';
import 'package:fh_radio_studio/core/siren_audio_cache.dart';
import 'package:fh_radio_studio/core/siren_catalog.dart';
import 'package:fh_radio_studio/screens/siren_library.dart';
import 'package:fh_radio_studio/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'studio_v21_workflow_test.dart' as helpers;

Future<void> _pumpLibrary(
  WidgetTester t, {
  required _Client client,
  required _Cache cache,
  required Player Function() player,
}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = const Size(1500, 1000);
  addTearDown(t.view.resetDevicePixelRatio);
  addTearDown(t.view.resetPhysicalSize);
  final project = Directory.systemTemp.createTempSync('siren_playback_review_');
  addTearDown(() => project.deleteSync(recursive: true));
  FhRadioStudioProject.writeSettings(project.path, sirenEnabled: true);
  SharedPreferences.setMockInitialValues({
    'rm.studio.projectDir': project.path,
  });
  final prefs = await SharedPreferences.getInstance();
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        sirenCatalogClientProvider.overrideWithValue(client),
        sirenAudioCacheProvider.overrideWithValue(cache),
        sirenPlayerFactoryProvider.overrideWithValue(player),
      ],
      child: helpers.app(const SirenLibraryScreen()),
    ),
  );
  await _settleRequests(t);
}

Future<void> _settleRequests(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 30));
  }
}

Future<void> _play(WidgetTester t, String cid) async {
  final row = find.byKey(ValueKey('siren-track-row-$cid'));
  final play = find.descendant(of: row, matching: find.byTooltip('在线试听'));
  expect(play, findsOneWidget);
  await t.ensureVisible(play);
  await t.tap(play);
  await _settleRequests(t);
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('leaving during cached audio lookup cannot create a player', (
    t,
  ) async {
    final cached = Completer<File?>();
    var created = 0;
    await _pumpLibrary(
      t,
      client: _Client(),
      cache: _Cache((_) => cached.future),
      player: () {
        created++;
        return _Player();
      },
    );
    await _play(t, '1');
    await t.pumpWidget(const SizedBox.shrink());
    cached.complete(File('cached-1.wav'));
    await _settleRequests(t);
    expect(created, 0);
    expect(t.takeException(), isNull);
  });

  testWidgets('late song details do not replace the latest selected song', (
    t,
  ) async {
    final detail = Completer<SirenSongDetail>();
    final client = _Client()..pendingDetails['1'] = detail.future;
    final player = _Player();
    await _pumpLibrary(
      t,
      client: client,
      cache: _Cache.immediate(),
      player: () => player,
    );
    await _play(t, '1');
    await _play(t, '2');
    expect(player.opened, [contains('cached-2.wav')]);
    expect(player.played, [contains('cached-2.wav')]);
    detail.complete(_detail('1'));
    await _settleRequests(t);
    expect(player.opened, [contains('cached-2.wav')]);
    expect(player.played, [contains('cached-2.wav')]);
    await t.pumpWidget(const SizedBox.shrink());
    expect(player.disposed, isTrue);
    expect(t.takeException(), isNull);
  });

  for (final close in [false, true]) {
    testWidgets(
      'pending native open ${close ? 'cannot play after disposal' : 'finishes before the next open without stale playback'}',
      (t) async {
        final opened = Completer<void>();
        final player = _Player()..pendingOpen = opened.future;
        await _pumpLibrary(
          t,
          client: _Client(),
          cache: _Cache.immediate(),
          player: () => player,
        );
        await _play(t, '1');
        expect(player.opened, [contains('cached-1.wav')]);
        if (close) {
          await t.pumpWidget(const SizedBox.shrink());
        } else {
          await _play(t, '2');
        }
        opened.complete();
        await _settleRequests(t);
        expect(player.played, close ? isEmpty : [contains('cached-2.wav')]);
        if (!close) {
          expect(player.opened, [
            contains('cached-1.wav'),
            contains('cached-2.wav'),
          ]);
          await t.pumpWidget(const SizedBox.shrink());
        }
        expect(player.disposed, isTrue);
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets('a failed native open does not block the next song', (t) async {
    final player = _Player()..failNextOpen = true;
    await _pumpLibrary(
      t,
      client: _Client(),
      cache: _Cache.immediate(),
      player: () => player,
    );
    await _play(t, '1');
    expect(player.played, isEmpty);
    await _play(t, '2');
    expect(player.played, [contains('cached-2.wav')]);
    await t.pumpWidget(const SizedBox.shrink());
    expect(t.takeException(), isNull);
  });
}

class _Client implements SirenCatalogClient {
  final pendingDetails = <String, Future<SirenSongDetail>>{};

  @override
  Future<SirenCatalogSnapshot> fetchCatalog() async => SirenCatalogSnapshot(
    fetchedAt: DateTime(2026, 10, 18),
    albums: const [
      SirenAlbum(
        cid: 'a',
        name: 'Album',
        coverUrl: '',
        artists: ['Artist'],
        trackCount: 2,
      ),
    ],
    tracks: [
      for (final cid in ['1', '2'])
        SirenTrack(
          cid: cid,
          name: 'Song $cid',
          albumCid: 'a',
          albumName: 'Album',
          coverUrl: '',
          artists: const ['Artist'],
          albumIsOst: false,
        ),
    ],
  );

  @override
  Future<SirenAlbumDetail> fetchAlbumDetail(String cid) async =>
      SirenAlbumDetail(
        cid: cid,
        name: 'Album',
        intro: '',
        belong: '',
        coverUrl: '',
        coverDeUrl: '',
        songs: const [],
      );

  @override
  Future<SirenSongDetail> fetchSongDetail(String cid) async =>
      pendingDetails[cid] ?? _detail(cid);
}

SirenSongDetail _detail(String cid) => SirenSongDetail(
  cid: cid,
  name: 'Song $cid',
  albumCid: 'a',
  sourceUrl: 'https://unused.invalid/song-$cid.wav',
  lyricUrl: null,
  mvUrl: null,
  mvCoverUrl: null,
  artists: const ['Artist'],
);

class _Cache extends SirenAudioCache {
  _Cache(this.lookup) : super(rootPath: 'unused-siren-review-cache');
  _Cache.immediate() : this((detail) async => File('cached-${detail.cid}.wav'));
  final Future<File?> Function(SirenSongDetail) lookup;

  @override
  Future<File?> cachedAudioFile(SirenSongDetail detail) => lookup(detail);
}

class _Player implements Player {
  final opened = <String>[], played = <String>[];
  bool disposed = false, failNextOpen = false;
  String? current;
  Future<void>? pendingOpen;

  @override
  PlayerStream get stream => _Streams();

  @override
  Future<void> open(Playable media, {bool play = true}) async {
    opened.add((media as Media).uri);
    expect(play, isFalse);
    final pending = pendingOpen;
    pendingOpen = null;
    await pending;
    if (failNextOpen) {
      failNextOpen = false;
      throw StateError('native open failed');
    }
    current = media.uri;
  }

  @override
  Future<void> play() async {
    expect(disposed, isFalse);
    played.add(current!);
  }

  @override
  Future<void> dispose() async => disposed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Streams implements PlayerStream {
  @override
  Stream<bool> get playing => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
