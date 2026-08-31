import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Lightweight store for the user's MAL *website* credentials so the favorite
/// toggle overlay can auto-submit its login form (the form requires the site
/// password directly; the app OAuth token is separate).
///
/// Only used when the user opts into auto-login during the favorite overlay.
/// Stored with [FlutterSecureStorage] (encrypted at rest).
class MalSiteCredentials {
  final String username;
  final String password;
  const MalSiteCredentials(this.username, this.password);

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _userKey = 'mal_site_username';
  static const String _passKey = 'mal_site_password';

  static Future<void> save(String username, String password) async {
    await _storage.write(key: _userKey, value: username);
    await _storage.write(key: _passKey, value: password);
  }

  static Future<MalSiteCredentials?> load() async {
    try {
      final u = await _storage.read(key: _userKey);
      final p = await _storage.read(key: _passKey);
      if (u == null || u.isEmpty || p == null || p.isEmpty) return null;
      return MalSiteCredentials(u, p);
    } catch (e) {
      return null;
    }
  }

  static Future<bool> has() async => (await load()) != null;

  static Future<void> clear() async {
    await _storage.delete(key: _userKey);
    await _storage.delete(key: _passKey);
  }
}