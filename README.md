<p align="center"><img src="docs/logo.svg" width="128" alt="Encore logo: a record whose label is a lowercase e"></p>

# Encore

A music player for Android, the Linux desktop (made for Fedora with KDE Plasma) and Windows that plays your **Navidrome** (or any Subsonic / OpenSubsonic) library. Dark,
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

## Desktop app (Linux and Windows)

The same app for your computer, made for Fedora with KDE Plasma (any Linux desktop with a system tray works,
and Windows 10 or 11). Every release on the [Releases](../../releases/latest) page has, next to the APKs:

| File | For |
|---|---|
| `encore-<version>-linux-x86_64.tar.gz` | any Linux on a 64-bit PC: install it for yourself, no password needed, and Encore updates itself |
| `encore-<version>-1.x86_64.rpm` | Fedora: install it for every user with dnf |
| `encore_<version>_amd64.deb` | Debian 12+, Ubuntu 22.04+, Linux Mint and the like: install it with apt |
| `encore-bin-<version>-1-x86_64.pkg.tar.zst` and `PKGBUILD` | Arch Linux, Manjaro, EndeavourOS: install it with pacman |
| `encore-<version>-windows-x64-setup.exe` | Windows 10 / 11: installs for you (no administrator), and Encore updates itself |
| `encore-<version>-windows-x64.zip` | Windows, portable: unpack anywhere and run `encore.exe` (update it by hand) |

**Linux, for yourself** (unpack, then run the installer in the folder; `./install.sh --uninstall` removes it again):

```bash
tar xf encore-*-linux-x86_64.tar.gz && encore-*-linux-x86_64/install.sh
```

It needs mpv's library for sound (`mpv-libs` on Fedora, `libmpv2` on Debian and Ubuntu, `mpv` on Arch).

**Fedora:**

```bash
sudo dnf install ./encore-*.x86_64.rpm
```

**Debian, Ubuntu, Mint:**

```bash
sudo apt install ./encore_*_amd64.deb
```

**Arch:** install the package from the release, or build it yourself from the release's `PKGBUILD` (it
repackages the Linux archive):

```bash
sudo pacman -U encore-bin-*-x86_64.pkg.tar.zst
```

```bash
makepkg -si
```

Run the second one in a folder with only the `PKGBUILD`.

A copy installed by dnf, apt or pacman is updated by them too: when there's a new version, Encore shows the
command to run.

**Windows:** run the setup program. It puts Encore in your Start menu (and, if you tick it, on the desktop and
in the tray at log-in). Windows may warn that the app is from an unknown publisher, since the builds aren't
code-signed: choose *More info › Run anyway*. Settings › About › Check for updates downloads the next setup
program and runs it for you. Uninstall it from Windows' Settings › Apps; your music, settings and downloads
stay in `%APPDATA%\Encore`.

The phone's update check only ever takes an APK, the Linux one only its own archive, and the Windows one only
the setup program.

**On the desktop**
- Every page from the phone, in a window made for a mouse and keyboard: a sidebar with your sections, liked
  songs and pins; a resizable side panel for the queue or lyrics; a player bar with volume along the bottom;
  right-click for the menus a long-press opens on the phone. The full-screen player is the phone's.
- Plasma's media controls, the lock screen, the keyboard's media keys and KDE Connect control Encore (MPRIS).
  On Windows: the media flyout by the volume, the lock screen and the media keys.
- A tray icon: left click shows or hides the window, right click for play / pause, next and quit. Closing the
  window keeps the music playing in the tray (Settings › Desktop). "Start when you log in" starts it in the tray.
- Colours from Plasma's accent colour (Settings › Appearance › Colour from wallpaper), or the album art, or yours.
- Sound: equalizer, speed and pitch, skip silence, ReplayGain and crossfade as on the phone, an output device
  picker (PipeWire), and Encore's own volume (also in Plasma's volume applet as "Encore").
- A **Now playing** panel beside the page (the button in the player bar, or Ctrl+Shift+N): the cover, the song
  and artist, about the artist, up next and the song's details.
- Notifications for new podcast episodes; downloads for offline play; Chromecast (the computer streams to the
  speaker on port 4547: on Fedora let it through with
  `sudo firewall-cmd --add-port=4547/tcp`, add `--permanent` to keep it).
- Keyboard: Space play / pause, Ctrl+→ / Ctrl+← next / previous, Shift+→ / Shift+← 10 seconds, Ctrl+↑ / Ctrl+↓
  volume, Ctrl+F search, Ctrl+L like, Ctrl+S shuffle, Ctrl+R repeat, Ctrl+P full-screen player, Ctrl+Shift+Q
  queue, Ctrl+Shift+L lyrics, Ctrl+D devices, Alt+← back, Ctrl+, settings, Ctrl+1…6 sections, Ctrl+Q quit
  (Settings › Desktop › Keyboard shortcuts).
- Windows: the same app, with the window, tray, media controls, notifications, sound settings and "Start when
  you log in" done the Windows way. The output-device picker lists Windows' devices.
- Not on the desktop: the home-screen widget (Plasma's media applet does that), Android Auto, the app icon
  choice, and USB-cable mode. If the computer runs your server, give it the server's own address in Settings ›
  Server › Address on your home network (e.g. `http://127.0.0.1:4540` with the server extras).

**With your phone**
- The same server accounts: sign in with your password, or **sign in with your phone**: type the server address
  on the computer, press "Sign in with your phone" and type the 6-digit code it shows on the phone (Settings ›
  Sign in another device). Works the other way round too.
- The queue and where you are follow you (kept on the server): "Continue from another device" on Home.
- Your devices (Settings › Connect to your other devices, or the devices button in the player): see what the
  other one is playing, **Play here** (take it over where it is), **Play on …** (hand it over), or use it as a
  remote: play / pause, skip, seek and volume.
- Pins, Home sections, smart-shuffle songs you dropped, lyrics you picked and podcast episodes marked played stay
  the same on both. Plays, stats, hearts, ratings, playlists and smart playlists are on the server anyway.
- Devices, sync and phone sign-in need the server extras (music-lookup); without them each device keeps its own
  pins and "Continue from another device" still works.

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
- Concerts near you (a row on Home, and Concerts): shows of the artists you play most and follow, near the town
  you set under Following › Shows, checked once a week by your server (Ticketmaster with your key there, else
  MusicBrainz). Tickets, Add to calendar, and a notification when a new one is announced.
- Your listening: minutes, plays, top artists / songs / albums and when you listen, by week, month, year or
  all time (needs the server extras).
- Your year (or a month) in review: a story of cards (top artists, songs, albums and genres, the first song,
  your longest streak, your hour, songs you found and kept) coloured from each one's art, ending with a picture to
  share, 9:16 or square (saved to Downloads on the desktop). From Stats, and a notification on 1 December.
- Your mixes (a row on Home, made by your server as real playlists, so every app has them): Discover Weekly
  (Mondays, 30 songs you don't have, fetched for a week, heart to keep), Release Radar (Fridays, new releases
  from artists you follow and play most), Daily Mix 1–6 (your library around your top artists, some songs new to
  you) and the Daylist (what you play at this time of day). Each can be turned off in Settings.
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
- Automix (Settings › Playback): the next song comes in where this one starts to fade, blending for 4 bars at its
  tempo (2–12 s); silence at the end of a song and at the start of the next is cut. Your server measures each
  song (mix-analyzer, the songs in your queue first); songs it hasn't measured use the crossfade.
  When two songs' tempos are within 6%, the next one comes in at the first one's tempo (pitch kept), beat on
  beat, and eases back to its own during the blend. The queue shows each song's BPM.
- Cast to Chromecast / Google Cast speakers and TVs on your Wi-Fi. The phone stays the remote and passes
  the music along, so it works even when the speaker can't reach your server (e.g. a Tailscale-only server).
- ReplayGain (track / album / automatic, pre-amp, peak protection), 5-band equalizer with presets.
- Synced lyrics (tap a line to jump), plain lyrics; online from LRCLIB, NetEase and lyrics.ovh (order and
  sources in Settings), and "Wrong lyrics?" to pick another match.
- Translate lyrics (a chip over the words): a muted second line under each line, in your phone's language or
  the one in Settings; Romanize for Japanese, Korean, Chinese, Cyrillic and other alphabets. Done by your server's
  own AI (music-lookup + Ollama, only while AI is on), cached per song: nothing leaves home.
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
- Over a USB cable: plug the phone (USB debugging on) into the computer that runs your server and run
  `tools/encore-usb.sh` there. Everything (browsing, playing, downloads) then goes through the cable, without
  Wi-Fi, internet or a VPN; Settings › Downloads › Copy all fetches the whole library. Unplug any time: it
  carries on over the network.
- Address on your home network (Settings › Server, optional): on the same Wi-Fi as your server, Encore goes
  straight there instead of through a VPN or the internet, and uses the main address everywhere else.
- Offline mode: the whole library index is kept on the phone (refreshed every 12 hours) for browsing and
  search; plays made offline are scrobbled later. When the server can't be reached (Tailscale off, the server
  asleep) the app notices within seconds and keeps working with what's on the phone.

**Covers**
- Missing album art is found online (iTunes, then Deezer), and artist pictures from Deezer. Can be switched off.

**Your stuff**
- Hearts, 1–5 star ratings, playlists (create, add, rename, reorder, remove, delete), scrobbling.
- Private session (Settings, or the devices sheet in the player): for up to 6 hours nothing you play is
  scrobbled, counted in stats, shown as "now playing" (Discord) or learned by autoplay. A lock in the player shows it.
- Add a whole album to a playlist (album page, long-press or right-click on an album): asks before adding songs
  the playlist already has, and a toast offers Undo.
- Follow artists (Follow on their page; Library → Artists → Followed artists). Follows are kept by the server's
  extras for your account, so the phone and the desktop share them. New releases (albums, EPs, singles, also
  upcoming ones and ones you don't have, as ⬇) from MusicBrainz and Deezer show on Home and under Following,
  checked once a day, with an optional notification on release day.
- Upcoming shows on artist pages and under Following → Shows, with a "near me" box (a city you type, no
  location permission). MusicBrainz events without setup; add a free Ticketmaster key for more shows and
  ticket links.

**Look**
- Screen readers (TalkBack): every button is labelled; a song row reads as one item ("title, artist, length,
  playing, downloaded, liked") with Play next / Like / More as actions; the cover's swipes and double-tap are
  actions too, and the seek bar says "1:12 of 3:40". Reduce animations (Appearance, or the phone's own "Remove
  animations") stops page slides, colour fades and smooth scrolling.
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
- `deviceHello` / `devicePoll` / `deviceCommand` / `deviceState`, `syncGet` / `syncSet` and `pairStart` /
  `pairPoll` / `pairApprove`: your devices controlling each other, small things kept in step, and signing in
  with your phone.
- `/rest/audiomuse/*`: a pass-through to [AudioMuse-AI](https://github.com/NeptuneHub/AudioMuse-AI) for the AI
  features. Song radio and sound-alike artists also use Navidrome's own AudioMuse plugin
  (`getSonicSimilarTracks`) and fall back to `getSimilarSongs2` without it.

Without these, the related buttons and rows just don't appear or come back empty.

## Building

Needs Flutter 3.50+ and the Android SDK (platform 36+).

```bash
flutter build apk --release --split-per-abi
```

The APKs are in `build/app/outputs/flutter-apk/`.

The desktop app (Fedora: `sudo dnf install clang cmake ninja-build gtk3-devel mpv-devel libsecret-devel
libayatana-appindicator-gtk3-devel lld rpm-build inkscape`):

```bash
flutter run -d linux                 # try it
tools/linux/build.sh                 # dist/: the .tar.gz, the .rpm and SHA256SUMS-linux.txt
tools/linux/build.sh --deb --arch    # also the .deb and the Arch package (in podman/docker containers)
```

The Windows app can only be built on Windows (Flutter, Visual Studio's C++ tools, Rust and Inno Setup 6):
`powershell -File tools\windows\build.ps1` makes the setup program and the portable zip in `dist\`.

GitHub Actions builds both (`.github/workflows/desktop.yml`): every Linux package is installed in a clean
Debian, Arch or Fedora container and started before anything is attached, and the Windows setup program is
installed and started on a Windows runner. Pushing a `v*` tag attaches all the desktop files to that release
(it's made as a draft if it isn't there yet), and "Run workflow" on the Actions page builds them without
releasing. `tools/release/upload.sh v<version> <files>` attaches files from here (the signed APKs) and keeps
the release's `SHA256SUMS.txt` whole. Release builds are signed with the key described in
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
                              audio devices, home-screen widget; desktop_audio.dart: mpv filters and devices
  data/devices.dart, sync.dart, pairing.dart   your devices, things kept in step, sign in with your phone
  desktop/                    the desktop window: layout, tray, MPRIS, shortcuts, Settings › Desktop
  ui/                         screens and shared widgets
linux/                        the GTK runner (one window; a second launch shows it; --hidden starts in the tray)
packages/just_audio_mpv/      just_audio on libmpv, with the equalizer and other filters (from just_audio_media_kit)
tools/linux/                  .desktop entry, metainfo, install.sh, RPM spec, build.sh
tools/debian/, tools/arch/    the .deb and the Arch package, made from the Linux archive
tools/windows/                the Windows setup program (Inno Setup) and build.ps1
windows/                      the Windows runner (one window; a second launch shows it; --hidden starts in the tray)
packages/audio_service_smtc/  Windows' media controls for audio_service (through smtc_windows)
android/app/src/main/kotlin   audio-device channel, home-screen widget, keep-running-while-downloading service
tools/encore-usb.sh           run on the server's computer: downloads over a USB cable (adb reverse)
```

## Credits

Font: [Inter](https://rsms.me/inter/) by Rasmus Andersson, SIL Open Font License 1.1 (`assets/fonts/OFL.txt`).
Lyrics: [LRCLIB](https://lrclib.net), NetEase Cloud Music, [lyrics.ovh](https://lyrics.ovh).
Covers, artist pages and share links: iTunes Search API, Deezer API, [Odesli / song.link](https://odesli.co),
Wikipedia. Radio stations: [Radio Browser](https://www.radio-browser.info).
