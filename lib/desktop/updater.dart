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
/// moment after this one quits. [into]: the folder to update (the running app's, see desktopInstallDir); [restart]:
/// whether to start the new version once this one has quit.
Future<void> installDesktopUpdate(File tarball, {Directory? into, bool restart = true}) async {
  final dir = into ?? desktopInstallDir();
  if (dir == null) throw const FileSystemException('Encore is installed by the system here: update it with its package manager');
  final staging = Directory('${dir.path}.new');
  if (await staging.exists()) await staging.delete(recursive: true);
  await staging.create(recursive: true);
  try {
    final r = await Process.run('tar', ['-xzf', tarball.path, '-C', staging.path]);
    if (r.exitCode != 0) throw FileSystemException("Couldn't unpack the update: ${r.stderr}");
    // the archive holds encore-<version>-linux-<arch>/app/…
    final app = (await staging.list(recursive: true).toList())
        .whereType<File>()
        .where((e) => e.path.endsWith('/app/encore'))
        .firstOrNull;
    if (app == null) throw const FormatException("The update doesn't contain the app");
    await File('${app.parent.path}/.encore-install').writeAsString('$appVersion\n');
    await swapInstall(dir, app.parent);
  } finally {
    if (await staging.exists()) await staging.delete(recursive: true).catchError((_) => staging);
  }
  if (!restart) return;
  // the new version starts once this one has ended: while it runs, a new copy would only bring this
  // window up and exit (only one Encore runs at a time). The caller quits; given up after a minute.
  await Process.start('sh', ['-c', restartScript, '${dir.path}/encore', '$pid'], mode: ProcessStartMode.detached);
}

/// Puts [fresh] where [dir] is, the old one moved aside to `<dir>.old` (the running app keeps its open files). When
/// the new one can't be moved in, the old one is put back and the error is thrown: Encore is never left missing.
Future<void> swapInstall(Directory dir, Directory fresh, {Future<void> Function(Directory, String) move = _move}) async {
  final old = Directory('${dir.path}.old');
  if (await old.exists()) await old.delete(recursive: true);
  await move(dir, old.path);
  try {
    await move(fresh, dir.path);
  } catch (e) {
    try {
      await move(old, dir.path);
    } catch (_) {
      throw FileSystemException("Couldn't put the new version in place ($e), nor this one back: it's in ${old.path}");
    }
    throw FileSystemException("Couldn't put the new version in place ($e). This version is still installed");
  }
}

Future<void> _move(Directory d, String to) => d.rename(to);

// One install at a time: a second would unpack into the folder the first is swapping in, or overwrite the
// Flatpak bundle it's installing.
bool _installing = false;

/// Runs [install] unless another install is running (then throws).
Future<void> oneInstallAtATime(Future<void> Function() install) async {
  if (_installing) throw const FileSystemException('Another update is being installed');
  _installing = true;
  try {
    await install();
  } finally {
    _installing = false;
  }
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

/// pkexec ended without running the package manager because you said no: 126, the password window was closed; 127
/// "Not authorized", the password refused. Its other 127 (no password window on this desktop: "No authentication
/// agent found") is a failure, so the terminal command is shown instead.
bool pkexecRefused(int exitCode, String stderr) => exitCode == 126 || (exitCode == 127 && stderr.contains('Not authorized'));

/// The system's password window, for installing a package as root: pkexec (polkit), which every desktop has an agent
/// for. Without it the update is shown as a command to run instead.
String? pkexec() => ['/usr/bin/pkexec', '/bin/pkexec'].where((p) => File(p).existsSync()).firstOrNull;

/// Encore runs in a Flatpak (tools/flatpak).
bool inFlatpak({String info = '/.flatpak-info'}) => File(info).existsSync();

/// Which installation this Flatpak is in, as `flatpak install` takes it: --user (~/.local/share/flatpak, no
/// password) or --system (for everyone; the system asks for your password). A user installation is always in your
/// home folder (also when XDG_DATA_HOME moves it), a system one never is.
String flatpakInstallation({String info = '/.flatpak-info', String? home}) {
  try {
    final line = File(info).readAsLinesSync().where((l) => l.startsWith('app-path=')).firstOrNull ?? '';
    final h = home ?? Platform.environment['HOME'] ?? '';
    final mine = line.contains('/.local/share/flatpak/') || (h.length > 1 && line.startsWith('app-path=$h/'));
    return mine ? '--user' : '--system';
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

/// This copy is the one a .deb, RPM or Arch package put in place (/usr/lib/encore, or /usr/lib64/encore for the
/// RPM). A copy run from anywhere else (unpacked by hand, a build) isn't updated with the package manager: that
/// would install the package beside it and start this old copy again.
bool runsFromSystemPackage({String? exe}) {
  final dir = File(exe ?? Platform.resolvedExecutable).parent.path;
  return dir == '/usr/lib/encore' || dir == '/usr/lib64/encore';
}

/// Installs the downloaded package with the system's package manager, as root through pkexec (the system asks for
/// your password in its own window), then starts the new version once this one has quit (the caller quits).
Future<void> installSystemPackage(File package, String kind) async {
  if (kind == 'flatpak') return _installFlatpak(package);
  final px = pkexec();
  final cmd = packageInstallCommand(kind, package.path);
  if (px == null || cmd == null) throw const FileSystemException('No way to install packages here');
  final r = await Process.run(px, cmd);
  if (pkexecRefused(r.exitCode, '${r.stderr}')) throw const core.PackageInstallCancelled();
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
