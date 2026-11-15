import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/settings.dart';
import 'data/account.dart';
import 'data/db.dart';
import 'data/jam.dart';
import 'data/library.dart';
import 'playback/handler.dart';
import 'playback/widget_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Errors are logged, never fatal: a failed request or a broken image must not take the app down.
  FlutterError.onError = (d) => FlutterError.presentError(d);
  PlatformDispatcher.instance.onError = (e, st) {
    debugPrint('Encore: unhandled $e');
    return true;
  };
  prefs = await SharedPreferences.getInstance();
  libraryDb = await LibraryDb.open();

  final container = ProviderContainer();
  await container.read(accountProvider.future); // the player needs the server before restoring the queue
  container.read(downloadsProvider); // start listening for finished downloads
  FileDownloader().start(autoCleanDatabase: true); // after the listener: picks up downloads finished while closed

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

  startWidgetSync(audioHandler);
  container.read(jamProvider); // picks up a Jam that was running when the app closed

  playerNotices.stream.listen((m) {
    messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  });
  runApp(UncontrolledProviderScope(container: container, child: const EncoreApp()));
}
