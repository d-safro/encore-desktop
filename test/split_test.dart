// What keeps existing desktop installs updating in place after the split from d-safro/encore: the same
// application id, binary name, desktop file, Windows installer id and Windows names (the settings, queue and
// downloads live in folders named after them), and the version the app reports.
import 'dart:io';

import 'package:encore/desktop/host.dart';
import 'package:encore/version.dart';
import 'package:encore_core/core/host.dart';
import 'package:encore_core/data/updates.dart';
import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('the same application id and binary name on Linux', () {
    final cmake = read('linux/CMakeLists.txt');
    expect(cmake, contains('set(BINARY_NAME "encore")'));
    expect(cmake, contains('set(APPLICATION_ID "dev.safro.encore")'));
    expect(File('tools/linux/dev.safro.encore.desktop').existsSync(), isTrue);
    expect(read('tools/linux/dev.safro.encore.desktop'), contains('Exec=encore'));
  });

  test('the same installer id and names on Windows', () {
    expect(read('windows/CMakeLists.txt'), contains('set(BINARY_NAME "encore")'));
    expect(read('tools/windows/encore.iss'), contains('AppId={{8C2B5D4E-7A1F-4E3B-9D6C-5F0A1B2C3D4E}'));
    final rc = read('windows/runner/Runner.rc');
    expect(rc, contains('VALUE "CompanyName", "Encore"'));
    expect(rc, contains('VALUE "ProductName", "Encore"'));
  });

  test('updates come from encore-desktop, and the version is the one in pubspec.yaml', () {
    const host = DesktopHost();
    expect(host.updateRepo, 'd-safro/encore-desktop');
    final pub = RegExp(r'^version: *([0-9.]+)', multiLine: true).firstMatch(read('pubspec.yaml'))!.group(1);
    expect(encoreVersion, pub);
    encoreHost = host;
    expect(updateRepo, 'd-safro/encore-desktop');
    encoreHost = const EncoreHost();
  });

  test('the desktop release still reaches copies that ask d-safro/encore', () {
    final wf = read('.github/workflows/desktop.yml');
    expect(wf, contains('d-safro/encore'));
    expect(wf, contains('ATTACH_TO_PHONE_REPO'));
  });
}
