import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dailyanimelist/api/auth/authresp.dart';
import 'package:dailyanimelist/api/credmal.dart';
import 'package:dailyanimelist/main.dart';
import 'package:dailyanimelist/cache/cachemanager.dart';
import 'package:dailyanimelist/user/user.dart';
import 'package:dailyanimelist/widgets/web/c_webview.dart';
import 'package:dailyanimelist/widgets/web/mal_site_login_screen.dart';
import 'package:dal_commons/dal_commons.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import '../../constant.dart';

/// What a reply from MAL's OAuth token endpoint actually means.
enum TokenOutcome {
  /// A usable token came back; the session may be replaced by it.
  renewed,

  /// The server rejected the credentials. The session cannot be recovered, and
  /// pretending otherwise is what turned a rejected refresh into a bricked app.
  dead,

  /// No verdict on our credentials - a server fault or an unparsable reply. The
  /// stored token is untouched and still worth trying.
  transient,
}

class MalAuth {
  String _chars =
      'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890-._~';
  Random _rnd = Random.secure();

  String getRandomString(int length) => String.fromCharCodes(Iterable.generate(
      length, (_) => _chars.codeUnitAt(_rnd.nextInt(_chars.length))));

  static String codeChallenge(int length) {
    return new MalAuth().getRandomString(length);
  }

  /// Standard Http POST Request with Auth Header
  static Future<http.Response> httpPostAsync(String url,
      {Map<String, String>? headers, Map<String, String>? body}) {
    if (headers == null) {
      headers = new Map();
    }
    body = body ?? {};
    headers["Accept"] = "application/json";
    headers["Content-Type"] = "application/x-www-form-urlencoded";

    return http.post(Uri.parse(url), headers: headers, body: body);
  }

  static bool checkIfTokenExpired(AuthResponse authResponse) {
    final createdTime = authResponse.createdTime;
    final expiresIn = authResponse.expiresIn;
    // An unknown expiry has to count as expired. The previous `createdTime!` /
    // `expiresIn!` pair threw here, the throw was swallowed by the callers'
    // catch, and the request went out on a token that should have been renewed.
    if (createdTime == null || expiresIn == null) return true;
    DateTime expiryDate = createdTime.add(Duration(seconds: expiresIn));
    return expiryDate.isBefore(DateTime.now());
  }

  /// Interprets a token-endpoint reply.
  ///
  /// Split out from [refreshToken] and [onCodeReceived] because both used to
  /// accept whatever JSON arrived and let it stand in for a credential. Neither
  /// checked the status code, and MAL answers a rejected refresh *and* a rejected
  /// code exchange with a decodable JSON object - `{"error":"invalid_request",
  /// "message":"The refresh token is invalid."}` - whose field lookups all miss.
  /// The result was an [AuthResponse] with a null `accessToken`/`tokenType` that
  /// was stored over the working token, flagged AUTHENTICATED, and written to
  /// secure storage. From there every write threw on `tokenType!` while the UI
  /// still showed a signed-in user, permanently, across restarts.
  ///
  /// [decoded] is the result of `jsonDecode` on the response body: null means
  /// the body was absent or unparsable.
  static TokenOutcome classifyTokenResponse(
      int statusCode, Map<String, dynamic>? decoded) {
    // A 5xx says nothing about our credentials, so keep them and let a later
    // request retry. Only an explicit rejection ends the session.
    if (statusCode >= 500) return TokenOutcome.transient;
    if (statusCode != 200) return TokenOutcome.dead;
    if (decoded == null) return TokenOutcome.transient;
    return AuthResponse.fromJson(decoded).isUsable
        ? TokenOutcome.renewed
        : TokenOutcome.dead;
  }

  /// Drops a session whose token the server refused to renew.
  ///
  /// A non-2xx from the token endpoint is not a transient hiccup: it means the
  /// refresh token is gone, and nothing will ever authorise a request with the
  /// old credentials. Clearing them and reporting UNAUTHENTICATED puts the UI in
  /// the state that can actually be recovered from (re-login) instead of a state
  /// that looks signed-in while every write throws.
  ///
  /// Awaited by [refreshToken]: the stored credential has to be cleared *before*
  /// the caller is told the refresh failed. Not awaiting it left the dead token
  /// on disk while the in-memory state said otherwise, so a restart resurrected
  /// a session that could only ever fail again.
  static Future<void> _endSession() async {
    user.authResponse = null;
    user.status = AuthStatus.UNAUTHENTICATED;
    user.updateUserStatus();
    await user.setIntance();
  }

  /// Renews the access token. Returns whether a usable token is now held.
  ///
  /// Only ever *replaces* [user.authResponse] once a usable token has actually
  /// been parsed, so a rejected refresh can no longer destroy the working
  /// credentials it was called to extend.
  static Future<bool> refreshToken() async {
    String url = CredMal.otokenEndPoint;

    Map<String, String> body = {
      "client_id": CredMal.clientId,
      "client_secret": CredMal.clientSecret,
      "grant_type": "refresh_token",
      "redirect_uri": CredMal.redirectUri,
      "refresh_token": user.authResponse?.refreshToken ?? ''
    };

    try {
      final response = await httpPostAsync(url, body: body);
      final Map<String, dynamic>? decoded = _tryDecode(response.body);
      switch (classifyTokenResponse(response.statusCode, decoded)) {
        case TokenOutcome.renewed:
          user.authResponse = AuthResponse.fromJson(decoded);
          user.status = AuthStatus.AUTHENTICATED;
          await user.setIntance();
          return true;
        case TokenOutcome.dead:
          logDal('refreshToken rejected -> ${response.statusCode} '
              '${response.body}');
          await _endSession();
          return false;
        case TokenOutcome.transient:
          logDal('refreshToken inconclusive -> ${response.statusCode} '
              '${response.body}');
          return false;
      }
    } catch (e) {
      // Transport-level failure: the request never got an answer, so the stored
      // credentials are untouched and still worth keeping.
      logDal(e);
      return false;
    }
  }

  /// `jsonDecode` without letting a non-JSON body escape as a throw.
  static Map<String, dynamic>? _tryDecode(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      logDal(e);
      return null;
    }
  }

  static void handleSignIn() async {
    if (user.status == AuthStatus.INPROGRESS) return;
    user.status = AuthStatus.INPROGRESS;
    user.updateUserStatus();
    oAuthSignIn((error) {
      user.status = AuthStatus.UNAUTHENTICATED;
      user.updateUserStatus();
      logDal(error);
    });
  }

  static Future<bool> onCodeReceived(String code, String cc) async {
    String url = CredMal.otokenEndPoint;

    Map<String, String> body = {
      "client_id": CredMal.clientId,
      "client_secret": CredMal.clientSecret,
      "grant_type": "authorization_code",
      "code": code,
      "code_verifier": cc,
      "redirect_uri": CredMal.redirectUri
    };

    try {
      final response = await httpPostAsync(url, body: body);
      final Map<String, dynamic>? decoded = _tryDecode(response.body);
      final outcome = classifyTokenResponse(response.statusCode, decoded);
      if (outcome != TokenOutcome.renewed) {
        // Routed through the same classifier as refreshToken so the two cannot
        // drift. Previously any decodable body counted as success: a rejected
        // code exchange left an all-null credential stored, flagged
        // AUTHENTICATED, and still returned true to the WebView login screen.
        logDal('onCodeReceived -> ${outcome.name} '
            '${response.statusCode} ${response.body}');
        user.status = AuthStatus.UNAUTHENTICATED;
        user.updateUserStatus();
        return false;
      }
      user.authResponse = AuthResponse.fromJson(decoded);
      user.status = AuthStatus.AUTHENTICATED;
      user.updateUserStatus();
      await user.setIntance();
      return true;
    } catch (e) {
      user.status = AuthStatus.UNAUTHENTICATED;
      user.updateUserStatus();
      logDal(e);
      return false;
    }
  }

  static void oAuthSignIn(ValueChanged<Error> gotError) async {
    String cc = codeChallenge(127);
    String url = CredMal.oauthEndPoint +
        "?response_type=code&client_id=" +
        CredMal.clientId +
        "&code_challenge=" +
        cc +
        "&state=OAuthLogin&redirect_uri=" +
        CredMal.redirectUri;
    await CacheManager.instance.setValue('cc', cc);

    // Use flutter_web_auth_2 for desktop platforms (Linux, Windows, macOS)
    if (!kIsWeb &&
        (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      try {
        logDal('Starting OAuth with flutter_web_auth_2 for desktop');
        final result = await FlutterWebAuth2.authenticate(
          url: url,
          callbackUrlScheme: CredMal.callbackUrlScheme,
          options: const FlutterWebAuth2Options(
            useWebview: false, // Use system browser with localhost callback
          ),
        );

        logDal('OAuth callback received: $result');
        final uri = Uri.parse(result);
        final code = uri.queryParameters['code'];

        if (code != null) {
          await onCodeReceived(code, cc);
        } else {
          logDal('No code received from OAuth callback');
          user.status = AuthStatus.UNAUTHENTICATED;
          user.updateUserStatus();
        }
      } catch (e) {
        logDal('OAuth error on desktop: $e');
        user.status = AuthStatus.UNAUTHENTICATED;
        user.updateUserStatus();
      }
    } else if (!kIsWeb && Platform.isAndroid) {
      // Android logs in inside the app's own WebView so the myanimelist.net
      // website session lands in the shared cookie jar and favorites can
      // auto-sync from the first login, with no second login.
      logDal('Starting OAuth with in-app WebView for Android');
      try {
        await MyApp.navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => MalSiteLoginScreen(url: url),
          ),
        );
      } catch (e) {
        logDal('OAuth error on Android: $e');
        user.status = AuthStatus.UNAUTHENTICATED;
        user.updateUserStatus();
      }
    } else {
      // iOS and other platforms keep the existing custom-tab webview approach.
      launchWebView(url);
    }
  }

  static Future<void> signOut() async {
    user.authResponse = new AuthResponse();
    user.status = AuthStatus.UNAUTHENTICATED;
    await user.setIntance();
    await CacheManager.instance.resetData();
  }

  static Future<bool> checkIfSignIn(Uri? uri) async {
    String? _code = uri?.queryParameters.tryAt("code");
    if (_code != null) {
      String? cc = await CacheManager.instance.getValue('cc');
      if (cc != null) {
        return onCodeReceived(_code, cc);
      }
    }
    return false;
  }
}
