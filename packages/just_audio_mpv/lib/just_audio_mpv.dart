/// just_audio on Linux (and Windows) through libmpv, via package:media_kit.
///
/// Based on just_audio_media_kit 2.1.0 by Pato05 (public domain, see LICENSE). Encore's changes: songs
/// inserted in the middle of the queue land where they were asked to go; sound filters (equalizer, pitch,
/// skip silence, extra gain), a volume for the whole app, and the output device list, which just_audio
/// itself has no way to reach.
library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter/services.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:media_kit/media_kit.dart';

import 'mediakit_player.dart';

export 'mediakit_player.dart' show MediaKitPlayer;
export 'package:media_kit/media_kit.dart' show AudioDevice;

class JustAudioMpv extends JustAudioPlatform {
  JustAudioMpv._();

  /// The name the sound server shows for Encore (KDE's volume applet, pavucontrol).
  static String title = 'Encore';

  /// Network protocols mpv may open.
  static List<String> protocolWhitelist = const ['udp', 'rtp', 'tcp', 'tls', 'data', 'file', 'http', 'https', 'crypto'];

  /// mpv's read-ahead buffer.
  static int bufferSize = 32 * 1024 * 1024;

  static final _players = HashMap<String, MediaKitPlayer>();
  static final _disposing = HashMap<String, Future<void>>();

  /// Use mpv for just_audio.
  static void ensureInitialized({String? libmpv}) {
    JustAudioPlatform.instance = JustAudioMpv._();
    MediaKit.ensureInitialized(libmpv: libmpv);
  }

  // ── Things shared by every player ──

  static String _filters = '';
  static double _master = 1;
  static String? _device;

  /// libavfilter filters every player runs its sound through (comma-separated, e.g.
  /// `equalizer=f=60:t=o:w=2:g=3,silenceremove=...`), or '' for none.
  static String get filters => _filters;
  static Future<void> setFilters(String f) async {
    if (f == _filters) return;
    _filters = f;
    await Future.wait(_players.values.map((p) => p.applyFilters()));
  }

  static double _boost = 0;

  /// Extra loudness in dB (ReplayGain above the reference level; mpv's volume can't go past 100 %).
  static double get boostDb => _boost;
  static Future<void> setBoost(double db) async {
    if ((db - _boost).abs() < 0.01) return;
    _boost = db;
    await Future.wait(_players.values.map((p) => p.applyFilters()));
  }

  /// The app's own volume (0..1), on top of each player's volume.
  static double get masterVolume => _master;
  static Future<void> setMasterVolume(double v) async {
    _master = v.clamp(0.0, 1.0);
    await Future.wait(_players.values.map((p) => p.applyVolume()));
  }

  /// Where the sound goes ('auto' is the sound server's default), as mpv names them.
  static String? get device => _device;
  static Future<void> setDevice(String name) async {
    _device = name;
    await Future.wait(_players.values.map((p) => p.applyDevice()));
  }

  /// The output devices mpv can play to, from any open player (empty before the first one starts).
  static List<AudioDevice> get devices => _players.values.firstOrNull?.devices ?? const [];
  static Stream<List<AudioDevice>> get devicesStream =>
      _players.values.firstOrNull?.devicesStream ?? const Stream.empty();

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    if (_players.containsKey(request.id)) {
      throw PlatformException(code: 'error', message: 'Player ${request.id} already exists!');
    }
    final player = MediaKitPlayer(request.id);
    _players[request.id] = player;
    await player.ready();
    await player.applyFilters();
    if (_device != null) await player.applyDevice();
    return player;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(DisposePlayerRequest request) async {
    if (_disposing.containsKey(request.id)) {
      await _disposing[request.id]!; // just_audio can ask twice
      return DisposePlayerResponse();
    }
    final player = _players.remove(request.id);
    if (player == null) return DisposePlayerResponse();
    final future = player.release();
    _disposing[request.id] = future;
    await future;
    _disposing.remove(request.id);
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(DisposeAllPlayersRequest request) async {
    await Future.wait(_players.values.map((e) => e.release()));
    _players.clear();
    return DisposeAllPlayersResponse();
  }
}
