/// Normalises jikan-edge (a mirror of the Jikan v4 API that serves the same
/// MyAnimeList data in a flatter, camelCase schema) onto the Jikan v4
/// (snake_case, nested) shape that the `dal_commons` models parse.
///
/// Deliberately dependency-free — no Flutter, no http, no app graph — so the
/// mapping can be pinned by a plain unit test. A silent drift here is the worst
/// possible failure for the character screen: the fallback would still return
/// HTTP 200, still parse, and still render an empty page.
class JikanEdgeMapper {
  const JikanEdgeMapper._();

  static Map<String, dynamic> character(Map<String, dynamic> source) {
    return {
      'mal_id': source['malId'],
      'url': source['url'],
      'images': _images(source),
      'name': source['name'],
      'name_kanji': source['nameKanji'],
      'nicknames':
          ((source['nicknames'] as List?) ?? const []).cast<String>().toList(),
      'favorites': source['favorites'],
      'about': source['about'],
      'anime': _roleNodes(source['anime'], 'anime'),
      'manga': _roleNodes(source['manga'], 'manga'),
      'voices': ((source['voices'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) {
        final entry = e.cast<String, dynamic>();
        return <String, dynamic>{
          'language': entry['language'],
          'person': {
            'mal_id': entry['malId'],
            'name': entry['name'],
            'images': _image(entry['imageUrl']),
          },
        };
      }).toList(),
    };
  }

  static Map<String, dynamic> person(Map<String, dynamic> source) {
    return {
      'mal_id': source['malId'],
      'url': source['url'],
      'website_url': source['website'],
      'images': _images(source),
      'name': source['name'],
      'given_name': source['givenName'],
      'family_name': source['familyName'],
      'alternate_names': ((source['alternateNames'] as List?) ?? const [])
          .cast<String>()
          .toList(),
      'birthday': source['birthday'],
      'favorites': source['favorites'],
      'about': source['about'],
      // A person's animeography/mangaography use the same role shape as a
      // character's, but jikan-edge leaves them empty; explicit empty lists keep
      // the models from treating the keys as missing.
      'anime': const <Map<String, dynamic>>[],
      'manga': const <Map<String, dynamic>>[],
      'voices': ((source['voices'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) {
        final entry = e.cast<String, dynamic>();
        return <String, dynamic>{
          'role': entry['characterRole'],
          'anime': {
            'mal_id': entry['animeId'],
            'title': entry['animeTitle'],
            'name': entry['animeTitle'],
            'images': _image(entry['animeImageUrl']),
          },
          'character': {
            'mal_id': entry['characterId'],
            'name': entry['characterName'],
            'title': entry['characterName'],
            'images': _image(entry['characterImageUrl']),
          },
        };
      }).toList(),
    };
  }

  static Map<String, dynamic> _image(dynamic url) => {
        'jpg': {'image_url': url},
        'webp': {'image_url': url},
      };

  /// jikan-edge ships `images: {small, medium, large}` plus a flat `imageUrl`;
  /// Jikan v4 nests them under `jpg`/`webp` behind an `image_url` key. Any
  /// missing tier falls back to the next best one, so a consumer that prefers
  /// `webp.large` still gets a usable url.
  static Map<String, dynamic> _images(Map<String, dynamic> source) {
    final images = source['images'];
    final flat = source['imageUrl'];
    if (images is! Map) return _image(flat);
    final medium = images['medium'] ?? flat;
    final large = images['large'] ?? medium;
    final small = images['small'] ?? medium;
    return {
      'jpg': {
        'image_url': medium,
        'small_image_url': small,
        'large_image_url': large,
      },
      'webp': {'image_url': large ?? medium},
    };
  }

  /// `[{malId, title, imageUrl, role}]` -> `[{role, <nodeKey>: {mal_id, title,
  /// images}}]`.
  static List<Map<String, dynamic>> _roleNodes(dynamic raw, String nodeKey) {
    return ((raw as List?) ?? const [])
        .whereType<Map>()
        .map((e) {
      final entry = e.cast<String, dynamic>();
      final node = <String, dynamic>{
        'mal_id': entry['malId'],
        'title': entry['title'],
        'name': entry['title'],
        'images': _image(entry['imageUrl']),
      };
      return <String, dynamic>{'role': entry['role'], nodeKey: node};
    }).toList();
  }
}
