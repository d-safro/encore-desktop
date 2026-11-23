import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'local_folders_settings.dart';

import 'desktop.dart';
import 'shortcuts.dart';
import 'updater.dart' show inFlatpak;

/// Start Encore when you log in (in the tray, no window): a standard XDG autostart entry on Linux, only
/// while this switch is on.
File _autostartFile() =>
    File(p.join(autostartFolder(Platform.environment, flatpak: inFlatpak()), 'dev.safro.encore.desktop'));

/// Where the desktop looks for autostart entries. In the Flatpak, XDG_CONFIG_HOME is the sandbox's own folder,
/// which the desktop never reads: the entry goes in your ~/.config/autostart (tools/flatpak allows it).
String autostartFolder(Map<String, String> env, {required bool flatpak}) {
  final home = env['HOME'] ?? '';
  final config = flatpak ? null : env['XDG_CONFIG_HOME'];
  return p.join(config == null || config.isEmpty ? p.join(home, '.config') : config, 'autostart');
}

// Windows keeps the same switch in the registry: the "Run" list of your own account.
const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';

bool autostartOn() {
  if (Platform.isWindows) {
    try {
      return Process.runSync('reg', ['query', _runKey, '/v', 'Encore']).exitCode == 0;
    } catch (_) {
      return false;
    }
  }
  return _autostartFile().existsSync();
}

/// The autostart entry's text for the app at [exe]. The Flatpak is started through flatpak: [exe] is a path in
/// its sandbox, which the desktop doesn't have.
String autostartEntry(String exe, {bool flatpak = false}) => '''[Desktop Entry]
Type=Application
Name=Encore
Comment=Music from your Navidrome server
Exec=${flatpak ? 'flatpak run dev.safro.encore --hidden' : '"$exe" --hidden'}
Icon=dev.safro.encore
X-KDE-autostart-phase=2
X-GNOME-Autostart-enabled=true
''';

Future<void> setAutostart(bool on) async {
  if (Platform.isWindows) {
    await Process.run('reg', on
        ? ['add', _runKey, '/v', 'Encore', '/t', 'REG_SZ', '/d', '"${Platform.resolvedExecutable}" --hidden', '/f']
        : ['delete', _runKey, '/v', 'Encore', '/f']);
    return;
  }
  final f = _autostartFile();
  if (on) {
    await f.parent.create(recursive: true);
    await f.writeAsString(autostartEntry(Platform.resolvedExecutable, flatpak: inFlatpak()));
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
        const LocalFoldersSettings(),
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
        SwitchListTile(
          secondary: const Icon(Icons.notifications_none_rounded),
          title: const Text('Show each new song'),
          subtitle: const Text('A notification when the song changes, while Encore isn\'t the window in front'),
          value: songNotifications,
          onChanged: (v) async {
            await setSongNotifications(v);
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
