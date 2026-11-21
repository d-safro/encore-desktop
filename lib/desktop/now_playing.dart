import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../data/artist_extra.dart';
import '../data/models.dart';
import '../data/share_links.dart';
import '../playback/handler.dart';
import '../ui/actions.dart';
import '../ui/state.dart';
import '../ui/widgets.dart';

/// The desktop's "Now playing" panel (like Spotify's): where the music comes from, a big cover, the song
/// and artist, about the artist, what's up next, and the song's details. It sits beside the page, in the
/// side panel's place, and scrolls on its own.
class NowPlayingPanel extends ConsumerWidget {
  const NowPlayingPanel({super.key, required this.onClose, required this.onQueue, required this.onLyrics});
  final VoidCallback onClose, onQueue, onLyrics;

  /// The page the queue was started from (a playlist, an album, your liked songs), or null.
  static (String, String)? sourceOf(PlayContext? c) => switch (c?.kind) {
    'playlist' when c!.id.isNotEmpty => (c.name.isEmpty ? 'Playlist' : c.name, '/playlist/${c.id}'),
    'album' when c!.id.isNotEmpty => (c.name.isEmpty ? 'Album' : c.name, '/album/${c.id}'),
    'starred' => ('Liked songs', '/liked'),
    _ => null,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(mediaItemProvider).value;
    final song = ref.watch(currentSongProvider);
    ref.watch(queueProvider);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final source = sourceOf(audioHandler.playContext);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // header: close, where it comes from, menu, full screen
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Hide Now playing',
                icon: const Icon(Icons.keyboard_double_arrow_right_rounded, size: 20),
                onPressed: onClose,
              ),
              Expanded(
                child: Center(
                  child: source == null
                      ? Text('Now playing', style: t.titleSmall)
                      : NameLink(source.$1, to: source.$2, style: t.titleSmall),
                ),
              ),
              IconButton(
                tooltip: 'More',
                icon: const Icon(Icons.more_horiz_rounded),
                onPressed: song == null ? null : () => showSongMenu(context, ref, song),
              ),
              IconButton(
                tooltip: 'Full-screen player',
                icon: const Icon(Icons.open_in_full_rounded, size: 18),
                onPressed: item == null ? null : () => context.push('/player'),
              ),
            ],
          ),
        ),
        Expanded(
          child: item == null
              ? Center(child: Text('Nothing playing', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    // the cover, as wide as the panel
                    AspectRatio(
                      aspectRatio: 1,
                      child: Tappable(
                        onTap: () => context.push('/player'),
                        radius: 12,
                        outset: 0,
                        child: Cover(
                          song?.coverArt ?? '',
                          size: double.infinity,
                          radius: 12,
                          icon: Icons.music_note_outlined,
                          artist: song?.artist ?? item.artist ?? '',
                          album: song?.album ?? '',
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Marquee(
                                child: NameLink(
                                  item.title,
                                  to: song == null ? null : NameLink.albumOf(song),
                                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              const SizedBox(height: 2),
                              NameLink(
                                item.artist ?? '',
                                to: song == null ? null : NameLink.artistOf(song.artistId),
                                style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        if (song != null && !isPodcastId(song.id)) ...[
                          IconButton(
                            tooltip: 'Copy a link to this song',
                            icon: const Icon(Icons.ios_share_rounded, size: 20),
                            onPressed: () => shareLink(context, '${song.title} — ${song.artist}', () => songLink(song)),
                          ),
                          IconButton(
                            tooltip: ref.hearted(song) ? 'Unlike' : 'Like',
                            icon: Icon(
                              ref.hearted(song) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              color: ref.hearted(song) ? cs.primary : null,
                            ),
                            onPressed: () => toggleStarSong(context, ref, song),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.lyrics_outlined, size: 18),
                          label: const Text('Lyrics'),
                          onPressed: onLyrics,
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.queue_music_rounded, size: 18),
                          label: const Text('Queue'),
                          onPressed: onQueue,
                        ),
                      ],
                    ),
                    if (song != null && song.artistId.isNotEmpty && !isPodcastId(song.id)) ...[
                      const SizedBox(height: 18),
                      _AboutArtist(song),
                    ],
                    _UpNext(onQueue: onQueue),
                    if (song != null && !isPodcastId(song.id)) _Details(song),
                  ],
                ),
        ),
      ],
    );
  }
}

/// A card with the artist's picture behind their name, fans and the start of their story; opens their page.
class _AboutArtist extends ConsumerWidget {
  const _AboutArtist(this.song);
  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final info = ref.watch(artistInfoProvider(song.artistId));
    final bio = info.value?.biography ?? '';
    // the server's story first, Wikipedia's when it has none (as on the artist page)
    final (wiki, _) = info.hasValue && bio.isEmpty
        ? ref.watch(artistWikiProvider(song.artist)).value ?? ('', '')
        : ('', '');
    final fans = ref.watch(artistExtraProvider(song.artist)).value?.fans;
    final story = bio.isNotEmpty ? bio : wiki;
    return Tappable(
      onTap: () => context.push('/artist/${song.artistId}'),
      radius: 12,
      outset: 0,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ColoredBox(
          color: cs.surfaceContainerHigh,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 10,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Cover(
                      'ar-${song.artistId}',
                      size: double.infinity,
                      radius: 0,
                      artistImage: true,
                      icon: Icons.person_rounded,
                      artist: song.artist,
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black54, Colors.transparent, Colors.transparent],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 14,
                      top: 12,
                      child: Text(
                        'About the artist',
                        style: t.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(song.artist, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    if (fans != null)
                      Text('${compactCount(fans)} fans', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    if (story.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        story,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 1234567 → 1.2M, 45200 → 45K.
String compactCount(int n) {
  String one(double v) => v >= 100 ? v.round().toString() : v.toStringAsFixed(v >= 10 ? 0 : 1).replaceAll('.0', '');
  if (n >= 1000000) return '${one(n / 1000000)}M';
  if (n >= 1000) return '${one(n / 1000)}K';
  return '$n';
}

/// The next few songs in the queue (a click plays from there), and a way to the whole queue.
class _UpNext extends ConsumerWidget {
  const _UpNext({required this.onQueue});
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(queueProvider);
    final at = ref.watch(playbackStateProvider.select((s) => s.value?.queueIndex)) ?? 0;
    final songs = audioHandler.songs;
    final next = [for (var i = at + 1; i < songs.length && i <= at + 4; i++) i];
    if (next.isEmpty) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 4, 0),
              child: Row(
                children: [
                  Expanded(child: Text('Up next', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                  TextButton(onPressed: onQueue, child: const Text('Open queue')),
                ],
              ),
            ),
            for (final i in next) SongTile(songs[i], queueIndex: i, trailing: const SizedBox(width: 8)),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

/// The song's facts: album, year, genre, file.
class _Details extends StatelessWidget {
  const _Details(this.song);
  final Song song;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final sub = t.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    final file = [
      if (song.suffix.isNotEmpty) song.suffix.toUpperCase(),
      if ((song.bitRate ?? 0) > 0) '${song.bitRate} kbps',
    ].join(' · ');
    Widget row(String label, Widget value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 72, child: Text(label, style: sub)),
          Expanded(child: value),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Material(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Details', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              if (song.album.isNotEmpty) row('Album', NameLink(song.album, to: NameLink.albumOf(song), style: t.bodySmall)),
              row('Artist', NameLink(song.artist, to: NameLink.artistOf(song.artistId), style: t.bodySmall)),
              if (song.year != null) row('Year', Text('${song.year}', style: t.bodySmall)),
              if (song.genre.isNotEmpty) row('Genre', Text(song.genre, style: t.bodySmall)),
              if (file.isNotEmpty) row('File', Text(file, style: t.bodySmall)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A line that's too long for its space slides slowly to its end and back (a song title), else just sits.
class Marquee extends StatefulWidget {
  const Marquee({super.key, required this.child});
  final Widget child;
  @override
  State<Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<Marquee> {
  final _ctl = ScrollController();
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loop());
  }

  @override
  void didUpdateWidget(Marquee old) {
    super.didUpdateWidget(old);
    if (_ctl.hasClients) _ctl.jumpTo(0); // a new song: from the start
    WidgetsBinding.instance.addPostFrameCallback((_) => _loop());
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _loop() async {
    if (_running || MediaQuery.disableAnimationsOf(context)) return; // Reduce animations: it stays put
    _running = true;
    try {
      while (mounted && _ctl.hasClients && _ctl.position.maxScrollExtent > 0) {
        await Future.delayed(const Duration(seconds: 3));
        if (!mounted || !_ctl.hasClients) break;
        final max = _ctl.position.maxScrollExtent;
        await _ctl.animateTo(max, duration: Duration(milliseconds: (max * 30).round()), curve: Curves.linear);
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted || !_ctl.hasClients) break;
        await _ctl.animateTo(0, duration: const Duration(milliseconds: 600), curve: Curves.easeOut);
      }
    } catch (_) {
      // the panel closed mid-slide
    } finally {
      _running = false;
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    controller: _ctl,
    scrollDirection: Axis.horizontal,
    physics: const NeverScrollableScrollPhysics(),
    child: widget.child,
  );
}
