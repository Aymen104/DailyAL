@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dailyanimelist/animex/animex_live.dart';
import 'package:dailyanimelist/animex/animex_meta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Live proof that the airing overlay fixes the label the user sees.
///
/// Skipped unless `RUN_LIVE_TESTS=1`; the rest of the suite must stay offline.
/// Run it deliberately when touching the airing code or the asset:
///
///     $env:RUN_LIVE_TESTS=1; flutter test test\animex_airing_live_test.dart
///
/// It exists because the bug was not in the parser -- it was in the *claim*:
/// the app showed "EP 7 · 19h" for a title AniList had at EP 6, and nothing
/// offline can catch that, because the offline suite only knows the snapshot
/// the app was already trusting.
void main() {
  final runLive = Platform.environment['RUN_LIVE_TESTS'] == '1';

  group('anilist live', () {
    late String raw;

    setUpAll(() {
      SharedPreferences.setMockInitialValues({});
      raw = File('assets/animex_meta.json').readAsStringSync();
      AnimeXService.i.debugLoadFromString(raw);
      AnimeXService.i.applyLive({});
    });

    test('the real endpoint answers in the shape the parser expects',
        () async {
      final res = await http.post(
        Uri.parse(AnimeXAiringLive.endpoint),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'query': 'query(\$ids:[Int]){Page(page:1,perPage:50){'
              'media(type:ANIME,idMal_in:\$ids){'
              'idMal status episodes nextAiringEpisode{airingAt episode}}}}',
          'variables': {
            'ids': [21, 61323],
          },
        }),
      ).timeout(const Duration(seconds: 30));

      expect(res.statusCode, 200);
      final rows = AnimeXAiringLive.parsePage(res.body);
      expect(rows.keys, containsAll([21, 61323]));
      for (final row in rows.values) {
        expect(row.status, isNotNull);
      }
    }, skip: runLive ? false : 'set RUN_LIVE_TESTS=1 to hit AniList for real');

    test('every label the app now shows agrees with AniList', () async {
      final live = AnimeXAiringLive.forTest(http.Client());
      final applied = await live.refresh(force: true);
      expect(applied, greaterThan(40),
          reason: 'AniList returned almost nothing - endpoint changed?');

      // Independent second read of the same titles, through a separate request
      // built by hand, so a bug in refresh() cannot hide itself.
      final ids = AnimeXService.i.scheduledIds;
      final confirmed = <int, Map<String, dynamic>>{};
      for (var i = 0; i < ids.length; i += 50) {
        final end = i + 50 < ids.length ? i + 50 : ids.length;
        final res = await http.post(
          Uri.parse(AnimeXAiringLive.endpoint),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'query': 'query(\$ids:[Int]){Page(page:1,perPage:50){'
                'media(type:ANIME,idMal_in:\$ids){'
                'idMal status episodes nextAiringEpisode{airingAt episode}}}}',
            'variables': {'ids': ids.sublist(i, end)},
          }),
        ).timeout(const Duration(seconds: 30));
        expect(res.statusCode, 200);
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        final media = ((decoded['data'] as Map)['Page'] as Map)['media'] as List;
        for (final entry in media) {
          final mal = (entry as Map)['idMal'];
          if (mal is int) confirmed[mal] = entry.cast<String, dynamic>();
        }
      }
      expect(confirmed, isNotEmpty);

      final now = DateTime.now();
      var labelled = 0;
      var withheld = 0;
      final mismatches = <String>[];

      for (final entry in confirmed.entries) {
        final malId = entry.key;
        final media = entry.value;
        final next = media['nextAiringEpisode'] as Map?;
        final label = AnimeXService.i.nextAiringLabel(malId, now: now);

        if (next == null) {
          // AniList schedules nothing: the app must not invent a countdown,
          // whether from a stale anchor or from the weekly projection.
          if (label != null) {
            mismatches.add('$malId: AniList has no next episode, app shows "$label"');
          } else {
            withheld++;
          }
          continue;
        }

        final episode = (next['episode'] as num).toInt();
        final airingAt =
            DateTime.fromMillisecondsSinceEpoch((next['airingAt'] as num).toInt() * 1000);
        if (label == null) {
          mismatches.add('$malId: AniList has EP $episode at $airingAt, app shows nothing');
          continue;
        }
        labelled++;
        if (!label.startsWith('EP $episode ')) {
          mismatches.add('$malId: AniList has EP $episode, app shows "$label"');
          continue;
        }
        final expectedDays = airingAt.difference(now).inDays;
        final shownDays = RegExp(r'· (\d+)d').firstMatch(label);
        if (shownDays != null && int.parse(shownDays.group(1)!) != expectedDays) {
          mismatches.add(
              '$malId: AniList airs in ${expectedDays}d, app shows "$label"');
        }
      }

      // ignore: avoid_print
      print('live verification: $labelled labelled, $withheld correctly withheld, '
          '${mismatches.length} mismatched');
      expect(mismatches, isEmpty, reason: mismatches.take(15).join('\n'));
    }, skip: runLive ? false : 'set RUN_LIVE_TESTS=1 to hit AniList for real');

    test('the bundled asset is not what the label falls back to today',
        () async {
      // Regression guard for the reported bug itself. Without the overlay the
      // asset alone mis-dates these titles: it was built seven weeks ago and
      // its weekly projection glosses over every delay since. With the overlay
      // the label must match the live number.
      final live = AnimeXAiringLive.forTest(http.Client());
      await live.refresh(force: true);

      const spotChecks = {
        61323: 'Ao no Hako Season 2',
        56733: 'Magical Explorer',
        53913: 'Tensei shitara Ken deshita II',
      };
      final res = await http.post(
        Uri.parse(AnimeXAiringLive.endpoint),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'query': 'query(\$ids:[Int]){Page(page:1,perPage:50){'
              'media(type:ANIME,idMal_in:\$ids){'
              'idMal status nextAiringEpisode{airingAt episode}}}}',
          'variables': {'ids': spotChecks.keys.toList()},
        }),
      ).timeout(const Duration(seconds: 30));
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final media = ((decoded['data'] as Map)['Page'] as Map)['media'] as List;

      for (final entry in media.cast<Map<String, dynamic>>()) {
        final malId = entry['idMal'] as int;
        final next = entry['nextAiringEpisode'] as Map?;
        final name = spotChecks[malId] ?? '$malId';
        if (next == null) continue; // on an unscheduled break right now
        final label = AnimeXService.i.nextAiringLabel(malId)!;
        // ignore: avoid_print
        print('$name: AniList EP ${next['episode']} -> "$label"');
        expect(label, startsWith('EP ${next['episode']} '),
            reason: '$name is labelled against the wrong episode');
      }
    }, skip: runLive ? false : 'set RUN_LIVE_TESTS=1 to hit AniList for real');

    tearDownAll(() => AnimeXService.i.applyLive({}));
  });
}
