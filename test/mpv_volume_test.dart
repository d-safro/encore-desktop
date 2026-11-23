import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_mpv/mediakit_player.dart';

/// mpv's gain for its volume: cubic (mpv's player/audio.c), so 50 % is −18 dB.
double mpvGain(double volume) => pow(volume / 100, 3).toDouble();
double db(double gain) => 20 * log(gain) / ln10;

void main() {
  test('a player volume comes out of mpv as the linear gain it asks for (ReplayGain, crossfades, the DJ dip)', () {
    // ReplayGain −6 dB is a volume of 0.5: mpv plays it 6 dB down, not 18
    expect(db(mpvGain(MediaKitPlayer.mpvVolume(0.5, 1))), closeTo(-6.02, 0.01));
    expect(db(mpvGain(MediaKitPlayer.mpvVolume(pow(10, -9.7 / 20).toDouble(), 1))), closeTo(-9.7, 0.01));
    expect(MediaKitPlayer.mpvVolume(1, 1), 100);
    expect(MediaKitPlayer.mpvVolume(0, 1), 0);
    expect(MediaKitPlayer.mpvVolume(2, 1), 100, reason: 'never past 100 %');
  });

  test("the app's own volume stays as mpv has it, on top", () {
    expect(MediaKitPlayer.mpvVolume(1, 0.5), 50);
    expect(db(mpvGain(MediaKitPlayer.mpvVolume(0.5, 0.5))), closeTo(-6.02 - 18.06, 0.02));
  });
}
