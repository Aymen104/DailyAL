import 'dart:convert';

import 'package:dailyanimelist/animex/animex_live.dart';
import 'package:dailyanimelist/animex/animex_meta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The overlay that keeps the airing countdown honest.
///
/// Everything here runs offline against a synthetic four-title asset, because
/// the point is the *rules*: a live reading outranks the snapshot, "nothing is
/// scheduled" is a real answer, and a failed fetch changes nothing. The real
/// endpoint is covered by `animex_airing_live_test.dart`, which needs
/// RUN_LIVE_TESTS=1.
void main() {
  // 2030-01-01T00:00:00Z, far enough out that no test depends on today's date.
  const anchor = 1893456000;
  final anchorAt = DateTime.fromMillisecondsSinceEpoch(anchor * 1000);

  const asset = '{'
      '"1":{"c":255,"st":"RELEASING","na":$anchor,"ne":5,"al":1},'
      '"2":{"c":256,"st":"FINISHED","na":$anchor,"ne":5,"al":2},'
      '"3":{"c":257,"st":"RELEASING","al":3},'
      '"4":{"c":258,"st":"RELEASING","na":$anchor,"ne":8,"al":4},'
      '"5":{"st":"FINISHED","al":5}'
      '}';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AnimeXService.i.debugLoadFromString(asset);
    AnimeXService.i.applyLive({});
  });

  tearDown(() => AnimeXService.i.applyLive({}));

  group('live reading beats the bundled snapshot', () {
    test('a fetched row replaces the date and the episode number', () {
      final now = anchorAt.subtract(const Duration(days: 2));
      expect(AnimeXService.i.nextAiringLabel(4, now: now), startsWith('EP 8'));

      AnimeXService.i.mergeLive({
        4: AnimeXAiring(
          airingAt: anchorAt.add(const Duration(days: 7)),
          episode: 9,
          status: 'RELEASING',
          episodes: 12,
        ),
      });

      final label = AnimeXService.i.nextAiringLabel(4, now: now)!;
      expect(label, startsWith('EP 9'));
      expect(label, contains('9d'), reason: 'countdown should follow the live slot');
    });

    test('a live reading of "nothing scheduled" suppresses the stale anchor', () {
      // This is the bug: AniList has no upcoming episode, the asset still names
      // one from build day, and the old code happily counted down to it.
      expect(AnimeXService.i.nextAiringLabel(1, now: anchorAt), isNotNull);

      AnimeXService.i.mergeLive({
        1: const AnimeXAiring(status: 'RELEASING'),
      });

      expect(AnimeXService.i.nextAiringLabel(1, now: anchorAt), isNull);
    });

    test('a live FINISHED status stops the countdown', () {
      AnimeXService.i.mergeLive({
        1: AnimeXAiring(airingAt: anchorAt, episode: 5, status: 'FINISHED'),
      });
      expect(AnimeXService.i.nextAiringLabel(1, now: anchorAt), isNull);
    });

    test('a projected episode past the announced total is not a countdown', () {
      // AniList's own number is trusted, but a number this code invented by
      // adding weeks must not exceed the announced run: at that point the show
      // has ended and there is nothing left to count down to.
      AnimeXService.i.mergeLive({
        1: AnimeXAiring(
          airingAt: anchorAt,
          episode: 12,
          status: 'RELEASING',
          episodes: 12,
        ),
      });
      expect(
        AnimeXService.i.nextAiringLabel(1, now: anchorAt),
        isNull,
        reason: 'EP 13 of a 12-episode run is invention, not data',
      );
    });

    test('a live episode number is trusted over the announced total', () {
      // Continuous numbering across cours makes "episode 13 of 12" legal on
      // AniList's side, so a fresh reading must not be second-guessed.
      AnimeXService.i.mergeLive({
        1: AnimeXAiring(
          airingAt: anchorAt,
          episode: 13,
          status: 'RELEASING',
          episodes: 12,
        ),
      });
      expect(
        AnimeXService.i
            .nextAiringLabel(1, now: anchorAt.subtract(const Duration(days: 1))),
        startsWith('EP 13'),
      );
    });

    test('the last episode of a run still counts down', () {
      AnimeXService.i.mergeLive({
        1: AnimeXAiring(
          airingAt: anchorAt,
          episode: 12,
          status: 'RELEASING',
          episodes: 12,
        ),
      });
      final label = AnimeXService.i
          .nextAiringLabel(1, now: anchorAt.subtract(const Duration(days: 1)));
      expect(label, startsWith('EP 12'));
    });

    test('clearing the overlay restores the bundled value exactly', () {
      final now = anchorAt.subtract(const Duration(days: 1));
      final before = AnimeXService.i.nextAiringLabel(1, now: now);
      AnimeXService.i.mergeLive({
        1: AnimeXAiring(airingAt: anchorAt, episode: 99),
      });
      expect(AnimeXService.i.nextAiringLabel(1, now: now), contains('99'));
      AnimeXService.i.applyLive({});
      expect(AnimeXService.i.nextAiringLabel(1, now: now), before);
      expect(AnimeXService.i.liveCount, 0);
    });
  });

  group('scheduledIds', () {
    test('is the asset rows that carry a schedule or are still airing', () {
      // 1 and 4 carry an anchor, 3 is RELEASING without one, 2 is FINISHED with
      // a leftover anchor from build day, 5 has nothing.
      expect(AnimeXService.i.scheduledIds, [1, 2, 3, 4]);
    });

    test('is empty when nothing in the asset is airing or scheduled', () async {
      AnimeXService.i.debugLoadFromString('{"1":{"st":"FINISHED"}}');
      expect(AnimeXService.i.scheduledIds, isEmpty);

      var requests = 0;
      final live = AnimeXAiringLive.forTest(MockClient((request) async {
        requests++;
        return http.Response('{}', 200);
      }));
      expect(await live.refresh(force: true), 0);
      expect(requests, 0, reason: 'no ids means nothing to ask');
    });
  });

  group('parsePage', () {
    test('reads the real response shape, including a null schedule', () {
      final body = jsonEncode({
        'data': {
          'Page': {
            'media': [
              {
                'idMal': 21,
                'status': 'RELEASING',
                'episodes': null,
                'nextAiringEpisode': {'airingAt': anchor, 'episode': 1181},
              },
              {
                'idMal': 9253,
                'status': 'FINISHED',
                'episodes': 24,
                'nextAiringEpisode': null,
              },
              {'idMal': null, 'status': 'RELEASING'},
            ],
          },
        },
      });

      final rows = AnimeXAiringLive.parsePage(body);
      expect(rows.keys, [21, 9253]);
      expect(rows[21]!.episode, 1181);
      expect(rows[21]!.airingAt!.toUtc(), anchorAt.toUtc());
      expect(rows[21]!.hasNextEpisode, isTrue);
      expect(rows[9253]!.hasNextEpisode, isFalse);
      expect(rows[9253]!.episodes, 24);
      expect(rows[9253]!.status, 'FINISHED');
    });

    test('refuses a payload that is not the requested shape', () {
      // Parsing to an empty map would look identical to "no title has a
      // schedule", which is the one wrong answer worth throwing on.
      expect(() => AnimeXAiringLive.parsePage('[]'), throwsFormatException);
      expect(() => AnimeXAiringLive.parsePage('{"data":{}}'),
          throwsFormatException);
      expect(() => AnimeXAiringLive.parsePage('{"errors":[{"message":"x"}]}'),
          throwsFormatException);
    });
  });

  group('a fetch that beats startup hydration', () {
    // The race that kept MAL 64084 wrong on the phone: the schedule map
    // registers its ids (kicking off a refresh) before `start()` finishes
    // hydrating the cached overlay. The hydrate then ran `applyLive`, which
    // CLEARED the freshly fetched rows and restored the stale cache - so the
    // title whose id only the schedule map knew was never corrected.
    test('hydrate does not wipe rows a fetch already landed', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        AnimeXAiringLive.prefsKey,
        jsonEncode({
          'at': 1000000,
          'rows': {'1': {'na': 1000000, 'ne': 1, 'st': 'RELEASING'}},
        }),
      );

      final live = AnimeXAiringLive.forTest(MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final ids = (body['variables'] as Map)['ids'] as List;
        return http.Response(jsonEncode({
          'data': {
            'Page': {
              'media': (ids as List)
                  .map((id) => {
                        'idMal': id,
                        'status': 'RELEASING',
                        'episodes': 12,
                        'nextAiringEpisode': {
                          'airingAt': 1794727800,
                          'episode': 6
                        },
                      })
                  .toList(),
            }
          }
        }), 200);
      }));

      // The schedule map lands first and asks for a title the asset does not
      // know; the fetch completes before hydration.
      live.includeIds(const [64084]);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(AnimeXService.i.liveAiringOf(64084)?.episode, 6);

      await live.hydrateFromCache();

      expect(AnimeXService.i.liveAiringOf(64084), isNotNull,
          reason: 'the cache hydrate wiped a fresh reading');
      expect(AnimeXService.i.liveAiringOf(64084)!.episode, 6);
      // The cached overlay was NOT applied on top: the live rows are the ones
      // still standing (the cache held a single id the fetch never touched).
      expect(AnimeXService.i.liveCount, greaterThan(1));
      expect(AnimeXService.i.liveAiringOf(1)?.episode, isNot(1),
          reason: 'the stale cache value must not replace a fetched one');
    });
  });

  group('refresh', () {
    String pageFor(List<dynamic> ids) {
      final media = ids
          .map((id) => {
                'idMal': id,
                'status': 'RELEASING',
                'episodes': 12,
                'nextAiringEpisode': {
                  'airingAt': anchor + 7 * 86400,
                  'episode': 9,
                },
              })
          .toList();
      return jsonEncode({
        'data': {
          'Page': {'media': media},
        },
      });
    }

    test('applies one request per fifty ids and caches the result', () async {
      final ids = <dynamic>[];
      final live = AnimeXAiringLive.forTest(MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final chunk = (body['variables'] as Map)['ids'] as List;
        ids.addAll(chunk);
        return http.Response(pageFor(chunk), 200);
      }));

      expect(live.isStale(), isTrue, reason: 'no cache yet');
      final applied = await live.refresh(force: true);

      expect(ids, [1, 2, 3, 4]);
      expect(applied, 4);
      expect(AnimeXService.i.liveCount, 4);
      expect(live.fetchedAt, isNotNull);
      expect(AnimeXService.i.nextAiringLabel(3, now: anchorAt),
          startsWith('EP 9'),
          reason: 'a title with no bundled anchor gained one');

      final prefs = await SharedPreferences.getInstance();
      final cached = jsonDecode(prefs.getString(AnimeXAiringLive.prefsKey)!)
          as Map<String, dynamic>;
      expect((cached['rows'] as Map).keys.toSet(),
          {'1', '2', '3', '4'});
    });

    test('does nothing while the overlay is fresh', () async {
      var requests = 0;
      final live = AnimeXAiringLive.forTest(MockClient((request) async {
        requests++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
            pageFor((body['variables'] as Map)['ids'] as List), 200);
      }));

      await live.refresh(force: true);
      expect(requests, 1);

      expect(live.isStale(), isFalse);
      expect(await live.refresh(), 0);
      expect(requests, 1, reason: 'a second call inside maxAge must not fire');

      expect(await live.refresh(force: true), 4);
      expect(requests, 2);
    });

    test('a failed fetch leaves the previous reading alone', () async {
      AnimeXService.i.mergeLive({
        4: AnimeXAiring(airingAt: anchorAt, episode: 42),
      });
      final before = AnimeXService.i.nextAiringLabel(4, now: anchorAt);

      final live = AnimeXAiringLive.forTest(MockClient(
          (request) async => throw const SocketFailure()));
      expect(await live.refresh(force: true), 0);
      expect(AnimeXService.i.nextAiringLabel(4, now: anchorAt), before);
      expect(live.fetchedAt, isNull);
    });

    test('an HTTP error is not mistaken for "nothing scheduled"', () async {
      final live = AnimeXAiringLive.forTest(
          MockClient((request) async => http.Response('rate limited', 429)));
      expect(await live.refresh(force: true), 0);
      expect(AnimeXService.i.liveCount, 0);
    });

    test('a garbage body does not apply or cache anything', () async {
      final live = AnimeXAiringLive.forTest(
          MockClient((request) async => http.Response('<html>', 200)));
      expect(await live.refresh(force: true), 0);
      expect(AnimeXService.i.liveCount, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AnimeXAiringLive.prefsKey), isNull);
    });
  });

  group('cache', () {
    test('hydrates the overlay without the network', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        AnimeXAiringLive.prefsKey,
        jsonEncode({
          'at': anchor - 3600,
          'rows': {
            '1': {'na': anchor + 7 * 86400, 'ne': 6, 'st': 'RELEASING'},
          },
        }),
      );

      var requests = 0;
      final live = AnimeXAiringLive.forTest(MockClient((request) async {
        requests++;
        return http.Response('{}', 200);
      }));
      await live.hydrateFromCache();

      expect(requests, 0, reason: 'hydration must not touch the network');
      expect(AnimeXService.i.liveCount, 1);
      expect(AnimeXService.i.nextAiringLabel(1, now: anchorAt),
          startsWith('EP 6'));
      expect(
        live.isStale(
            DateTime.fromMillisecondsSinceEpoch((anchor - 3600) * 1000)),
        isFalse,
      );
    });

    test('survives a corrupt cache', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AnimeXAiringLive.prefsKey, '{not json');
      final live = AnimeXAiringLive.forTest(
          MockClient((request) async => http.Response('{}', 200)));
      await live.hydrateFromCache();
      expect(AnimeXService.i.liveCount, 0);
      expect(AnimeXService.i.nextAiringLabel(1, now: anchorAt), isNotNull,
          reason: 'the bundled asset still speaks');
    });

    test('a cache stamped in the future is treated as stale', () async {
      final future = DateTime.now().add(const Duration(days: 10));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        AnimeXAiringLive.prefsKey,
        jsonEncode({
          'at': future.toUtc().millisecondsSinceEpoch ~/ 1000,
          'rows': {
            '1': {'na': anchor, 'ne': 5, 'st': 'RELEASING'},
          },
        }),
      );
      final live = AnimeXAiringLive.forTest(
          MockClient((request) async => http.Response('{}', 200)));
      await live.hydrateFromCache();
      expect(live.isStale(), isTrue,
          reason: 'a clock jump must not pin a stale overlay forever');
    });
  });
}

class SocketFailure implements Exception {
  const SocketFailure();
  @override
  String toString() => 'connection closed';
}
