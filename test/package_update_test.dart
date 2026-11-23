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
    expect(flatpakInstallation(info: info.path), '--system');
    expect(packageInstallCommand('flatpak', '/c/u.flatpak', installation: '--user'),
        ['flatpak-spawn', '--host', 'flatpak', 'install', '--user', '-y', '--noninteractive', '/c/u.flatpak']);
  });

  test('the release\'s .flatpak is the update for a Flatpak copy', () {
    final names = ['encore-1.13.0-linux-x86_64.tar.gz', 'encore-1.13.0-x86_64.flatpak', 'encore-1.13.0-aarch64.flatpak'];
    expect(pickFlatpak(names, 'x86_64'), 'encore-1.13.0-x86_64.flatpak');
    expect(pickFlatpak(names, 'riscv64'), isNull);
    const u = UpdateInfo(version: '1.13.0', notes: '', apkUrl: '', apkName: '', size: 0, sumsUrl: '', pageUrl: '',
        flatpakUrl: 'https://x/encore-1.13.0-x86_64.flatpak');
    expect(systemPackageUrl(u, 'flatpak'), u.flatpakUrl);
    expect(systemUpdateCommand(u, 'flatpak'), contains('flatpak install -y ./encore-1.13.0-x86_64.flatpak'));
  });
}
