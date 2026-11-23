import 'dart:io';

import 'package:encore_core/core/host.dart' as core show PackageInstallCancelled;
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
  // the new version starts once this one has ended: while it runs, a new copy would only bring this
  // window up and exit (only one Encore runs at a time). The caller quits; given up after a minute.
  await Process.start('sh', ['-c', restartScript, '${dir.path}/encore', '$pid'], mode: ProcessStartMode.detached);
}

/// Waits for the old copy (the process given second) to end, then starts the new one (given first).
const restartScript = r'i=0; while kill -0 "$1" 2>/dev/null && [ $i -lt 120 ]; do sleep 0.5; i=$((i+1)); done; exec "$0"';

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

/// The system's password window, for installing a package as root: pkexec (polkit), which every desktop has an agent
/// for. Without it the update is shown as a command to run instead.
String? pkexec() => ['/usr/bin/pkexec', '/bin/pkexec'].where((p) => File(p).existsSync()).firstOrNull;

/// Encore runs in a Flatpak (tools/flatpak).
bool inFlatpak({String info = '/.flatpak-info'}) => File(info).existsSync();

/// Which installation this Flatpak is in, as `flatpak install` takes it: --user (~/.local/share/flatpak, no
/// password) or --system (for everyone; the system asks for your password).
String flatpakInstallation({String info = '/.flatpak-info'}) {
  try {
    final line = File(info).readAsLinesSync().where((l) => l.startsWith('app-path=')).firstOrNull ?? '';
    return line.contains('/.local/share/flatpak/') ? '--user' : '--system';
  } catch (_) {
    return '--user';
  }
}

/// The package manager command that installs the local package file [path] of [kind] (deb, rpm, arch, flatpak),
/// or null. A Flatpak's is run on the computer, outside the sandbox (flatpak-spawn --host).
List<String>? packageInstallCommand(String kind, String path, {bool Function(String) exists = _exists, String? installation}) => switch (kind) {
  // (not --noninteractive: that also turns off the system's password window, so a system-wide copy could never update)
  'flatpak' => ['flatpak-spawn', '--host', 'flatpak', 'install', installation ?? flatpakInstallation(), '-y', path],
  'deb' => ['apt-get', 'install', '-y', path],
  'arch' => ['pacman', '-U', '--noconfirm', path],
  // Fedora's dnf, else openSUSE's zypper (the package isn't signed: the release's checksum was checked instead)
  _ when exists('/usr/bin/dnf') || exists('/usr/bin/dnf5') => ['dnf', 'install', '-y', path],
  _ when exists('/usr/bin/zypper') => ['zypper', '--non-interactive', 'install', '--allow-unsigned-rpm', path],
  _ => null,
};

bool _exists(String p) => File(p).existsSync();

/// Installs the downloaded package with the system's package manager, as root through pkexec (the system asks for
/// your password in its own window), then starts the new version once this one has quit (the caller quits).
Future<void> installSystemPackage(File package, String kind) async {
  if (kind == 'flatpak') return _installFlatpak(package);
  final px = pkexec();
  final cmd = packageInstallCommand(kind, package.path);
  if (px == null || cmd == null) throw const FileSystemException('No way to install packages here');
  final r = await Process.run(px, cmd);
  // 126: the password window was closed (or the password refused three times); 127: not allowed at all
  if (r.exitCode == 126 || r.exitCode == 127) throw const core.PackageInstallCancelled();
  if (r.exitCode != 0) {
    final err = '${r.stderr}'.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
    throw FileSystemException(err.isEmpty ? '${cmd.first} failed (${r.exitCode})' : err.last);
  }
  // the package put the new version where this one runs from (a running program keeps its old files open)
  await Process.start('sh', ['-c', restartScript, Platform.resolvedExecutable, '$pid'], mode: ProcessStartMode.detached);
}

/// The host's flatpak installs the downloaded .flatpak over this copy (it sees only paths outside the sandbox's
/// own /tmp, so the file goes to Encore's cache folder, the same path on both sides). The new version starts once
/// this one has quit (the caller quits): the host waits for this copy to end, then runs it again.
Future<void> _installFlatpak(File bundle) async {
  final cache = Platform.environment['XDG_CACHE_HOME'];
  if (cache == null || cache.isEmpty) throw const FileSystemException('No folder outside the sandbox for the update');
  final shared = await bundle.copy('$cache/encore-update.flatpak');
  try {
    final cmd = packageInstallCommand('flatpak', shared.path)!;
    final r = await Process.run(cmd.first, cmd.sublist(1));
    if (r.exitCode != 0) {
      final err = '${r.stderr}'.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
      if (flatpakRefused(err)) throw const core.PackageInstallCancelled();
      throw FileSystemException(err.isEmpty ? 'flatpak failed (${r.exitCode})' : err.last);
    }
  } finally {
    await shared.delete().catchError((_) => shared);
  }
  final id = Platform.environment['FLATPAK_ID'] ?? 'dev.safro.encore';
  await Process.start('flatpak-spawn', ['--host', 'sh', '-c', flatpakRestartScript, id], mode: ProcessStartMode.detached);
}

/// A system-wide copy's update was refused: the password window was closed, or the password not given (flatpak's
/// system helper says "Flatpak system operation InstallBundle not allowed for user").
bool flatpakRefused(List<String> stderr) =>
    stderr.any((l) => l.contains('not allowed for user') || l.contains('Not authorized'));

/// Run on the computer: waits (up to a minute) for the app given first to have no copy running, then starts it.
const flatpakRestartScript =
    r'i=0; while flatpak ps --columns=application 2>/dev/null | grep -qx "$0" && [ $i -lt 120 ]; do sleep 0.5; i=$((i+1)); done; exec flatpak run "$0"';
