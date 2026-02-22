import 'dart:collection';
import 'dart:convert';

import 'package:dal_commons/dal_commons.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserListCache {
  static final Map<int, String> animeStatusCache = HashMap();
  static final Map<int, String> mangaStatusCache = HashMap();

  static Future<void> loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final animeJson = prefs.getString('anime_status_cache');
      final mangaJson = prefs.getString('manga_status_cache');

      if (animeJson != null) {
        final Map<String, dynamic> animeData = jsonDecode(animeJson);
        animeStatusCache.clear();
        animeData.forEach((key, value) {
          animeStatusCache[int.parse(key)] = value.toString();
        });
      }

      if (mangaJson != null) {
        final Map<String, dynamic> mangaData = jsonDecode(mangaJson);
        mangaStatusCache.clear();
        mangaData.forEach((key, value) {
          mangaStatusCache[int.parse(key)] = value.toString();
        });
      }
    } catch (e) {
      // Fail silently
    }
  }

  static Future<void> _saveCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final animeData = <String, String>{};
      animeStatusCache.forEach((key, value) {
        animeData[key.toString()] = value;
      });
      await prefs.setString('anime_status_cache', jsonEncode(animeData));

      final mangaData = <String, String>{};
      mangaStatusCache.forEach((key, value) {
        mangaData[key.toString()] = value;
      });
      await prefs.setString('manga_status_cache', jsonEncode(mangaData));
    } catch (e) {
      // Fail silently
    }
  }

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
    _saveCache();
  }

  static String? getStatus(int? id, String category) {
    if (id == null) return null;
    var cache = category == 'anime' ? animeStatusCache : mangaStatusCache;
    return cache[id];
  }
}
