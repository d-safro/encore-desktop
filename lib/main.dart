import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/platform.dart';
import 'core/settings.dart';
import 'data/account.dart';
import 'data/cover_cache.dart';
import 'data/saved_covers.dart';
import 'data/saved_lyrics.dart';
import 'data/db.dart';
import 'data/devices.dart';
import 'data/jam.dart';
import 'data/library.dart';
import 'data/local_android.dart';
import 'data/local_files.dart';
import 'desktop/desktop.dart';
import 'playback/handler.dart';
import 'playback/local_open.dart';
import 'playback/widget_sync.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (isDesktop) {
    readArgs(args);
    await initDesktopPlatform(); // mpv, SQLite, MPRIS: before the first database or player
  }
  // Errors are logged, never fatal: a failed request or a broken image must not take the app down.
  FlutterError.onError = (d) => FlutterError.presentError(d);
  PlatformDispatcher.instance.onError = (e, st) {
    // where it came from too (the first lines are enough to find it)
    debugPrint('Encore: unhandled $e\n${st.toString().split('\n').take(12).join('\n')}');
    return true;
  };
  prefs = await SharedPreferences.getInstance();
  if (isDesktop) await initWindow();
  libraryDb = await LibraryDb.open(file: await currentDbFile()); // each server has its own copy
  // the covers kept with the downloads: before the player, which shows them on the lock screen
  savedCovers = await SavedCovers.open(Directory(p.join((await getApplicationSupportDirectory()).path, 'covers')));
  // and their lyrics, so they show with no server too
  savedLyrics = await SavedLyrics.open(Directory(p.join((await getApplicationSupportDirectory()).path, 'lyrics')));

  final container = ProviderContainer();
  await container.read(accountProvider.future); // the player needs the server before restoring the queue
  container.read(downloadsProvider); // start listening for finished downloads
  // the player rebuilds the saved queue from these: downloaded songs must play from the phone, not the server
  await container.read(downloadsProvider.notifier).loaded.timeout(const Duration(seconds: 10), onTimeout: () {});
  // songs made smaller a few at a time (unlimited, hundreds would hit the server at once)
  await FileDownloader()
      .configure(globalConfig: [(Config.holdingQueue, (3, null, null))])
      .catchError((_) => <(String, String)>[]);
  // after the listener: picks up songs made smaller while closed (song downloads are Encore's own: see
  // DownloadsNotifier; ones an older version left with Android move over)
  FileDownloader()
      .start(autoCleanDatabase: true, doRescheduleKilledTasks: false)
      .then((_) => container.read(downloadsProvider.notifier).adoptOldDownloads());

  audioHandler = await AudioService.init(
    builder: () => EncoreAudioHandler(container),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'dev.safro.encore.playback',
      androidNotificationChannelName: 'Playback',
      androidNotificationIcon: 'drawable/ic_stat_encore',
      androidStopForegroundOnPause: false,
      androidBrowsableRootExtras: {'android.media.browse.CONTENT_STYLE_SUPPORTED': true},
      preloadArtwork: true,
    ),
  );

  if (isDesktop) {
    unawaited(startTray(audioHandler));
  } else {
    startWidgetSync(audioHandler); // the home-screen widget (Android)
  }
  container.read(jamProvider); // picks up a Jam that was running when the app closed
  // music that's only on this device (local_files.dart): Android's MediaStore; the desktop set its own source
  if (!isDesktop) localSource = MediaStoreSource();
  container.read(localLibraryProvider);
  unawaited(listenForOpenedFiles(startedWith: isDesktop ? fileArgs(args) : const []));

  playerNotices.stream.listen((m) {
    messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  });
  if (isDesktop) beforeQuit = () => container.read(devicesProvider.notifier).bye();
  runApp(UncontrolledProviderScope(container: container, child: const EncoreApp()));
  // later, and only while the server answers: covers are fetched again as you browse
  Future.delayed(const Duration(seconds: 30), () {
    if (!container.read(offlineProvider)) dropOldCoverCache(prefs);
  });
}
