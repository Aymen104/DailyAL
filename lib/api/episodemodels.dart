class EpisodeV4 {
  final int? malId;
  final String? title;
  final String? titleJapanese;
  final String? titleRomanji;
  final String? duration;
  final String? aired;
  final double? score;
  final bool filler;
  final bool recap;
  final String? synopsis;
  final String? forumUrl;
  final int? replies;

  EpisodeV4({
    this.malId,
    this.title,
    this.titleJapanese,
    this.titleRomanji,
    this.duration,
    this.aired,
    this.score,
    this.filler = false,
    this.recap = false,
    this.synopsis,
    this.forumUrl,
    this.replies,
  });

  factory EpisodeV4.fromJson(Map<String, dynamic>? json) {
    if (json == null) return EpisodeV4();
    return EpisodeV4(
      malId: json["mal_id"],
      title: json["title"],
      titleJapanese: json["title_japanese"],
      titleRomanji: json["title_romanji"],
      duration: json["duration"],
      aired: json["aired"],
      score: (json["score"] as num?)?.toDouble(),
      filler: json["filler"] == true,
      recap: json["recap"] == true,
      synopsis: json["synopsis"],
      forumUrl: json["forum_url"],
      replies: json["replies"],
    );
  }
}

class AnimeEpisodesResult {
  final List<EpisodeV4> items;
  final bool hasNext;

  const AnimeEpisodesResult({this.items = const [], this.hasNext = false});

  factory AnimeEpisodesResult.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AnimeEpisodesResult();
    final data = (json["data"] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map((e) => EpisodeV4.fromJson(e))
        .toList();
    final pagination = json["pagination"] as Map<String, dynamic>?;
    return AnimeEpisodesResult(
      items: data,
      hasNext: pagination?["has_next_page"] == true,
    );
  }
}