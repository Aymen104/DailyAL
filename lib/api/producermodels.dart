class ProducerV4 {
  final int? malId;
  final String? url;
  final String? name;
  final String? japaneseName;
  final String? established;
  final String? about;
  final int? favorites;
  final int? count;
  final String? imageUrl;
  final List<ProducerExternal>? external;

  ProducerV4({
    this.malId,
    this.url,
    this.name,
    this.japaneseName,
    this.established,
    this.about,
    this.favorites,
    this.count,
    this.imageUrl,
    this.external,
  });

  factory ProducerV4.fromJson(Map<String, dynamic>? json) {
    if (json == null) return ProducerV4();
    String? defaultName;
    String? japaneseName;
    if (json["titles"] is List) {
      for (final t in json["titles"] as List) {
        if (t is Map<String, dynamic>) {
          final type = t["type"];
          final title = t["title"];
          if (type == "Default" && defaultName == null) defaultName = title;
          if (type == "Japanese" && japaneseName == null) japaneseName = title;
        }
      }
    }
    String? imageUrl;
    final images = json["images"];
    if (images is Map<String, dynamic>) {
      final jpg = images["jpg"];
      if (jpg is Map<String, dynamic>) {
        imageUrl = jpg["image_url"];
      }
    }
    return ProducerV4(
      malId: json["mal_id"],
      url: json["url"],
      name: defaultName ?? json["name"],
      japaneseName: japaneseName,
      established: json["established"],
      about: json["about"],
      favorites: json["favorites"],
      count: json["count"],
      imageUrl: imageUrl,
      external: json["external"] is List
          ? (json["external"] as List)
              .whereType<Map<String, dynamic>>()
              .map((e) => ProducerExternal.fromJson(e))
              .toList()
          : null,
    );
  }
}

class ProducerExternal {
  final String? name;
  final String? url;

  ProducerExternal({this.name, this.url});

  factory ProducerExternal.fromJson(Map<String, dynamic>? json) {
    if (json == null) return ProducerExternal();
    return ProducerExternal(
      name: json["name"],
      url: json["url"],
    );
  }
}