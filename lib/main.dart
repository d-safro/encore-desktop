import 'package:audio_service/audio_service.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/settings.dart';
import 'data/account.dart';
import 'data/db.dart';
import 'data/library.dart';
import 'playback/handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  prefs = await SharedPreferences.getInstance();
  libraryDb = await LibraryDb.open();

  final container = ProviderContainer();
  await container.read(accountProvider.future); // the player needs the server before restoring the queue
  container.read(downloadsProvider); // start listening for finished downloads

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

  runApp(UncontrolledProviderScope(container: container, child: const EncoreApp()));
}
