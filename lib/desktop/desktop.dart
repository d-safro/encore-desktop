import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_service_mpris/audio_service_mpris.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart' show Rect, Size, debugPrint;
import 'package:just_audio_mpv/just_audio_mpv.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../core/settings.dart';
import '../data/episode_alerts.dart' show notifications;
import '../playback/handler.dart';

/// The desktop app's pieces that the phone doesn't have: mpv for sound, SQLite through FFI, MPRIS for
/// Plasma's media controls, the window (size remembered, close to the tray) and the tray icon.

/// Song addresses carry the login (Subsonic token and salt): never write those to a log.
String scrubLogin(String text) =>
    text.replaceAllMapped(RegExp(r'([?&](?:u|t|s|p|apiKey)=)[^&\s]*'), (m) => '${m[1]}…');

/// Before anything opens a database or a player (main() calls this first).
Future<void> initDesktopPlatform() async {
  // mpv's warnings and errors (a song that won't open, a filter it refuses) go to the log
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((r) => debugPrint('Encore ${r.loggerName}: ${scrubLogin(r.message)}'));
  JustAudioMpv.ensureInitialized();
  // sqflite through FFI, with the databases in ~/.local/share/dev.safro.encore (not the current folder)
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final dir = await getApplicationSupportDirectory();
  await databaseFactory.setDatabasesPath(p.join(dir.path, 'databases'));
  // Plasma's media controls, lock screen, media keys and KDE Connect talk to Encore through MPRIS
  AudioServiceMpris.init(
    dBusName: 'encore',
    identity: 'Encore',
    desktopEntry: 'dev.safro.encore',
    canControl: true,
    canPlay: true,
    canPause: true,
    canGoNext: true,
    canGoPrevious: true,
    minimumRate: 0.5,
    maximumRate: 2.0,
    supportedUriSchemes: const ['http', 'https', 'file'],
    onRaiseRequest: () => showWindow(),
    onQuitRequest: () => quitApp(),
  );
}

// ── The window ──

/// Close (the window's ×) keeps Encore playing in the tray; Quit in the tray menu ends it.
bool get closeToTray => prefs.getBool('closeToTray') ?? true;
Future<void> setCloseToTray(bool v) => prefs.setBool('closeToTray', v);

class _WindowEvents with WindowListener {
  Timer? _save;

  @override
  void onWindowClose() async {
    if (closeToTray) {
      await windowManager.hide();
      // the first time: say where it went, so music going on isn't a mystery
      if (prefs.getBool('trayHintShown') != true) {
        await prefs.setBool('trayHintShown', true);
        try {
          await notifications.show(
            id: 7001,
            title: 'Encore is still running',
            body: 'It keeps playing in the system tray. Quit from the tray icon, or turn this off in Settings › Desktop.',
            notificationDetails: const NotificationDetails(linux: LinuxNotificationDetails()),
          );
        } catch (_) {}
      }
    } else {
      await quitApp();
    }
  }

  // size and place remembered (a moment after the last change)
  void _remember() {
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 600), () async {
      if (await windowManager.isMaximized()) {
        await prefs.setBool('windowMaximized', true);
        return;
      }
      final b = await windowManager.getBounds();
      await prefs.setBool('windowMaximized', false);
      await prefs.setString('windowBounds', '${b.left},${b.top},${b.width},${b.height}');
    });
  }

  @override
  void onWindowResized() => _remember();
  @override
  void onWindowMoved() => _remember();
  @override
  void onWindowMaximize() => _remember();
  @override
  void onWindowUnmaximize() => _remember();
}

/// The saved window place, or null the first time. Sizes smaller than the minimum are ignored.
Rect? savedBounds(String? s) {
  final v = (s ?? '').split(',').map(double.tryParse).toList();
  if (v.length != 4 || v.any((x) => x == null)) return null;
  if (v[2]! < 600 || v[3]! < 400) return null;
  return Rect.fromLTWH(v[0]!, v[1]!, v[2]!, v[3]!);
}

const minWindowSize = Size(760, 520);

Future<void> initWindow() async {
  await windowManager.ensureInitialized();
  final bounds = savedBounds(prefs.getString('windowBounds'));
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      title: 'Encore',
      size: bounds?.size ?? const Size(1280, 820),
      minimumSize: minWindowSize,
      center: bounds == null,
    ),
    () async {
      // Wayland doesn't let apps place their own windows; KWin puts it back where it was itself
      if (bounds != null && !Platform.environment.containsKey('WAYLAND_DISPLAY')) {
        await windowManager.setPosition(bounds.topLeft);
      }
      if (prefs.getBool('windowMaximized') == true) await windowManager.maximize();
      // started hidden (autostart with --hidden): only the tray icon
      if (!_startHidden) {
        await windowManager.show();
        await windowManager.focus();
      }
    },
  );
  await windowManager.setPreventClose(true);
  windowManager.addListener(_WindowEvents());
}

bool _startHidden = false;

/// Command-line options: --hidden starts in the tray.
void readArgs(List<String> args) => _startHidden = args.contains('--hidden');

Future<void> showWindow() async {
  if (await windowManager.isMinimized()) await windowManager.restore();
  await windowManager.show();
  await windowManager.focus();
}

Future<void> toggleWindow() async {
  if (await windowManager.isVisible() && await windowManager.isFocused()) {
    await windowManager.hide();
  } else {
    await showWindow();
  }
}

/// Set by the app: say goodbye to your other devices before quitting.
Future<void> Function()? beforeQuit;

/// Saves the queue and where you are, then ends the app.
Future<void> quitApp() async {
  try {
    await (beforeQuit?.call() ?? Future.value()).timeout(const Duration(seconds: 3));
  } catch (_) {}
  try {
    await audioHandler.saveNow().timeout(const Duration(seconds: 3));
    await audioHandler.pause().timeout(const Duration(seconds: 2));
  } catch (_) {}
  try {
    await trayManager.destroy();
  } catch (_) {}
  await windowManager.setPreventClose(false);
  await windowManager.destroy();
  exit(0);
}

/// Settings › Desktop: a notification when the song changes (only while Encore's window isn't in front).
bool get songNotifications => prefs.getBool('songNotifications') ?? false;
Future<void> setSongNotifications(bool v) => prefs.setBool('songNotifications', v);

Future<void> _songNotification(MediaItem m) async {
  if (!songNotifications) return;
  try {
    if (await windowManager.isVisible() && await windowManager.isFocused()) return;
    await notifications.show(
      id: 7002, // the same id each time: the new song replaces the last one
      title: m.title,
      body: [m.artist, m.album].whereType<String>().where((x) => x.isNotEmpty).join(' — '),
      notificationDetails: const NotificationDetails(linux: LinuxNotificationDetails()),
    );
  } catch (_) {}
}

// ── The tray icon (StatusNotifierItem, shown in Plasma's system tray) ──

class _Tray with TrayListener {
  _Tray(this.handler);
  final AudioHandler handler;
  String? _notified;
  MediaItem? _item;
  bool _playing = false;

  Future<void> start() async {
    final icon = p.join(
      p.dirname(Platform.resolvedExecutable),
      'data',
      'flutter_assets',
      'assets',
      'icons',
      'script.png',
    );
    await trayManager.setIcon(icon);
    trayManager.addListener(this);
    handler.mediaItem.listen((m) {
      _item = m;
      _menu();
      // the window's title (taskbar, Alt+Tab): what's playing
      final artist = m?.artist ?? '';
      windowManager.setTitle(m == null ? 'Encore' : '${m.title}${artist.isEmpty ? '' : ' · $artist'} — Encore');
      if (m != null && m.id != _notified) {
        _notified = m.id;
        _songNotification(m);
      }
    });
    handler.playbackState.map((s) => s.playing).distinct().listen((pl) {
      _playing = pl;
      _menu();
    });
    await _menu();
  }

  Future<void> _menu() async {
    final m = _item;
    final now = m == null ? 'Nothing playing' : [m.title, if ((m.artist ?? '').isNotEmpty) m.artist].join(' — ');
    try {
      await trayManager.setToolTip(m == null ? 'Encore' : 'Encore: $now');
    } catch (_) {} // not every tray shows tooltips
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'now', label: now.length > 60 ? '${now.substring(0, 57)}…' : now, disabled: true),
          MenuItem.separator(),
          MenuItem(key: 'play', label: _playing ? 'Pause' : 'Play'),
          MenuItem(key: 'next', label: 'Next'),
          MenuItem(key: 'previous', label: 'Previous'),
          MenuItem.separator(),
          MenuItem(key: 'show', label: 'Show Encore'),
          MenuItem(key: 'quit', label: 'Quit'),
        ],
      ),
    );
  }

  @override
  void onTrayIconMouseDown() => toggleWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem item) {
    switch (item.key) {
      case 'play':
        _playing ? handler.pause() : handler.play();
      case 'next':
        handler.skipToNext();
      case 'previous':
        handler.skipToPrevious();
      case 'show':
        showWindow();
      case 'quit':
        quitApp();
    }
  }
}

Future<void> startTray(AudioHandler handler) async {
  try {
    await _Tray(handler).start();
  } catch (e) {
    // no tray (another desktop without StatusNotifierItem): closing the window then quits
    await setCloseToTray(false);
  }
}
