# Encore

A music player for Android that plays your **Navidrome** (or any Subsonic / OpenSubsonic) library, with a
Material You dark theme. It also shows music you *don't* have yet when the server runs
[music-lookup](https://github.com/d-safro/media-stack) and can fetch it with one tap.

Built with Flutter. Original code and design.

## Features

**Library**
- Home: recently played / added, most played, favourites, discover, top rated, playlists (choose and order the
  sections), quick mixes, "continue from another device".
- Library tabs: albums (grid or list, 8 sort orders, endless scrolling), artists, songs, playlists, genres,
  favourites; folder browsing; internet radio stations from the server.
- Album pages (discs, track numbers, total length), artist pages (popular songs, albums, albums you don't have,
  biography, similar artists, artist radio), genre pages.
- Search across the server, with recent searches; "Not in your library" results kept separate.

**Playback**
- Background playback with media notification, lock screen, Bluetooth / headset buttons, heart from the
  notification; Android Auto (browse recent, new, favourites, playlists; voice search).
- Gapless queue: play now / next / last, drag to reorder, swipe to remove, save as playlist, queue restored after
  restart and kept on the server (continue in Feishin or on another device).
- Shuffle, repeat one / all, speed 0.5×–2×, skip silence, sleep timer (minutes or end of song).
- ReplayGain (track / album / automatic, pre-amp, peak protection), 5-band equalizer with presets.
- Instant mix from any song (AudioMuse sound-alikes, else similar songs), endless playback.
- Synced lyrics (tap a line to jump), plain lyrics.
- Full-screen player coloured from the album art; swipe the cover to skip, double-tap to heart.

**Your stuff**
- Hearts and 1–5 star ratings, playlists: create, add to, rename, reorder, remove songs, delete.
- Scrobbling (now playing + plays after half the song or 4 minutes); plays made offline are sent later.

**Offline**
- The whole library index is saved on the phone for offline browsing and search.
- Download songs, albums, playlists (original or converted, Wi-Fi only option); downloaded copies play first.
- Offline mode; quality per network (original on Wi-Fi, Opus/MP3/AAC at a chosen bitrate on mobile data).

**Music you don't have (music-lookup)**
- Search, album and artist pages show ⬇ songs and albums; tap to download through the server or play a
  30-second preview; ⏳ updates to the real song when it arrives. Never mixed into offline data or shuffles.

**Look**
- Dark theme from your wallpaper (Material You), from the playing album's art, or a colour you pick;
  pure black option for OLED.

## Building

```bash
flutter build apk --release
```

The APK is in `build/app/outputs/flutter-apk/`. Needs Flutter 3.50+ and the Android SDK (platform 36+).

## Layout

```
lib/
  main.dart, app.dart         start-up, theme, navigation
  core/settings.dart          every setting
  data/                       Subsonic API client, models, sign-in, offline database, library sync, downloads
  playback/handler.dart       the player: queue, gapless, ReplayGain, EQ, scrobbling, sleep timer, Android Auto
  ui/                         screens and shared widgets
```
