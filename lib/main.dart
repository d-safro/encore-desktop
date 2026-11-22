import 'package:encore_core/run.dart';

import 'desktop/host.dart';

/// Encore for Linux and Windows. Everything both apps share is in encore_core; DesktopHost adds the
/// desktop's own pieces (mpv, the window, the tray, the layout, its updater).
Future<void> main(List<String> args) => runEncore(const DesktopHost(), args);
