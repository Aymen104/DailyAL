import 'package:dailyanimelist/api/jikan_edge_mapper.dart';
import 'package:dal_commons/commons.dart';
import 'package:flutter_test/flutter_test.dart';

/// The character/person screen used to be the last route served by a single
/// upstream (Tenrai, reached through the embedded handler). When that upstream
/// returned nothing the screen showed "Couldn't retreive Content", and because
/// the client cached the HTTP-200 error body the failure persisted for the
/// whole cache window. [JikanEdgeMapper] lets the app carry the same data from
/// the jikan-edge mirror instead.
///
/// These tests pin that mapping against real payloads. If it silently drifts,
/// the fallback still returns HTTP 200, still parses, and still renders an empty
/// page — the exact failure the fallback exists to prevent.
void main() {
  // Trimmed from a live https://jikan.lucashdo.com/v1/characters/156422/full
  // response (Fran — Tensei shitara Ken deshita II, the reported title).
  final fran = <String, dynamic>{
    'malId': 156422,
    'url': 'https://myanimelist.net/character/156422/Fran',
    'name': 'Fran',
    'nicknames': <String>[],
    'nameKanji': 'フラン',
    'imageUrl': 'https://cdn.myanimelist.net/images/characters/15/489905.jpg',
    'images': {
      'small': 'https://cdn.myanimelist.net/images/characters/15/489905t.jpg',
      'medium': 'https://cdn.myanimelist.net/images/characters/15/489905.jpg',
      'large': null,
    },
    'about': 'Fran is a black cat beastkin.',
    'favorites': 990,
    'anime': [
      {
        'malId': 49891,
        'title': 'Tensei shitara Ken deshita',
        'imageUrl': 'https://cdn.myanimelist.net/images/anime/1191/127909.jpg',
        'role': 'Main',
      },
      {
        'malId': 53913,
        'title': 'Tensei shitara Ken deshita II',
        'imageUrl': 'https://cdn.myanimelist.net/images/anime/1539/159559.jpg',
        'role': 'Main',
      },
    ],
    'manga': [
      {
        'malId': 99891,
        'title': 'Tensei shitara Ken deshita',
        'imageUrl': 'https://cdn.myanimelist.net/images/manga/1/203310.jpg',
        'role': 'Main',
      },
    ],
    'voices': [
      {
        'malId': 18511,
        'name': 'Kakuma, Ai',
        'imageUrl': 'https://cdn.myanimelist.net/images/voiceactors/2/65855.jpg',
        'language': 'Japanese',
      },
    ],
  };

  // Trimmed from https://jikan.lucashdo.com/v1/people/11158/full.
  final gotou = <String, dynamic>{
    'malId': 11158,
    'url': 'https://myanimelist.net/people/11158/Hiroki_Gotou',
    'name': 'Gotou, Hiroki',
    'givenName': 'ヒロキ',
    'familyName': '後藤',
    'alternateNames': <String>[],
    'birthday': 'Nov 16, 1985',
    'website': 'https://www.gotohiro8bit.com/',
    'imageUrl': 'https://cdn.myanimelist.net/images/voiceactors/3/10008.jpg',
    'images': {
      'small': null,
      'medium': 'https://cdn.myanimelist.net/images/voiceactors/3/10008.jpg',
      'large': 'https://cdn.myanimelist.net/images/voiceactors/3/10008l.jpg',
    },
    'about': 'Hometown: Saitama, Japan',
    'favorites': 25,
    'anime': <dynamic>[],
    'manga': <dynamic>[],
    'voices': [
      {
        'animeId': 53913,
        'animeTitle': 'Tensei shitara Ken deshita II',
        'animeImageUrl': 'https://cdn.myanimelist.net/images/anime/1539/159559.jpg',
        'characterId': 302205,
        'characterName': 'Urushi',
        'characterRole': 'Supporting',
        'characterImageUrl':
            'https://cdn.myanimelist.net/images/characters/5/643153.jpg',
      },
    ],
  };

  group('jikan-edge character mapping', () {
    test('parses as CharacterV4Data with every field the screen reads', () {
      final parsed = JikanV4Result<CharacterV4Data>.fromJson(
          DataUnionType.character, {'data': JikanEdgeMapper.character(fran)});
      final data = parsed.data!;

      expect(data.malId, 156422);
      expect(data.name, 'Fran');
      expect(data.nameKanji, 'フラン');
      expect(data.favorites, 990);
      expect(data.about, 'Fran is a black cat beastkin.');
      expect(data.nicknames, isEmpty);

      // The screen falls back from webp to jpg; jikan-edge has no large, so both
      // must resolve to the medium url rather than null.
      expect(data.images?.jpg?.imageUrl,
          'https://cdn.myanimelist.net/images/characters/15/489905.jpg');
      expect(data.images?.webp?.imageUrl,
          'https://cdn.myanimelist.net/images/characters/15/489905.jpg');

      expect(data.anime?.length, 2);
      expect(data.anime!.first.anime?.malId, 49891);
      expect(data.anime!.first.anime?.title, 'Tensei shitara Ken deshita');
      expect(data.anime!.first.anime?.images?.jpg?.imageUrl,
          'https://cdn.myanimelist.net/images/anime/1191/127909.jpg');

      expect(data.manga?.length, 1);
      expect(data.manga!.first.manga?.malId, 99891);

      expect(data.voices?.length, 1);
      expect(data.voices!.first.language, 'Japanese');
      expect(data.voices!.first.person?.malId, 18511);
      expect(data.voices!.first.person?.name, 'Kakuma, Ai');
    });

    test('does not throw on a sparse payload', () {
      final parsed = JikanV4Result<CharacterV4Data>.fromJson(
          DataUnionType.character,
          {
            'data': JikanEdgeMapper.character({'malId': 1, 'name': 'X'}),
          });
      // Keys absent from the edge payload must not make fromJson throw.
      expect(parsed.data!.name, 'X');
      expect(parsed.data!.nicknames, isEmpty);
      expect(parsed.data!.anime, isEmpty);
      expect(parsed.data!.voices, isEmpty);
    });
  });

  group('jikan-edge person mapping', () {
    test('parses as PeopleV4Data with voice-acting roles', () {
      final parsed = JikanV4Result<PeopleV4Data>.fromJson(
          DataUnionType.people, {'data': JikanEdgeMapper.person(gotou)});
      final data = parsed.data!;

      expect(data.malId, 11158);
      expect(data.name, 'Gotou, Hiroki');
      expect(data.givenName, 'ヒロキ');
      expect(data.familyName, '後藤');
      expect(data.alternateNames, isEmpty);
      expect(data.favorites, 25);
      expect(data.websiteUrl, 'https://www.gotohiro8bit.com/');
      expect(data.images?.webp?.imageUrl,
          'https://cdn.myanimelist.net/images/voiceactors/3/10008l.jpg');

      expect(data.voices?.length, 1);
      final role = data.voices!.first;
      expect(role.role, 'Supporting');
      expect(role.anime?.malId, 53913);
      expect(role.anime?.title, 'Tensei shitara Ken deshita II');
      expect(role.character?.malId, 302205);
      expect(role.character?.name, 'Urushi');
    });
  });
}
