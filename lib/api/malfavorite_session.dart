import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Stores the myanimelist.net website session in secure storage so the
/// favorites overlay can seed its WebView and toggle favorites without ever
/// showing a login screen.
///
/// The favorite toggle needs the site session cookie (HttpOnly, unreadable
/// from Dart) plus a fresh reCAPTCHA token. When the user logs in once — via
/// the in-app OAuth WebView or the overlay's own login page — the session is
/// captured from the shared WebView cookie jar, persisted here, and re-applied
/// on the next favorite tap.
class MalSessionStore {
  MalSessionStore._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  /// Session cookie list key.
  static const String key = 'mal_site_cookie';

  static Future<List<WebViewCookie>> load() async {
    try {
      final raw = await _storage.read(key: key);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(_cookieFromMap)
          .toList();
    } catch (e) {
      return const [];
    }
  }

  static Future<bool> hasSession() async => (await load()).isNotEmpty;

  static Future<void> save(List<WebViewCookie> cookies) async {
    if (cookies.isEmpty) return;
    await _storage.write(
      key: key,
      value: jsonEncode(cookies.map(_cookieToMap).toList()),
    );
  }

  static Future<void> clear() => _storage.delete(key: key);

  /// Whether [cookies] looks like a live MAL session.
  static bool _isLiveSession(List<WebViewCookie> cookies) =>
      cookies.any((c) => c.name == 'is_logged_in' && c.value == '1');

  /// Copies the current session out of the shared WebView cookie jar.
  static Future<void> captureFromWebView() async {
    try {
      final manager = WebViewCookieManager();
      final cookies = await manager.getCookies('https://myanimelist.net');
      if (!_isLiveSession(cookies)) return;
      await save(cookies);
    } catch (e) {
      // capture is best-effort; the overlay can fall back to its login page
    }
  }

  /// Seeds the shared WebView cookie jar from the stored session. Safe to run
  /// more than once — identical cookies overwrite harmlessly.
  static Future<void> applyToWebView() async {
    final cookies = await load();
    if (cookies.isEmpty) return;
    final manager = WebViewCookieManager();
    for (final cookie in cookies) {
      await manager.setCookie(
        WebViewCookie(
          name: cookie.name,
          value: cookie.value,
          domain: cookie.domain.isEmpty ? '.myanimelist.net' : cookie.domain,
          path: cookie.path.isEmpty ? '/' : cookie.path,
        ),
      );
    }
  }

  static Map<String, Object?> _cookieToMap(WebViewCookie cookie) => {
        'name': cookie.name,
        'value': cookie.value,
        'domain': cookie.domain,
        'path': cookie.path,
      };

  static WebViewCookie _cookieFromMap(Map<String, dynamic> map) => WebViewCookie(
        name: map['name'] as String? ?? '',
        value: map['value'] as String? ?? '',
        domain: map['domain'] as String? ?? '',
        path: map['path'] as String? ?? '/',
      );
}