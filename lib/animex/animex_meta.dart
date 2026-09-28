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

  /// Exact next broadcast time. Present only for currently-airing titles
  /// (~125 of them), which is the point: it is the only precise airing data
  /// the app can get, since MAL only exposes a weekly `broadcast` string.
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
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final out = <int, AnimeXMeta>{};
      decoded.forEach((key, value) {
        final id = int.tryParse(key);
        if (id != null && value is Map) {
          out[id] = AnimeXMeta.fromJson(value);
        }
      });
      _byMalId = out;
      logDal('AnimeX: indexed ${out.length} titles');
    } catch (e) {
      // Never fatal. The whole feature is an enhancement; the app has to keep
      // working if the asset is missing or malformed.
      logDal('AnimeX: asset load failed, continuing without it -> $e');
    }
  }

  /// Raw record for [malId], or null if unknown.
  AnimeXMeta? metaOf(int? malId) {
    if (malId == null) return null;
    return _byMalId?[malId];
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

  /// How many weeks ahead a bundled airing slot is trusted before giving up.
  ///
  /// AniList hands over a single upcoming broadcast, not a schedule, and the
  /// asset is frozen into the APK at build time -- so an installed build can
  /// never learn that the episode it names has since aired. Projecting the
  /// weekly slot forward keeps the countdown self-correcting with no network
  /// access, but an irregular slot (hiatus, split cour, a one-off delay) would
  /// let it drift, so the projection is bounded and past the bound the honest
  /// answer is "I do not know".
  static const int _maxProjectionWeeks = 6;

  /// Compact airing label such as `EP 1180 · 3d 4h`, or null when this title has
  /// no schedule we can still stand behind.
  ///
  /// Null is the honest answer in three cases: the title has no airing data, it
  /// has a broadcast time but no episode number to pair with it, or the bundled
  /// snapshot is too old to extrapolate from. Callers fall back to MAL's weekly
  /// `broadcast` string on null, which is vague but not wrong -- a frozen
  /// "EP 1180" that stopped three weeks ago is strictly worse than vague.
  String? nextAiringLabel(int? malId, {DateTime? now}) {
    final m = metaOf(malId);
    final anchor = m?.nextAiringAt;
    final episode = m?.nextEpisode;
    if (anchor == null || episode == null) return null;

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
