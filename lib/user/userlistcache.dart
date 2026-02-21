import 'dart:collection';

import 'package:dal_commons/dal_commons.dart';

class UserListCache {
  static final Map<int, String> animeStatusCache = HashMap();
  static final Map<int, String> mangaStatusCache = HashMap();

  static void updateCache(List<BaseNode> nodes, String category) {
    var cache = category == 'anime' ? animeStatusCache : mangaStatusCache;
    for (var baseNode in nodes) {
      final node = baseNode.content;
      int? id;
      try {
        id = node?.id;
      } catch (e) {}

      if (id != null && baseNode.myListStatus != null) {
        dynamic statusObj = baseNode.myListStatus;
        if (statusObj is MyAnimeListStatus) {
          if (statusObj.status != null) {
            cache[id] = statusObj.status!;
          }
        } else if (statusObj is MyMangaListStatus) {
          if (statusObj.status != null) {
            cache[id] = statusObj.status!;
          }
        } else {
          try {
            if (statusObj?.status != null) {
              cache[id] = statusObj.status.toString();
            }
          } catch (e) {}
        }
      }
    }
  }

  static String? getStatus(int? id, String category) {
    if (id == null) return null;
    var cache = category == 'anime' ? animeStatusCache : mangaStatusCache;
    return cache[id];
  }
}
