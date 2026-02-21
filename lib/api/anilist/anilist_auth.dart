import 'dart:convert';
import 'dart:io';

import 'package:dailyanimelist/api/anilist/anilist_models.dart';
import 'package:dailyanimelist/api/anilist/anilist_service.dart';
import 'package:dailyanimelist/main.dart';
import 'package:dailyanimelist/widgets/web/c_webview.dart';
import 'package:dal_commons/dal_commons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

/// AniList implicit grant OAuth (Client ID: 36293).
class AniListAuth {
  static const _clientId = '36293';
  static const _storageKeyToken = 'anilist_token';
  static const _storageKeyUser = 'anilist_user';

  static String get _authorizeUrl =>
      'https://anilist.co/api/v2/oauth/authorize?client_id=$_clientId&response_type=token';

  /// Open AniList authorize page. On desktop uses FlutterWebAuth2; on mobile
  /// opens a Custom Tab / browser. The token is extracted from the redirect
  /// URI fragment (#access_token=...).
  static Future<void> handleSignIn() async {
    try {
      if (!kIsWeb &&
          (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
        // Desktop: FlutterWebAuth2 with localhost callback
        final result = await FlutterWebAuth2.authenticate(
          url: _authorizeUrl,
          callbackUrlScheme: 'com.teen.dailyanimelist',
          options: const FlutterWebAuth2Options(useWebview: false),
        );
        final uri = Uri.parse(result);
        await checkIfSignIn(uri);
      } else {
        // Mobile: custom tab – token comes back via deep link handled in pathutils
        launchWebView(_authorizeUrl);
      }
    } catch (e) {
      logDal('AniList OAuth error: $e');
    }
  }

  /// Try to extract the access_token from a URI fragment.
  /// Returns true if a token was successfully handled.
  static Future<bool> checkIfSignIn(Uri uri) async {
    // The implicit grant puts the token in the fragment: #access_token=TOKEN&...
    String? token;

    // Check fragment first
    if (uri.fragment.isNotEmpty) {
      final fragmentParams = Uri.splitQueryString(uri.fragment);
      token = fragmentParams['access_token'];
    }

    // Some platforms may deliver via query params instead
    token ??= uri.queryParameters['access_token'];

    if (token != null && token.isNotEmpty) {
      await onTokenReceived(token);
      return true;
    }
    return false;
  }

  /// Store token, fetch Viewer profile, persist user, notify listeners.
  static Future<void> onTokenReceived(String token) async {
    final ss = FlutterSecureStorage();
    await ss.write(key: _storageKeyToken, value: token);

    // Store in memory
    user.anilistToken = token;

    // Fetch viewer profile
    try {
      final viewer = await AniListService.getViewer(token);
      if (viewer != null) {
        user.anilistUser = viewer;
        await ss.write(
            key: _storageKeyUser, value: jsonEncode(viewer.toJson()));
      }
    } catch (e) {
      logDal('AniList getViewer error: $e');
    }

    await user.setIntance(updateAuth: false);
    user.updateUserStatus();
  }

  /// Clear AniList token + user from storage and memory.
  static Future<void> signOut() async {
    final ss = FlutterSecureStorage();
    await ss.delete(key: _storageKeyToken);
    await ss.delete(key: _storageKeyUser);
    user.anilistToken = null;
    user.anilistUser = null;
    await user.setIntance(updateAuth: false);
    user.updateUserStatus();
  }

  /// Read saved AniList token and user from secure storage (called on app start).
  static Future<void> loadFromStorage() async {
    final ss = FlutterSecureStorage();
    user.anilistToken = await ss.read(key: _storageKeyToken);
    final userJson = await ss.read(key: _storageKeyUser);
    if (userJson != null) {
      try {
        user.anilistUser = AniListUser.fromJson(jsonDecode(userJson));
      } catch (e) {
        logDal('AniList loadFromStorage error: $e');
      }
    }
  }
}
