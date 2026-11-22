<p align="center"><img src="docs/logo.svg" width="128" alt="Encore logo: a record whose label is a lowercase e"></p>

# Encore for the desktop

Encore for Linux (made for Fedora with KDE Plasma) and Windows: a music player for your **Navidrome** (or any
Subsonic / OpenSubsonic) library. Dark, minimalist, Material You. The Android app is
[d-safro/encore](https://github.com/d-safro/encore), where the features and the optional server extras are
described; the code both share is [d-safro/encore-core](https://github.com/d-safro/encore-core).

## Install

The same app for your computer, made for Fedora with KDE Plasma (any Linux desktop with a system tray works,
and Windows 10 or 11). Every release on the [Releases](../../releases/latest) page has:

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

### Updating from 1.9 and older

Desktop copies up to 1.9 look for updates in d-safro/encore. For a while each desktop release is attached
there as well (see the switch at the top of `.github/workflows/desktop.yml`), so they update to a version that
looks here. The application id (`dev.safro.encore`), the program's name, the desktop entry and the Windows
installer's id are the same as before, so an update keeps your settings, queue and downloads.

## Building

The desktop app (Fedora: `sudo dnf install clang cmake ninja-build gtk3-devel mpv-devel libsecret-devel
libayatana-appindicator-gtk3-devel lld rpm-build inkscape`):

```bash
flutter run -d linux                 # try it
tools/linux/build.sh                 # dist/: the .tar.gz, the .rpm and SHA256SUMS-linux.txt
tools/linux/build.sh --deb --arch    # also the .deb and the Arch package (in podman/docker containers)
```

The Windows app can only be built on Windows (Flutter, Visual Studio's C++ tools, Rust and Inno Setup 6):
`powershell -File tools\windows\build.ps1` makes the setup program and the portable zip in `dist\`.

GitHub Actions builds everything (`.github/workflows/desktop.yml`): every Linux package is installed in a
clean Debian, Arch or Fedora container and started before anything is attached, and the Windows setup program
is installed and started on a Windows runner. Pushing a `v*` tag attaches all the files to that release (made
as a draft if it isn't there yet); "Run workflow" on the Actions page builds them without releasing.
`tools/release/upload.sh v<version> <files>` attaches files by hand and keeps the release's `SHA256SUMS.txt`
whole. Keep `lib/version.dart` in step with `version:` in `pubspec.yaml`.

## Layout

```
lib/
  main.dart                   start-up: encore_core's runEncore with the desktop's hooks
  version.dart                the app's version (keep it in step with pubspec.yaml)
  desktop/host.dart           the hooks encore_core asks for (see EncoreHost there)
  desktop/                    the window: layout, tray, MPRIS, shortcuts, Now Playing, drag and drop,
                              Settings › Desktop; updater.dart: putting an update in place
  playback/desktop_audio.dart mpv's filters, volume and output devices
linux/                        the GTK runner (one window; a second launch shows it; --hidden starts in the tray)
windows/                      the Windows runner (one window; a second launch shows it; --hidden starts in the tray)
packages/just_audio_mpv/      just_audio on libmpv, with the equalizer and other filters (from just_audio_media_kit)
packages/audio_service_smtc/  Windows' media controls for audio_service (through smtc_windows)
tools/linux/                  .desktop entry, metainfo, install.sh, RPM spec, build.sh
tools/debian/, tools/arch/    the .deb and the Arch package, made from the Linux archive
tools/windows/                the Windows setup program (Inno Setup) and build.ps1
```

## Changing the shared code (encore_core)

Everything both apps share (the server client, playback, downloads, settings, the shared screens and widgets)
is in [encore-core](https://github.com/d-safro/encore-core), the `encore_core` package. This app's
`pubspec.yaml` takes it from git at a tag:

```yaml
  encore_core:
    git:
      url: https://github.com/d-safro/encore-core.git
      ref: v1.0.0
```

CI and release builds use that tag. To work on the shared code next to this app, clone both side by side
(`../encore-core`) and add a `pubspec_overrides.yaml` here (it's in `.gitignore`):

```yaml
dependency_overrides:
  encore_core:
    path: ../encore-core
```

Then `flutter pub get`, and changes in `../encore-core` show up at once (hot reload included). To ship them:

1. In encore-core: commit, run `flutter analyze` and `flutter test`, push, then tag a new version
   (`git tag v1.1.0 && git push origin v1.1.0`; also bump `version:` in its `pubspec.yaml`).
2. Here: set `ref:` to the new tag, then move `pubspec_overrides.yaml` aside and run `flutter pub get`, so
   `pubspec.lock` records the git version (not your local folder), and commit `pubspec.yaml` and `pubspec.lock`.
3. Bump the other app to the same tag when it should get the change too.

encore_core never imports either app. Where shared code needs something only one app has, it asks the app
through `EncoreHost` (encore_core's `lib/core/host.dart`), which this app fills in at start-up.


## Credits

Font: [Inter](https://rsms.me/inter/) by Rasmus Andersson, SIL Open Font License 1.1 (`assets/fonts/OFL.txt`).
Lyrics: [LRCLIB](https://lrclib.net), NetEase Cloud Music, [lyrics.ovh](https://lyrics.ovh).
Covers, artist pages and share links: iTunes Search API, Deezer API, [Odesli / song.link](https://odesli.co),
Wikipedia. Radio stations: [Radio Browser](https://www.radio-browser.info).
