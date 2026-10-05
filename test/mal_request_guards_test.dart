import 'dart:convert';

import 'package:dailyanimelist/api/auth/authresp.dart';
import 'package:dailyanimelist/api/malapi.dart';
import 'package:dailyanimelist/api/maluser.dart';
import 'package:dailyanimelist/theme/theme.dart';
import 'package:dailyanimelist/user/user.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression tests for the two request-construction bugs that left the home
/// page's "my list" blank, plus the URL one that silently dropped fields.
///
/// Both original defects sat behind a network call whose failure mode is an
/// *empty* result - indistinguishable from a correct early return - so these
/// assert on the predicates that decide whether to call out at all, not on the
/// result that comes back.
void main() {
  group('MalUser.canReadUserList', () {
    // The regression: this case used to be allowed through. `@me` without a
    // token is the one request guaranteed to be rejected, and letting it out
    // produced the blank list.
    test('refuses @me when there is no token', () {
      expect(
        MalUser.canReadUserList(AuthStatus.UNAUTHENTICATED, "@me"),
        isFalse,
        reason: '@me is resolved from the caller token; unauthenticated '
            'must not be sent',
      );
    });

    test('refuses @me mid-login too', () {
      // INPROGRESS is not a usable token, so it must not read as one.
      expect(MalUser.canReadUserList(AuthStatus.INPROGRESS, "@me"), isFalse);
    });

    test('allows @me once authenticated', () {
      expect(MalUser.canReadUserList(AuthStatus.AUTHENTICATED, "@me"), isTrue);
    });

    test('allows a named user regardless of auth - that route is public', () {
      expect(
        MalUser.canReadUserList(AuthStatus.UNAUTHENTICATED, "someone"),
        isTrue,
      );
      expect(MalUser.canReadUserList(AuthStatus.INPROGRESS, "someone"), isTrue);
    });

    test('does not confuse a name that merely contains @me', () {
      // Guards the string comparison: only the exact `@me` is token-bound.
      expect(MalUser.canReadUserList(AuthStatus.UNAUTHENTICATED, "@mesh"), isTrue);
      expect(MalUser.canReadUserList(AuthStatus.UNAUTHENTICATED, "me"), isTrue);
    });
  });

  group('MalUser.buildUserListUrl', () {
    // These pin the guard *and* the request shape in one place. A standalone
    // canReadUserList cannot: a build that stopped calling it, or reinstated
    // the original inverted condition, passed every predicate test while
    // producing a blank list. Null-vs-URL is what actually distinguishes
    // "bailed out on purpose" from "asked and got nothing back".

    test('refuses to build a URL for @me without a token', () {
      // The regression: an unauthenticated @me used to be let through, and
      // MAL rejected it - which is what blanked the home page's my list.
      expect(MalUser.buildUserListUrl(AuthStatus.UNAUTHENTICATED), isNull);
      expect(MalUser.buildUserListUrl(AuthStatus.INPROGRESS), isNull);
      expect(
          MalUser.buildUserListUrl(AuthStatus.UNAUTHENTICATED,
              username: '@me'),
          isNull);
    });

    test('builds a URL for @me once authenticated', () {
      final url = MalUser.buildUserListUrl(AuthStatus.AUTHENTICATED);
      expect(url, isNotNull);
      expect(url, contains('/users/@me/animelist'));
      expect(url, contains('&limit=100'));
      expect(url, contains('&offset=0'));
    });

    test('builds a URL for a named user without any token', () {
      // That route is public, so an anonymous read must still be attempted.
      final url = MalUser.buildUserListUrl(AuthStatus.UNAUTHENTICATED,
          username: 'someone');
      expect(url, isNotNull);
      expect(url, contains('/users/someone/animelist'));
    });

    test('carries category, paging and filters through', () {
      final url = MalUser.buildUserListUrl(AuthStatus.AUTHENTICATED,
          category: 'manga', limit: 25, offset: 50);
      expect(url, contains('/users/@me/mangalist'));
      expect(url, contains('&limit=25'));
      expect(url, contains('&offset=50'));
    });

    test('appends status and sort only when given', () {
      final bare = MalUser.buildUserListUrl(AuthStatus.AUTHENTICATED)!;
      expect(bare, isNot(contains('&status=')));
      expect(bare, isNot(contains('&sort=')));

      final filtered = MalUser.buildUserListUrl(AuthStatus.AUTHENTICATED,
          status_: 'watching', sortType: 'list_score');
      expect(filtered, contains('&status=watching'));
      expect(filtered, contains('&sort=list_score'));
    });

    test('merges extra fields into the field list', () {
      final url = MalUser.buildUserListUrl(AuthStatus.AUTHENTICATED,
          fields: ['id', 'title']);
      expect(url, contains('num_volumes,id,title,list_status'));
    });

    test('opens the query string exactly once', () {
      for (final status in AuthStatus.values) {
        final url = MalUser.buildUserListUrl(status, username: 'someone');
        if (url == null) continue;
        expect('?'.allMatches(url).length, 1, reason: 'stray ?: $url');
        expect(url, isNot(contains('&fields=')),
            reason: 'fields belong to the first, only, query string');
      }
    });

    test('the my_list_status sub-object survives', () {
      // Dropping this strips the signed-in user's own progress off every row.
      final url = MalUser.buildUserListUrl(AuthStatus.AUTHENTICATED)!;
      expect(url, contains('list_status{is_rewatching'));
    });
  });

  group('MalApi.buildSearchUrl', () {
    test('opens the query string exactly once', () {
      final url = MalApi.buildSearchUrl('cowboy bebop');
      // A second `?` swallows everything after it into the previous value.
      expect('?'.allMatches(url).length, 1, reason: 'url has a stray ?: $url');
      expect(url.contains('&fields='), isTrue);
    });

    test('falls back to the default fields, joined with &', () {
      final url = MalApi.buildSearchUrl('naruto');
      expect(url.contains('&fields=${MalApi.defaultSearchFields}'), isTrue,
          reason: 'default fields must survive intact');
      // The regression: `my_list_status` silently missing strips the user's own
      // progress off every row.
      expect(url, contains('my_list_status'));
    });

    test('honours an explicit field list', () {
      final url = MalApi.buildSearchUrl('naruto', fields: ['id', 'title']);
      expect(url, endsWith('&fields=id,title'));
      expect(url, isNot(contains('my_list_status')));
    });

    test('an empty field list is treated as unspecified', () {
      final url = MalApi.buildSearchUrl('naruto', fields: []);
      expect(url, contains('&fields=${MalApi.defaultSearchFields}'));
    });

    test('carries paging and category through', () {
      final url =
          MalApi.buildSearchUrl('x', limit: 25, offset: 50, category: 'manga');
      expect(url, contains('/manga?'));
      expect(url, contains('&limit=25'));
      expect(url, contains('&offset=50'));
    });

    test('percent-encodes the query so it cannot inject a parameter', () {
      final url = MalApi.buildSearchUrl('a&limit=9999&x=b c');
      expect('?'.allMatches(url).length, 1);
      expect(url, isNot(contains('&limit=9999')));
      expect(url, contains('%26limit%3D9999'));
    });
  });

  group('User.resolvePersistedStatus', () {
    // The regression: a user killed mid-login came back INPROGRESS forever,
    // because nothing completes a login across a restart.
    test('a stored token wins over a persisted INPROGRESS', () {
      expect(
        User.resolvePersistedStatus(
            AuthStatus.INPROGRESS, AuthResponse(accessToken: 'abc')),
        AuthStatus.AUTHENTICATED,
      );
    });

    test('a stored token also repairs a stale UNAUTHENTICATED', () {
      // The token is the durable evidence; the flag is a cache of it.
      expect(
        User.resolvePersistedStatus(
            AuthStatus.UNAUTHENTICATED, AuthResponse(accessToken: 'abc')),
        AuthStatus.AUTHENTICATED,
      );
    });

    test('never restores INPROGRESS, whatever was persisted', () {
      for (final persisted in AuthStatus.values) {
        expect(
          User.resolvePersistedStatus(persisted, AuthResponse()),
          AuthStatus.UNAUTHENTICATED,
          reason: 'persisted=$persisted must not survive as INPROGRESS',
        );
      }
    });

    test('no token reads as signed out', () {
      expect(
        User.resolvePersistedStatus(AuthStatus.AUTHENTICATED, AuthResponse()),
        AuthStatus.UNAUTHENTICATED,
      );
    });

    test('a missing authResponse reads as signed out', () {
      expect(
        User.resolvePersistedStatus(AuthStatus.AUTHENTICATED, null),
        AuthStatus.UNAUTHENTICATED,
      );
      expect(
        User.resolvePersistedStatus(AuthStatus.INPROGRESS, null),
        AuthStatus.UNAUTHENTICATED,
      );
    });

    test('a resolved status always satisfies the @me guard', () {
      // The two fixes have to agree: whatever getInstance() produces must let a
      // signed-in user's own list be read, or the blank list comes back.
      final signedIn = User.resolvePersistedStatus(
          AuthStatus.INPROGRESS, AuthResponse(accessToken: 'abc'));
      expect(MalUser.canReadUserList(signedIn, '@me'), isTrue);

      final signedOut =
          User.resolvePersistedStatus(AuthStatus.INPROGRESS, AuthResponse());
      expect(MalUser.canReadUserList(signedOut, '@me'), isFalse);
    });
  });

  group('User.getInstance restores a usable status', () {
    // The unit tests above pin the predicate, but on their own they cannot catch
    // the predicate never being *called* - a mutant with the helper defined and
    // the getInstance() call site deleted passed all 17 of them. These go
    // through the real restore path instead.

    late List<FlutterSecureStoragePlatform> restore;

    /// A platform stub backed by an in-memory map.
    FlutterSecureStoragePlatform stubWith(Map<String, String> data) =>
        _MemorySecureStorage(data);

    void setStoredUser({required int authStatusIndex, String? accessToken}) {
      // theme_v3 must carry a valid enum name: User.fromJson treats a missing
      // key as "use defaults" but an *invalid* value as a decode error.
      final user = <String, dynamic>{
        'auth_status': authStatusIndex,
        'preferences': {},
        'theme_v3': UserTheme.defaultTheme().toJson(),
      };
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({'user': jsonEncode(user)});

      final ssData = <String, String>{};
      if (accessToken != null) {
        ssData['authResponse'] = jsonEncode({
          'access_token': accessToken,
          'expires_in': 3600,
          'token_type': 'Bearer',
          'refresh_token': 'r',
          'created_time': DateTime.now().toIso8601String(),
        });
      }
      FlutterSecureStoragePlatform.instance = stubWith(ssData);
    }

    setUp(() {
      restore = [FlutterSecureStoragePlatform.instance];
    });

    tearDown(() {
      for (final p in restore) {
        FlutterSecureStoragePlatform.instance = p;
      }
    });

    test('a user killed mid-login comes back signed in', () async {
      // The regression in full: INPROGRESS persisted + a real token stored.
      setStoredUser(
          authStatusIndex: AuthStatus.INPROGRESS.index, accessToken: 'tok');

      final user = await User.getInstance();

      expect(user.status, AuthStatus.AUTHENTICATED);
      expect(MalUser.canReadUserList(user.status, '@me'), isTrue,
          reason: 'a restored session must be able to read its own list');
    });

    test('a stale UNAUTHENTICATED with a token comes back signed in', () async {
      setStoredUser(
          authStatusIndex: AuthStatus.UNAUTHENTICATED.index,
          accessToken: 'tok');

      final user = await User.getInstance();

      expect(user.status, AuthStatus.AUTHENTICATED);
    });

    test('never comes back INPROGRESS', () async {
      for (final persisted in AuthStatus.values) {
        setStoredUser(authStatusIndex: persisted.index, accessToken: 'tok');
        expect((await User.getInstance()).status, isNot(AuthStatus.INPROGRESS),
            reason: 'persisted=$persisted must not be restored verbatim');

        setStoredUser(authStatusIndex: persisted.index);
        expect((await User.getInstance()).status, isNot(AuthStatus.INPROGRESS),
            reason: 'persisted=$persisted, no token');
      }
    });

    test('no stored token leaves the user signed out', () async {
      setStoredUser(authStatusIndex: AuthStatus.AUTHENTICATED.index);
      expect((await User.getInstance()).status, AuthStatus.UNAUTHENTICATED);
    });

    test('a fresh install is signed out', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStoragePlatform.instance = stubWith({});

      final user = await User.getInstance();

      expect(user.status, AuthStatus.UNAUTHENTICATED);
      expect(user.authResponse?.accessToken, isNull);
    });
  });
}

class _MemorySecureStorage extends FlutterSecureStoragePlatform {
  _MemorySecureStorage(this.data);

  final Map<String, String> data;

  @override
  Future<String?> read({required String key, required Map<String, String> options}) async =>
      data[key];

  @override
  Future<void> write({required String key, required String value, required Map<String, String> options}) async =>
      data[key] = value;

  @override
  Future<void> delete({required String key, required Map<String, String> options}) async =>
      data.remove(key);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      data.clear();

  @override
  Future<bool> containsKey({required String key, required Map<String, String> options}) async =>
      data.containsKey(key);

  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) async =>
      data;
}