import 'dart:convert';

import 'package:dal_commons/dal_commons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// One record from the bundled AnimeX/AniList metadata set, keyed by MAL id.
///
/// Everything in here is data MAL's own API cannot supply: MAL has no banner
/// endpoint and no colour field at all. The scoring numbers are AniList's
/// independent opinion, which is useful precisely because it disagrees with MAL
/// often enough to be worth showing side by side.
class AnimeXMeta {
  /// 16:9 key art. Only 37% of titles have one, so this must never be the
  /// primary artwork for a surface that every entry shares.
  final String? banner;

  /// TMDB backdrop, higher resolution than [banner], 51% coverage.
  final String? backdrop;

  /// Dominant colour as 0xRRGGBB, 90% coverage.
  final int? color;

  /// AniList popularity score, ~100% coverage. Higher is more popular.
  final int? popularity;

  /// AniList average score on a 0-100 scale, 78% coverage.
  final double? score;

  /// AniList status, e.g. `RELEASING`, `FINISHED`, `NOT_YET_RELEASED`.
  final String? status;

  /// Exact next broadcast time, as of the moment this asset was built.
  /// Present only for titles AniList scheduled that day (under a hundred of the
  /// 19k), which is the point: it is the only precise airing data the app can
  /// get, since MAL only exposes a weekly `broadcast` string. A build that has
  /// been installed for a while is past its anchor date, so this is a starting
  /// point for [AnimeXService.nextAiringLabel], never the last word.
  final DateTime? nextAiringAt;

  /// The episode number that will air at [nextAiringAt].
  final int? nextEpisode;

  /// AniList's own numeric id, 100% coverage. Only needed to build an outbound
  /// link. It is *not* the MAL id: the two coincide for older titles and
  /// diverge from around 2014 onward (e.g. MAL 36055 is AniList 145756).
  final int? anilistId;

  const AnimeXMeta({
    this.banner,
    this.backdrop,
    this.color,
    this.popularity,
    this.score,
    this.status,
    this.nextAiringAt,
    this.nextEpisode,
    this.anilistId,
  });

  bool get isReleasing => status == 'RELEASING';

  /// AniList page for this title, or null when the id is unknown.
  String? get anilistUrl =>
      anilistId == null ? null : 'https://anilist.co/anime/$anilistId';

  /// Best available wide image.
  ///
  /// Prefers [banner] over the higher-resolution [backdrop] on purpose. The
  /// banner comes from AniList's own media records, so it is always the right
  /// show; the backdrop comes from TMDB, whose anime entries are community
  /// mapped and are sometimes attached to the wrong season or to a live-action
  /// remake. A wrong-but-sharp header is worse than a right-and-slightly-soft
  /// one, and at 1920x400 the banner is already wider than any phone display
  /// this header is shown on.
  String? get wideImage => banner ?? backdrop;

  factory AnimeXMeta.fromJson(Map<dynamic, dynamic> json) {
    final na = json['na'];
    return AnimeXMeta(
      banner: json['b'] as String?,
      backdrop: json['bd'] as String?,
      color: (json['c'] as num?)?.toInt(),
      popularity: (json['p'] as num?)?.toInt(),
      score: (json['s'] as num?)?.toDouble(),
      status: json['st'] as String?,
      nextAiringAt: na is num
          ? DateTime.fromMillisecondsSinceEpoch(na.toInt() * 1000)
          : null,
      nextEpisode: (json['ne'] as num?)?.toInt(),
      anilistId: (json['al'] as num?)?.toInt(),
    );
  }
}

/// A next-broadcast reading fetched from AniList at runtime.
///
/// The bundled asset can only describe the day it was built on; this is the
/// same field asked again. It is kept beside [AnimeXMeta] rather than inside it
/// so the nineteen-thousand-record index stays immutable: only the handful of
/// titles that carry a schedule ever get an override, and clearing the overlay
/// restores the bundled value exactly.
///
/// Serialised with the same short keys as the asset (`na`, `ne`, `st`) so the
/// cache, the network payload and the bundled row all read through one parser.
class AnimeXAiring {
  /// The episode that airs at [airingAt]. Null when AniList had an entry but no
  /// episode number, which is treated as "nothing to count down to".
  final int? episode;

  /// AniList status at fetch time.
  final String? status;

  /// Total episode count, when AniList publishes one. Only used to notice that
  /// the numbered run is already over.
  final int? episodes;

  /// Next broadcast, or null when AniList schedules nothing for this title any
  /// more (finished, cancelled, or on an unscheduled break).
  final DateTime? airingAt;

  const AnimeXAiring({
    this.airingAt,
    this.episode,
    this.status,
    this.episodes,
  });

  /// True when there is a real upcoming episode to count down to.
  bool get hasNextEpisode => airingAt != null && episode != null;

  factory AnimeXAiring.fromJson(Map<dynamic, dynamic> json) {
    final na = json['na'];
    return AnimeXAiring(
      airingAt: na is num
          ? DateTime.fromMillisecondsSinceEpoch(na.toInt() * 1000)
          : null,
      episode: (json['ne'] as num?)?.toInt(),
      status: json['st'] as String?,
      episodes: (json['t'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        if (airingAt != null)
          'na': airingAt!.toUtc().millisecondsSinceEpoch ~/ 1000,
        if (episode != null) 'ne': episode,
        if (status != null) 'st': status,
        if (episodes != null) 't': episodes,
      };
}

/// Lazily-loaded read-only index over `assets/animex_meta.json`.
///
/// Lookups are synchronous once loaded so widgets can read an accent colour
/// during build without any plumbing. Loading is kicked off during startup and
/// deliberately does not block the first frame; until it lands every accessor
/// degrades to a neutral value rather than throwing.
class AnimeXService {
  static final AnimeXService i = AnimeXService._();

  AnimeXService._();

  static const String assetPath = 'assets/animex_meta.json';

  Map<int, AnimeXMeta>? _byMalId;
  Future<void>? _inFlight;

  bool get isReady => _byMalId != null;

  /// Number of indexed titles, or 0 before the asset has loaded.
  int get count => _byMalId?.length ?? 0;

  Future<void> ensureLoaded() {
    return _inFlight ??= _load();
  }

  Future<void> _load() async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final out = parse(raw);
      _byMalId = out;
      logDal('AnimeX: indexed ${out.length} titles');
    } catch (e) {
      // Never fatal. The whole feature is an enhancement; the app has to keep
      // working if the asset is missing or malformed.
      logDal('AnimeX: asset load failed, continuing without it -> $e');
    }
  }

  /// Parses the flat `{malId: {...}}` asset into an index.
  ///
  /// Split out from [_load] so tests can run the real asset off disk instead of
  /// stubbing the bundle. A row whose key is not a number, or whose value is not
  /// an object, is skipped rather than thrown on: one malformed entry must not
  /// cost the other nineteen thousand.
  @visibleForTesting
  static Map<int, AnimeXMeta> parse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('AnimeX asset must be a JSON object');
    }
    final out = <int, AnimeXMeta>{};
    decoded.forEach((key, value) {
      final id = key is int ? key : int.tryParse('$key');
      if (id != null && value is Map) {
        out[id] = AnimeXMeta.fromJson(value);
      }
    });
    return out;
  }

  /// Loads [raw] into this instance. Test-only; production goes through
  /// [ensureLoaded] and the asset bundle.
  @visibleForTesting
  void debugLoadFromString(String raw) => _byMalId = parse(raw);

  /// Raw record for [malId], or null if unknown.
  AnimeXMeta? metaOf(int? malId) {
    if (malId == null) return null;
    return _byMalId?[malId];
  }

  /// Runtime overrides, keyed by MAL id. Empty until a fetch lands.
  final Map<int, AnimeXAiring> _live = {};

  /// Called after [applyLive]/[mergeLive] change the overlay.
  ///
  /// Anything that cached a value derived from the overlay (a schedule
  /// projection, a fetched row) registers here instead of guessing when to
  /// re-read it. Registration lives outside the service so a derived cache does
  /// not have to poll.
  static final List<VoidCallback> onOverlayChanged = [];

  /// Fires [onOverlayChanged] after every overlay change. A listener that
  /// throws must not take the overlay down with it.
  void _notifyOverlayChanged() {
    for (final cb in onOverlayChanged) {
      try {
        cb();
      } catch (_) {
        // A broken listener is that listener's problem; the overlay is right.
      }
    }
  }

  /// Bumped on every overlay change so a derived cache can notice without a
  /// callback. Callers compare it to the version they last derived against.
  int _liveVersion = 0;

  /// How many titles are currently running on live data rather than the asset.
  /// Only ever read for logging and tests; the UI must not branch on it.
  int get liveCount => _live.length;

  /// The live reading for [malId], or null when the asset is still the only
  /// source. A live reading saying "nothing scheduled" is still a reading.
  AnimeXAiring? liveAiringOf(int? malId) {
    if (malId == null) return null;
    return _live[malId];
  }

  /// The overlay itself, for callers that need to fold it into another
  /// projection (see `DalApi.scheduleForMalIdsSync`). Read-only by convention.
  Map<int, AnimeXAiring> get liveRows => _live;

  /// Version of [liveRows]. Any change -- hydrate, merge, clear -- bumps it.
  int get liveVersion => _liveVersion;

  /// Replaces the whole overlay. Used when hydrating from the on-disk cache,
  /// which is itself the complete overlay; tests use it to reset state.
  void applyLive(Map<int, AnimeXAiring> rows) {
    _live
      ..clear()
      ..addAll(rows);
    _liveVersion++;
    _notifyOverlayChanged();
  }

  /// Folds a freshly fetched page into the overlay. Merging rather than
  /// replacing means a request that failed halfway leaves the titles it did not
  /// reach on their previous reading instead of silently reverting them to a
  /// snapshot that may be weeks older.
  void mergeLive(Map<int, AnimeXAiring> rows) {
    _live.addAll(rows);
    _liveVersion++;
    _notifyOverlayChanged();
  }

  /// MAL ids worth asking AniList about: the ones that carry an anchor, plus
  /// everything still airing. `tool/sync_animex_airing.py` narrows the bundled
  /// asset with this same rule, so the snapshot and the refresh agree on what
  /// "scheduled" means.
  List<int> get scheduledIds {
    final ids = <int>{};
    for (final entry in (_byMalId ?? const <int, AnimeXMeta>{}).entries) {
      final meta = entry.value;
      if (meta.nextAiringAt != null || meta.status == 'RELEASING') {
        ids.add(entry.key);
      }
    }
    return ids.toList()..sort();
  }

  /// Accent colour for [malId]. Never null.
  ///
  /// 90% of titles carry a real dominant colour; the remaining 10% get a stable
  /// colour derived from the id instead. That fallback is the whole reason this
  /// can be applied to every card: a title never falls back to flat grey, so
  /// the grid stays visually consistent rather than showing a grid of holes.
  /// 47 is coprime with 360, which spreads consecutive ids across the hue wheel
  /// instead of walking through it in visible steps.
  Color accentOf(int? malId) {
    final real = metaOf(malId)?.color;
    if (real != null) {
      return Color(0xFF000000 | (real & 0xFFFFFF));
    }
    final id = malId ?? 0;
    final hue = ((id * 47) % 360).toDouble();
    return HSLColor.fromAHSL(1, hue, 0.42, 0.52).toColor();
  }

  /// True when [accentOf] used a real colour rather than the derived fallback.
  /// Lets a surface opt out of synthetic colours if it ever needs to.
  bool hasRealAccent(int? malId) => metaOf(malId)?.color != null;

  /// How many weekly slots a frozen reading is projected forward.
  ///
  /// AniList hands over a single upcoming broadcast, not a schedule, so the only
  /// way to keep a countdown alive with no network is to assume the same weekly
  /// slot repeats. That assumption holds for a healthy weekly run and breaks the
  /// moment the show takes a break, ends, or shifts its slot -- and a broken
  /// assumption invents both a date and an episode number, which is worse than
  /// showing nothing. So it is bounded to three weeks, and a live reading (see
  /// [mergeLive]) always wins over it. Past the bound the honest answer is "I do
  /// not know".
  static const int _maxProjectionWeeks = 3;

  static const String _finished = 'FINISHED';
  static const String _cancelled = 'CANCELLED';

  /// Compact airing label such as `EP 1181 · 3d 4h`, or null when this title has
  /// no schedule we can still stand behind.
  ///
  /// Null is the honest answer in five cases: the title has no airing data, it
  /// has a broadcast time but no episode number to pair with it, the show is
  /// finished or cancelled, projecting the weekly slot forward would run past
  /// the announced last episode, or the bundled snapshot is too old to
  /// extrapolate from. Callers fall back to MAL's weekly `broadcast` string on
  /// null, which is vague but never wrong -- a frozen "EP 1180" that stopped
  /// airing weeks ago is strictly worse than vague.
  ///
  /// A live reading outranks the asset completely, including when it reports no
  /// upcoming episode: that is AniList saying the run is over, and falling back
  /// to the bundled anchor there would resurrect the episode that just aired.
  String? nextAiringLabel(int? malId, {DateTime? now}) {
    final live = liveAiringOf(malId);
    final meta = metaOf(malId);

    if (live != null && !live.hasNextEpisode) return null;

    final anchor = live?.airingAt ?? meta?.nextAiringAt;
    final episode = live?.episode ?? meta?.nextEpisode;
    if (anchor == null || episode == null) return null;

    final status = live?.status ?? meta?.status;
    if (status == _finished || status == _cancelled) return null;

    // A live episode number is AniList's own reading, so it is taken as given
    // even when it disagrees with the announced total -- some entries number
    // episodes continuously across cours, and "correcting" that would hide a
    // real countdown. The total is only used below, on a number this code
    // invented itself.
    final total = live?.episodes;

    final ref = now ?? DateTime.now();
    // Project in UTC so a DST boundary in the device's locale cannot slide the
    // slot by an hour; only the relative countdown is ever shown.
    var slot = anchor.toUtc();
    var ep = episode;
    var weeks = 0;
    while (!slot.isAfter(ref) && weeks < _maxProjectionWeeks) {
      slot = slot.add(const Duration(days: 7));
      ep++;
      weeks++;
    }
    if (!slot.isAfter(ref)) return null;
    // Only a projected number is held to the announced run: with weeks == 0 the
    // episode is AniList's own reading and is left alone (see above).
    if (weeks > 0 && total != null && ep > total) return null;

    final remaining = slot.difference(ref);
    final days = remaining.inDays;
    final hours = remaining.inHours % 24;
    final minutes = remaining.inMinutes % 60;

    final buf = StringBuffer('EP $ep');
    if (days > 0) {
      buf.write(' · ${days}d');
      if (hours > 0) buf.write(' ${hours}h');
    } else if (hours > 0) {
      buf.write(' · ${hours}h');
      if (minutes > 0) buf.write(' ${minutes}m');
    } else {
      buf.write(' · ${minutes}m');
    }
    return buf.toString();
  }
}
