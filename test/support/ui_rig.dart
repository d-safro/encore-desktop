// The real desktop window (shell, router, screens) with a pretend server and a pretend player, for widget tests
// of the desktop UI. Nothing touches the network, real settings, the queue or a server.
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:encore_core/app.dart';
import 'package:encore_core/core/settings.dart';
import 'package:encore_core/data/account.dart';
import 'package:encore_core/data/artist_extra.dart';
import 'package:encore_core/data/db.dart';
import 'package:encore_core/data/follows.dart';
import 'package:encore_core/data/library.dart';
import 'package:encore_core/data/local_files.dart';
import 'package:encore_core/data/models.dart';
import 'package:encore_core/data/online_art.dart';
import 'package:encore_core/data/shows.dart';
import 'package:encore_core/data/subsonic.dart';
import 'package:encore_core/playback/handler.dart';
import 'package:encore_core/ui/screens/player.dart';

import 'fake_server.dart';

export 'fake_server.dart' show serverMode;

import 'package:encore_core/core/host.dart';
import 'package:encore/desktop/host.dart';

const _creds = Credentials('https://music.example.test', 'demo', 'demo');

class _Account extends AccountNotifier {
  @override
  Future<Credentials?> build() async => _creds;
}

class _Downloads extends DownloadsNotifier {
  @override
  DownloadsState build() => const DownloadsState();
}

class _Releases extends ReleasesNotifier {
  @override
  List<Release> build() => [
    for (var i = 0; i < 3; i++)
      Release(artistId: 'ar$i', artist: 'Artist $i', title: 'Release $i', date: '2026-11-${10 + i}'),
  ];
}

class _Local extends LocalLibraryNotifier {
  @override
  LocalLibrary build() => LocalLibrary(
    loaded: true,
    tracks: [
      for (var i = 0; i < 4; i++)
        LocalTrack(uri: '/music/t$i.flac', title: 'Local $i', artist: i.isEven ? 'Band' : '', duration: 100 + i),
    ],
  );
}

/// A player that says it's playing a queue, without any sound.
class _Handler extends EncoreAudioHandler {
  _Handler(super.container, this.fake);
  final List<Song> fake;
  @override
  Song? get currentSong => fake.isEmpty ? null : fake.first;
  @override
  List<Song> get songs => fake;
  @override
  Future<void> skipBy(Duration by) async => skipsAsked.add(by);

  void announce() {
    if (fake.isEmpty) return;
    MediaItem item(Song s) => MediaItem(id: s.id, title: s.title, artist: s.artist, duration: const Duration(minutes: 3));
    queue.add([for (final s in fake) item(s)]);
    mediaItem.add(item(fake.first));
    playbackState.add(PlaybackState(processingState: AudioProcessingState.ready, queueIndex: 0));
  }
}

/// The skips back / forward the pretend player was asked for (cleared by each pumpDesktop).
final skipsAsked = <Duration>[];

bool _ready = false;

/// Once per test file (setUpAll): a database and the plugins the screens ask for.
Future<void> setUpRig() async {
  encoreHost = const DesktopHost(); // the desktop window, layout and menus (encore_core alone has none)
  if (_ready) return;
  _ready = true;
  // the app's typeface, so text has its real size (the test font's is different and overflows the player bar)
  final inter = FontLoader('Inter');
  for (final w in [400, 500, 600, 700]) {
    inter.addFont(Future.value(ByteData.view(File('assets/fonts/Inter-$w.ttf').readAsBytesSync().buffer)));
  }
  await inter.load();
  final tmp = await Directory.systemTemp.createTemp('encore-ui-test');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => tmp.path,
  );
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  await databaseFactory.setDatabasesPath(tmp.path);
  libraryDb = await LibraryDb.open(file: 'ui-test.db');
}

/// Shows the desktop window at [path] (signed in, a song playing) and waits for the page to load.
/// [theme]: 'dark' or 'light'. Returns the router, to go elsewhere.
Future<GoRouter> pumpDesktop(
  WidgetTester t,
  String path, {
  Size size = const Size(1280, 800),
  String theme = 'dark',
  String server = 'normal',
  bool playing = true,
  Map<String, Object> extraPrefs = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    'connectDevices': false,
    'settings': jsonEncode({...const Settings().toJson(), 'appTheme': theme}),
    ...extraPrefs,
  });
  prefs = await SharedPreferences.getInstance();
  skipsAsked.clear();
  serverMode = server;
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final container = ProviderContainer(
    overrides: [
      accountProvider.overrideWith(_Account.new),
      clientProvider.overrideWithValue(SubsonicClient(_creds, httpClient: fakeServer())),
      offlineProvider.overrideWithValue(false),
      downloadsProvider.overrideWith(_Downloads.new),
      releasesProvider.overrideWith(_Releases.new),
      localLibraryProvider.overrideWith(_Local.new),
      onlineArtProvider.overrideWith((ref, k) async => null),
      artSchemeProvider.overrideWith((ref, k) async => null),
      artistExtraProvider.overrideWith((ref, k) async => const ArtistExtra()),
      artistWikiProvider.overrideWith((ref, k) async => ('', '')),
      artistShowsProvider.overrideWith((ref, k) async => const <Show>[]),
      followedShowsProvider.overrideWith((ref) => Stream.value((const <Show>[], true))),
    ],
  );
  addTearDown(container.dispose);
  final h = _Handler(container, playing ? [for (var k = 0; k < 6; k++) Song.fromJson(songJson(k, k % 4))] : const []);
  audioHandler = h;
  h.announce();
  final router = container.read(routerProvider);
  final settings = container.read(settingsProvider);
  ThemeData themed(Brightness b) =>
      encoreTheme(ColorScheme.fromSeed(seedColor: Color(settings.accentColor), brightness: b), settings);
  await t.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      themeMode: theme == 'light' ? ThemeMode.light : ThemeMode.dark,
      theme: themed(Brightness.light),
      darkTheme: themed(Brightness.dark),
      routerConfig: router,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(disableAnimations: true),
        child: child!,
      ),
    ),
  ));
  await t.pump();
  if (path.startsWith('/library') || path.startsWith('/search')) {
    router.go(path);
  } else if (path != '/home') {
    router.push(path);
  }
  await settle(t);
  // let go of the window and its timers when the test ends
  addTearDown(() async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 5));
  });
  return router;
}

/// Lets requests answer and the page build (fake time; animations are off).
Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 120));
  }
}

/// A mouse pointer resting on [f].
Future<void> hover(WidgetTester t, Finder f) async {
  final g = await t.createGesture(kind: PointerDeviceKind.mouse);
  await g.addPointer(location: Offset.zero);
  addTearDown(g.removePointer);
  await g.moveTo(t.getCenter(f));
  await t.pump();
}
