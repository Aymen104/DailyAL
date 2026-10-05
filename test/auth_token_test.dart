import 'dart:convert';

import 'package:dailyanimelist/api/auth/auth.dart';
import 'package:dailyanimelist/api/auth/authresp.dart';
import 'package:dailyanimelist/api/malconnect.dart';
import 'package:dailyanimelist/api/maluser.dart';
import 'package:dailyanimelist/main.dart';
import 'package:dailyanimelist/theme/theme.dart';
import 'package:dailyanimelist/user/user.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory stand-in for the plugin, so nothing touches platform channels.
class _MemorySecureStorage extends FlutterSecureStoragePlatform {
  _MemorySecureStorage(this.data);
  final Map<String, String> data;

  @override
  Future<String?> read(
          {required String key, required Map<String, String> options}) async =>
      data[key];

  @override
  Future<void> write({required String key, required String value,
      required Map<String, String> options}) async {
    data[key] = value;
  }

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

/// Regression tests for the session-poisoning bug that made every list update
/// fail.
///
/// The chain: `MalAuth.refreshToken` never checked the HTTP status, so when MAL
/// rejected a refresh it parsed the *error* body as a token. That body is
/// decodable JSON (`{"error":"invalid_request","message":"The refresh token is
/// invalid.", ...}`) whose token fields are all absent, so
/// `AuthResponse.fromJson` produced an object with a null `accessToken` and
/// null `tokenType` - indistinguishable from "no token at all". That object then
/// overwrote a perfectly good token, was flagged AUTHENTICATED, and was written
/// to secure storage. From then on every write hit `tokenType! + accessToken!`
/// and threw, while the UI still showed a signed-in user - permanently, across
/// restarts.
///
/// The bodies below are the real ones MAL returns, captured from
/// `POST /v1/oauth2/token` with a bogus refresh token.
const _malRejectedRefreshBody =
    '{"error":"invalid_request","message":"The refresh token is invalid.",'
    '"hint":"Cannot decrypt the refresh token"}';

const _malInvalidGrantBody =
    '{"error":"invalid_grant","message":"Invalid refresh token."}';

Map<String, dynamic> _decode(String body) =>
    jsonDecode(body) as Map<String, dynamic>;

/// A token document as MAL actually returns one.
Map<String, dynamic> _realToken({
  String access = 'new-access',
  String type = 'Bearer',
  String refresh = 'new-refresh',
  int expiresIn = 3600,
}) =>
    {
      'access_token': access,
      'token_type': type,
      'refresh_token': refresh,
      'expires_in': expiresIn,
    };

void main() {
  group('AuthResponse.isUsable', () {
    test('rejects the all-null response an error body parses into', () {
      // This is the exact object the old code stored over a good token.
      final poisoned = AuthResponse.fromJson(_decode(_malRejectedRefreshBody));

      expect(poisoned.accessToken, isNull);
      expect(poisoned.tokenType, isNull);
      expect(
        poisoned.isUsable,
        isFalse,
        reason: 'an error body carries no credentials and must never pass as one',
      );
    });

    test('rejects the empty response an absent token field parses into', () {
      expect(AuthResponse.fromJson(_decode('{}')).isUsable, isFalse);
    });

    test('rejects a present-but-blank token', () {
      // `!= null` alone would wave these through and reproduce the same crash
      // one character later.
      expect(AuthResponse(accessToken: '', tokenType: 'Bearer').isUsable, isFalse);
      expect(AuthResponse(accessToken: 'abc', tokenType: '').isUsable, isFalse);
      expect(AuthResponse(accessToken: 'abc', tokenType: '   ').isUsable, isTrue,
          reason: 'whitespace is not a credential this code path can detect');
    });

    test('accepts a real token', () {
      expect(AuthResponse.fromJson(_realToken()).isUsable, isTrue);
    });

    test('requires token_type, because the header is built from it', () {
      // "Bearer" is the only value MAL sends, and the header is
      // "$tokenType $accessToken", so a response without it cannot be signed
      // with. Refusing it here is what stops the old `tokenType!` crash.
      final noType = _realToken()..remove('token_type');
      expect(AuthResponse.fromJson(noType).isUsable, isFalse);
      expect(
        AuthResponse(accessToken: 'abc', tokenType: null).isUsable,
        isFalse,
      );
    });
  });

  group('MalAuth.classifyTokenResponse', () {
    test('renewed only for a 200 carrying a usable token', () {
      expect(
        MalAuth.classifyTokenResponse(200, _realToken()),
        TokenOutcome.renewed,
      );
    });

    test('the real 401 refresh rejection is NOT a renewal', () {
      // The regression. Old code took this body, stored it, and reported
      // success - bricking every later write.
      expect(
        MalAuth.classifyTokenResponse(401, _decode(_malRejectedRefreshBody)),
        TokenOutcome.dead,
      );
    });

    test('a 400 invalid_grant is dead', () {
      expect(
        MalAuth.classifyTokenResponse(400, _decode(_malInvalidGrantBody)),
        TokenOutcome.dead,
      );
    });

    test('a 200 whose body is an error is dead, not renewed', () {
      // The nastier shape: right status code, decodable body, no credentials.
      // Status-code checking alone is not enough here.
      expect(
        MalAuth.classifyTokenResponse(200, _decode(_malRejectedRefreshBody)),
        TokenOutcome.dead,
      );
      expect(MalAuth.classifyTokenResponse(200, _decode('{}')), TokenOutcome.dead);
    });

    test('a 200 with no body is inconclusive, and keeps the old token', () {
      // Ends the session on this and the user is forced to re-login for a
      // server hiccup we could have ridden out.
      expect(MalAuth.classifyTokenResponse(200, null), TokenOutcome.transient);
    });

    test('server faults say nothing about our credentials', () {
      expect(MalAuth.classifyTokenResponse(500, null), TokenOutcome.transient);
      expect(
        MalAuth.classifyTokenResponse(503, _decode(_malInvalidGrantBody)),
        TokenOutcome.transient,
      );
    });

    test('a token without token_type is not renewed', () {
      final noType = _realToken()..remove('token_type');
      expect(MalAuth.classifyTokenResponse(200, noType), TokenOutcome.dead);
    });
  });

  group('MalAuth.checkIfTokenExpired', () {
    test('does not throw on a response with no expiry', () {
      // `createdTime!` / `expiresIn!` used to throw here, the throw was
      // swallowed, and a stale token went out unrenewed.
      expect(
        () => MalAuth.checkIfTokenExpired(AuthResponse.fromJson(_decode('{}'))),
        returnsNormally,
      );
    });

    test('unknown expiry counts as expired so the token gets renewed', () {
      expect(
        MalAuth.checkIfTokenExpired(AuthResponse(accessToken: 'a', expiresIn: null)),
        isTrue,
      );
      expect(
        MalAuth.checkIfTokenExpired(
            AuthResponse(accessToken: 'a', createdTime: null, expiresIn: 3600)),
        isTrue,
      );
    });

    test('honours a real expiry window', () {
      final now = DateTime.now();
      expect(
        MalAuth.checkIfTokenExpired(AuthResponse(
            accessToken: 'a',
            createdTime: now.subtract(const Duration(hours: 2)),
            expiresIn: 3600)),
        isTrue,
        reason: 'issued two hours ago with a one hour life',
      );
      expect(
        MalAuth.checkIfTokenExpired(AuthResponse(
            accessToken: 'a',
            createdTime: now,
            expiresIn: 3600)),
        isFalse,
      );
    });
  });

  group('MalUser.isWriteSuccessful', () {
    test('accepts every 2xx, not just 200', () {
      // MAL answers a completed DELETE with 204 No Content. Requiring exactly
      // 200 made every successful removal-from-list report "Couldn't Update!".
      for (final code in [200, 201, 202, 204]) {
        expect(MalUser.isWriteSuccessful(code), isTrue, reason: '$code is a 2xx');
      }
    });

    test('rejects everything else', () {
      for (final code in [301, 400, 401, 403, 404, 422, 429, 500, 503]) {
        expect(MalUser.isWriteSuccessful(code), isFalse, reason: '$code is not a 2xx');
      }
    });
  });

  group('MalConnect.authorizationHeader (the write path, behaviourally)', () {
    // The classifier tests above pin the decision. These pin what the user sees:
    // that a poisoned session makes the request builder *degrade* rather than
    // throw. This is the seam that matters, because it is the one the UI waits on
    // - a throw here became "Couldn't Update!", or an unhandled async error on
    // the manga path which had no handler at all.
    late FlutterSecureStoragePlatform originalSs;

    setUp(() {
      originalSs = FlutterSecureStoragePlatform.instance;
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStoragePlatform.instance = _MemorySecureStorage({});
    });

    tearDown(() => FlutterSecureStoragePlatform.instance = originalSs);

    /// Builds a session the way the app does, from stored JSON, so this test
    /// exercises the same object graph a real restore produces. `theme_v3` has
    /// to carry a valid enum name (a missing key means "defaults", an invalid
    /// value is a decode error) and `preferences: {}` yields default prefs.
    User sessionWith(AuthResponse? auth, AuthStatus status) {
      final restored = User.fromJson(jsonDecode(jsonEncode({
        'auth_status': status.index,
        'preferences': {},
        'theme_v3': UserTheme.defaultTheme().toJson(),
      })));
      restored.authResponse = auth;
      restored.status = status;
      return restored;
    }

    void signInWith(AuthResponse? auth) {
      user = sessionWith(auth, AuthStatus.AUTHENTICATED);
    }

    test('a poisoned session omits the header instead of throwing', () async {
      // Exactly the state a rejected refresh used to leave behind: flagged
      // AUTHENTICATED, holding a credential-less AuthResponse.
      signInWith(AuthResponse.fromJson(_decode(_malRejectedRefreshBody)));

      await expectLater(
        MalConnect.authorizationHeader(),
        completion(isNull),
      );
    });

    test('a null token with a signed-in-looking status is also safe', () async {
      signInWith(null);
      await expectLater(MalConnect.authorizationHeader(), completion(isNull));
    });

    test('an empty-string token is safe', () async {
      signInWith(AuthResponse(accessToken: '', tokenType: 'Bearer'));
      await expectLater(MalConnect.authorizationHeader(), completion(isNull));
    });

    test('a healthy unexpired session still signs the request', () async {
      // Guards the over-correction: refusing to sign would break every feature.
      signInWith(AuthResponse(
        accessToken: 'abc',
        tokenType: 'Bearer',
        expiresIn: 3600,
        createdTime: DateTime.now(),
      ));

      expect(await MalConnect.authorizationHeader(), 'Bearer abc');
    });

    test('an unauthenticated user sends no credentials', () async {
      user = sessionWith(
        AuthResponse(accessToken: 'abc', tokenType: 'Bearer', expiresIn: 3600),
        AuthStatus.UNAUTHENTICATED,
      );

      expect(await MalConnect.authorizationHeader(), isNull);
    });
  });

  group('the bug as an end-to-end shape', () {
    test('a rejected refresh cannot produce a usable credential', () {
      // Guards the whole chain in one assertion: the body that actually bricks
      // the app, taken through the classifier and the parser, must never yield
      // something the header builder would accept.
      final outcome =
          MalAuth.classifyTokenResponse(401, _decode(_malRejectedRefreshBody));
      final stored = AuthResponse.fromJson(_decode(_malRejectedRefreshBody));

      expect(outcome, isNot(TokenOutcome.renewed));
      expect(stored.isUsable, isFalse);
    });

    test('a blank-token response is caught even when the status is 200', () {
      final blank = _realToken(access: '');
      expect(MalAuth.classifyTokenResponse(200, blank), TokenOutcome.dead);
    });
  });
}
