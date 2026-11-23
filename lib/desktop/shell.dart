import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:encore_core/core/appearance.dart';
import 'package:encore_core/core/settings.dart';
import 'package:encore_core/data/devices.dart';
import 'package:encore_core/data/library.dart';
import 'package:encore_core/data/library_pins.dart';
import 'package:encore_core/data/models.dart';
import 'package:encore_core/data/song_id.dart' show canIdentify;
import '../playback/desktop_audio.dart';
import 'package:encore_core/playback/handler.dart';
import 'package:encore_core/playback/private_session.dart';
import 'package:encore_core/playback/skip.dart' show skipShownFor;
import 'package:encore_core/ui/actions.dart';
import 'package:encore_core/ui/devices_sheet.dart';
import 'package:encore_core/ui/screens/player.dart';
import 'package:encore_core/ui/screens/search.dart' show searchBoxText;
import 'package:encore_core/ui/state.dart';
import 'package:encore_core/ui/whats_playing.dart';
import 'package:encore_core/ui/widgets.dart';
import 'desktop.dart';
import 'drag.dart';
import 'focus_ring.dart';
import 'now_playing.dart';
import 'sheets.dart';
import 'shortcuts.dart';

/// The desktop window: a sidebar (sections, your library and pins), the page, an optional side panel (queue
/// or lyrics), and a player bar along the bottom. Built for a wide, resizable window and a mouse and keyboard;
/// the pages themselves are the phone's.

/// A place in the sidebar.
class SideItem {
  const SideItem(this.label, this.icon, this.path, {this.match});
  final String label, path;
  final IconData icon;
  final bool Function(String location)? match; // is this the page shown? (default: the path's start)
  bool shows(String loc) => match?.call(loc) ?? (loc == path || loc.startsWith('$path/'));
}

bool _libraryTab(String loc, int tab) =>
    loc.startsWith('/library') && (int.tryParse(Uri.parse(loc).queryParameters['tab'] ?? '0') ?? 0) == tab;

final sideSections = [
  const SideItem('Home', Icons.home_rounded, '/home'),
  const SideItem('Search', Icons.search_rounded, '/search'),
  const SideItem('Discover', Icons.auto_awesome_rounded, '/discover'),
  SideItem('Playlists', Icons.queue_music_rounded, '/library?tab=0', match: (l) => _libraryTab(l, 0)),
  SideItem('Podcasts', Icons.podcasts_rounded, '/library?tab=1', match: (l) => _libraryTab(l, 1)),
  const SideItem('Radio', Icons.radio_rounded, '/radio'),
];

final sideLibrary = [
  SideItem('Albums', Icons.album_rounded, '/library?tab=2', match: (l) => _libraryTab(l, 2)),
  SideItem('Artists', Icons.person_rounded, '/library?tab=3', match: (l) => _libraryTab(l, 3)),
  const SideItem('Following', Icons.how_to_reg_rounded, '/following'),
  SideItem('Songs', Icons.music_note_rounded, '/library?tab=4', match: (l) => _libraryTab(l, 4)),
  const SideItem('On this computer', Icons.computer_rounded, '/local'),
  SideItem('Genres', Icons.category_rounded, '/library?tab=6', match: (l) => _libraryTab(l, 6)),
  const SideItem('Folders', Icons.folder_rounded, '/folders'),
  const SideItem('Your listening', Icons.insights_rounded, '/stats'),
  const SideItem('Downloaded', Icons.download_done_rounded, '/downloads'),
];

/// What the side panel shows.
enum SidePanel { none, queue, lyrics, nowPlaying }

double _pref(String k, double d) => prefs.getDouble(k) ?? d;

class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({super.key, required this.location, required this.child, this.banner});
  final String location;
  final Widget child;
  final Widget? banner; // the server-trouble strip
  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> {
  late double _side = _pref('sidebarWidth', 248).clamp(200, 360);
  late double _panel = _pref('panelWidth', 360).clamp(280, 520);
  late SidePanel _shown = SidePanel.values.firstWhere(
    // debug builds can open with a panel (visual checks: ENCORE_PANEL=nowPlaying)
    (p) => p.name == ((kDebugMode ? Platform.environment['ENCORE_PANEL'] : null) ?? prefs.getString('sidePanel')),
    orElse: () => SidePanel.none,
  );

  // Back and forward like a browser: Back pops (or goes to the page before), Forward undoes a Back.
  final _visited = <String>[];
  final _forward = <String>[];
  bool _byHistory = false, _goingBack = false;

  @override
  void didUpdateWidget(DesktopShell old) {
    super.didUpdateWidget(old);
    if (old.location == widget.location) return;
    if (!_byHistory) _forward.clear(); // somewhere new: Forward has nothing to redo
    final back = _goingBack;
    _byHistory = _goingBack = false;
    // Back took its page off the list: the page it left goes to Forward, not back on the list (else the next
    // Back would return to it, and Back would go to and fro between two pages)
    if (back) return;
    _visited.add(old.location);
    if (_visited.length > 100) _visited.removeAt(0);
  }

  bool get canBack => context.canPop() || _visited.isNotEmpty;

  void back() {
    if (!canBack) return;
    _byHistory = _goingBack = true;
    _forward.add(widget.location);
    if (context.canPop()) {
      context.pop();
      if (_visited.isNotEmpty) _visited.removeLast();
    } else {
      context.go(_visited.removeLast());
    }
    setState(() {});
  }

  void forward() {
    if (_forward.isEmpty) return;
    _byHistory = true;
    context.push(_forward.removeLast());
    setState(() {});
  }

  void _show(SidePanel p) {
    // a window too narrow for a panel: Now playing is the full-screen player instead
    if (!_panelFits && p != SidePanel.none) {
      if (p == SidePanel.nowPlaying && audioHandler.mediaItem.value != null) context.push('/player');
      return;
    }
    setState(() => _shown = _shown == p ? SidePanel.none : p);
    prefs.setString('sidePanel', _shown.name);
  }

  /// The page keeps at least this much room; below it the side panel stays hidden.
  static const _minPage = 520.0;
  bool get _panelFits => MediaQuery.sizeOf(context).width - _side - _panel - 32 >= _minPage;

  void _run(String id) {
    final h = audioHandler;
    final song = h.currentSong;
    switch (id) {
      case 'playPause':
        h.playbackState.value.playing ? h.pause() : h.play();
      case 'next':
        h.skipToNext();
      case 'previous':
        h.skipToPrevious();
      case 'forward':
        h.fastForward(); // the seconds in Settings › Playback (past the end: the next song)
      case 'back':
        h.rewind();
      case 'louder':
        setDesktopVolume((desktopVolume + 0.05).clamp(0, 1));
      case 'quieter':
        setDesktopVolume((desktopVolume - 0.05).clamp(0, 1));
      case 'heart':
        if (song != null && !isPodcastId(song.id)) toggleStarSong(context, ref, song);
      case 'shuffle':
        h.setShuffleKind(switch (h.shuffleKind) {
          ShuffleKind.off => ShuffleKind.on,
          ShuffleKind.on => ShuffleKind.smart,
          ShuffleKind.smart => ShuffleKind.off,
        });
      case 'repeat':
        final r = h.playbackState.value.repeatMode;
        h.setRepeatMode(switch (r) {
          AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
          AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
          _ => AudioServiceRepeatMode.none,
        });
      case 'search':
        desktopSearchFocus.requestFocus();
      case 'player':
        if (h.mediaItem.value != null) context.push('/player');
      case 'queue':
        _show(SidePanel.queue);
      case 'lyrics':
        _show(SidePanel.lyrics);
      case 'nowPlaying':
        _show(SidePanel.nowPlaying);
      case 'devices':
        showDevicesSheet(context);
      case 'goBack':
        back();
      case 'goForward':
        forward();
      case 'settings':
        context.push('/settings');
      case 'quit':
        quitApp();
      default:
        if (id.startsWith('tab')) {
          final i = int.parse(id.substring(3)) - 1;
          if (i < sideSections.length) context.go(sideSections[i].path);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasSong = ref.watch(mediaItemProvider).value != null;
    return DesktopShortcuts(
      onRun: _run,
      // keyboard focus shown with a ring; menus and panels the desktop's way
      child: FocusRing(child: DesktopSheets(child: Scaffold(
        backgroundColor: windowBackground(cs),
        body: Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(width: 8),
                  SizedBox(
                    width: _side,
                    child: _Pane(child: _Sidebar(location: widget.location)),
                  ),
                  _Splitter(
                    onDrag: (dx) {
                      setState(() => _side = (_side + dx).clamp(200, 360));
                    },
                    onDone: () => prefs.setDouble('sidebarWidth', _side),
                  ),
                  Expanded(
                    child: _Pane(
                      child: Column(
                        children: [
                          _TopBar(
                            canBack: canBack,
                            canForward: _forward.isNotEmpty,
                            onBack: back,
                            onForward: forward,
                            // one search box, always here: on the Search page it searches as you type
                            onSearchPage: widget.location.startsWith('/search'),
                            offline: ref.watch(offlineProvider),
                            query: widget.location.startsWith('/search')
                                ? Uri.parse(widget.location).queryParameters['q'] ?? ''
                                : '',
                          ),
                          Expanded(child: widget.child),
                        ],
                      ),
                    ),
                  ),
                  if (_shown != SidePanel.none && _panelFits) ...[
                    _Splitter(
                      onDrag: (dx) {
                        setState(() => _panel = (_panel - dx).clamp(280, 520));
                      },
                      onDone: () => prefs.setDouble('panelWidth', _panel),
                    ),
                    SizedBox(
                      width: _panel,
                      child: _Pane(
                        child: switch (_shown) {
                          SidePanel.nowPlaying => NowPlayingPanel(
                            onClose: () => _show(SidePanel.nowPlaying),
                            onQueue: () => _show(SidePanel.queue),
                            onLyrics: () => _show(SidePanel.lyrics),
                          ),
                          SidePanel.queue => SongDropTarget(
                            radius: 12,
                            onDrop: (songs) => dropOnQueue(context, songs),
                            child: QueueScreen(embedded: true, onClose: () => _show(SidePanel.queue)),
                          ),
                          _ => _LyricsPanel(onClose: () => _show(SidePanel.lyrics)),
                        },
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                ],
              ),
            ),
            ?widget.banner,
            if (hasSong) PlayerBar(panel: _shown, onPanel: _show),
          ],
        ),
      ))),
    );
  }
}

/// The window behind the rounded panes (sidebar, page, side panel), where the player bar sits: darker than the
/// panes on the dark theme; on the light theme a soft gray (half black made it a muddy gray that the player
/// bar's gray text barely showed on).
Color windowBackground(ColorScheme cs) => cs.brightness == Brightness.dark
    ? Color.alphaBlend(Colors.black.withValues(alpha: 0.5), cs.surface)
    : Color.alphaBlend(cs.onSurface.withValues(alpha: 0.07), cs.surface);

/// A rounded page area, like the panes of a desktop music app.
class _Pane extends StatelessWidget {
  const _Pane({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final look = AppLook.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(look.r(12)),
        child: ColoredBox(color: Theme.of(context).colorScheme.surface, child: child),
      ),
    );
  }
}

/// The handle between two panes: drag to resize.
class _Splitter extends StatelessWidget {
  const _Splitter({required this.onDrag, required this.onDone});
  final void Function(double dx) onDrag;
  final VoidCallback onDone;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
      onHorizontalDragEnd: (_) => onDone(),
      child: const SizedBox(width: 8),
    ),
  );
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.location});
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final pins = ref.watch(libraryPinsProvider);
    final offline = ref.watch(offlineProvider);
    final online = ref.watch(devicesProvider).online;
    Widget item(SideItem i, {Widget? leading}) {
      final on = i.shows(location);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: Material(
          color: on ? cs.primary.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppLook.of(context).r(10)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.go(i.path),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  leading ?? Icon(i.icon, size: 20, color: on ? cs.primary : cs.onSurfaceVariant),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      i.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.labelLarge?.copyWith(
                        color: on ? cs.primary : cs.onSurface,
                        fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Text(text.toUpperCase(), style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant, letterSpacing: 1.1)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
          child: Row(
            children: [
              const EncoreLogo(size: 30),
              const SizedBox(width: 10),
              Text('Encore', style: t.titleLarge),
              const Spacer(),
              if (offline)
                Tooltip(
                  message: 'Offline: playing what\'s on this computer',
                  child: Icon(Icons.cloud_off_rounded, size: 18, color: cs.onSurfaceVariant),
                ),
            ],
          ),
        ),
        Expanded(
          child: _GutterScroll(
            builder: (ctl) => ListView(
              controller: ctl,
              // the rows stop short of the edge: the scrollbar has its own lane beside them
              padding: const EdgeInsets.only(bottom: 8, right: 10),
              children: [
                for (final i in sideSections) item(i),
                header('Your library'),
                SongDropTarget(
                  onDrop: (songs) => dropOnLiked(context, ref, songs),
                  child: item(
                    const SideItem('Liked songs', Icons.favorite_rounded, '/liked'),
                    leading: Icon(Icons.favorite_rounded, size: 20, color: cs.primary),
                  ),
                ),
                for (final p in pins)
                  GestureDetector(
                    onSecondaryTap: () => showCollectionMenu(
                      context,
                      ref,
                      p.name,
                      () async => p.kind == 'album'
                          ? (await ref.read(repoProvider).album(p.id)).songs
                          : (await ref.read(repoProvider).playlist(p.id)).songs,
                      pin: p,
                    ),
                    child: p.kind == 'playlist'
                        ? SongDropTarget(
                            onDrop: (songs) => dropOnPlaylist(context, ref, p.id, p.name, songs),
                            child: item(
                              SideItem(p.name, Icons.push_pin_rounded, '/${p.kind}/${p.id}'),
                              leading: Cover(p.cover, size: 22, radius: 5),
                            ),
                          )
                        : item(
                            SideItem(p.name, Icons.push_pin_rounded, '/${p.kind}/${p.id}'),
                            leading: Cover(p.cover, size: 22, radius: 5),
                          ),
                  ),
                ...switch (ref.watch(playlistsProvider).value) {
                  final lists? when lists.isNotEmpty => [
                    header('Playlists'),
                    for (final pl in lists.where((pl) => !pins.any((p) => p.kind == 'playlist' && p.id == pl.id)))
                      GestureDetector(
                        onSecondaryTap: () => showCollectionMenu(
                          context,
                          ref,
                          pl.name,
                          () async => (await ref.read(repoProvider).playlist(pl.id)).songs,
                          pin: LibraryPin('playlist', pl.id, pl.name, cover: pl.coverArt, subtitle: 'Playlist'),
                        ),
                        child: SongDropTarget(
                          onDrop: (songs) => dropOnPlaylist(context, ref, pl.id, pl.name, songs),
                          child: item(
                            SideItem(pl.name, Icons.queue_music_rounded, '/playlist/${pl.id}'),
                            leading: Cover(pl.coverArt, size: 22, radius: 5, icon: Icons.queue_music_rounded),
                          ),
                        ),
                      ),
                  ],
                  _ => const <Widget>[],
                },
                header('Browse'),
                for (final i in sideLibrary) item(i),
              ],
            ),
          ),
        ),
        // a line between the scrolling list and what stays at the bottom; the same right inset as the rows
        // above (they leave a lane for the scrollbar)
        const Divider(height: 9, indent: 16, endIndent: 26),
        if (online.isNotEmpty)
          Padding(padding: const EdgeInsets.fromLTRB(8, 0, 18, 4), child: _DeviceHint(online.first)),
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: item(const SideItem('Settings', Icons.settings_rounded, '/settings')),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// "Pixel 10a is playing …": a nudge to take it over or control it.
class _DeviceHint extends StatelessWidget {
  const _DeviceHint(this.d);
  final RemoteDevice d;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final s = d.state;
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppLook.of(context).r(10)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showDevicesSheet(context),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Icon(deviceIcon(d.kind), size: 18, color: s.playing ? cs.primary : cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.playing && s.hasSong ? '${d.name}: ${s.title}' : '${d.name} is open',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LyricsPanel extends ConsumerWidget {
  const _LyricsPanel({required this.onClose});
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(currentSongProvider);
    return Scaffold(
      // the same small header as Now playing and the queue
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Hide the lyrics',
          icon: const Icon(Icons.keyboard_double_arrow_right_rounded, size: 20),
          onPressed: onClose,
        ),
        centerTitle: true,
        toolbarHeight: 60,
        titleTextStyle: Theme.of(context).textTheme.titleSmall,
        title: const Text('Lyrics'),
        actions: const [SizedBox(width: 48)],
      ),
      body: song == null
          ? const Center(child: Text('Nothing playing'))
          : LyricsView(key: ValueKey('lyrics-${song.id}'), song: song),
    );
  }
}

/// Along the bottom: what's playing, the controls and the seek bar, and volume / queue / lyrics / devices.
class PlayerBar extends ConsumerWidget {
  const PlayerBar({super.key, required this.panel, required this.onPanel});
  final SidePanel panel;
  final void Function(SidePanel) onPanel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(mediaItemProvider).value;
    final song = ref.watch(currentSongProvider);
    final st = ref.watch(playbackStateProvider).value;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    if (item == null) return const SizedBox.shrink();
    final playing = st?.playing ?? false;
    final loading =
        st?.processingState == AudioProcessingState.loading || st?.processingState == AudioProcessingState.buffering;
    final shuffle = audioHandler.shuffleKind;
    final repeat = st?.repeatMode ?? AudioServiceRepeatMode.none;
    Color on(bool v) => v ? cs.primary : cs.onSurfaceVariant;
    final skip = skipShownFor(ref.watch(settingsProvider), item.id);
    return SizedBox(
      height: 84,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Row(
          children: [
            // what's playing
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Tappable(
                      onTap: () => context.push('/player'),
                      child: HeroMode(enabled: !MediaQuery.disableAnimationsOf(context), child: Hero(
                        tag: 'cover',
                        child: Cover(
                          song?.coverArt ?? '',
                          size: 56,
                          radius: 8,
                          icon: Icons.music_note_outlined,
                          artist: song?.artist ?? '',
                          album: song?.album ?? '',
                        ),
                      )),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Link(
                          text: item.title,
                          style: t.titleSmall,
                          onTap: song == null || song.albumId.isEmpty
                              ? null
                              : () => context.push('/album/${song.albumId}'),
                        ),
                        _Link(
                          text: item.artist ?? '',
                          style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          onTap: song == null || song.artistId.isEmpty
                              ? null
                              : () => context.push('/artist/${song.artistId}'),
                        ),
                      ],
                    ),
                  ),
                  if (song != null && !isPodcastId(song.id))
                    IconButton(
                      tooltip: 'Like (Ctrl+L)',
                      icon: Icon(
                        ref.hearted(song) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: ref.hearted(song) ? cs.primary : cs.onSurfaceVariant,
                        size: 20,
                      ),
                      onPressed: () => toggleStarSong(context, ref, song),
                    ),
                ],
              ),
            ),
            // controls and seek bar
            Expanded(
              flex: 4,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Shuffle (Ctrl+S)',
                        icon: Icon(
                          shuffle == ShuffleKind.smart ? Icons.auto_awesome_rounded : Icons.shuffle_rounded,
                          size: 20,
                          color: on(shuffle != ShuffleKind.off),
                        ),
                        onPressed: () => audioHandler.setShuffleKind(switch (shuffle) {
                          ShuffleKind.off => ShuffleKind.on,
                          ShuffleKind.on => ShuffleKind.smart,
                          ShuffleKind.smart => ShuffleKind.off,
                        }),
                      ),
                      IconButton(
                        tooltip: 'Previous (Ctrl+←)',
                        icon: const Icon(Icons.skip_previous_rounded),
                        onPressed: audioHandler.skipToPrevious,
                      ),
                      if (skip) const SkipButton(key: ValueKey('bar-skip-back'), forward: false, size: 22, shortcut: 'Shift+←'),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            shape: const CircleBorder(),
                            padding: EdgeInsets.zero,
                            backgroundColor: cs.onSurface,
                            foregroundColor: cs.surface,
                          ),
                          onPressed: playing ? audioHandler.pause : audioHandler.play,
                          child: loading
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: cs.surface),
                                )
                              : Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 26),
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (skip) const SkipButton(key: ValueKey('bar-skip-forward'), forward: true, size: 22, shortcut: 'Shift+→'),
                      IconButton(
                        tooltip: 'Next (Ctrl+→)',
                        icon: const Icon(Icons.skip_next_rounded),
                        onPressed: audioHandler.skipToNext,
                      ),
                      IconButton(
                        tooltip: 'Repeat (Ctrl+R)',
                        icon: Icon(
                          repeat == AudioServiceRepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                          size: 20,
                          color: on(repeat != AudioServiceRepeatMode.none),
                        ),
                        onPressed: () => audioHandler.setRepeatMode(switch (repeat) {
                          AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
                          AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
                          _ => AudioServiceRepeatMode.none,
                        }),
                      ),
                    ],
                  ),
                  const _BarSeek(),
                ],
              ),
            ),
            // volume and panels
            Expanded(
              flex: 3,
              child: Align(
                alignment: Alignment.centerRight,
                child: IconButtonTheme(
                  // compact buttons, so they all fit beside the volume
                  data: IconButtonThemeData(style: IconButton.styleFrom(visualDensity: VisualDensity.compact)),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: 'Now playing (Ctrl+Shift+N)',
                          icon: Icon(Icons.view_sidebar_outlined, size: 20, color: on(panel == SidePanel.nowPlaying)),
                          onPressed: () => onPanel(SidePanel.nowPlaying),
                        ),
                        IconButton(
                          tooltip: 'Lyrics (Ctrl+Shift+L)',
                          icon: Icon(Icons.lyrics_outlined, size: 20, color: on(panel == SidePanel.lyrics)),
                          onPressed: () => onPanel(SidePanel.lyrics),
                        ),
                        IconButton(
                          tooltip: 'Queue (Ctrl+Shift+Q)',
                          icon: Icon(Icons.queue_music_rounded, size: 20, color: on(panel == SidePanel.queue)),
                          onPressed: () => onPanel(SidePanel.queue),
                        ),
                        // the private session's badge (tap: end it)
                        if (privateSessionOn(ref.watch(privateSessionProvider), DateTime.now()))
                          IconButton(
                            tooltip: 'Private session: plays aren\'t counted or shared. Click to end it',
                            icon: Icon(Icons.lock_rounded, size: 20, color: cs.primary),
                            onPressed: () => ref.read(privateSessionProvider.notifier).set(false),
                          ),
                        ValueListenableBuilder<CastInfo?>(
                          valueListenable: castInfo,
                          builder: (ctx, info, _) => IconButton(
                            tooltip: info == null ? 'Your devices (Ctrl+D)' : 'Playing on ${info.name}',
                            icon: Icon(
                              info == null ? Icons.devices_rounded : Icons.cast_connected_rounded,
                              size: 20,
                              color: on(info != null),
                            ),
                            onPressed: () => showDevicesSheet(ctx),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Sound',
                          icon: Icon(Icons.tune_rounded, size: 20, color: cs.onSurfaceVariant),
                          onPressed: () => showSoundPanel(context, ref),
                        ),
                        const _Volume(),
                        IconButton(
                          tooltip: 'Full-screen player (Ctrl+P)',
                          icon: Icon(Icons.open_in_full_rounded, size: 18, color: cs.onSurfaceVariant),
                          onPressed: () => context.push('/player'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The player bar's song and artist: links like every other name (see NameLink).
class _Link extends StatelessWidget {
  const _Link({required this.text, this.style, this.onTap});
  final String text;
  final TextStyle? style;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => NameLink(text, onTap: onTap, style: style);
}

class _BarSeek extends ConsumerStatefulWidget {
  const _BarSeek();
  @override
  ConsumerState<_BarSeek> createState() => _BarSeekState();
}

class _BarSeekState extends ConsumerState<_BarSeek> {
  double? _drag;
  @override
  Widget build(BuildContext context) {
    var p = ref.watch(positionProvider).value ?? const PositionData(Duration.zero, Duration.zero, Duration.zero);
    final song = ref.watch(currentSongProvider);
    if (p.duration == Duration.zero && (song?.duration ?? 0) > 0) {
      // not loaded yet (paused since the app started): the song's own length
      p = PositionData(p.position, p.buffered, Duration(seconds: song!.duration!));
    }
    final max = p.duration.inMilliseconds.toDouble();
    final v = (_drag ?? p.position.inMilliseconds.toDouble()).clamp(0.0, max > 0 ? max : 1.0);
    final t = Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(formatDuration(v ~/ 1000), style: t, textAlign: TextAlign.right),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: SizedBox(
              height: 20,
              child: Semantics(label: 'Position', child: Slider(
                value: v,
                max: max > 0 ? max : 1,
                secondaryTrackValue: p.buffered.inMilliseconds.toDouble().clamp(0.0, max > 0 ? max : 1.0),
                onChanged: max > 0 ? (x) => setState(() => _drag = x) : null,
                onChangeEnd: (x) {
                  audioHandler.seek(Duration(milliseconds: x.round()));
                  setState(() => _drag = null);
                },
              )),
            ),
          ),
        ),
        SizedBox(width: 44, child: Text(formatDuration(p.duration.inSeconds), style: t)),
      ],
    );
  }
}

/// Encore's own volume (the "Encore" stream in KDE's volume applet); scroll on it to change it.
class _Volume extends StatefulWidget {
  const _Volume();
  @override
  State<_Volume> createState() => _VolumeState();
}

class _VolumeState extends State<_Volume> {
  double _v = desktopVolume, _before = 1;
  StreamSubscription<double>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = desktopVolumeChanges.listen((v) {
      if (mounted) setState(() => _v = v);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _set(double v) {
    setState(() => _v = v.clamp(0, 1));
    setDesktopVolume(_v);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Listener(
      onPointerSignal: (e) {
        if (e is PointerScrollEvent) _set(_v - e.scrollDelta.dy.sign * 0.05);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: _v == 0 ? 'Unmute' : 'Mute',
            icon: Icon(
              _v == 0 ? Icons.volume_off_rounded : (_v < 0.5 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
              size: 20,
              color: cs.onSurfaceVariant,
            ),
            onPressed: () {
              if (_v > 0) {
                _before = _v;
                _set(0);
              } else {
                _set(_before > 0 ? _before : 0.5);
              }
            },
          ),
          SizedBox(
            width: 110,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Semantics(label: 'Volume', child: Slider(value: _v, onChanged: _set)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Above the page: back and forward, and a search box (Enter searches; Ctrl+F jumps here).
class _TopBar extends StatefulWidget {
  const _TopBar({
    required this.canBack,
    required this.canForward,
    required this.onBack,
    required this.onForward,
    required this.query,
    this.onSearchPage = false,
    this.offline = false,
  });
  final bool canBack, canForward, onSearchPage, offline;
  final VoidCallback onBack, onForward;
  final String query;

  @override
  State<_TopBar> createState() => _TopBarState();
}

/// So Ctrl+F can put the cursor in the search box.
final desktopSearchFocus = FocusNode(debugLabel: 'desktop search');

class _TopBarState extends State<_TopBar> {
  late final _ctl = TextEditingController(text: widget.query);

  @override
  void initState() {
    super.initState();
    searchBoxText ??= ValueNotifier(''); // the Search page shows no box of its own (search.dart)
  }

  @override
  void didUpdateWidget(_TopBar old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query && !desktopSearchFocus.hasFocus) _ctl.text = widget.query;
    // what the Search page follows: this box's text while it's open, nothing once it's left
    if (old.onSearchPage != widget.onSearchPage || old.query != widget.query) {
      searchBoxText?.value = widget.onSearchPage ? _ctl.text : '';
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back (Alt+←)',
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            onPressed: widget.canBack ? widget.onBack : null,
          ),
          IconButton(
            tooltip: 'Forward (Alt+→)',
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
            onPressed: widget.canForward ? widget.onForward : null,
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SizedBox(
              height: 40,
              child: ListenableBuilder(
                listenable: _ctl,
                builder: (context, _) => TextField(
                  controller: _ctl,
                  focusNode: desktopSearchFocus,
                  textInputAction: TextInputAction.search,
                  // on the Search page: results as you type (the page follows this box)
                  onChanged: (q) {
                    if (widget.onSearchPage) searchBoxText?.value = q;
                  },
                  onSubmitted: (q) =>
                      context.go(q.trim().isEmpty ? '/search' : '/search?q=${Uri.encodeQueryComponent(q.trim())}'),
                  decoration: InputDecoration(
                    hintText: widget.offline ? 'Search downloaded music' : 'What do you want to play?',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _ctl.text.isNotEmpty
                        ? IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _ctl.clear();
                              if (widget.onSearchPage) searchBoxText?.value = '';
                            },
                          )
                        // the Search page's "What's playing?" (it has no box of its own on the desktop)
                        : widget.onSearchPage && !widget.offline && canIdentify
                        ? IconButton(
                            tooltip: 'Pitch · What\'s playing?',
                            icon: const Icon(Icons.hearing_rounded, size: 18),
                            onPressed: () => showWhatsPlaying(context),
                          )
                        : null,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppLook.of(context).r(12)),
                      borderSide: BorderSide.none,
                    ),
                    fillColor: cs.surfaceContainerHigh,
                    filled: true,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A list with a thin scrollbar in its own lane at the right (the default one is drawn over the rows): the
/// list gives its rows right padding so a highlighted row never runs under the bar.
class _GutterScroll extends StatefulWidget {
  const _GutterScroll({required this.builder});
  final Widget Function(ScrollController controller) builder;
  @override
  State<_GutterScroll> createState() => _GutterScrollState();
}

class _GutterScrollState extends State<_GutterScroll> {
  final _ctl = ScrollController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
    child: RawScrollbar(
      controller: _ctl,
      thickness: 6,
      radius: const Radius.circular(3),
      crossAxisMargin: 2,
      mainAxisMargin: 4,
      thumbColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.28),
      child: widget.builder(_ctl),
    ),
  );
}
