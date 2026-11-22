import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:encore_core/core/settings.dart';
import 'package:encore_core/data/local_files.dart';
import 'local_folders.dart';

/// Settings > Desktop > Music on this computer: the folders Encore looks in (~/Music at first).
class LocalFoldersSettings extends ConsumerStatefulWidget {
  const LocalFoldersSettings({super.key});
  @override
  ConsumerState<LocalFoldersSettings> createState() => _LocalFoldersSettingsState();
}

class _LocalFoldersSettingsState extends ConsumerState<LocalFoldersSettings> {
  Future<void> _save(List<String> folders) async {
    await prefs.setStringList('localFolders', folders);
    setState(() {});
    await ref.read(localLibraryProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final folders = DesktopFolderSource.folders();
    final l = ref.watch(localLibraryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.computer_rounded),
          title: const Text('Music on this computer'),
          subtitle: Text(l.scanning
              ? 'Looking…'
              : '${l.tracks.length} song${l.tracks.length == 1 ? '' : 's'} in these folders, under Library > On this '
                  'computer. They stay here: never uploaded or scrobbled.'),
        ),
        for (final f in folders)
          ListTile(
            leading: const SizedBox(width: 24),
            title: Text(f, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              tooltip: 'Stop looking in $f',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => _save([for (final x in folders) if (x != f) x]),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
          child: Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Add a folder'),
                onPressed: () async {
                  final d = await FilePicker.getDirectoryPath(dialogTitle: 'A folder with music');
                  if (d != null && !folders.contains(d)) await _save([...folders, d]);
                },
              ),
              TextButton(
                onPressed: l.scanning ? null : () => ref.read(localLibraryProvider.notifier).refresh(),
                child: const Text('Look again now'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
