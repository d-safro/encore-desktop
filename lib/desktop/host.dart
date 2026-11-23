import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:encore_core/core/host.dart' as core;
import 'package:encore_core/core/settings.dart' show Settings;
import 'package:encore_core/data/devices.dart';
import 'package:encore_core/data/models.dart';
import 'package:encore_core/playback/sound.dart' as core;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../playback/desktop_audio.dart' as sound;
import '../version.dart';
import 'desktop.dart' as desktop;
import 'desktop_page.dart' as page;
import 'desktop_settings.dart' as settings;
import 'drag.dart' as drag;
import 'file_drop.dart' as file_drop;
import 'shell.dart' as shell;
import 'updater.dart' as updater;

/// Where this app's releases are. Copies of 1.9 and older ask d-safro/encore (the phone app's), and
/// the desktop release workflow also attaches its files there for a while (see .github/workflows/desktop.yml).
const desktopUpdateRepo = 'd-safro/encore-desktop';

/// The desktop app's pieces for encore_core (see EncoreHost there).
class DesktopHost extends core.EncoreHost {
  const DesktopHost();

  @override
  String get appVersion => encoreVersion;

  @override
  String get updateRepo => desktopUpdateRepo;

  @override
  Future<void> beforeStart(List<String> args) async {
    desktop.readArgs(args);
    await desktop.initDesktopPlatform(); // mpv, SQLite, MPRIS: before the first database or player
  }

  @override
  Future<void> afterPrefs() => desktop.initWindow();

  @override
  Future<void> afterPlayer(AudioHandler handler, ProviderContainer container) async {
    unawaited(desktop.startTray(handler));
    desktop.beforeQuit = () => container.read(devicesProvider.notifier).bye();
  }

  @override
  Widget desktopShell({required String location, required Widget child, Widget? banner}) =>
      shell.DesktopShell(location: location, banner: banner, child: child);

  @override
  Page<T> desktopPage<T>({LocalKey? key, required Widget child}) => page.DesktopPage<T>(key: key, child: child);

  @override
  Widget fileDropArea(Widget child) => file_drop.FileDropArea(child: child);

  @override
  Widget desktopSettings() => const settings.DesktopSettings();

  @override
  Widget songDragSource({required List<Song> songs, required Widget child}) =>
      drag.songDragSource(songs: songs, child: child);

  @override
  Future<void> quitApp() => desktop.quitApp();

  @override
  core.DesktopSound get sound => const MpvSound();

  @override
  core.UpdateInstaller get updates => const DesktopUpdater();
}

/// mpv's sound (playback/desktop_audio.dart) for the shared player and screens.
class MpvSound extends core.DesktopSound {
  const MpvSound();
  @override
  Future<void> restore() => sound.restoreDesktopSound();
  @override
  Future<void> apply(Settings s) => sound.applyDesktopSound(s);
  @override
  Future<void> setBoost(double db) => sound.setDesktopBoost(db);
  @override
  double get volume => sound.desktopVolume;
  @override
  Future<void> setVolume(double v) => sound.setDesktopVolume(v);
  @override
  Stream<double> get volumeChanges => sound.desktopVolumeChanges;
  @override
  List<core.OutputDevice> devices() => sound.currentOutputDevices();
  @override
  String get device => sound.desktopDevice;
  @override
  Future<void> setDevice(String id) => sound.setDesktopDevice(id);
  @override
  (String, String) output() => sound.desktopOutput();
  @override
  Future<void> openSettings(String which) => sound.openKdeSettings(which);
}

/// The desktop updating itself: the archive swapped in place (a copy in your home folder), or the Windows
/// setup program run quietly. Copies installed by a package manager are updated by it (see ui/update.dart).
class DesktopUpdater extends core.UpdateInstaller {
  const DesktopUpdater();

  @override
  Future<bool> canInstall() async =>
      Platform.isWindows ? updater.windowsInstalledBySetup() : updater.desktopInstallDir() != null;

  @override
  Future<void> allowInstalls() async {}

  @override
  Future<void> install(File file) => updater.oneInstallAtATime(
    () => Platform.isWindows ? updater.installWindowsUpdate(file) : updater.installDesktopUpdate(file),
  );

  @override
  Future<bool> canInstallPackage(String kind) async => !Platform.isLinux
      ? false
      : kind == 'flatpak'
      ? updater.inFlatpak() && File('/usr/bin/flatpak-spawn').existsSync()
      : updater.runsFromSystemPackage() && updater.pkexec() != null && updater.packageInstallCommand(kind, '/x') != null;

  @override
  Future<void> installPackage(File file, String kind) =>
      updater.oneInstallAtATime(() => updater.installSystemPackage(file, kind));
}
