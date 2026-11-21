import 'dart:async';

import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
import 'package:audio_service_platform_interface/no_op_audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:smtc_windows/smtc_windows.dart';

/// audio_service on Windows: what's playing shows in Windows' media flyout (the volume popup, the lock
/// screen, the taskbar's media controls), and the keyboard's media keys and those buttons control Encore.
///
/// Windows calls this the System Media Transport Controls (SMTC). Everything audio_service doesn't need on
/// Windows (Android's notification, browsing) stays a no-op.
class AudioServiceSmtc extends NoOpAudioService {
  /// Called by Flutter when the app starts on Windows (see this package's pubspec).
  static void registerWith() => AudioServicePlatform.instance = AudioServiceSmtc();

  SMTCWindows? _smtc;
  AudioHandlerCallbacks? _handler;
  Future<void>? _starting;
  final _subs = <StreamSubscription>[];

  // What Windows was told last, so the same thing isn't sent again on every position tick
  bool? _playing;
  String? _itemId;
  int _durationMs = 0;
  bool? _shuffle;
  AudioServiceRepeatModeMessage? _repeat;

  /// Starts the Windows side once. If it can't (an old Windows, a missing library), Encore plays on
  /// without media controls.
  Future<void> _start() => _starting ??= () async {
    try {
      await SMTCWindows.initialize();
      final smtc = SMTCWindows(
        config: const SMTCConfig(
          playEnabled: true,
          pauseEnabled: true,
          nextEnabled: true,
          prevEnabled: true,
          stopEnabled: true,
          fastForwardEnabled: false,
          rewindEnabled: false,
        ),
        enabled: false, // hidden until there's something to play
      );
      _subs.add(smtc.buttonPressStream.listen(_pressed));
      _subs.add(smtc.shuffleChangeStream.listen((on) => _handler?.setShuffleMode(SetShuffleModeRequest(
            shuffleMode: on ? AudioServiceShuffleModeMessage.all : AudioServiceShuffleModeMessage.none,
          ))));
      _subs.add(smtc.repeatModeChangeStream.listen((m) => _handler?.setRepeatMode(SetRepeatModeRequest(
            repeatMode: switch (m) {
              RepeatMode.track => AudioServiceRepeatModeMessage.one,
              RepeatMode.list => AudioServiceRepeatModeMessage.all,
              RepeatMode.none => AudioServiceRepeatModeMessage.none,
            },
          ))));
      _smtc = smtc;
    } catch (e) {
      debugPrint('Encore: Windows media controls are not available ($e)');
    }
  }();

  void _pressed(PressedButton b) {
    final h = _handler;
    if (h == null) return;
    switch (b) {
      case PressedButton.play:
        h.play(const PlayRequest());
      case PressedButton.pause:
        h.pause(const PauseRequest());
      case PressedButton.next:
        h.skipToNext(const SkipToNextRequest());
      case PressedButton.previous:
        h.skipToPrevious(const SkipToPreviousRequest());
      case PressedButton.stop:
        h.stop(const StopRequest());
      default:
        break;
    }
  }

  @override
  void setHandlerCallbacks(AudioHandlerCallbacks callbacks) => _handler = callbacks;

  @override
  Future<void> configure(ConfigureRequest request) => _start();

  @override
  Future<void> setState(SetStateRequest request) async {
    await _start();
    final smtc = _smtc;
    if (smtc == null) return;
    final s = request.state;
    try {
      if (s.processingState == AudioProcessingStateMessage.idle) {
        if (_playing != null) await smtc.setPlaybackStatus(PlaybackStatus.stopped);
        _playing = null;
      } else if (s.playing != _playing) {
        _playing = s.playing;
        if (!smtc.enabled) await smtc.enableSmtc();
        await smtc.setPlaybackStatus(s.playing ? PlaybackStatus.playing : PlaybackStatus.paused);
      }
      // where the song is, for the flyout's progress bar (worked out for now, as audio_service does)
      var pos = s.updatePosition;
      if (s.playing) pos += DateTime.now().difference(s.updateTime) * s.speed;
      final ms = _durationMs > 0 ? pos.inMilliseconds.clamp(0, _durationMs) : pos.inMilliseconds;
      await smtc.updateTimeline(PlaybackTimeline(
        startTimeMs: 0,
        endTimeMs: _durationMs,
        positionMs: ms,
        minSeekTimeMs: 0,
        maxSeekTimeMs: _durationMs,
      ));
      final shuffle = s.shuffleMode != AudioServiceShuffleModeMessage.none;
      if (shuffle != _shuffle) {
        _shuffle = shuffle;
        await smtc.setShuffleEnabled(shuffle);
      }
      if (s.repeatMode != _repeat) {
        _repeat = s.repeatMode;
        await smtc.setRepeatMode(switch (s.repeatMode) {
          AudioServiceRepeatModeMessage.one => RepeatMode.track,
          AudioServiceRepeatModeMessage.all || AudioServiceRepeatModeMessage.group => RepeatMode.list,
          AudioServiceRepeatModeMessage.none => RepeatMode.none,
        });
      }
    } catch (e) {
      debugPrint('Encore: Windows media controls: $e');
    }
  }

  @override
  Future<void> setMediaItem(SetMediaItemRequest request) async {
    await _start();
    final smtc = _smtc;
    if (smtc == null) return;
    final m = request.mediaItem;
    _durationMs = m.duration?.inMilliseconds ?? 0;
    // the cover: audio_service's saved copy on disk when it has one, else the address
    final cached = m.extras?['artCacheFile'];
    final art = cached is String && cached.isNotEmpty ? Uri.file(cached).toString() : m.artUri?.toString();
    try {
      if (!smtc.enabled) await smtc.enableSmtc();
      // audio_service sends a song twice: first without its cover, then with it once the cover is saved
      if (m.id == _itemId && cached == null) return;
      _itemId = m.id;
      await smtc.updateMetadata(MusicMetadata(
        title: m.title,
        artist: m.artist,
        album: m.album,
        albumArtist: m.artist,
        thumbnail: art,
      ));
    } catch (e) {
      debugPrint('Encore: Windows media controls: $e');
    }
  }

  @override
  Future<void> stopService(StopServiceRequest request) async {
    try {
      await _smtc?.disableSmtc();
    } catch (_) {}
    _playing = null;
  }
}
