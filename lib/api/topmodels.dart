class TopRankedItem {
  final int id;
  final int rank;
  final String? name;
  final String? animeTitle;
  final String? imageUrl;
  final int? favorites;

  TopRankedItem({
    required this.id,
    required this.rank,
    this.name,
    this.animeTitle,
    this.imageUrl,
    this.favorites,
  });

  factory TopRankedItem.fromJson(Map<String, dynamic>? json,
      {required int rank}) {
    if (json == null) return TopRankedItem(id: 0, rank: rank);
    String? imageUrl;
    final images = json["images"];
    if (images is Map<String, dynamic>) {
      final jpg = images["jpg"];
      if (jpg is Map<String, dynamic>) imageUrl = jpg["image_url"];
    }
    final animeList = json["anime"];
    String? animeTitle;
    if (animeList is List && animeList.isNotEmpty) {
      final first = animeList.first;
      if (first is Map<String, dynamic>) {
        animeTitle = first["name"] ?? first["title"];
      }
    }
    return TopRankedItem(
      id: json["mal_id"] ?? 0,
      rank: rank,
      name: json["name"] ?? json["title"],
      animeTitle: animeTitle,
      imageUrl: imageUrl,
      favorites: (json["favorites"] as num?)?.toInt(),
    );
  }
}

class TopRankedPage {
  final List<TopRankedItem> items;
  final bool hasNext;

  const TopRankedPage({this.items = const [], this.hasNext = false});
}