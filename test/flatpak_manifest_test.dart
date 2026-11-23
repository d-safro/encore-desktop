import 'dart:io';

import 'package:encore/desktop/desktop.dart' show mprisName;
import 'package:flutter_test/flutter_test.dart';

/// The session bus names the Flatpak may own (--own-name), matched as xdg-dbus-proxy does: "org.foo.*" is
/// org.foo and every name below it, anything else only that exact name.
bool flatpakMayOwn(String name) {
  final own = File('tools/flatpak/dev.safro.encore.yml')
      .readAsLinesSync()
      .map((l) => RegExp(r'^\s*-\s*--own-name=(\S+)').firstMatch(l)?.group(1))
      .nonNulls;
  return own.any((o) => o.endsWith('.*')
      ? name == o.substring(0, o.length - 2) || name.startsWith(o.substring(0, o.length - 1))
      : name == o);
}

void main() {
  test('the Flatpak may own the MPRIS name the player asks for (else the player never starts)', () {
    // audio_service_mpris asks for org.mpris.MediaPlayer2.<name>.instance<pid>; the app is pid 2 in the sandbox
    expect(flatpakMayOwn('org.mpris.MediaPlayer2.$mprisName.instance2'), isTrue);
    expect(flatpakMayOwn('org.mpris.MediaPlayer2.$mprisName.instance12345'), isTrue);
  });
}
