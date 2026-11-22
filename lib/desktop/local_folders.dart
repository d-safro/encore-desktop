import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:encore_core/core/settings.dart';
import 'package:encore_core/data/library.dart';
import 'package:encore_core/data/local_files.dart';

/// Desktop: the music in folders you choose (Settings > Music on this computer; ~/Music at first), scanned
/// for audio files and their tags (local_files.dart), and looked at again when a folder changes and every
/// 15 minutes. Encore's own downloads folder is never listed (those songs are on your server already).
class DesktopFolderSource extends LocalSource {
  DesktopFolderSource() {
    Timer.periodic(const Duration(minutes: 15), (_) => _changed.add(null));
  }

  final _changed = StreamController<void>.broadcast();
  final _watching = <String, StreamSubscription<FileSystemEvent>>{};

  @override
  Stream<void> get changes => _changed.stream;

  @override
  Future<bool> allowed({bool ask = false}) async => true;

  static List<String> folders() => localFolders(prefs.getStringList('localFolders'));

  @override
  Future<List<LocalTrack>> scan(Map<String, LocalTrack> known) async {
    final own = p.normalize((await DownloadsNotifier.musicDir()).path);
    final covers = await localCoversDir();
    final out = <LocalTrack>[];
    final seen = <String>{};
    final dirs = folders();
    _watch(dirs);
    for (final d in dirs) {
      final dir = Directory(d);
      if (!await dir.exists()) continue;
      await for (final e in dir.list(recursive: true, followLinks: false).handleError((_) {})) {
        if (e is! File || !isAudioFile(e.path)) continue;
        final path = p.normalize(e.path);
        if (p.isWithin(own, path) || hiddenBelow(d, path) || !seen.add(path)) continue;
        final had = known[path];
        final mtime = (await e.stat()).modified.millisecondsSinceEpoch;
        out.add(had != null && had.mtime == mtime ? had : await readTags(e, coversDir: covers));
      }
    }
    return out;
  }

  /// A folder changing (a file added, renamed or removed) asks for a new scan. Linux can't watch a folder and
  /// everything under it, so there it's the top folders (the 15-minute look catches the rest).
  void _watch(List<String> dirs) {
    for (final gone in _watching.keys.where((d) => !dirs.contains(d)).toList()) {
      _watching.remove(gone)?.cancel();
    }
    for (final d in dirs) {
      if (_watching.containsKey(d) || !Directory(d).existsSync()) continue;
      try {
        _watching[d] = Directory(d).watch(recursive: !Platform.isLinux).listen((_) => _changed.add(null), onError: (_) {});
      } catch (_) {}
    }
  }
}

/// Whether [path] is a hidden file, or in a hidden folder, under the chosen folder [root] (the folder itself
/// may be anywhere, ~/.local included). Names like "...And Justice for All" or ".38 Special" aren't hidden.
bool hiddenBelow(String root, String path) => p
    .split(p.relative(path, from: root))
    .any((x) => x.length > 1 && x.startsWith('.') && !x.startsWith('..') && !RegExp(r'^\.\d').hasMatch(x));

/// The folders, from the setting ('~' is your home); ~/Music when none are set.
List<String> localFolders(List<String>? saved, {String? home}) {
  final h = home ?? Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  final list = saved ?? [p.join('~', 'Music')];
  return [
    for (final d in list)
      if (d.trim().isNotEmpty) p.normalize(d.startsWith('~') ? p.join(h, d.substring(1).replaceFirst(RegExp(r'^[\\/]'), '')) : d),
  ];
}
