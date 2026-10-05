@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dailyanimelist/api/auth/authresp.dart';
import 'package:dailyanimelist/api/malconnect.dart';
import 'package:dailyanimelist/main.dart';
import 'package:dailyanimelist/theme/theme.dart';
import 'package:dailyanimelist/user/user.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Live test against MAL's real token endpoint.
///
/// Skipped unless `RUN_LIVE_TESTS=1`, because the whole rest of this suite is
/// offline and CI must not depend on the network. Run it deliberately:
///
///     $env:RUN_LIVE_TESTS=1; flutter test test\auth_token_live_test.dart
///
/// (The `live` tag in dart_test.yaml only sets a timeout. A `skip:` rule there
/// would apply unconditionally and win over `--tags live`, so the gate lives here,
/// in the suite, where it can be inverted by the environment.)
///
/// It exists because the expired-token branch of `authorizationHeader` cannot be
/// observed any other way: an expired session is the *only* thing that triggers a
/// refresh, and a refresh is the only thing that used to destroy a working
/// credential. Offline, that branch is either mocked (proving nothing about the
/// real rejection shape) or left untested - and leaving it untested is how the
/// original bug shipped.
class _MemorySecureStorage extends FlutterSecureStoragePlatform {
  _MemorySecureStorage(this.data);
  final Map<String, String> data;

  @override
  Future<String?> read(
          {required String key, required Map<String, String> options}) async =>
      data[key];

  @override
  Future<void> write({required String key, required String value,
      required Map<String, String> options}) async =>
      data[key] = value;

  @override
  Future<void> delete(
          {required String key, required Map<String, String> options}) async =>
      data.remove(key);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      data.clear();

  @override
  Future<bool> containsKey(
          {required String key, required Map<String, String> options}) async =>
      data.containsKey(key);

  @override
  Future<Map<String, String>> readAll(
          {required Map<String, String> options}) async =>
      data;
}

void main() {
  // The `live` tag in dart_test.yaml is what keeps this out of a default run; the
  // env var is a convenience for running this one file directly.
  final runLive = Platform.environment['RUN_LIVE_TESTS'] == '1';

  test('a rejected refresh ends the session instead of poisoning it', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final ss = _MemorySecureStorage({});
    FlutterSecureStoragePlatform.instance = ss;

    // TestWidgetsFlutterBinding installs an HttpOverrides that answers every
    // request with a synthetic 400 and never opens a socket. Left in place this
    // test would "verify" the rejection path against a response MAL never sent -
    // green while proving nothing, which is worse than no test. Clearing it makes
    // the call below hit MAL for real.
    HttpOverrides.global = null;

    // Real client credentials, so MAL rejects on the refresh token (which is the
    // path under test) rather than on the client id.
    try {
      await dotenv.load(fileName: 'assets/n8TN5qDG22PAuP50Il');
    } catch (_) {
      // Falls back to the literal 'null' client id. MAL still rejects, which is
      // the behaviour under test.
    }

    // A session that was working: real-shaped token, issued two hours ago with a
    // one hour life, so the next request must renew it.
    final working = AuthResponse(
      accessToken: 'access-token-that-was-working',
      tokenType: 'Bearer',
      refreshToken: 'definitely-not-a-valid-refresh-token',
      expiresIn: 3600,
      createdTime: DateTime.now().subtract(const Duration(hours: 2)),
    );

    user = User.fromJson(jsonDecode(jsonEncode({
      'auth_status': AuthStatus.AUTHENTICATED.index,
      'preferences': {},
      'theme_v3': UserTheme.defaultTheme().toJson(),
    })));
    user.authResponse = working;
    user.status = AuthStatus.AUTHENTICATED;

    String? header;
    Object? thrown;
    try {
      header = await MalConnect.authorizationHeader();
    } catch (e) {
      thrown = e;
    }

    expect(thrown, isNull,
        reason: 'an expired session must degrade, never throw');
    expect(header, isNull,
        reason: 'a rejected refresh yields no usable credential to sign with');

    expect(user.status, AuthStatus.UNAUTHENTICATED,
        reason: 'the UI must be able to recover by asking the user to sign in');

    expect(user.authResponse?.accessToken, isNot('access-token-that-was-working'),
        reason: 'the dead credential must not be left in place');

    // The decisive one: whatever landed in secure storage must not read back as
    // a live credential. This is the exact state that made every later write
    // throw. `setIntance` writes `jsonEncode(authResponse)`, which for a cleared
    // field is the literal "null", so the read side has to tolerate that - it goes
    // through `AuthResponse.fromJson`, which maps null to an empty response.
    final persisted = ss.data['authResponse'];
    expect(persisted, isNotNull,
        reason: 'the dead credential must not still be on disk');

    final restored = jsonDecode(persisted!) as Map<String, dynamic>?;
    expect(
      AuthResponse.fromJson(restored).isUsable,
      isFalse,
      reason: 'storage must not hold a phantom credential flagged as usable',
    );

    // And a restart must not resurrect the session: restoring from that stored
    // value has to agree that nobody is signed in.
    expect(User.resolvePersistedStatus(AuthStatus.AUTHENTICATED,
            AuthResponse.fromJson(restored)),
        AuthStatus.UNAUTHENTICATED);
  }, skip: runLive ? false : 'set RUN_LIVE_TESTS=1 to hit MAL for real');
}
