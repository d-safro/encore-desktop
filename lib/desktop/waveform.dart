import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/account.dart';
import '../data/library.dart';
import '../data/models.dart';
import '../playback/handler.dart';
import '../ui/state.dart';

/// The shape of the playing song (a waveform) as a seek bar, on the desktop.
///
/// Where the shape comes from: the computer's own ffmpeg decodes the song (the downloaded file, else a
/// small MP3 copy from the server, fed through a pipe so the login never shows on a command line) into a
/// few seconds' worth of low-rate sound, which becomes [waveBars] heights. They're kept in
/// ~/.cache/dev.safro.encore/waveforms, a couple of KB a song, so each song is worked out once. Without
/// ffmpeg the bar is plain.

const waveBars = 200;

/// The bars' heights (0..1) from 16-bit mono samples: the average loudness of each slice, the loudest at
/// 1, gently lifted so quiet parts still show.
List<double> peaksFromPcm(Int16List samples, [int bars = waveBars]) {
  if (samples.isEmpty) return const [];
  final out = List<double>.filled(bars, 0);
  final per = samples.length / bars;
  for (var b = 0; b < bars; b++) {
    final from = (b * per).floor(), to = min(samples.length, ((b + 1) * per).ceil());
    if (to <= from) continue;
    var sum = 0;
    for (var i = from; i < to; i++) {
      sum += samples[i].abs();
    }
    out[b] = sum / (to - from);
  }
  final top = out.reduce(max);
  if (top <= 0) return List.filled(bars, 0.05);
  return [for (final v in out) max(0.05, sqrt(v / top))];
}

Future<Directory> _cacheDir() async {
  final d = Directory(p.join((await getApplicationCacheDirectory()).path, 'waveforms'));
  await d.create(recursive: true);
  return d;
}

/// One song at a time: ffmpeg is quick, but a run of skips shouldn't start a crowd of them.
Future<void> _queue = Future.value();

Future<List<double>?> _compute(Ref ref, Song s) async {
  final local = ref.read(downloadsProvider).files[s.id];
  final client = ref.read(clientProvider);
  // a downloaded file is read straight from disk (some formats need to be read out of order); a stream
  // goes through a pipe
  final fromFile = local != null && File(local).existsSync();
  Process proc;
  try {
    proc = await Process.start('ffmpeg', [
      '-v',
      'error',
      '-i',
      fromFile ? local : 'pipe:0',
      '-ac',
      '1',
      '-ar',
      '2000',
      '-f',
      's16le',
      'pipe:1',
    ]);
  } on ProcessException {
    return null; // no ffmpeg: a plain bar
  }
  final pcm = BytesBuilder(copy: false);
  final done = proc.stdout.forEach(pcm.add);
  unawaited(proc.stderr.drain<void>());
  try {
    if (fromFile) {
      // nothing to send
    } else if (client != null) {
      final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      try {
        final req = await http.getUrl(client.streamUrl(s.id, format: 'mp3', maxBitRate: 96));
        final res = await req.close();
        if (res.statusCode != 200) throw HttpException('server answered ${res.statusCode}');
        await proc.stdin.addStream(res);
      } finally {
        http.close();
      }
    }
    await proc.stdin.close();
  } catch (_) {
    proc.kill();
    return null;
  }
  await done;
  if (await proc.exitCode != 0) return null;
  final bytes = pcm.takeBytes();
  if (bytes.length < 4) return null;
  return peaksFromPcm(bytes.buffer.asInt16List(bytes.offsetInBytes, bytes.length ~/ 2));
}

/// The waveform of a song, null while it's worked out (or when it can't be).
final waveformProvider = FutureProvider.autoDispose.family<List<double>?, String>((ref, id) async {
  final s = audioHandler.songs.where((x) => x.id == id).firstOrNull;
  if (s == null || s.isLookup || isPodcastId(s.id)) return null; // episodes are long; ⬇ songs aren't yours yet
  final file = File(p.join((await _cacheDir()).path, '$id.json'));
  if (await file.exists()) {
    try {
      return [for (final v in jsonDecode(await file.readAsString()) as List) (v as num).toDouble()];
    } catch (_) {}
  }
  final result = Completer<List<double>?>();
  _queue = _queue.then((_) async {
    try {
      result.complete(await _compute(ref, s));
    } catch (_) {
      result.complete(null);
    }
  });
  final peaks = await result.future;
  if (peaks != null && peaks.isNotEmpty) {
    await file.writeAsString(jsonEncode([for (final v in peaks) double.parse(v.toStringAsFixed(3))]));
  }
  return peaks;
});

/// A seek bar drawn as the song's waveform: the part played in the app's colour, the rest gray. Click or
/// drag to move. A thin plain bar while the shape is worked out.
class WaveformSeekBar extends ConsumerStatefulWidget {
  const WaveformSeekBar({super.key, this.height = 44});
  final double height;
  @override
  ConsumerState<WaveformSeekBar> createState() => _WaveformSeekBarState();
}

class _WaveformSeekBarState extends ConsumerState<WaveformSeekBar> {
  double? _drag; // 0..1 while dragging

  @override
  Widget build(BuildContext context) {
    final item = ref.watch(mediaItemProvider).value;
    final song = ref.watch(currentSongProvider);
    final pos = ref.watch(positionProvider).value;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final peaks = item == null ? null : ref.watch(waveformProvider(item.id)).value;
    final dur = (pos?.duration ?? Duration.zero) > Duration.zero
        ? pos!.duration
        : Duration(seconds: song?.duration ?? 0);
    final played = dur.inMilliseconds == 0
        ? 0.0
        : ((pos?.position ?? Duration.zero).inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
    final shown = _drag ?? played;
    void seekTo(double f) => audioHandler.seek(Duration(milliseconds: (dur.inMilliseconds * f).round()));
    String fmt(Duration d) => formatDuration(d.inSeconds);
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, box) {
            double frac(double x) => (x / box.maxWidth).clamp(0.0, 1.0);
            return MouseRegion(
              cursor: dur > Duration.zero ? SystemMouseCursors.click : MouseCursor.defer,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: dur > Duration.zero ? (d) => seekTo(frac(d.localPosition.dx)) : null,
                onHorizontalDragUpdate: dur > Duration.zero
                    ? (d) => setState(() => _drag = frac(d.localPosition.dx))
                    : null,
                onHorizontalDragEnd: dur > Duration.zero
                    ? (_) {
                        if (_drag != null) seekTo(_drag!);
                        setState(() => _drag = null);
                      }
                    : null,
                child: SizedBox(
                  height: widget.height,
                  width: double.infinity,
                  // its own layer: the position moving repaints only these bars
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _WavePainter(
                        peaks: peaks,
                        played: shown,
                        on: cs.primary,
                        off: cs.onSurface.withValues(alpha: 0.22),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(fmt(Duration(milliseconds: (dur.inMilliseconds * shown).round())), style: t.labelSmall),
            const Spacer(),
            Text(fmt(dur), style: t.labelSmall),
          ],
        ),
      ],
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.peaks, required this.played, required this.on, required this.off});
  final List<double>? peaks;
  final double played;
  final Color on, off;

  @override
  void paint(Canvas canvas, Size size) {
    final ps = peaks;
    final mid = size.height / 2;
    final paintOn = Paint()..color = on;
    final paintOff = Paint()..color = off;
    if (ps == null || ps.isEmpty) {
      // not worked out yet: a plain bar
      final r = RRect.fromLTRBR(0, mid - 2, size.width, mid + 2, const Radius.circular(2));
      canvas.drawRRect(r, paintOff);
      canvas.drawRRect(RRect.fromLTRBR(0, mid - 2, size.width * played, mid + 2, const Radius.circular(2)), paintOn);
      return;
    }
    final step = size.width / ps.length;
    final w = max(1.0, step * 0.62);
    for (var i = 0; i < ps.length; i++) {
      final x = i * step + (step - w) / 2;
      final h = max(2.0, ps[i] * size.height);
      final r = RRect.fromLTRBR(x, mid - h / 2, x + w, mid + h / 2, Radius.circular(w / 2));
      canvas.drawRRect(r, (i + 0.5) / ps.length <= played ? paintOn : paintOff);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.played != played || !identical(old.peaks, peaks) || old.on != on || old.off != off;
}
