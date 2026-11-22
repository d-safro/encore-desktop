import 'package:desktop_drop/desktop_drop.dart';
import 'package:material_ui/material_ui.dart';

import 'package:encore_core/data/local_files.dart' show isAudioFile;
import 'package:encore_core/playback/local_open.dart';

/// Music files dropped on the window from the file manager play (local_open.dart); a hint shows while
/// something is dragged over the window.
class FileDropArea extends StatefulWidget {
  const FileDropArea({super.key, required this.child});
  final Widget child;
  @override
  State<FileDropArea> createState() => _FileDropAreaState();
}

class _FileDropAreaState extends State<FileDropArea> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DropTarget(
      onDragEntered: (_) => setState(() => _over = true),
      onDragExited: (_) => setState(() => _over = false),
      onDragDone: (d) {
        setState(() => _over = false);
        final files = [for (final f in d.files) if (isAudioFile(f.path)) f.path];
        if (files.isNotEmpty) openFiles(files);
      },
      child: Stack(
        children: [
          widget.child,
          if (_over)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: cs.surface.withValues(alpha: 0.7),
                  child: Center(
                    child: Text('Drop music here to play it', style: Theme.of(context).textTheme.headlineSmall),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
