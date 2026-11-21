# Encore desktop, packaged from an already built Flutter bundle (tools/linux/build.sh makes it).
%global debug_package %{nil}
%global __brp_strip %{nil}
%global __brp_strip_static_archive %{nil}
%global __brp_check_rpaths %{nil}

Name:           encore
Version:        %{encore_version}
Release:        1%{?dist}
Summary:        Music from your Navidrome or Subsonic server
License:        LicenseRef-Unspecified
URL:            https://github.com/d-safro/encore
Source0:        encore-%{version}-linux-%{_arch}.tar.gz
ExclusiveArch:  x86_64 aarch64
# the bundle carries its own Flutter libraries; the rest comes from the system
AutoReqProv:    no
Requires:       gtk3
Requires:       mpv-libs
Requires:       libsecret
Requires:       libayatana-appindicator-gtk3
# the Now playing panel's waveform (without it the seek bar is plain)
Recommends:     ffmpeg-free

%description
Encore plays your own music library from a Navidrome (or any Subsonic / OpenSubsonic) server: podcasts,
radio, lyrics, smart playlists and offline downloads, with Plasma's media controls and a tray icon. It works
with Encore on your phone: the same account, the queue carries over, and each can control the other.

%prep
%setup -q -n encore-%{version}-linux-%{_arch}

%install
mkdir -p %{buildroot}%{_libdir}/encore %{buildroot}%{_bindir}
cp -a app/. %{buildroot}%{_libdir}/encore/
ln -s ../%{_lib}/encore/encore %{buildroot}%{_bindir}/encore
install -Dm644 dev.safro.encore.desktop %{buildroot}%{_datadir}/applications/dev.safro.encore.desktop
install -Dm644 dev.safro.encore.metainfo.xml %{buildroot}%{_metainfodir}/dev.safro.encore.metainfo.xml
for d in icons/*; do
  size=$(basename "$d")
  install -Dm644 "$d"/* -t %{buildroot}%{_datadir}/icons/hicolor/$size/apps/
done

%files
%{_libdir}/encore
%{_bindir}/encore
%{_datadir}/applications/dev.safro.encore.desktop
%{_metainfodir}/dev.safro.encore.metainfo.xml
%{_datadir}/icons/hicolor/*/apps/dev.safro.encore.*

%changelog
* %(date '+%a %b %d %Y') Encore <noreply@github.com> - %{version}-1
- Encore %{version}
