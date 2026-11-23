import 'package:encore/desktop/updater.dart';
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
}
