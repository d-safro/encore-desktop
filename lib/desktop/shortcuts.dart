import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:encore_core/core/settings.dart';
import 'package:encore_core/playback/skip.dart' show skipLabel;

/// The desktop's keyboard shortcuts. Media keys (play, next…) come through MPRIS, so they work even when
/// Encore isn't the active window.
class DesktopShortcut {
  const DesktopShortcut(this.id, this.keys, this.label, this.activators, {this.whileTyping = false});
  final String id; // what it does (DesktopShell runs it)
  final String keys, label; // for the help list
  final List<ShortcutActivator> activators;
  final bool whileTyping; // also while a text field has the keyboard (else the key types / moves the cursor)
}

const _c = true;
final desktopShortcuts = <DesktopShortcut>[
  const DesktopShortcut('playPause', 'Space', 'Play / pause', [SingleActivator(LogicalKeyboardKey.space)]),
  const DesktopShortcut('next', 'Ctrl+→', 'Next song', [SingleActivator(LogicalKeyboardKey.arrowRight, control: _c)]),
  const DesktopShortcut('previous', 'Ctrl+←', 'Previous song', [SingleActivator(LogicalKeyboardKey.arrowLeft, control: _c)]),
  const DesktopShortcut('forward', 'Shift+→', 'Skip forward', [SingleActivator(LogicalKeyboardKey.arrowRight, shift: true)]),
  const DesktopShortcut('back', 'Shift+←', 'Skip back', [SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true)]),
  const DesktopShortcut('louder', 'Ctrl+↑', 'Louder', [SingleActivator(LogicalKeyboardKey.arrowUp, control: _c)]),
  const DesktopShortcut('quieter', 'Ctrl+↓', 'Quieter', [SingleActivator(LogicalKeyboardKey.arrowDown, control: _c)]),
  const DesktopShortcut('heart', 'Ctrl+L', 'Like the playing song', [SingleActivator(LogicalKeyboardKey.keyL, control: _c)]),
  const DesktopShortcut('shuffle', 'Ctrl+S', 'Shuffle: off, on, smart', [SingleActivator(LogicalKeyboardKey.keyS, control: _c)]),
  const DesktopShortcut('repeat', 'Ctrl+R', 'Repeat: off, all, one', [SingleActivator(LogicalKeyboardKey.keyR, control: _c)]),
  const DesktopShortcut('search', 'Ctrl+F or Ctrl+K', 'Search', [
    SingleActivator(LogicalKeyboardKey.keyF, control: _c),
    SingleActivator(LogicalKeyboardKey.keyK, control: _c),
  ], whileTyping: true),
  const DesktopShortcut('player', 'Ctrl+P', 'Full-screen player', [SingleActivator(LogicalKeyboardKey.keyP, control: _c)], whileTyping: true),
  const DesktopShortcut('queue', 'Ctrl+Shift+Q', 'Show / hide the queue', [
    SingleActivator(LogicalKeyboardKey.keyQ, control: _c, shift: true),
  ], whileTyping: true),
  const DesktopShortcut('lyrics', 'Ctrl+Shift+L', 'Show / hide the lyrics', [
    SingleActivator(LogicalKeyboardKey.keyL, control: _c, shift: true),
  ], whileTyping: true),
  const DesktopShortcut('nowPlaying', 'Ctrl+Shift+N', 'Show / hide Now playing', [
    SingleActivator(LogicalKeyboardKey.keyN, control: _c, shift: true),
  ], whileTyping: true),
  const DesktopShortcut('devices', 'Ctrl+D', 'Your devices', [SingleActivator(LogicalKeyboardKey.keyD, control: _c)], whileTyping: true),
  const DesktopShortcut('goBack', 'Alt+← or Esc', 'Go back', [
    SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true),
    SingleActivator(LogicalKeyboardKey.escape),
  ]),
  const DesktopShortcut('goForward', 'Alt+→', 'Go forward', [SingleActivator(LogicalKeyboardKey.arrowRight, alt: true)]),
  const DesktopShortcut('settings', 'Ctrl+,', 'Settings', [SingleActivator(LogicalKeyboardKey.comma, control: _c)], whileTyping: true),
  for (var i = 1; i <= 6; i++)
    DesktopShortcut('tab$i', 'Ctrl+$i', i == 1 ? 'Sidebar sections 1 to 6' : '', [
      SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i - 1), control: _c),
    ], whileTyping: true),
  const DesktopShortcut('quit', 'Ctrl+Q', 'Quit Encore', [SingleActivator(LogicalKeyboardKey.keyQ, control: _c)], whileTyping: true),
];

class _Run extends Intent {
  const _Run(this.id);
  final String id;
}

/// True while a text field has the keyboard.
bool typing() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  return ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null;
}

class _RunAction extends Action<_Run> {
  _RunAction(this.onRun);
  final void Function(String id) onRun;
  _Run? _last;

  @override
  bool isEnabled(_Run intent) {
    _last = intent;
    final s = desktopShortcuts.firstWhere((s) => s.id == intent.id);
    return s.whileTyping || !typing();
  }

  // a disabled shortcut lets the key through (to the text field)
  @override
  bool consumesKey(_Run intent) => isEnabled(intent);

  @override
  Object? invoke(_Run intent) {
    onRun((_last ?? intent).id);
    return null;
  }
}

/// Puts the shortcuts around the app; [onRun] gets the shortcut's id.
class DesktopShortcuts extends StatelessWidget {
  const DesktopShortcuts({super.key, required this.onRun, required this.child});
  final void Function(String id) onRun;
  final Widget child;

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: {
      for (final s in desktopShortcuts)
        for (final a in s.activators) a: _Run(s.id),
    },
    child: Actions(
      actions: {_Run: _RunAction(onRun)},
      child: Focus(autofocus: true, child: child),
    ),
  );
}

/// A shortcut's name in the help list: the skips say their seconds (Settings › Playback).
String _labelOf(BuildContext context, DesktopShortcut s) {
  if (s.id != 'forward' && s.id != 'back') return s.label;
  final st = ProviderScope.containerOf(context, listen: false).read(settingsProvider);
  final forward = s.id == 'forward';
  return skipLabel(forward ? st.skipForward : st.skipBack, forward: forward);
}

Future<void> showShortcutsHelp(BuildContext context) => showDialog(
  context: context,
  useRootNavigator: true,
  builder: (ctx) {
    final t = Theme.of(ctx).textTheme;
    final cs = Theme.of(ctx).colorScheme;
    return AlertDialog(
      title: const Text('Keyboard shortcuts'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final s in desktopShortcuts.where((s) => s.label.isNotEmpty))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(_labelOf(ctx, s))),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(s.id == 'tab1' ? 'Ctrl+1 … 6' : s.keys, style: t.labelMedium),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'The keyboard\'s media keys and ${Platform.isWindows ? 'Windows\'' : 'Plasma\'s'} media controls work too, even when Encore is in the tray.',
                style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
    );
  },
);
