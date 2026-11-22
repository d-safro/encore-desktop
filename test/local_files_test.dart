import 'dart:io';

import 'package:encore_core/core/appearance.dart';
import 'package:encore_core/core/settings.dart';
import 'package:encore_core/data/device_playlists.dart';
import 'package:encore_core/data/library.dart';
import 'package:encore_core/data/local_android.dart';
import 'package:encore_core/data/local_files.dart';
import 'package:encore_core/data/models.dart';
import 'package:encore/desktop/local_folders.dart';
import 'package:encore_core/playback/autoplay.dart';
import 'package:encore_core/playback/local_open.dart';
import 'package:encore_core/ui/screens/local_music.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class FakeSource extends LocalSource {
  FakeSource(this.found, {this.ok = true});
  List<LocalTrack> found;
  bool ok;
  int scans = 0;
  Map<String, LocalTrack>? lastKnown;
  @override
  Future<bool> allowed({bool ask = false}) async => ok || ask;
  @override
  Future<List<LocalTrack>> scan(Map<String, LocalTrack> known) async {
    scans++;
    lastKnown = known;
    return found;
  }
}

bool get hasFfmpeg => Process.runSync('which', ['ffmpeg']).exitCode == 0;

Future<File> tagged(Directory d, String name, Map<String, String> tags, {bool cover = false}) async {
  final f = File(p.join(d.path, name));
  await f.parent.create(recursive: true);
  final args = ['-v', 'error', '-y', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=2'];
  if (cover) args.addAll(['-f', 'lavfi', '-i', 'color=c=red:s=64x64:d=1', '-map', '0', '-map', '1', '-frames:v', '1', '-disposition:v', 'attached_pic']);
  for (final e in tags.entries) {
    args.addAll(['-metadata', '${e.key}=${e.value}']);
  }
  final r = await Process.run('ffmpeg', [...args, f.path]);
  if (r.exitCode != 0) throw r.stderr;
  return f;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    tmp = await Directory.systemTemp.createTemp('local');
    LocalLibraryNotifier.store = () async => File(p.join(tmp.path, 'store.json'));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => p.join(tmp.path, 'support'),
    );
  });
  tearDown(() => tmp.delete(recursive: true));

  test('ids, titles from file names, songs', () {
    expect(localId('/m/a.flac'), localId('/m/a.flac'));
    expect(localId('/m/a.flac'), isNot(localId('/m/b.flac')));
    expect(isLocalFileId(localId('/x')), isTrue);
    expect(titleFromFileName('/m/03 - The Kinks - Sunny Afternoon.flac'), 'Sunny Afternoon');
    expect(titleFromFileName('/m/track_one.mp3'), 'track one');
    const t = LocalTrack(uri: '/m/a.flac', title: 'A', artist: 'X', album: 'Y', track: 2, cover: 'file:/c.jpg', mtime: 5);
    final s = t.toSong();
    expect((s.id, s.albumId, s.artistId, s.suffix, s.coverArt), (t.id, '', '', 'flac', 'file:/c.jpg')); // no links
    expect(LocalTrack.fromJson(t.toJson())!.toSong().track, 2);
  });

  test('Android rows: tags from MediaStore', () {
    final t = trackFromMediaStore({'uri': 'content://media/external/audio/media/7', 'title': '', 'artist': '<unknown>',
      'album': 'Live', 'track': 2003, 'duration': 183500, 'name': '05 - Song.mp3', 'cover': '/c/ma-1.jpg'})!;
    expect((t.title, t.artist, t.track, t.duration, t.cover), ('Song', '', 3, 184, 'file:/c/ma-1.jpg'));
  });

  test('command-line files', () {
    expect(fileArgs(['--hidden', '/m/a.flac', 'file:///m/b%20c.mp3', '/m/notes.txt']), ['/m/a.flac', 'file:///m/b%20c.mp3']);
  });

  test('the list: found, kept between runs, unchanged files not read again, searched', () async {
    const a = LocalTrack(uri: '/m/b.flac', title: 'Taxman', artist: 'The Beatles', album: 'Revolver', mtime: 1);
    const b = LocalTrack(uri: '/m/a.flac', title: 'Sunny Afternoon', artist: 'The Kinks', album: 'Face to Face', mtime: 1);
    final src = FakeSource([a, b]);
    localSource = src;
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(localLibraryProvider);
    await Future.delayed(const Duration(milliseconds: 50));
    expect(c.read(localLibraryProvider).tracks.map((t) => t.artist), ['The Beatles', 'The Kinks']); // sorted
    expect(localUriFor(a.id), '/m/b.flac');
    expect(c.read(localLibraryProvider).search('kinks sunny').single.title, 'Sunny Afternoon');
    expect(c.read(localLibraryProvider).search('nothing'), isEmpty);
    // the next start: the saved list, and the scan is told what it had
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    c2.read(localLibraryProvider);
    await Future.delayed(const Duration(milliseconds: 50));
    expect(src.lastKnown!.keys, containsAll(['/m/a.flac', '/m/b.flac']));
  });

  test('no permission: says so, and asks when told to', () async {
    final src = FakeSource([const LocalTrack(uri: '/m/a.flac', title: 'A')], ok: false);
    localSource = src;
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(localLibraryProvider.notifier).refresh();
    expect(c.read(localLibraryProvider).allowed, isFalse);
    expect(src.scans, 0);
    await c.read(localLibraryProvider.notifier).refresh(ask: true);
    expect(c.read(localLibraryProvider).tracks.length, 1);
  });

  test('tags and covers read from real files', () async {
    if (!hasFfmpeg) return;
    final f = await tagged(tmp, 'x/01 - song.flac', {'title': 'Real Title', 'artist': 'Real Artist', 'album': 'An Album', 'track': '4', 'date': '1999'});
    final t = await readTags(f, coversDir: Directory(p.join(tmp.path, 'covers')));
    expect((t.title, t.artist, t.album, t.track, t.year), ('Real Title', 'Real Artist', 'An Album', 4, 1999));
    expect(t.duration, inInclusiveRange(1, 3));
    final m = await tagged(tmp, 'x/pic.mp3', {'title': 'With picture'}, cover: true);
    final withPic = await readTags(m, coversDir: Directory(p.join(tmp.path, 'covers')));
    expect(withPic.cover, startsWith('file:'));
    expect(await File(withPic.cover.substring(5)).exists(), isTrue);
    final junk = File(p.join(tmp.path, 'x/broken.mp3'))..writeAsBytesSync([1, 2, 3]);
    expect((await readTags(junk)).title, 'broken'); // no tags: the file name
  });

  test('desktop folders: audio files, not Encore\'s downloads, not hidden folders; ~ is home', () async {
    expect(localFolders(null, home: '/home/me'), ['/home/me/Music']);
    expect(localFolders(['~/Tunes', '/srv/music'], home: '/home/me'), ['/home/me/Tunes', '/srv/music']);
    // hidden means under the chosen folder, and not an album that starts with dots or a number
    expect(hiddenBelow('/home/me/.local/Music', '/home/me/.local/Music/A/one.flac'), isFalse);
    expect(hiddenBelow('/m', '/m/Metallica/...And Justice for All/01.flac'), isFalse);
    expect(hiddenBelow('/m', '/m/.38 Special/Wild-Eyed Southern Boys/01.flac'), isFalse);
    expect(hiddenBelow('/m', '/m/.hidden/two.flac'), isTrue);
    expect(hiddenBelow('/m', '/m/A/._one.flac'), isTrue);
    if (!hasFfmpeg) return;
    final music = Directory(p.join(tmp.path, 'Music'));
    await tagged(music, 'A/one.flac', {'title': 'One'});
    await tagged(music, '.hidden/two.flac', {'title': 'Two'});
    File(p.join(music.path, 'A/cover.jpg')).writeAsBytesSync([0]);
    final own = await DownloadsNotifier.musicDir(); // in the test's own folder (path_provider mocked above)
    await tagged(own, 'mine.flac', {'title': 'Mine'});
    await prefs.setStringList('localFolders', [music.path, own.path]);
    final found = await DesktopFolderSource().scan({});
    expect(found.map((t) => t.title), ['One']);
  });

  test('a file on this device never seeds autoplay', () {
    final local = const LocalTrack(uri: '/m/a.flac', title: 'A').toSong();
    expect(chooseSeeds([local, local]), isEmpty);
    expect(chooseSeeds([const Song(id: 's1', title: 'Server'), local]).map((s) => s.id), ['s1']);
  });

  test('playlists on this device mix both kinds', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(devicePlaylistsProvider.notifier);
    final local = const LocalTrack(uri: '/m/a.flac', title: 'Local').toSong();
    final pl = n.create('Mixed', [local]);
    expect(n.add(pl.id, [const Song(id: 's1', title: 'Server'), local]), 1); // the local one is in already
    n.move(pl.id, 1, 0);
    expect(c.read(devicePlaylistsProvider).single.songs.map((s) => s.title), ['Server', 'Local']);
    final again = ProviderContainer();
    addTearDown(again.dispose);
    expect(again.read(devicePlaylistsProvider).single.songs.last.path, '/m/a.flac'); // kept, with where it is
    n.removeAt(pl.id, 0);
    n.delete(pl.id);
    expect(c.read(devicePlaylistsProvider), isEmpty);
  });

  testWidgets('the screen lists them', (tester) async {
    localSource = FakeSource([const LocalTrack(uri: '/m/a.flac', title: 'Sunny Afternoon', artist: 'The Kinks')]);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(theme: ThemeData(extensions: [AppLook.from(const Settings())]), home: const LocalMusicScreen()),
    ));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(find.text('Sunny Afternoon'), findsOneWidget);
    expect(find.textContaining('stay private'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 4)); // the downloads' own timer (song rows watch them)
  });
}
