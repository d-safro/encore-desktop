import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'desktop.dart';
import 'shortcuts.dart';

/// Start Encore when you log in (in the tray, no window): a standard XDG autostart entry, only while this
/// switch is on.
File _autostartFile() =>
    File(p.join(Platform.environment['XDG_CONFIG_HOME'] ?? p.join(Platform.environment['HOME'] ?? '', '.config'),
        'autostart', 'dev.safro.encore.desktop'));

bool autostartOn() => _autostartFile().existsSync();

/// The autostart entry's text for the app at [exe].
String autostartEntry(String exe) => '''[Desktop Entry]
Type=Application
Name=Encore
Comment=Music from your Navidrome server
Exec="$exe" --hidden
Icon=dev.safro.encore
X-KDE-autostart-phase=2
X-GNOME-Autostart-enabled=true
''';

Future<void> setAutostart(bool on) async {
  final f = _autostartFile();
  if (on) {
    await f.parent.create(recursive: true);
    await f.writeAsString(autostartEntry(Platform.resolvedExecutable));
  } else if (await f.exists()) {
    await f.delete();
  }
}

class DesktopSettings extends ConsumerStatefulWidget {
  const DesktopSettings({super.key});
  @override
  ConsumerState<DesktopSettings> createState() => _DesktopSettingsState();
}

class _DesktopSettingsState extends ConsumerState<DesktopSettings> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.close_fullscreen_rounded),
          title: const Text('Keep playing in the tray when closed'),
          subtitle: const Text('Closing the window leaves Encore in the system tray; Quit there ends it'),
          value: closeToTray,
          onChanged: (v) async {
            await setCloseToTray(v);
            setState(() {});
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.login_rounded),
          title: const Text('Start when you log in'),
          subtitle: const Text('In the tray, without a window'),
          value: autostartOn(),
          onChanged: (v) async {
            await setAutostart(v);
            setState(() {});
          },
        ),
        ListTile(
          leading: const Icon(Icons.keyboard_rounded),
          title: const Text('Keyboard shortcuts'),
          subtitle: const Text('Space, Ctrl+→, Ctrl+F… and the media keys'),
          onTap: () => showShortcutsHelp(context),
        ),
      ],
    );
  }
}
