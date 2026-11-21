import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:just_audio_mpv/just_audio_mpv.dart' as mpv;

import '../core/platform.dart';
import '../core/settings.dart';

/// Sound on the desktop. mpv plays the music, so the equalizer, skip silence and extra loudness are mpv
/// filters instead of Android's audio effects, and the output device and volume are Encore's own.

/// The equalizer's bands (the same five centres Android's equalizer uses, so saved gains mean the same).
const eqCentres = [60.0, 230.0, 910.0, 3600.0, 14000.0];
const eqMinDb = -15.0, eqMaxDb = 15.0;

/// The libavfilter chain for these settings ('' when nothing is switched on).
String desktopFilters({required bool eq, required List<double> gains, required bool skipSilence}) {
  final parts = <String>[];
  if (eq) {
    for (var i = 0; i < eqCentres.length && i < gains.length; i++) {
      final g = gains[i].clamp(eqMinDb, eqMaxDb);
      if (g.abs() < 0.05) continue; // a flat band does nothing
      // each band about two octaves wide, like a 5-band graphic equalizer
      parts.add('equalizer=f=${eqCentres[i].round()}:t=o:w=2:g=${g.toStringAsFixed(1)}');
    }
  }
  if (skipSilence) {
    // quiet stretches longer than a second, anywhere in the song (not the music's quiet parts: -50 dB)
    parts.add('silenceremove=start_periods=1:start_threshold=-50dB:stop_periods=-1:stop_duration=1:stop_threshold=-50dB');
  }
  return parts.join(',');
}

/// Applies the sound settings to every mpv player.
Future<void> applyDesktopSound(Settings s) =>
    mpv.JustAudioMpv.setFilters(desktopFilters(eq: s.eqEnabled, gains: s.eqGains, skipSilence: s.skipSilence));

/// Extra loudness (ReplayGain above the reference level), 0 for none.
Future<void> setDesktopBoost(double db) => mpv.JustAudioMpv.setBoost(db);

// ── Volume and output device ──

/// Encore's own volume (0..1), remembered between runs. KDE's volume applet shows it as the "Encore" stream.
double get desktopVolume => prefs.getDouble('desktopVolume') ?? 1.0;
Future<void> setDesktopVolume(double v) async {
  await mpv.JustAudioMpv.setMasterVolume(v);
  await prefs.setDouble('desktopVolume', v.clamp(0.0, 1.0));
  _volumeChanges.add(v.clamp(0.0, 1.0));
}

final _volumeChanges = StreamController<double>.broadcast();
Stream<double> get desktopVolumeChanges => _volumeChanges.stream;

/// An output device: mpv's name for it, what to call it, and speaker / bluetooth / headphones / tv / other.
class OutputDevice {
  const OutputDevice(this.id, this.name, this.kind);
  final String id, name, kind;
}

/// What a sound-server device is, from its name (PipeWire names say how it's connected).
String deviceKindOf(String id, String description) {
  final s = '$id $description'.toLowerCase();
  if (s.contains('bluez') || s.contains('bluetooth')) return 'bluetooth';
  if (s.contains('hdmi') || s.contains('displayport')) return 'tv';
  if (s.contains('headphone') || s.contains('headset') || s.contains('usb')) return 'headphones';
  return 'speaker';
}

/// The devices to offer: the sound server's default first ("This computer"), then each real device once
/// (mpv lists the same device under PipeWire and PulseAudio; the PipeWire one is kept).
List<OutputDevice> outputDevices(List<mpv.AudioDevice> raw) {
  final out = <OutputDevice>[const OutputDevice('auto', 'This computer (system default)', 'speaker')];
  final seen = <String>{};
  final pipewire = raw.any((d) => d.name.startsWith('pipewire/'));
  for (final d in raw) {
    if (d.name == 'auto' || !d.name.contains('/')) continue;
    if (pipewire && !d.name.startsWith('pipewire/')) continue;
    final key = d.description.trim().isEmpty ? d.name : d.description.trim();
    if (!seen.add(key)) continue;
    out.add(OutputDevice(d.name, key, deviceKindOf(d.name, d.description)));
  }
  return out;
}

List<OutputDevice> currentOutputDevices() => outputDevices(mpv.JustAudioMpv.devices);

/// The chosen device (remembered), or the system default.
String get desktopDevice => prefs.getString('desktopDevice') ?? 'auto';
Future<void> setDesktopDevice(String id) async {
  await prefs.setString('desktopDevice', id);
  await mpv.JustAudioMpv.setDevice(id);
}

/// (name, kind) of where the sound plays now.
(String, String) desktopOutput() {
  final id = desktopDevice;
  final d = currentOutputDevices().where((d) => d.id == id).firstOrNull;
  if (d == null || id == 'auto') return ('This computer', 'speaker');
  return (d.name, d.kind);
}

/// Opens the system's sound or Bluetooth settings ('sound' or 'bluetooth'): KDE's System Settings, or the
/// Settings app on Windows.
Future<void> openKdeSettings(String which) async {
  if (Platform.isWindows) {
    try {
      await Process.start('explorer.exe', [which == 'bluetooth' ? 'ms-settings:bluetooth' : 'ms-settings:sound']);
    } catch (_) {}
    return;
  }
  final page = which == 'bluetooth' ? 'kcm_bluetooth' : 'kcm_pulseaudio';
  try {
    await Process.start('systemsettings', [page], mode: ProcessStartMode.detached);
  } catch (_) {
    try {
      await Process.start('kcmshell6', [page], mode: ProcessStartMode.detached);
    } catch (_) {}
  }
}

/// Puts the remembered volume and device back when the app starts.
Future<void> restoreDesktopSound() async {
  if (!isDesktop) return;
  await mpv.JustAudioMpv.setMasterVolume(desktopVolume);
  if (desktopDevice != 'auto') await mpv.JustAudioMpv.setDevice(desktopDevice);
}

// ── The equalizer screen's view of the bands (Android's equalizer, or the desktop's mpv filter) ──

class EqBand {
  EqBand(this.centerFrequency, double gain, this._apply) : _gain = StreamController<double>.broadcast() {
    _now = gain;
  }
  final double centerFrequency;
  final Future<void> Function(double) _apply;
  final StreamController<double> _gain;
  late double _now;

  double get gain => _now;
  Stream<double> get gainStream => _gain.stream;
  Future<void> setGain(double g) async {
    _now = g;
    _gain.add(g);
    await _apply(g);
  }
}

class EqParams {
  EqParams(this.minDecibels, this.maxDecibels, this.bands);
  final double minDecibels, maxDecibels;
  final List<EqBand> bands;

  factory EqParams.android(AndroidEqualizerParameters p) => EqParams(p.minDecibels, p.maxDecibels, [
        for (final b in p.bands) EqBand(b.centerFrequency, b.gain, b.setGain),
      ]);

  /// The desktop's bands hold the gains; the screen saves them to Settings, which re-applies the filter.
  factory EqParams.desktop(List<double> gains) => EqParams(eqMinDb, eqMaxDb, [
        for (var i = 0; i < eqCentres.length; i++)
          EqBand(eqCentres[i], i < gains.length ? gains[i] : 0.0, (_) async {}),
      ]);
}
