import 'dart:async';
import 'dart:io';

import 'package:just_audio_mpv/just_audio_mpv.dart' as mpv;

import 'package:encore_core/core/platform.dart';
import 'package:encore_core/core/settings.dart';
import 'package:encore_core/playback/sound.dart' show OutputDevice, eqCentres, eqMinDb, eqMaxDb;

/// Sound on the desktop. mpv plays the music, so the equalizer, skip silence and extra loudness are mpv
/// filters instead of Android's audio effects, and the output device and volume are Encore's own.

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
