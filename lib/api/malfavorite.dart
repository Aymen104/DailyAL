import 'dart:convert';

import 'package:dailyanimelist/api/jikahelper.dart';
import 'package:dailyanimelist/api/maluser.dart';
import 'package:dailyanimelist/cache/cachemanager.dart';
import 'package:dailyanimelist/main.dart';
import 'package:dailyanimelist/user/user.dart';
import 'package:dailyanimelist/widgets/web/mal_toggle_overlay.dart';
import 'package:dal_commons/dal_commons.dart';

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
/// The website uses an internal endpoint that requires the site session cookie
/// (HttpOnly, not readable from Dart) plus a fresh Google reCAPTCHA v3 token —
/// the official OAuth v2 API does not expose favorites. The actual request is
/// therefore performed inside a WebView on the myanimelist.net origin (see
/// [MalToggleOverlay]), reusing the shared cookie jar.
class MalFavorite {
  static const String _loginKey = 'mal_site_login';

  /// Whether the user has gone through the MAL site sign-in at least once.
  /// The WebView cookie jar itself is the real auth; this is only a UI hint to
  /// skip the login screen when a session is already established.
  static Future<bool> hasSiteLogin() async {
    try {
      final value = await CacheManager.instance.getValue(_loginKey);
      return value == '1';
    } catch (_) {
      return false;
    }
  }

  static Future<void> setSiteLogin(bool on) async {
    try {
      await CacheManager.instance.setValue(_loginKey, on ? '1' : '');
    } catch (_) {}
  }

  static Future<String?> currentUsername() async {
    try {
      if (user.status != AuthStatus.AUTHENTICATED) return null;
      final prof = await MalUser.getUserInfo(fromCache: true);
      return prof.name;
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

  /// Maps the outcome of the in-WebView toggle request to a friendly result.
  static MalFavResult fromOutcome(
    MalToggleOutcome outcome, {
    required bool wasAdded,
  }) {
    final status = outcome.status;
    if (status == 200 || status == 201) {
      return MalFavResult(ok: true, wasAdded: wasAdded);
    }
    if (outcome.looksLikeLoginPage || status == 401) {
      return const MalFavResult(
        needsAuth: true,
        message: 'Sign in to MyAnimeList first.',
      );
    }
    if (status == 400) {
      return _maxFavsError(outcome.body);
    }
    if (status == 0) {
      return const MalFavResult(message: "Couldn't connect to MyAnimeList.");
    }
    return MalFavResult(message: _serverMessage(outcome.body));
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