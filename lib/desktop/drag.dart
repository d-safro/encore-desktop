import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/account.dart';
import '../data/library.dart';
import '../data/models.dart';
import '../playback/handler.dart';
import '../ui/actions.dart';
import '../ui/state.dart';
import '../ui/widgets.dart' show nSongs;

/// Desktop drag and drop: drag songs from any list onto the queue panel, Liked songs, or a playlist in the
/// sidebar.

/// What is being dragged.
class SongDrag {
  const SongDrag(this.songs);
  final List<Song> songs;
  String get label => songs.length == 1 ? songs.first.title : nSongs(songs.length);
}

/// Makes [child] draggable as [songs] (a small label follows the mouse).
Widget songDragSource({required List<Song> songs, required Widget child}) => Draggable<SongDrag>(
  data: SongDrag(songs),
  dragAnchorStrategy: pointerDragAnchorStrategy,
  feedback: _DragLabel(SongDrag(songs)),
  child: child,
);

class _DragLabel extends StatelessWidget {
  const _DragLabel(this.drag);
  final SongDrag drag;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Transform.translate(
      offset: const Offset(12, 8),
      child: Material(
        color: cs.primaryContainer,
        elevation: 6,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.music_note_rounded, size: 16, color: cs.onPrimaryContainer),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  drag.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A place songs can be dropped: [child] is outlined while songs hover over it.
class SongDropTarget extends StatelessWidget {
  const SongDropTarget({super.key, required this.onDrop, required this.child, this.radius = 10});
  final Future<void> Function(List<Song> songs) onDrop;
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) => DragTarget<SongDrag>(
    onAcceptWithDetails: (d) => onDrop(d.data.songs),
    builder: (ctx, candidates, _) {
      if (candidates.isEmpty) return child;
      final cs = Theme.of(ctx).colorScheme;
      return DecoratedBox(
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.12),
          border: Border.all(color: cs.primary, width: 2),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: child,
      );
    },
  );
}

/// Dropped on a playlist: add the songs to it on the server.
Future<void> dropOnPlaylist(BuildContext context, WidgetRef ref, String id, String name, List<Song> songs) async {
  final c = ref.read(clientProvider);
  final mine = songs.where((s) => !s.isLookup).toList();
  if (c == null || mine.isEmpty) return;
  try {
    await c.updatePlaylist(id, add: [for (final s in mine) s.id]);
    ref.invalidate(playlistProvider(id));
    ref.invalidate(playlistsProvider);
    if (context.mounted) toast(context, 'Added ${SongDrag(mine).label} to $name');
  } catch (e) {
    if (context.mounted) toast(context, "Couldn't add: $e");
  }
}

/// Dropped on Liked songs: heart the ones that aren't yet.
Future<void> dropOnLiked(BuildContext context, WidgetRef ref, List<Song> songs) async {
  final hearts = ref.read(heartsProvider);
  final todo = songs.where((s) => !s.isLookup && !(hearts[s.id] ?? s.starred)).toList();
  for (final s in todo) {
    if (!context.mounted) return;
    await toggleStarSong(context, ref, s);
  }
  if (context.mounted && todo.isNotEmpty) toast(context, 'Liked ${SongDrag(todo).label}');
}

/// Dropped on the queue: they play after everything else.
Future<void> dropOnQueue(BuildContext context, List<Song> songs) async {
  await audioHandler.addLast(songs.where((s) => !s.isLookup).toList());
  if (context.mounted) toast(context, 'Added ${SongDrag(songs).label} to the queue');
}
