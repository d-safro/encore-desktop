import 'package:encore_core/data/local_files.dart' show localSource;
import 'local_folders.dart';
import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_service_mpris/audio_service_mpris.dart';
import 'package:dbus/dbus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart' show Offset, Rect, Size, debugPrint;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:just_audio_mpv/just_audio_mpv.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'package:encore_core/core/settings.dart';
import 'package:encore_core/data/episode_alerts.dart' show notifications;
import 'package:encore_core/playback/handler.dart';

/// The desktop app's pieces that the phone doesn't have: mpv for sound, SQLite through FFI, the system's
/// media controls (MPRIS on Linux, Windows' media flyout on Windows), the window (size remembered, close to
/// the tray) and the tray icon.

/// Song addresses carry the login (Subsonic token and salt): never write those to a log.
String scrubLogin(String text) =>
    text.replaceAllMapped(RegExp(r'([?&](?:u|t|s|p|apiKey)=)[^&\s]*'), (m) => '${m[1]}…');

/// Before anything opens a database or a player (main() calls this first).
Future<void> initDesktopPlatform() async {
  localSource = DesktopFolderSource(); // music in the folders you pick (Settings > Music on this computer)
  // mpv's warnings and errors (a song that won't open, a filter it refuses) go to the log
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((r) => debugPrint('Encore ${r.loggerName}: ${scrubLogin(r.message)}'));
  JustAudioMpv.ensureInitialized();
  // sqflite through FFI, with the databases in ~/.local/share/dev.safro.encore (not the current folder)
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final dir = await getApplicationSupportDirectory();
  await databaseFactory.setDatabasesPath(p.join(dir.path, 'databases'));
  // Windows: packages/audio_service_smtc registers itself and needs nothing here
  if (!Platform.isLinux) return;
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
    // no tray icon to come back from: closing quits, as if the setting were off (the setting is kept)
    if (closeToTray && await trayShown()) {
      await windowManager.hide();
      // the first time: say where it went, so music going on isn't a mystery
      if (prefs.getBool('trayHintShown') != true) {
        await prefs.setBool('trayHintShown', true);
        try {
          await notifications.show(
            id: 7001,
            title: 'Encore is still running',
            body: 'It keeps playing in the system tray. Quit from the tray icon, or turn this off in Settings › Desktop.',
            notificationDetails: desktopNotification,
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

/// Whether enough of the window (a strip along its top, where you grab it) is on one of these screens.
/// A window saved on a screen that's since been unplugged isn't.
bool onSomeScreen(Rect window, List<Rect> screens) {
  final grip = Rect.fromLTWH(window.left, window.top, window.width, 40);
  return screens.any((d) {
    final i = d.intersect(grip);
    return i.width >= 100 && i.height >= 20;
  });
}

Future<List<Rect>> _screens() async {
  try {
    return [
      for (final d in await screenRetriever.getAllDisplays())
        (d.visiblePosition ?? Offset.zero) & (d.visibleSize ?? d.size),
    ];
  } catch (_) {
    return const [];
  }
}

Future<void> initWindow() async {
  await windowManager.ensureInitialized();
  var bounds = savedBounds(prefs.getString('windowBounds'));
  // the saved place is used only if it's still on a screen (no screens found: it's kept)
  if (bounds != null && !Platform.environment.containsKey('WAYLAND_DISPLAY')) {
    final screens = await _screens();
    if (screens.isNotEmpty && !onSomeScreen(bounds, screens)) bounds = null;
  }
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
      // started hidden (autostart with --hidden): only the tray icon, if there is one
      if (!_startHidden) {
        await windowManager.show();
        await windowManager.focus();
      } else {
        unawaited(_showIfNoTray());
      }
    },
  );
  await windowManager.setPreventClose(true);
  windowManager.addListener(_WindowEvents());
}

bool _startHidden = false;

/// Started hidden: the window comes up after all if no tray shows up (the desktop's tray can take a moment
/// at login), else Encore would run with no way to reach it.
Future<void> _showIfNoTray() async {
  for (var i = 0; i < 15; i++) {
    await Future.delayed(const Duration(seconds: 1));
    if (_trayStarted && await trayShown()) return;
  }
  await showWindow();
}

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
      notificationDetails: desktopNotification,
    );
  } catch (_) {}
}

/// How the desktop's notifications look (the defaults on each system).
const desktopNotification = NotificationDetails(
  linux: LinuxNotificationDetails(),
  windows: WindowsNotificationDetails(),
);

// ── The app's icon ──

const appIconName = 'dev.safro.encore';

String _dataHome() =>
    Platform.environment['XDG_DATA_HOME'] ?? p.join(Platform.environment['HOME'] ?? '', '.local', 'share');

/// Where icon themes live (your own first, then the system's).
List<String> _dataDirs() => [
  _dataHome(),
  ...(Platform.environment['XDG_DATA_DIRS'] ?? '/usr/local/share:/usr/share').split(':').where((d) => d.isNotEmpty),
];

/// Is Encore's icon installed where the desktop looks (by a package, install.sh, or an earlier run)?
bool appIconInstalled([List<String>? dirs]) {
  for (final d in dirs ?? _dataDirs()) {
    for (final size in const ['64x64', '128x128', '256x256', '512x512', '48x48']) {
      if (File(p.join(d, 'icons', 'hicolor', size, 'apps', '$appIconName.png')).existsSync()) return true;
    }
    if (File(p.join(d, 'icons', 'hicolor', 'scalable', 'apps', '$appIconName.svg')).existsSync()) return true;
  }
  return false;
}

/// The icon's name for the tray and windows. A build run straight from its folder has no installed icon:
/// then the logo goes into your own icon folder (~/.local/share/icons), as an installer would put it.
Future<String> ensureAppIcon() async {
  if (Platform.isWindows) return appIconName; // Windows takes the icon from encore.exe
  if (appIconInstalled()) return appIconName;
  final assets = p.join(p.dirname(Platform.resolvedExecutable), 'data', 'flutter_assets', 'assets', 'icons');
  try {
    for (final size in const [64, 256]) {
      final dir = Directory(p.join(_dataHome(), 'icons', 'hicolor', '${size}x$size', 'apps'));
      await dir.create(recursive: true);
      await File(p.join(assets, 'logo-$size.png')).copy(p.join(dir.path, '$appIconName.png'));
    }
    return appIconName;
  } catch (_) {
    return p.join(assets, 'logo-256.png'); // the file itself, if the icon folder can't be written
  }
}

// ── The tray icon (StatusNotifierItem in Plasma's system tray; the notification area on Windows) ──

/// tray_manager's own setIcon turns every icon into a file path inside the app, which Plasma's tray doesn't
/// draw (it shows a generic icon). Its native side takes the icon as given, so Encore hands it the icon's
/// name; the id stays the same between runs, so Plasma remembers where the icon goes in the tray.
///
/// Windows' tray takes an .ico file: tray_manager's own setIcon finds it among the app's assets.
Future<void> _setTrayIcon(String icon) async {
  if (Platform.isWindows) return trayManager.setIcon('assets/icons/encore.ico');
  await const MethodChannel('tray_manager').invokeMethod('setIcon', {
  'id': appIconName,
  'iconPath': icon,
  'isTemplate': false,
  'iconPosition': 'left',
  'iconSize': 18,
  });
}

class _Tray with TrayListener {
  _Tray(this.handler);
  final AudioHandler handler;
  String? _notified;
  MediaItem? _item;
  bool _playing = false;

  Future<void> start() async {
    // Plasma's tray draws icons it can look up by name (not a file path): Encore's own icon
    await _setTrayIcon(await ensureAppIcon());
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

bool _trayStarted = false, _trayFailed = false;

/// Whether the tray icon can be seen: it started, and (Linux) something draws it. GNOME without the
/// AppIndicator extension has no tray; the icon is then made but never shown.
Future<bool> trayShown() async {
  if (_trayFailed) return false;
  if (!Platform.isLinux) return true;
  final bus = DBusClient.session();
  try {
    return await bus.nameHasOwner('org.kde.StatusNotifierWatcher').timeout(const Duration(seconds: 2));
  } catch (_) {
    return true; // can't tell: as before
  } finally {
    unawaited(bus.close());
  }
}

Future<void> startTray(AudioHandler handler) async {
  try {
    await _Tray(handler).start();
    _trayStarted = true;
  } catch (e) {
    // no tray: closing the window then quits (your setting is kept, for when there is one), and a copy
    // started hidden shows its window
    debugPrint('Encore: no tray icon: $e');
    _trayFailed = true;
    if (_startHidden) await showWindow();
  }
}
