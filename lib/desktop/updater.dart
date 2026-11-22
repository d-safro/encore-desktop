import 'dart:io';

import 'package:encore_core/core/settings.dart' show appVersion;

/// The desktop app putting a downloaded update in place (see DesktopUpdater in host.dart). Finding and
/// downloading the update is shared (encore_core's data/updates.dart).

/// The folder this desktop app runs from, when Encore may replace it itself: installed in your home folder
/// (tools/linux/install.sh). null for an RPM (dnf updates it) or a build run from the source folder.
Directory? desktopInstallDir() {
  final dir = File(Platform.resolvedExecutable).parent;
  final home = Platform.environment['HOME'] ?? '';
  if (home.isEmpty || !dir.path.startsWith('$home/')) return null;
  if (!File('${dir.path}/.encore-install').existsSync()) return null; // put there by install.sh
  return dir;
}

/// Unpacks the downloaded .tar.gz next to the running app and swaps the folders; the new version starts a
/// moment after this one quits.
Future<void> installDesktopUpdate(File tarball) async {
  final dir = desktopInstallDir();
  if (dir == null) throw const FileSystemException('Encore is installed by the system here: update it with its package manager');
  final staging = Directory('${dir.path}.new');
  if (await staging.exists()) await staging.delete(recursive: true);
  await staging.create(recursive: true);
  final r = await Process.run('tar', ['-xzf', tarball.path, '-C', staging.path]);
  if (r.exitCode != 0) throw FileSystemException("Couldn't unpack the update: ${r.stderr}");
  // the archive holds encore-<version>-linux-<arch>/app/…
  final app = (await staging.list(recursive: true).toList())
      .whereType<File>()
      .where((e) => e.path.endsWith('/app/encore'))
      .firstOrNull;
  if (app == null) throw const FormatException("The update doesn't contain the app");
  await File('${app.parent.path}/.encore-install').writeAsString('$appVersion\n');
  final old = Directory('${dir.path}.old');
  if (await old.exists()) await old.delete(recursive: true);
  await dir.rename(old.path); // the running app keeps its open files
  await app.parent.rename(dir.path);
  await staging.delete(recursive: true);
  // the new version starts once this one has quit (only one Encore runs at a time); the caller quits
  await Process.start('sh', ['-c', 'sleep 2; exec "\$0"', '${dir.path}/encore'], mode: ProcessStartMode.detached);
}

/// Installed by the setup program (it leaves its uninstaller next to encore.exe), so a new setup program
/// can update it. The portable .zip has none: that copy is updated by hand.
bool windowsInstalledBySetup() =>
    File('${File(Platform.resolvedExecutable).parent.path}\\unins000.exe').existsSync();

/// Runs the downloaded setup program quietly: it closes this copy, puts the new version in place and
/// starts it again (/launch=1, see tools/windows/encore.iss). The caller then quits.
Future<void> installWindowsUpdate(File setup) async {
  await Process.start(
    setup.path,
    ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS', '/launch=1'],
    mode: ProcessStartMode.detached,
  );
}
