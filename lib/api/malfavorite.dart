import 'dart:convert';

import 'package:dailyanimelist/api/credmal.dart';
import 'package:dailyanimelist/api/jikahelper.dart';
import 'package:dailyanimelist/api/maluser.dart';
import 'package:dailyanimelist/cache/cachemanager.dart';
import 'package:dailyanimelist/constant.dart';
import 'package:dailyanimelist/main.dart';
import 'package:dailyanimelist/user/user.dart';
import 'package:http/http.dart' as http;

class MalFavResult {
  final bool ok;
  final bool needsAuth;
  final String? message;
  final bool wasAdded;
  const MalFavResult({
    this.ok = false,
    this.needsAuth = false,
    this.message,
    this.wasAdded = false,
  });
}

/// Syncs "likes" (favorites) with a real MyAnimeList account, exactly like the
/// MAL website "Add to Favorites" button.
///
/// The website uses an internal endpoint that requires a site session cookie
/// (`MALCF`) plus a fresh Google reCAPTCHA v3 token — the official OAuth v2
/// API does not expose favorites, so this taps into the same mechanism the
/// website's `#v-favorite` Vue component uses.
class MalFavorite {
  static const String cookieKey = 'mal_site_cookie';
  static String? _cachedCookie;

  static Future<String?> getSessionCookie() async {
    if (_cachedCookie != null && _cachedCookie!.isNotEmpty) {
      return _cachedCookie;
    }
    try {
      final value = await CacheManager.instance.getValue(cookieKey);
      _cachedCookie = (value == null || value.isEmpty) ? null : value;
    } catch (_) {
      _cachedCookie = null;
    }
    return _cachedCookie;
  }

  static Future<void> storeSessionCookie(String? cookie) async {
    _cachedCookie = (cookie == null || cookie.isEmpty) ? null : cookie;
    try {
      await CacheManager.instance.setValue(cookieKey, cookie ?? '');
    } catch (_) {}
  }

  static Future<void> clearSessionCookie() => storeSessionCookie(null);

  static Future<String?> currentUsername() async {
    try {
      if (user.status != AuthStatus.AUTHENTICATED) return null;
      final prof = await MalUser.getUserInfo(fromCache: true);
      return prof?.name;
    } catch (_) {
      return null;
    }
  }

  /// Whether this user already has [id] (of `character`/`people`) in their
  /// MAL favorites. Reads through the Tenrai/Jikan mirror of the profile.
  static Future<bool> isFavorited(String type, int id) async {
    final username = await currentUsername();
    if (username == null || username.isEmpty) return false;
    try {
      final favs = await JikanHelper.getUserFavorites(username);
      if (type == 'people') {
        return favs.people?.any((p) => p.malId == id) ?? false;
      }
      return favs.characters?.any((c) => c.malId == id) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Calls `POST`/`DELETE https://myanimelist.net/favorite/{type}/{id}.json`
  /// — the same endpoint the website's toggle hits.
  static Future<MalFavResult> call({
    required String type,
    required int id,
    required bool add,
    required String token,
  }) async {
    final cookie = await getSessionCookie();
    if (cookie == null || cookie.isEmpty) {
      return const MalFavResult(
        needsAuth: true,
        message: 'Sign in to MyAnimeList first.',
      );
    }
    final pageUrl =
        '${CredMal.htmlEnd}${type == 'people' ? 'people' : 'character'}/$id';
    final headers = <String, String>{
      'Accept': 'application/json',
      'Cookie': cookie,
      'Referer': pageUrl,
      'Origin': 'https://myanimelist.net',
    };
    final body = <String, String>{'g-recaptcha-response': token};
    final url = '${CredMal.htmlEnd}favorite/$type/$id.json';
    try {
      final http.Response response = add
          ? await http.post(Uri.parse(url), headers: headers, body: body)
          : await http.delete(Uri.parse(url), headers: headers, body: body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return MalFavResult(ok: true, wasAdded: add);
      }
      if (response.statusCode == 400) {
        return _maxFavsError(response.body);
      }
      if (response.statusCode == 401) {
        await clearSessionCookie();
        return const MalFavResult(
          needsAuth: true,
          message: 'Your MyAnimeList session expired. Please sign in again.',
        );
      }
      return MalFavResult(message: _serverMessage(response.body));
    } catch (e) {
      logDal(e);
      return const MalFavResult(message: "Couldn't connect to MyAnimeList.");
    }
  }

  static MalFavResult _maxFavsError(String body) {
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      final max = j['max_favs'];
      if (j['is_supporter'] == true) {
        return MalFavResult(
            message: 'Only a maximum of $max favorites allowed.');
      }
      return MalFavResult(
        message:
            'Only a maximum of $max favorites allowed. Become a MAL Supporter to double it!',
      );
    } catch (_) {
      return const MalFavResult(message: "Couldn't add to favorites.");
    }
  }

  static String _serverMessage(String body) {
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      final errors = j['errors'];
      if (errors is List && errors.isNotEmpty && errors[0] is Map) {
        final first = errors[0] as Map;
        if (first['message'] != null) return first['message'] as String;
      }
    } catch (_) {}
    return "Couldn't update favorites.";
  }
}