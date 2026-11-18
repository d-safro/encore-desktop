import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show SingleActivator;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_mpv/just_audio_mpv.dart' as mpv;

import 'package:encore/data/devices.dart';
import 'package:encore/data/pairing.dart';
import 'package:encore/data/sync.dart';
import 'package:encore/data/updates.dart';
import 'package:encore/desktop/desktop.dart';
import 'package:encore/desktop/desktop_settings.dart';
import 'package:encore/desktop/shortcuts.dart';
import 'package:encore/playback/desktop_audio.dart';

void main() {
  group('updates on GitHub releases', () {
    const assets = [
      'encore-1.8.0-arm64-v8a.apk',
      'encore-1.8.0-armeabi-v7a.apk',
      'encore-1.8.0-x86_64.apk',
      'encore-1.8.0-universal.apk',
      'encore-1.8.0-linux-x86_64.tar.gz',
      'encore-1.8.0-1.fc44.x86_64.rpm',
      'SHA256SUMS.txt',
    ];

    test('the phone still only ever picks an APK', () {
      expect(pickApk(assets, ['arm64-v8a']), 'encore-1.8.0-arm64-v8a.apk');
      expect(pickApk(assets, ['x86_64']), 'encore-1.8.0-x86_64.apk');
      expect(pickApk(assets, ['mips']), 'encore-1.8.0-universal.apk');
      expect(pickApk(['encore-1.8.0-linux-x86_64.tar.gz', 'encore-1.8.0-1.fc44.x86_64.rpm'], ['x86_64']), isNull);
    });

    test('the desktop picks its own archive and RPM, never an APK', () {
      expect(pickLinuxAsset(assets, 'x86_64'), 'encore-1.8.0-linux-x86_64.tar.gz');
      expect(pickLinuxAsset(assets, 'aarch64'), isNull);
      expect(pickLinuxAsset(['encore-1.8.0-x86_64.apk'], 'x86_64'), isNull);
      expect(pickRpm(assets, 'x86_64'), 'encore-1.8.0-1.fc44.x86_64.rpm');
      expect(pickRpm(assets, 'aarch64'), isNull);
    });
  });

  group('desktop sound', () {
    test('nothing on: no filters', () {
      expect(desktopFilters(eq: false, gains: [6, 0, 0, 0, 0], skipSilence: false), '');
      expect(desktopFilters(eq: true, gains: [0, 0, 0, 0, 0], skipSilence: false), '');
    });

    test('equalizer bands and skip silence become libavfilter filters', () {
      final f = desktopFilters(eq: true, gains: [6, 0, -3, 0, 40], skipSilence: true);
      expect(f.split(',equalizer').length, 3); // three bands not flat
      expect(f, contains('equalizer=f=60:t=o:w=2:g=6.0'));
      expect(f, contains('equalizer=f=910:t=o:w=2:g=-3.0'));
      expect(f, contains('equalizer=f=14000:t=o:w=2:g=15.0')); // held to the limit
      expect(f, contains('silenceremove='));
    });

    test('mpv gets pitch, the shared filters and the ReplayGain boost in one chain', () {
      expect(mpv.MediaKitPlayer.filterChain('', 1, 0), '');
      expect(mpv.MediaKitPlayer.filterChain('equalizer=f=60:t=o:w=2:g=3.0', 1, 0), 'lavfi=[equalizer=f=60:t=o:w=2:g=3.0]');
      expect(
        mpv.MediaKitPlayer.filterChain('a=1', 1.1, 2.5),
        'rubberband=pitch-scale=1.1000,lavfi=[a=1,volume=volume=2.50dB]',
      );
    });

    test('output devices: the system default first, each device once, by kind', () {
      final list = outputDevices(const [
        mpv.AudioDevice('auto', 'Autoselect device'),
        mpv.AudioDevice('pipewire', 'Default (pipewire)'),
        mpv.AudioDevice('pipewire/alsa_output.pci-0000_c5_00.6.analog-stereo', 'Ryzen HD Audio Controller Analog Stereo'),
        mpv.AudioDevice('pipewire/bluez_output.A4_C1_39_18_22_1F.1', 'soundcore P20i'),
        mpv.AudioDevice('pipewire/alsa_output.pci-0000_c5_00.1.hdmi-stereo', 'Radeon HDMI'),
        mpv.AudioDevice('pulse/bluez_output.A4_C1_39_18_22_1F.1', 'soundcore P20i'),
      ]);
      expect(list.map((d) => d.id).first, 'auto');
      expect(list.length, 4);
      expect(list.where((d) => d.name == 'soundcore P20i').single.kind, 'bluetooth');
      expect(list.where((d) => d.name == 'Radeon HDMI').single.kind, 'tv');
    });
  });

  group('devices', () {
    test('what a device plays survives the trip through the server', () {
      const s = RemoteState(
        songId: 's1',
        title: 'Song',
        artist: 'Artist',
        durationMs: 200000,
        positionMs: 10000,
        playing: true,
        volume: 0.4,
        queue: ['s0', 's1', 's2'],
        index: 1,
      );
      final back = RemoteState.fromJson({...s.toJson(), 'at': 1000});
      expect(back.title, 'Song');
      expect(back.queue, ['s0', 's1', 's2']);
      expect(back.index, 1);
      expect(back.volume, 0.4);
      // playing: the position moves on with the time since it was said; never past the end
      expect(back.positionAt(6000), 15000);
      expect(back.positionAt(10000000), 200000);
      expect(RemoteState.fromJson({...s.toJson(), 'playing': false, 'at': 1000}).positionAt(9000), 10000);
    });

    test('rubbish from the server is harmless', () {
      expect(RemoteState.fromJson(null).hasSong, isFalse);
      expect(RemoteState.fromJson({'volume': 7, 'queue': 'x'}).volume, 1.0);
      expect(RemoteDevice.fromJson({'name': 'no id'}), isNull);
    });
  });

  group('sync: the newest change wins', () {
    test('first time on a device: what your other devices have wins', () {
      expect(syncStep(local: '["a"]', last: null, lastAt: 0, server: '["b"]', serverAt: 5), SyncStep.take);
    });
    test('nothing on the server yet: send ours', () {
      expect(syncStep(local: '["a"]', last: null, lastAt: 0, server: null, serverAt: 0), SyncStep.send);
      expect(syncStep(local: null, last: null, lastAt: 0, server: null, serverAt: 0), SyncStep.none);
    });
    test('changed here: send; changed elsewhere: take; both the same: nothing', () {
      expect(syncStep(local: '["a","c"]', last: '["a"]', lastAt: 5, server: '["a"]', serverAt: 5), SyncStep.send);
      expect(syncStep(local: '["a"]', last: '["a"]', lastAt: 5, server: '["a","b"]', serverAt: 9), SyncStep.take);
      expect(syncStep(local: '["a"]', last: '["a"]', lastAt: 5, server: '["a"]', serverAt: 9), SyncStep.none);
    });
  });

  group('sign in with your phone', () {
    test('server addresses as typed', () {
      expect(serverBase('music.example.com/'), 'https://music.example.com');
      expect(serverBase(' http://127.0.0.1:4540 '), 'http://127.0.0.1:4540');
      expect(serverBase(''), '');
    });
    test('codes read in two groups', () {
      expect(const PairingCode('123456', 't', Duration(minutes: 5)).pretty, '123 456');
    });
  });

  group('window and keyboard', () {
    test('the saved window place is used only when it makes sense', () {
      expect(savedBounds('10,20,1280,820')?.width, 1280);
      expect(savedBounds('10,20,300,200'), isNull);
      expect(savedBounds('rubbish'), isNull);
      expect(savedBounds(null), isNull);
    });

    test('no two shortcuts share a key', () {
      final seen = <String>{};
      for (final s in desktopShortcuts) {
        for (final a in s.activators.cast<SingleActivator>()) {
          final k = '${a.trigger.keyId}-${a.control}-${a.shift}-${a.alt}';
          expect(seen.add(k), isTrue, reason: '${s.id} shares ${a.trigger.keyLabel}');
        }
      }
    });

    test('space and arrows never fire while typing; search and quit do', () {
      final byId = {for (final s in desktopShortcuts) s.id: s};
      expect(byId['playPause']!.whileTyping, isFalse);
      expect(byId['next']!.whileTyping, isFalse);
      expect(byId['search']!.whileTyping, isTrue);
      final q = byId['quit']!.activators.single as SingleActivator;
      expect((q.trigger, q.control, q.shift), (LogicalKeyboardKey.keyQ, true, false));
    });

    test('the autostart entry starts Encore in the tray', () {
      final e = autostartEntry('/home/me/.local/share/encore/app/encore');
      expect(e, contains('Exec="/home/me/.local/share/encore/app/encore" --hidden'));
      expect(e, contains('Icon=dev.safro.encore'));
    });
  });
}
