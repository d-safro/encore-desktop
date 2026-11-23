import 'dart:io';

import 'package:encore/desktop/updater.dart';
import 'package:encore_core/data/updates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("a system-installed copy is updated with its own package manager", () {
    bool none(String _) => false;
    expect(packageInstallCommand('deb', '/u/encore.deb', exists: none), ['apt-get', 'install', '-y', '/u/encore.deb']);
    expect(packageInstallCommand('arch', '/u/encore.pkg.tar.zst', exists: none), ['pacman', '-U', '--noconfirm', '/u/encore.pkg.tar.zst']);
    // an RPM: Fedora's dnf, else openSUSE's zypper, else nothing (the command is shown instead)
    expect(packageInstallCommand('rpm', '/u/e.rpm', exists: (p) => p == '/usr/bin/dnf'), ['dnf', 'install', '-y', '/u/e.rpm']);
    expect(packageInstallCommand('rpm', '/u/e.rpm', exists: (p) => p == '/usr/bin/zypper'),
        ['zypper', '--non-interactive', 'install', '--allow-unsigned-rpm', '/u/e.rpm']);
    expect(packageInstallCommand('rpm', '/u/e.rpm', exists: none), isNull);
  });

  test('a closed password window is "cancelled"; a desktop without one gets the terminal command', () {
    expect(pkexecRefused(126, ''), isTrue);
    expect(pkexecRefused(127, 'Error executing command as another user: Not authorized\n\nThis incident has been reported.\n'),
        isTrue);
    expect(pkexecRefused(127, 'Error executing command as another user: No authentication agent found.\n'), isFalse);
    expect(pkexecRefused(100, 'E: Unable to locate package'), isFalse);
  });

  test('only the copy a package installed is updated with the package manager', () {
    expect(runsFromSystemPackage(exe: '/usr/lib/encore/encore'), isTrue); // .deb, Arch
    expect(runsFromSystemPackage(exe: '/usr/lib64/encore/encore'), isTrue); // RPM
    // unpacked by hand, or a build: dnf would install the RPM beside it and this old copy would start again
    expect(runsFromSystemPackage(exe: '/home/me/Downloads/encore-1.12.0-linux-x86_64/app/encore'), isFalse);
    expect(runsFromSystemPackage(exe: '/home/me/src/encore-desktop/build/linux/x64/release/bundle/encore'), isFalse);
    expect(runsFromSystemPackage(exe: '/opt/encore/encore'), isFalse);
  });

  test('a Flatpak is updated by the computer\'s flatpak, in the installation it came from', () {
    final dir = Directory.systemTemp.createTempSync('fp');
    addTearDown(() => dir.deleteSync(recursive: true));
    final info = File('${dir.path}/.flatpak-info');
    expect(inFlatpak(info: info.path), isFalse);
    expect(linuxPackageKind(root: dir.path), isNot('flatpak'));
    info.writeAsStringSync('[Application]\nname=dev.safro.encore\n\n[Instance]\n'
        'app-path=/home/me/.local/share/flatpak/app/dev.safro.encore/x86_64/master/abc/files\n');
    expect(inFlatpak(info: info.path), isTrue);
    expect(linuxPackageKind(root: dir.path), 'flatpak');
    expect(flatpakInstallation(info: info.path), '--user');
    info.writeAsStringSync('[Instance]\napp-path=/var/lib/flatpak/app/dev.safro.encore/x86_64/master/abc/files\n');
    expect(flatpakInstallation(info: info.path, home: '/home/me'), '--system');
    // your own installation moved with XDG_DATA_HOME: still --user, not a second copy for everyone
    info.writeAsStringSync('[Instance]\napp-path=/home/me/.data/flatpak/app/dev.safro.encore/x86_64/master/abc/files\n');
    expect(flatpakInstallation(info: info.path, home: '/home/me'), '--user');
    expect(packageInstallCommand('flatpak', '/c/u.flatpak', installation: '--user'),
        ['flatpak-spawn', '--host', 'flatpak', 'install', '--user', '-y', '/c/u.flatpak']);
    // a system-wide copy: the system's password window may come up (--noninteractive would forbid it)
    expect(packageInstallCommand('flatpak', '/c/u.flatpak', installation: '--system'), isNot(contains('--noninteractive')));
    // the password window closed
    expect(flatpakRefused(['error: Failed to install dev.safro.encore: Flatpak system operation InstallBundle not allowed for user']),
        isTrue);
    expect(flatpakRefused(['error: No space left on device']), isFalse);
  });

  test('the release\'s .flatpak is the update for a Flatpak copy', () {
    final names = ['encore-1.13.0-linux-x86_64.tar.gz', 'encore-1.13.0-x86_64.flatpak', 'encore-1.13.0-aarch64.flatpak'];
    expect(pickFlatpak(names, 'x86_64'), 'encore-1.13.0-x86_64.flatpak');
    expect(pickFlatpak(names, 'riscv64'), isNull);
    const u = UpdateInfo(version: '1.13.0', notes: '', apkUrl: '', apkName: '', size: 0, sumsUrl: '', pageUrl: '',
        flatpakUrl: 'https://x/encore-1.13.0-x86_64.flatpak');
    expect(systemPackageUrl(u, 'flatpak'), u.flatpakUrl);
    expect(systemUpdateCommand(u, 'flatpak', flatpakInstallation: '--user'),
        contains('flatpak install --user -y ./encore-1.13.0-x86_64.flatpak'));
  });
}
