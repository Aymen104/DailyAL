import 'dart:async';
import 'dart:convert';

import 'package:dailyanimelist/animex/animex_meta.dart';
import 'package:dal_commons/commons.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps [AnimeXService]'s airing data current instead of frozen at build time.
///
/// `assets/animex_meta.json` is a snapshot baked into the APK: it ships correct
/// and then ages, so an installed build ends up counting down to a broadcast
/// that aired weeks ago (and the countdown's weekly projection then invents an
/// episode number on top of the stale date). AniList serves the same field from
/// a public endpoint with no key and no auth, so the app re-pins the schedule at
/// runtime instead of extrapolating from a fixed point.
///
/// The contract is deliberately small and failure-tolerant:
///  * the bundled asset is always the fallback, so a new install is correct
///    before the first request finishes;
///  * a fetch that fails changes nothing -- the previous reading stays;
///  * the last good reading is cached, so a cold start is correct offline;
///  * nothing here is awaited on the path to the first frame.
class AnimeXAiringLive {
  static final AnimeXAiringLive i = AnimeXAiringLive._();

  AnimeXAiringLive._({http.Client? client}) : _client = client ?? http.Client();

  /// Test entry point: the real code with a fake transport, so the parser, the
  /// merge and the cache are all exercised without a socket.
  @visibleForTesting
  factory AnimeXAiringLive.forTest(http.Client client) =>
      AnimeXAiringLive._(client: client);

  /// Public AniList GraphQL endpoint. No auth, no key, no per-user quota.
  static const String endpoint = 'https://graphql.anilist.co';

  /// AniList caps a page at 50 media, and accepts a list of MAL ids directly --
  /// which is what makes this affordable: one request per fifty titles instead
  /// of one per title.
  static const int _pageSize = 50;

  /// How long a fetched overlay is trusted before it is asked again. An airing
  /// slot changes at most once a week per title, so six hours is generous; the
  /// only reason not to make it twelve is a delayed episode being announced
  /// late.
  static const Duration maxAge = Duration(hours: 6);

  /// Cache key. Versioned so a shape change can be dropped without migration.
  static const String prefsKey = 'animex_airing_v1';

  /// Ceiling on a single request, so a half-dead network cannot hold the
  /// overlay hostage (or keep the app's io alive) for minutes.
  static const Duration _timeout = Duration(seconds: 15);

  /// `idMal_in` returns every requested title that AniList knows, one page at a
  /// time. `nextAiringEpisode` is null when nothing is scheduled, which is a
  /// real answer and has to survive the round trip as one.
  static const String _query = 'query(\$ids:[Int]){'
      'Page(page:1,perPage:50){'
      'media(type:ANIME,idMal_in:\$ids){'
      'idMal status episodes nextAiringEpisode{airingAt episode}'
      '}}}';

  final http.Client _client;
  DateTime? _fetchedAt;

  /// When the current overlay was fetched, or null if it is still the asset.
  DateTime? get fetchedAt => _fetchedAt;

  /// True when the overlay is missing or older than [maxAge].
  bool isStale([DateTime? now]) {
    final at = _fetchedAt;
    if (at == null) return true;
    final age = (now ?? DateTime.now()).difference(at);
    // A cache stamped in the future means the clock moved, so the age is
    // meaningless -- treat it like no cache at all.
    return age.isNegative || age >= maxAge;
  }

  /// Ids worth asking AniList about beyond the ones the bundled asset knows.
  ///
  /// The asset only contains what it contained the day it was built: a title
  /// added since, or one whose status the asset still calls NOT_YET_RELEASED,
  /// is never asked about -- and those are exactly the titles whose prediction
  /// stays wrong, because the only other source is MAL's weekly broadcast
  /// projection. `DalApi` hands over the ids of everything it currently thinks
  /// is airing, which is the set the user actually sees predictions for.
  final Set<int> _extraIds = {};
  int _extraIdsSinceRefresh = 0;

  /// Ids the asset selection covers, plus every id registered through
  /// [includeIds].
  List<int> get refreshIds {
    final ids = <int>{...AnimeXService.i.scheduledIds, ..._extraIds};
    return ids.toList()..sort();
  }

  /// Registers extra ids to fetch. A newly added id triggers a refresh
  /// immediately rather than waiting for [maxAge], because the whole point is
  /// that this title's prediction is wrong *now*.
  void includeIds(Iterable<int> ids) {
    final before = _extraIds.length;
    _extraIds.addAll(ids.where((id) => id > 0));
    if (_extraIds.length == before) return;
    _extraIdsSinceRefresh++;
    unawaited(refresh(force: true));
  }

  /// Startup entry point: index the asset, hydrate the cached overlay, then
  /// refresh in the background. Never throws.
  ///
  /// Awaits the asset so [AnimeXService.scheduledIds] is populated before the
  /// first request is built, but the network part is fire-and-forget.
  Future<void> start() async {
    try {
      await AnimeXService.i.ensureLoaded();
      await hydrateFromCache();
      // Ids registered while the asset was still loading were fetched with an
      // incomplete query set, so ask again now that both sets are known.
      if (_extraIds.isNotEmpty) {
        unawaited(refresh(force: true));
      } else {
        unawaited(refresh());
      }
    } catch (e) {
      logDal('AnimeX live: startup skipped -> $e');
    }
  }

  /// Fetches the schedule for every title that can have one and folds it into
  /// [AnimeXService]. Returns how many titles were re-pinned (0 on failure).
  ///
  /// [force] bypasses the [maxAge] check; tests use it, production does not.
  Future<int> refresh({DateTime? now, bool force = false}) async {
    final ref = now ?? DateTime.now();
    if (!force && !isStale(ref) && _extraIdsSinceRefresh == 0) return 0;

    final ids = refreshIds;
    if (ids.isEmpty) return 0;

    final rows = <int, AnimeXAiring>{};
    var pages = 0;
    for (var start = 0; start < ids.length; start += _pageSize) {
      final end = start + _pageSize < ids.length ? start + _pageSize : ids.length;
      final chunk = ids.sublist(start, end);
      try {
        final res = await _client.post(
          Uri.parse(endpoint),
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'query': _query,
            'variables': {'ids': chunk},
          }),
        ).timeout(_timeout);
        if (res.statusCode != 200) {
          logDal('AnimeX live: HTTP ${res.statusCode} for ${chunk.length} ids');
          continue;
        }
        final parsed = parsePage(res.body);
        if (parsed.isEmpty) continue;
        rows.addAll(parsed);
        pages++;
      } catch (e) {
        // One bad page must not cost the others, and must not cost the overlay
        // already in memory either.
        logDal('AnimeX live: chunk at $start failed -> $e');
      }
    }

    if (rows.isEmpty) return 0;

    AnimeXService.i.mergeLive(rows);
    _fetchedAt = ref;
    _extraIdsSinceRefresh = 0;
    await _persist(rows, ref);
    logDal('AnimeX live: re-pinned ${rows.length} schedules in $pages request(s)');
    return rows.length;
  }

  /// Parses one AniList page into [AnimeXAiring] rows keyed by MAL id.
  ///
  /// Throws [FormatException] on a payload that is not the shape asked for: a
  /// response that silently parses to nothing would look exactly like "no title
  /// has a schedule", which is the one wrong answer worth refusing.
  @visibleForTesting
  static Map<int, AnimeXAiring> parsePage(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const FormatException('AniList response must be an object');
    }
    final data = decoded['data'];
    if (data is! Map) {
      throw const FormatException('AniList response has no data');
    }
    final page = data['Page'];
    if (page is! Map) {
      throw const FormatException('AniList response has no Page');
    }
    final media = page['media'];
    if (media is! List) {
      throw const FormatException('AniList response has no media list');
    }

    final out = <int, AnimeXAiring>{};
    for (final entry in media) {
      if (entry is! Map) continue;
      final malId = (entry['idMal'] as num?)?.toInt();
      if (malId == null) continue;
      final next = entry['nextAiringEpisode'];
      DateTime? airingAt;
      int? episode;
      if (next is Map) {
        final at = next['airingAt'];
        if (at is num) {
          airingAt = DateTime.fromMillisecondsSinceEpoch(at.toInt() * 1000);
        }
        episode = (next['episode'] as num?)?.toInt();
      }
      out[malId] = AnimeXAiring(
        airingAt: airingAt,
        episode: episode,
        status: entry['status'] as String?,
        episodes: (entry['episodes'] as num?)?.toInt(),
      );
    }
    return out;
  }

  /// Re-spells a schedule projection with AniList's live reading.
  ///
  /// The schedule map that drives the calendar, the list cards' `Ep N · date`
  /// line and the detail page's countdown is built from MAL's weekly
  /// `broadcast` string and a *derived* episode number -- the count of weeks
  /// since the premiere. That derivation assumes an unbroken weekly run, and
  /// the first skipped week (or a delayed episode) permanently offsets it by
  /// one: the app then counts down to an episode that already aired, which is
  /// exactly the bug this method closes. Live AniList data is the same reading
  /// the airing label already trusts, so the same trust is applied here.
  ///
  /// Rules, in order, for every id in [base]:
  ///  * no live reading -> the projected row is kept unchanged (no better data,
  ///    and inventing a row for a title the app never showed is worse);
  ///  * live reading with an upcoming episode -> `timestamp` and `episode` are
  ///    replaced with AniList's, and everything else is carried through;
  ///  * live reading with nothing scheduled -> the row is dropped, because
  ///    AniList saying "no next episode" is the end of the run, and a weekly
  ///    projection would otherwise count down to the episode that just aired.
  ///
  /// Pure and non-destructive: [base] is not modified.
  static Map<int, ScheduleData> reconcileSchedules(
      Map<int, ScheduleData> base) {
    if (base.isEmpty || AnimeXService.i.liveCount == 0) return base;
    final out = <int, ScheduleData>{};
    for (final entry in base.entries) {
      final live = AnimeXService.i.liveAiringOf(entry.key);
      final row = entry.value;
      if (live == null) {
        out[entry.key] = row;
        continue;
      }
      if (!live.hasNextEpisode) {
        continue; // run over, cancelled, or on an unscheduled break
      }
      final corrected = ScheduleData(
        timestamp: live.airingAt!.toUtc().millisecondsSinceEpoch ~/ 1000,
        episode: live.episode,
        relatedLinks: row.relatedLinks,
      );
      out[entry.key] = corrected;
    }
    return out;
  }

  /// Hydrates the overlay from the last successful fetch. Silent on any failure:
  /// a corrupt cache simply means the asset speaks until the network answers.
  @visibleForTesting
  Future<void> hydrateFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final at = (decoded['at'] as num?)?.toInt();
      final rows = decoded['rows'];
      if (rows is! Map) return;
      final out = <int, AnimeXAiring>{};
      rows.forEach((key, value) {
        final id = key is int ? key : int.tryParse('$key');
        if (id != null && value is Map) {
          out[id] = AnimeXAiring.fromJson(value);
        }
      });
      if (out.isEmpty) return;
      // A fetch that already landed must not be wiped by the cache. The
      // schedule map can register ids (and kick off a refresh) before startup
      // hydration finishes, and an `applyLive` here would discard those fresh
      // rows and restore the stale cache - which is exactly how a title whose
      // id was only known to the schedule map stayed uncorrected.
      if (AnimeXService.i.liveCount > 0) {
        logDal('AnimeX live: cache hydrate skipped ('
            '${out.length} rows) - live data already present');
        return;
      }
      AnimeXService.i.applyLive(out);
      if (at != null) {
        _fetchedAt = DateTime.fromMillisecondsSinceEpoch(at * 1000);
      }
      logDal('AnimeX live: hydrated ${out.length} cached schedules');
    } catch (e) {
      logDal('AnimeX live: cache read failed -> $e');
    }
  }

  /// Stores [rows] as the whole overlay. Merges with whatever was cached so a
  /// partial fetch cannot shrink the overlay between runs.
  Future<void> _persist(Map<int, AnimeXAiring> rows, DateTime at) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = <String, dynamic>{};
      final previous = prefs.getString(prefsKey);
      if (previous != null && previous.isNotEmpty) {
        final decoded = jsonDecode(previous);
        if (decoded is Map && decoded['rows'] is Map) {
          (decoded['rows'] as Map).forEach((k, v) => existing['$k'] = v);
        }
      }
      rows.forEach((id, row) {
        final json = row.toJson();
        if (json.isNotEmpty) existing['$id'] = json;
      });
      await prefs.setString(
        prefsKey,
        jsonEncode({
          'at': at.toUtc().millisecondsSinceEpoch ~/ 1000,
          'rows': existing,
        }),
      );
    } catch (e) {
      logDal('AnimeX live: cache write failed -> $e');
    }
  }
}
