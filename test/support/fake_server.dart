// A pretend Navidrome for the desktop UI tests: made-up artists, albums, playlists and podcasts, answered
// through a MockClient so the real SubsonicClient and screens run unchanged.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// No pictures in tests: covers draw their placeholder.
String cover(int i) => '';

const _artistNames = [
  'Marisol Vega',
  'The Lantern Hours',
  'Kofi Mensah-Achterberg',
  'Northbound Static',
  'Ilse Johansson',
  'Paper Satellites',
  'Dr. Ambrose & The Midnight Orchestra of Unreasonably Long Names',
  'Yuki Tanabe',
  'Low Tide Choir',
  'Ravel Okonkwo',
  'Glass Harbour',
  'Ana Lucía Ferreira',
];

const _albumNames = [
  'Salt & Static',
  'Weathervane',
  'Everything I Meant to Say Before the Lights Came Up (Deluxe Anniversary Edition)',
  'Night Ferry',
  'Copper Rain',
  'Small Hours',
  'Orbit of the Quiet Moon',
  'Fieldnotes',
  'Harbour Lights',
  'The Long Way Round',
  'Blue Season',
  'Afterglow / Undertow',
  'Paper Houses',
  'Lumen',
  'Northern Lines',
  'Echo Chamber Music',
  'Sundial',
  'Velvet Hour',
];

const _songWords = [
  'Lighthouse',
  'Coming Home Again',
  'Paper Moon',
  'A Song for the Ones Who Stayed Up Waiting Until the Morning Came (Extended Mix)',
  'Gravity',
  'Undertow',
  'Glasshouse',
  'Slow Burn',
  'Neon Rivers',
  'Satellite Heart',
  'Late Bloom',
  'Static on the Line',
  'Wildflower',
  'Over the Water',
  'Ghosts in the Hallway',
  'Hold Still',
];

Map<String, dynamic> artistJson(int i) => {
  'id': 'ar$i',
  'name': _artistNames[i % _artistNames.length],
  'coverArt': cover(20 + i),
  'albumCount': 1 + i % 4,
};

int albumArtist(int a) => a % _artistNames.length;

Map<String, dynamic> songJson(int album, int track) {
  final a = albumArtist(album);
  return {
    'id': 's$album-$track',
    'title': _songWords[(album * 3 + track) % _songWords.length],
    'album': _albumNames[album % _albumNames.length],
    'albumId': 'al$album',
    'artist': _artistNames[a],
    'artistId': 'ar$a',
    'coverArt': cover(album),
    'track': track + 1,
    'discNumber': 1,
    'year': 2008 + album % 17,
    'duration': 150 + (album * 37 + track * 53) % 240,
    'suffix': 'flac',
    'bitRate': 1011,
    'genre': _genres[album % _genres.length],
    'playCount': (album * 7 + track * 3) % 40,
    if ((album + track) % 5 == 0) 'starred': '2025-01-01T00:00:00Z',
  };
}

Map<String, dynamic> albumJson(int i, {bool songs = false}) => {
  'id': 'al$i',
  'name': _albumNames[i % _albumNames.length],
  'artist': _artistNames[albumArtist(i)],
  'artistId': 'ar${albumArtist(i)}',
  'coverArt': cover(i),
  'year': 2008 + i % 17,
  'genre': _genres[i % _genres.length],
  'songCount': 8 + i % 6,
  'duration': 2400 + i * 97,
  'playCount': i * 11,
  'created': '2025-0${1 + i % 9}-1${i % 9}T10:00:00Z',
  if (songs) 'song': [for (var t = 0; t < 8 + i % 6; t++) songJson(i, t)],
};

const _genres = ['Indie Folk', 'Electronic', 'Jazz', 'Ambient', 'Alternative Rock', 'Soul', 'Classical', 'Hip-Hop'];

const playlistNames = [
  'Morning Coffee',
  'Deep Focus',
  'Road Trip 2025 — the long version with every song anyone asked for',
  'Rainy Sunday',
  'Workout',
  'Late Night Drive',
  'Dinner Party',
  'Liked from Radio',
];

Map<String, dynamic> playlistJson(int i, {bool songs = false}) {
  final entries = [for (var k = 0; k < 14; k++) songJson((i * 5 + k) % 18, k % 8)];
  return {
    'id': 'pl$i',
    'name': playlistNames[i % playlistNames.length],
    'comment': i == 0 ? 'Gentle songs to start the day' : '',
    'owner': 'demo',
    'public': i.isEven,
    'songCount': entries.length,
    'duration': entries.fold<int>(0, (n, s) => n + (s['duration'] as int)),
    'coverArt': cover(30 + i),
    'changed': '2026-10-0${1 + i % 9}T12:00:00Z',
    if (songs) 'entry': entries,
  };
}

Map<String, dynamic> episodeJson(int ch, int e) => {
  'id': 'ep$ch-$e',
  'channelId': 'pc$ch',
  'title': e == 1
      ? 'Episode ${120 - e}: Why every city sounds different at night, and what that tells us about ourselves'
      : 'Episode ${120 - e}: ${_songWords[(ch + e) % _songWords.length]}',
  'description': 'A conversation about sound, memory and the places we listen. With a guest from the field.',
  'publishDate': '2026-11-${(20 - e).toString().padLeft(2, '0')}T06:00:00Z',
  'duration': 1800 + e * 240,
  'coverArt': cover(10 + ch),
  'status': 'completed',
  'streamId': 'st$ch-$e',
};

const _shows = ['The Listening Room', 'Field Recordings Weekly', 'Liner Notes', 'Half-Speed Mastering'];

Map<String, dynamic> channelJson(int i, {bool episodes = false}) => {
  'id': 'pc$i',
  'url': 'https://example.com/feed$i.xml',
  'title': _shows[i % _shows.length],
  'author': _artistNames[(i + 3) % _artistNames.length],
  'description': 'Stories about music and the people who make it, every week.',
  'coverArt': cover(10 + i),
  'status': 'completed',
  'unplayed': i == 0 ? 3 : 0,
  'episodeCount': 6,
  'episode': [if (episodes) for (var e = 0; e < 6; e++) episodeJson(i, e)],
};

/// 'normal', 'empty' (a new server: nothing in it) or 'error' (every request fails).
var serverMode = 'normal';

/// The server says what it's getting (Conductor's encore.requests): a song looking, one downloading, one arrived.
var serverGets = false;

Map<String, dynamic> _request(String id, String title, String state, {double progress = 0, String? songId}) => {
  'id': id, 'type': 'song', 'title': title, 'artist': _artistNames[1], 'album': '', 'duration': 200,
  'state': state, 'progress': progress, 'reasons': ['heart'], 'users': ['me'], 'trial': false, 'kept': true,
  'asked': '2026-11-23T10:00:00Z', 'actions': [], 'songId': ?songId,
  if (songId != null) 'arrived': '2026-11-23T11:00:00Z',
};

/// Answers for each Subsonic method. Unknown methods get an empty "ok".
Map<String, dynamic> answer(String method, Map<String, String> q) {
  if (serverMode == 'empty' && method != 'ping') return {};
  switch (method) {
    case 'ping':
      return {};
    case 'getAlbumList2':
      final type = q['type'] ?? '';
      final size = int.tryParse(q['size'] ?? '') ?? 30;
      final shift = switch (type) { 'newest' => 3, 'frequent' => 7, 'recent' => 11, 'random' => 5, _ => 0 };
      return {
        'albumList2': {
          'album': [for (var i = 0; i < size.clamp(0, 18); i++) albumJson((i + shift) % 18)],
        },
      };
    case 'getAlbum':
      final i = int.tryParse((q['id'] ?? 'al0').substring(2)) ?? 0;
      return {'album': albumJson(i, songs: true)};
    case 'getArtists':
      return {
        'artists': {
          'index': [
            {'name': 'A', 'artist': [for (var i = 0; i < _artistNames.length; i++) artistJson(i)]},
          ],
        },
      };
    case 'getArtist':
      final i = int.tryParse((q['id'] ?? 'ar0').substring(2)) ?? 0;
      return {
        'artist': {
          ...artistJson(i),
          'album': [for (var a = 0; a < 18; a++) if (albumArtist(a) == i) albumJson(a)],
        },
      };
    case 'getArtistInfo2':
      return {
        'artistInfo2': {
          'biography':
              'Formed in a converted boathouse, they spent a decade playing small rooms up and down the coast before '
              'their third record found a wider audience. Their songs mix field recordings, brass and close harmonies.',
          'similarArtist': [for (var i = 1; i < 7; i++) artistJson(i)],
        },
      };
    case 'getTopSongs':
      return {
        'topSongs': {'song': [for (var t = 0; t < 10; t++) songJson(t % 3, t)]},
      };
    case 'getPlaylists':
      return {
        'playlists': {'playlist': [for (var i = 0; i < playlistNames.length; i++) playlistJson(i)]},
      };
    case 'getPlaylist':
      final i = int.tryParse((q['id'] ?? 'pl0').substring(2)) ?? 0;
      return {'playlist': playlistJson(i, songs: true)};
    case 'getStarred2':
      return {
        'starred2': {
          'song': [for (var k = 0; k < 20; k++) songJson(k % 18, k % 8)],
          'album': [for (var i = 0; i < 6; i++) albumJson(i)],
          'artist': [for (var i = 0; i < 4; i++) artistJson(i)],
        },
      };
    case 'search3':
      final query = (q['query'] ?? '').replaceAll('"', '');
      if (query.isEmpty) {
        return {
          'searchResult3': {'song': [for (var k = 0; k < 40; k++) songJson(k % 18, k % 8)]},
        };
      }
      return {
        'searchResult3': {
          'artist': [artistJson(0), artistJson(5), artistJson(9)],
          'album': [for (var i = 0; i < 8; i++) albumJson(i)],
          'song': [for (var k = 0; k < 12; k++) songJson(k % 18, k % 8)],
        },
      };
    case 'getGenres':
      return {
        'genres': {
          'genre': [
            for (var i = 0; i < _genres.length; i++) {'value': _genres[i], 'songCount': 40 + i * 13, 'albumCount': 3 + i},
          ],
        },
      };
    case 'getSongsByGenre':
      return {
        'songsByGenre': {'song': [for (var k = 0; k < 20; k++) songJson(k % 18, k % 8)]},
      };
    case 'getRandomSongs':
      return {
        'randomSongs': {'song': [for (var k = 0; k < 20; k++) songJson((k * 5) % 18, k % 8)]},
      };
    case 'getSimilarSongs2':
    case 'getSimilarSongs':
      return {
        method == 'getSimilarSongs2' ? 'similarSongs2' : 'similarSongs': {
          'song': [for (var k = 0; k < 12; k++) songJson((k * 3) % 18, k % 8)],
        },
      };
    case 'getPodcasts':
      final id = q['id'];
      return {
        'podcasts': {
          'channel': [
            for (var i = 0; i < _shows.length; i++)
              if (id == null || id == 'pc$i') channelJson(i, episodes: id != null || q['includeEpisodes'] == 'true'),
          ],
        },
      };
    case 'getNewestPodcasts':
      return {
        'newestPodcasts': {'episode': [for (var e = 0; e < 6; e++) episodeJson(e % 4, e)]},
      };
    case 'getInternetRadioStations':
      return {
        'internetRadioStations': {
          'internetRadioStation': [
            for (final (i, n) in ['Harbour FM', 'Jazz Lounge 24/7', 'Night Shift Ambient — commercial-free'].indexed)
              {'id': 'r$i', 'name': n, 'streamUrl': 'https://example.com/r$i', 'homePageUrl': 'https://example.com'},
          ],
        },
      };
    case 'getMusicFolders':
      return {
        'musicFolders': {
          'musicFolder': [
            {'id': 1, 'name': 'Music'},
          ],
        },
      };
    case 'getIndexes':
      return {
        'indexes': {
          'index': [
            {'name': 'A', 'artist': [for (var i = 0; i < 8; i++) {'id': 'd$i', 'name': _artistNames[i]}]},
          ],
        },
      };
    case 'getMusicDirectory':
      return {
        'directory': {
          'id': q['id'],
          'name': 'Folder',
          'child': [for (var i = 0; i < 6; i++) {'id': 'dd$i', 'title': _albumNames[i], 'isDir': true, 'coverArt': cover(i)}],
        },
      };
    case 'getLyricsBySongId':
      return {
        'lyricsList': {
          'structuredLyrics': [
            {
              'synced': true,
              'lang': 'eng',
              'line': [
                for (var i = 0; i < 24; i++)
                  {
                    'start': i * 4000,
                    'value': [
                      'The harbour lights are low tonight',
                      'And every boat is coming home',
                      'I kept the window open wide',
                      'So you would never walk alone',
                    ][i % 4],
                  },
              ],
            },
          ],
        },
      };
    case 'getMixes':
      return {
        'mixes': {
          'kind': [
            {'kind': 'daily', 'enabled': true},
            {'kind': 'discover', 'enabled': true},
          ],
          'mix': [
            for (var i = 0; i < 5; i++)
              {
                'kind': i == 0 ? 'discover' : 'daily',
                'playlistId': 'pl$i',
                'name': i == 0 ? 'Discover Weekly' : 'Daily Mix $i',
                'comment': '${_artistNames[i]}, ${_artistNames[i + 1]} and more',
                'coverArt': cover(30 + i),
              },
          ],
        },
      };
    case 'getConcerts':
      return {
        'concerts': {
          'city': 'Lisbon',
          'source': 'MusicBrainz',
          'show': [
            for (var i = 0; i < 6; i++)
              {
                'artist': _artistNames[i],
                'date': '2026-12-${(5 + i * 3).toString().padLeft(2, '0')}',
                'venue': i == 2 ? 'Coliseu dos Recreios — Grande Sala (standing only)' : 'Musicbox',
                'city': 'Lisbon',
                'url': 'https://example.com/show$i',
                'first': 1,
              },
          ],
        },
      };
    case 'getListeningStats':
    case 'getListeningReview':
      return {
        method == 'getListeningStats' ? 'listeningStats' : 'listeningReview': {
          'period': q['period'] ?? 'month',
          'plays': 1284,
          'minutes': 4410,
          'songs': 612,
          'artistCount': 143,
          'albumCount': 201,
          'newArtists': 18,
          'from': DateTime(2026, 11, 1).millisecondsSinceEpoch,
          'to': DateTime(2026, 11, 30).millisecondsSinceEpoch,
          'song': [for (var k = 0; k < 10; k++) {...songJson(k, k % 8), 'plays': 40 - k * 3}],
          'artist': [for (var i = 0; i < 10; i++) {...artistJson(i), 'plays': 90 - i * 7, 'minutes': 300 - i * 20}],
          'album': [for (var i = 0; i < 10; i++) {...albumJson(i), 'plays': 50 - i * 4}],
          'day': [
            for (var d = 1; d <= 22; d++)
              {'date': '2026-11-${d.toString().padLeft(2, '0')}', 'minutes': 60 + (d * 37) % 160},
          ],
          'hour': [for (var h = 0; h < 24; h++) (h >= 7 && h <= 23) ? 20 + (h * 13) % 90 : 4],
          'genre': [for (var i = 0; i < 5; i++) {'name': _genres[i], 'minutes': 900 - i * 140}],
          'streak': {'days': 23, 'from': '2026-10-31'},
          'peakHour': 21,
          'firstSong': songJson(2, 1),
          'discoveries': [for (var k = 0; k < 5; k++) {...songJson(k + 5, k), 'plays': 12 - k}],
          'discoveryCount': 31,
        },
      };
    case 'getPlayQueue':
      return {};
    case 'getOpenSubsonicExtensions':
      return {
        'openSubsonicExtensions': [
          if (serverGets) {'name': 'encore.requests', 'versions': [1]},
        ],
      };
    case 'getRequests':
      final done = (q['state'] ?? '') == 'done';
      final list = done
          ? [_request('dz-t-3', 'Arrived Song', 'done', progress: 100, songId: songJson(0, 0)['id'] as String)]
          : [_request('dz-t-1', 'Looking Song', 'searching'), _request('dz-t-2', 'Moving Song', 'downloading', progress: 55)];
      return {
        'requests': {
          'total': list.length, 'offset': 0, 'onTrial': 0, 'downloadsPaused': false, 'canPick': false,
          'counts': {'searching': 1, 'downloading': 1, 'done': 1},
          'request': list,
        },
      };
    default:
      return {};
  }
}

http.Client fakeServer() => MockClient((req) async {
  final method = req.url.pathSegments.isEmpty ? '' : req.url.pathSegments.last;
  final q = {...req.url.queryParameters};
  if (req.method == 'POST' && req.body.isNotEmpty) q.addAll(Uri.splitQueryString(req.body));
  if (!req.url.path.contains('/rest/')) return http.Response('{}', 404);
  if (serverMode == 'error' && !req.url.path.endsWith('/ping')) {
    return http.Response(
      jsonEncode({
        'subsonic-response': {
          'status': 'failed',
          'version': '1.16.1',
          'error': {'code': 0, 'message': 'The server had a problem (database is locked)'},
        },
      }),
      200,
    );
  }
  final body = {
    'subsonic-response': {'status': 'ok', 'version': '1.16.1', 'type': 'navidrome', 'openSubsonic': true, ...answer(method, q)},
  };
  return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
});
