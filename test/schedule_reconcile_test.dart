import 'dart:convert';

import 'package:dailyanimelist/animex/animex_live.dart';
import 'package:dailyanimelist/animex/animex_meta.dart';
import 'package:dal_commons/commons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The schedule map is a weekly broadcast projection whose episode number is
/// derived from "weeks since the premiere" -- so the first skipped week
/// permanently offsets the countdown, and the app counts down to an episode
/// that already aired. This suite pins the rules that close that gap.
///
/// Run it offline: it exercises `AnimeXAiringLive.reconcileSchedules` and the
/// id registration, which are pure and read only the overlay singleton.
void main() {
  // 2026-11-20T00:26:00Z == the Friday 00:26 JST slot AniList reports for
  // MAL 59741 ("Tsuihou sareta Tensei Juukishi..."), whose app-side countdown
  // said "Ep 20 in 05d 08h" while AniList had ep 21 there.
  const ep21At = 1795101960;
  final ep21 = DateTime.fromMillisecondsSinceEpoch(ep21At * 1000);

  // A stale projection: ep 20, timestamp one week EARLIER than the truth and
  // the same weekday, which is what a one-skipped-week derivation produces.
  final staleEp20 = ep21.subtract(const Duration(days: 7)).toUtc();
  final staleTimestamp = staleEp20.millisecondsSinceEpoch ~/ 1000;

  setUp(() {
    AnimeXService.i.debugLoadFromString('{"59741":{"st":"RELEASING","al":1}}');
    AnimeXService.i.applyLive({});
  });

  tearDown(() => AnimeXService.i.applyLive({}));

  group('reconcileSchedules', () {
    test('takes the live timestamp and episode over the projection', () {
      final base = {
        59741: ScheduleData(timestamp: staleTimestamp, episode: 20),
      };
      AnimeXService.i.mergeLive({
        59741: AnimeXAiring(
          airingAt: ep21,
          episode: 21,
          status: 'RELEASING',
          episodes: 26,
        ),
      });

      final out = AnimeXAiringLive.reconcileSchedules(base);

      expect(out.length, 1, reason: 'a corrected row must not be dropped');
      expect(out[59741]!.episode, 21);
      expect(out[59741]!.timestamp, ep21At);
    });

    test('leaves a projected row alone when AniList has no reading', () {
      // No overlay at all: the projection stays untouched rather than being
      // deleted, because nothing better is known.
      final base = {
        59741: ScheduleData(timestamp: staleTimestamp, episode: 20),
      };
      final out = AnimeXAiringLive.reconcileSchedules(base);
      expect(out[59741]!.episode, 20);
      expect(out[59741]!.timestamp, staleTimestamp);
    });

    test('drops the row when AniList schedules nothing for it', () {
      // This is the end-of-run case a weekly projection cannot see: it would
      // keep counting down to the episode that just aired.
      final base = {
        59741: ScheduleData(timestamp: staleTimestamp, episode: 20),
      };
      AnimeXService.i.mergeLive({
        59741: const AnimeXAiring(status: 'FINISHED'),
      });

      final out = AnimeXAiringLive.reconcileSchedules(base);
      expect(out, isEmpty);
    });

    test('drops the row for a live run with no posted slot', () {
      // Many RELEASING titles have `nextAiringEpisode: null` -- long runners
      // with no schedule posted. "Nothing scheduled" is still an answer, and it
      // must not be projected.
      final base = {
        1: ScheduleData(timestamp: staleTimestamp, episode: 5),
      };
      AnimeXService.i.mergeLive({
        1: const AnimeXAiring(status: 'RELEASING'),
      });
      expect(AnimeXAiringLive.reconcileSchedules(base), isEmpty);
    });

    test('carries relatedLinks through untouched', () {
      final base = {
        59741: ScheduleData(
          timestamp: staleTimestamp,
          episode: 20,
          relatedLinks: RelatedLinks(mal: 'https://myanimelist.net/anime/59741'),
        ),
      };
      AnimeXService.i.mergeLive({
        59741: AnimeXAiring(airingAt: ep21, episode: 21),
      });

      final out = AnimeXAiringLive.reconcileSchedules(base);
      expect(out[59741]!.relatedLinks?.mal,
          'https://myanimelist.net/anime/59741');
    });

    test('does not mutate its input', () {
      final base = {
        59741: ScheduleData(timestamp: staleTimestamp, episode: 20),
      };
      AnimeXService.i.mergeLive({
        59741: AnimeXAiring(airingAt: ep21, episode: 21),
      });
      AnimeXAiringLive.reconcileSchedules(base);
      expect(base[59741]!.episode, 20, reason: 'caller data must survive');
    });

    test('an empty input is returned as-is', () {
      final base = <int, ScheduleData>{};
      expect(AnimeXAiringLive.reconcileSchedules(base), same(base));
    });

    test('a live number past the announced total is still honoured', () {
      // Continuous numbering across cours makes "episode 27 of 26" legal on
      // AniList's side, exactly as on the airing label: a fresh reading must
      // not be second-guessed.
      final base = {
        59741: ScheduleData(timestamp: staleTimestamp, episode: 20),
      };
      AnimeXService.i.mergeLive({
        59741: AnimeXAiring(
          airingAt: ep21,
          episode: 27,
          status: 'RELEASING',
          episodes: 26,
        ),
      });
      final out = AnimeXAiringLive.reconcileSchedules(base);
      expect(out[59741]!.episode, 27);
    });
  });

  group('stale-slate end to end', () {
    test('the corrected row produces the label AniList agrees with', () {
      // MAL 59741 on device showed "Ep 20 in 05d 08h"; the overlay turns the
      // schedule into ep 21, and the anime card label follows the same number.
      AnimeXService.i.mergeLive({
        59741: AnimeXAiring(
          airingAt: ep21,
          episode: 21,
          status: 'RELEASING',
          episodes: 26,
        ),
      });
      final corrected = AnimeXAiringLive.reconcileSchedules({
        59741: ScheduleData(timestamp: staleTimestamp, episode: 20),
      });
      final row = corrected[59741]!;
      final airing = DateTime.fromMillisecondsSinceEpoch(row.timestamp! * 1000);

      final now = ep21.subtract(const Duration(days: 5, hours: 8));
      expect(row.episode, 21);
      expect(airing.toUtc(), ep21.toUtc());
      expect(AnimeXService.i.nextAiringLabel(59741, now: now),
          startsWith('EP 21'));
    });
  });

  group('titles the bundled asset does not cover', () {
    // The bug this suite exists for, measured on the phone: the AnimeX overlay
    // was missing exactly the titles whose card read the wrong episode --
    // MAL 61999 because the asset still says NOT_YET_RELEASED, and MAL 64084
    // because it is not in the asset at all. The schedule map knows they air,
    // so it has to be able to add them to the query set.
    String pageFor(List<int> ids) => jsonEncode({
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
        });

    test('ids come from the schedule map, not only the asset', () async {
      // Asset only knows 59741.
      AnimeXService.i.debugLoadFromString('{"59741":{"st":"RELEASING","al":1}}');
      final live = AnimeXAiringLive.forTest(MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final ids = (body['variables'] as Map)['ids'] as List;
        return http.Response(pageFor(ids.cast<int>()), 200);
      }));

      expect(live.refreshIds, [59741],
          reason: 'only the asset can know anything before a schedule lands');

      // The schedule map (what the app shows predictions for) says 61999 and
      // 64084 are airing too.
      live.includeIds(const [61999, 64084]);

      expect(live.refreshIds, [59741, 61999, 64084]);

      var asked = <int>[];
      final live2 = AnimeXAiringLive.forTest(MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final ids = (body['variables'] as Map)['ids'] as List;
        asked.addAll(ids.cast<int>());
        return http.Response(pageFor(ids.cast<int>()), 200);
      }));
      live2.includeIds(const [61999, 64084]);

      expect(live2.isStale(), isTrue);
      AnimeXService.i.applyLive({});
      AnimeXService.i.debugLoadFromString(
          '{"59741":{"st":"RELEASING","al":1}}');
      final applied = await live2.refresh(force: true);
      expect(applied, greaterThan(0));
      expect(asked, containsAll([61999, 64084]),
          reason: 'a title missing from the asset must still be asked for');
    });

    test('registering the same ids twice never asks twice', () async {
      var requests = 0;
      final live = AnimeXAiringLive.forTest(MockClient((request) async {
        requests++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final ids = (body['variables'] as Map)['ids'] as List;
        return http.Response(pageFor(ids.cast<int>()), 200);
      }));

      live.includeIds(const [61999, 64084]);
      await Future.delayed(const Duration(milliseconds: 50));
      final afterFirst = requests;
      live.includeIds(const [61999, 64084, 61999]);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(requests, afterFirst,
          reason: 'repeat ids must not trigger another fetch');
    });
  });

  group('the two titles the user reported wrong', () {
    // Measured on the phone: both cards read an episode number one lower than
    // AniList, and neither title was in the AnimeX overlay at all -- 64084 is
    // absent from the bundled asset, 61999 is still NOT_YET_RELEASED there.
    // These are the real AniList values; the on-screen labels were
    // "ep 6 · 3d 20h" for 64084 and "Ep 6 · 6d 15h" for 61999.
    const shuiroNoKamen = {
      'idMal': 61999,
      'status': 'RELEASING',
      'episodes': null,
      'nextAiringEpisode': {'airingAt': 1795249800, 'episode': 7}
    };
    const sekaiSaikyou = {
      'idMal': 64084,
      'status': 'RELEASING',
      'episodes': null,
      'nextAiringEpisode': {'airingAt': 1795006800, 'episode': 7}
    };

    String realPage(List<int> ids) => jsonEncode({
          'data': {
            'Page': {
              'media': [
                if (ids.contains(61999)) shuiroNoKamen,
                if (ids.contains(64084)) sekaiSaikyou,
              ],
            }
          }
        });

    test('both are asked for, and both predictions are corrected', () async {
      // The asset knows nothing about either title.
      AnimeXService.i.debugLoadFromString('{"59741":{"st":"RELEASING","al":1}}');
      var asked = <int>[];
      final live = AnimeXAiringLive.forTest(MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final ids = (body['variables'] as Map)['ids'] as List;
        asked.addAll(ids.cast<int>());
        return http.Response(realPage(ids.cast<int>()), 200);
      }));

      // What the schedule projection says today: ep 6, on the weekly slot.
      final projected = <int, ScheduleData>{
        61999: ScheduleData(timestamp: 1795249800 - 7 * 86400, episode: 6),
        64084: ScheduleData(timestamp: 1795006800 - 7 * 86400, episode: 6),
      };

      live.includeIds(projected.keys);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(asked, containsAll([61999, 64084]),
          reason: 'titles absent from the asset must still be asked for');
      expect(AnimeXService.i.liveAiringOf(61999)?.episode, 7);
      expect(AnimeXService.i.liveAiringOf(64084)?.episode, 7);

      final corrected = AnimeXAiringLive.reconcileSchedules(projected);
      expect(corrected[61999]!.episode, 7);
      expect(corrected[61999]!.timestamp, 1795249800);
      expect(corrected[64084]!.episode, 7);
      expect(corrected[64084]!.timestamp, 1795006800);

      // And the card label follows the corrected number.
      final now = DateTime.fromMillisecondsSinceEpoch(1795249800 * 1000)
          .subtract(const Duration(days: 6, hours: 15));
      expect(AnimeXService.i.nextAiringLabel(61999, now: now),
          startsWith('EP 7'));
    });
  });
}