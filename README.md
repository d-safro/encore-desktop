<p align="center"><img src="docs/logo.svg" width="128" alt="Encore logo: a record whose label is a lowercase e"></p>

# Encore

A music player for Android that plays your **Navidrome** (or any Subsonic / OpenSubsonic) library. Dark,
minimalist, Material You. It can also show and fetch music you *don't* have yet, and recommend songs by how they
sound, when the server has the extras described below.

Built with Flutter. Original code and design.

## Install

Download an APK from [Releases](../../releases/latest):

| File | For |
|---|---|
| `encore-<version>-arm64-v8a.apk` | almost every phone from the last ~8 years (pick this if unsure) |
| `encore-<version>-armeabi-v7a.apk` | older 32-bit phones |
| `encore-<version>-x86_64.apk` | emulators, Chromebooks |
| `encore-<version>-universal.apk` | any device (bigger download) |

Open it on the phone and allow installing from your browser or file manager. Android 8.0 or newer.
Every release is signed with the same key, so new versions install over old ones and keep your data.
`SHA256SUMS.txt` in each release lets you check the download.

Sign in with your server address (e.g. `https://music.example.com`), user name and password. The password stays
in Android's encrypted storage and requests use salted tokens. Add more servers in Settings; each keeps its own
downloads, queue and pins.

Encore checks GitHub for new versions (about twice a day, can be switched off) and offers to install them; the
download is checked against the release's `SHA256SUMS.txt`. Android asks once to let Encore install updates.

## Features

**Home and library**
- Home: greeting, quick pills (shuffle all, liked songs, made for you, continue from another device),
  "Jump back in", recently added, most played, favourites, something different, top rated, your playlists
  (choose and order the sections).
- Library: Liked songs pinned on top like a playlist, plus your own pinned playlists and albums (long-press → Pin).
- Library tabs: playlists, albums (grid or list, sort orders, endless scrolling), artists, songs, liked songs,
  genres; folder browsing; internet radio stations from the server.
- Artist pages like Spotify's: fans, their top 10 (yours or ⬇), the whole discography (albums, singles & EPs,
  compilations; ⬇ for what you don't have), a bio (your server's, else Wikipedia), similar and sound-alike artists.
- Album, playlist and genre pages; share links (song.link) that open in any music app.
- Search across the server; recent searches remember the songs, albums and artists you opened.
- Your listening: minutes, plays, top artists / songs / albums and when you listen, by week, month, year or
  all time (needs the server extras).
- Smart playlists (Navidrome's own, so every app sees them): one-tap presets like "Forgotten favourites" and
  "On repeat", or your own rules.
- Folders: your real folders on disk (with the server extras), else Navidrome's artist / album view.

**Playback**
- Background playback, media notification, lock screen, Bluetooth / headset buttons, home-screen widget,
  Android Auto (Home / Playlists / Albums / Radio tabs, smart shuffle button, voice search, resume). Android
  Auto hides apps not installed from the Play Store until you allow "Unknown sources" in its developer settings
  (tap the version in Android Auto's settings 10 times).
- Exact play / pause / position reported to the server (OpenSubsonic playbackReport), so "now playing" in other
  apps and Discord-status tools is right.
- Gapless queue: play now / next / last, drag to reorder, swipe to remove, save as playlist; restored after a
  restart and kept on the server (continue in another app or device).
- Shuffle, repeat, speed and pitch, skip silence, sleep timer (minutes or end of song).
- Crossfade (up to 12 s); albums played in order stay seamless unless you choose otherwise.
- Cast to Chromecast / Google Cast speakers and TVs on your Wi-Fi. The phone stays the remote and passes
  the music along, so it works even when the speaker can't reach your server (e.g. a Tailscale-only server).
- ReplayGain (track / album / automatic, pre-amp, peak protection), 5-band equalizer with presets.
- Synced lyrics (tap a line to jump), plain lyrics; online from LRCLIB, NetEase and lyrics.ovh (order and
  sources in Settings), and "Wrong lyrics?" to pick another match.
- Internet radio: find stations in the Radio Browser directory or paste an address; shows the song playing.
- Full-screen player coloured from the album art; swipe the cover to skip, double-tap to heart.

**Sound and devices**
- One panel for output device (switch to Bluetooth / speakers with Android's output picker), system volume,
  speed, pitch, equalizer, loudness, skip silence, and shortcuts to Android's mono-audio / left-right balance
  and Bluetooth settings.

**Podcasts**
- A Podcasts tab: follow shows (search Apple's podcast directory or paste a feed), see new episodes on Home,
  resume where you stopped (kept on the server, so it carries over to other apps), mark played, show notes,
  download episodes to the phone (or save them on the server). A notification when a show you follow has a new
  episode (checked about hourly). Needs the server extras (music-lookup's podcast support).

**Jam (like Spotify Jam)**
- Start a Jam and share the link or QR code: friends search your library (and songs you don't have, which
  download first) and add, reorder, remove or skip from their phone's browser. Needs the server extras and a
  public address for the Jam page (Tailscale Funnel or similar).

**Song radio and discovery**
- Smart shuffle (like Spotify's): tap shuffle twice. It shuffles the list and mixes in a song that fits about
  every three songs, marked ✦; keep one with ⊕ (saved to that playlist or your liked songs) or drop it with ⊖
  and it won't be suggested for that list again. Shuffle buttons on pages remember which kind you used last.
- Song radio from any song: the song, then songs that sound like it, and it keeps going as you listen.
- "New to you": songs in your library you've never played that match your taste.
- Discovery rows and "More like this, not in your library": songs you don't have, picked from what you play;
  preview them or tap to fetch them.

**AI recommendations** (needs AudioMuse-AI, see below)
- Made for you (from your listening "fingerprint"), moods, describe a sound in words, find songs about a topic
  from lyrics, song alchemy (add and subtract songs or moods), and a path from one song to another.

**Downloads (like Spotify's download switch)**
- Switch on download for an album, playlist, your liked songs, or the whole library (with a size estimate);
  new songs added to them download too. Or download single songs.
- Download quality like Spotify's: Low, Normal, High (the default, about 72 MB an hour) or Very high, made
  smaller as Opus on your server, or Lossless (the original files). Changing it offers to shrink songs already
  downloaded; each keeps playing from the phone until its smaller copy has arrived. Wi-Fi only option;
  downloaded copies play first and work offline.
- No duplicates: the same recording that's in your library twice is stored once.
- Downloads never start over: a song that stops part-way (no signal, the app closed, the phone restarted)
  carries on from the byte it reached once the app is open and the server can be reached, and nothing you
  asked for is forgotten. Downloads keep going in the background, with a quiet "Downloading" notification.
- Copy music over a USB cable: plug the phone (USB debugging on) into the computer that runs your server and
  run `tools/encore-usb.sh` there. Downloads then go through the cable, without Wi-Fi or internet; Settings ›
  Downloads › Copy all fetches the whole library. Unplug any time: it carries on over the network.
- Offline mode: the whole library index is kept on the phone (refreshed every 12 hours) for browsing and
  search; plays made offline are scrobbled later. When the server can't be reached (Tailscale off, the server
  asleep) the app notices within seconds and keeps working with what's on the phone.

**Covers**
- Missing album art is found online (iTunes, then Deezer), and artist pictures from Deezer. Can be switched off.

**Your stuff**
- Hearts, 1–5 star ratings, playlists (create, add, rename, reorder, remove, delete), scrobbling.

**Look**
- Choose the app icon: Encore's, a line style that matches icon packs like Arcticons, or the original.
- Phones, tablets and landscape: a side rail and a side-by-side player on wide screens.
- Inter type, near-black surfaces, colour from your wallpaper (Material You), the playing album's art, or a
  colour you pick; pure black option for OLED.

## Server extras (optional)

Everything above under "Home", "Playback", "Downloads", "Covers" and "Your stuff" works with plain Navidrome.
The rest needs a small companion service in front of Navidrome, **music-lookup**, which is part of the author's
self-hosted media stack (not published yet):

- `getDiscoveries` / `getSongDiscoveries` and ⬇ results for music you don't have, fetched on request.
- `jamStart` / `jamState` / `jamPoll` / `jamEnd` and the public Jam page.
- The Subsonic podcast API (`getPodcasts`, `getNewestPodcasts`, `createPodcastChannel`…, bookmarks for where you
  stopped, `setPodcastProgress`), which Navidrome itself doesn't have.
- `/rest/audiomuse/*`: a pass-through to [AudioMuse-AI](https://github.com/NeptuneHub/AudioMuse-AI) for the AI
  features. Song radio and sound-alike artists also use Navidrome's own AudioMuse plugin
  (`getSonicSimilarTracks`) and fall back to `getSimilarSongs2` without it.

Without these, the related buttons and rows just don't appear or come back empty.

## Building

Needs Flutter 3.50+ and the Android SDK (platform 36+).

```bash
flutter build apk --release --split-per-abi
```

The APKs are in `build/app/outputs/flutter-apk/`. Release builds are signed with the key described in
`android/key.properties`, or the file named by the `ENCORE_KEY_PROPERTIES` environment variable:

```properties
storeFile=/path/to/release.jks
storePassword=…
keyAlias=…
keyPassword=…
```

Neither file is in git. Without one, release builds are signed with the debug key.

## Layout

```
lib/
  main.dart, app.dart         start-up, theme, navigation
  core/settings.dart          every setting
  data/                       Subsonic client, models, sign-in, offline database, sync, downloads,
                              AI (AudioMuse), online covers and lyrics
  playback/                   the player (queue, gapless, ReplayGain, EQ, scrobbling, radio, Android Auto),
                              audio devices, home-screen widget
  ui/                         screens and shared widgets
android/app/src/main/kotlin   audio-device channel, home-screen widget, keep-running-while-downloading service
tools/encore-usb.sh           run on the server's computer: downloads over a USB cable (adb reverse)
```

## Credits

Font: [Inter](https://rsms.me/inter/) by Rasmus Andersson, SIL Open Font License 1.1 (`assets/fonts/OFL.txt`).
Lyrics: [LRCLIB](https://lrclib.net), NetEase Cloud Music, [lyrics.ovh](https://lyrics.ovh).
Covers, artist pages and share links: iTunes Search API, Deezer API, [Odesli / song.link](https://odesli.co),
Wikipedia. Radio stations: [Radio Browser](https://www.radio-browser.info).
