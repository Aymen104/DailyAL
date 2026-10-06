import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dailyanimelist/api/auth/auth.dart';
import 'package:dailyanimelist/api/credmal.dart';
import 'package:dailyanimelist/constant.dart';
import 'package:dailyanimelist/main.dart';
import 'package:dailyanimelist/cache/cachemanager.dart';
import 'package:dailyanimelist/user/user.dart';
import 'package:dal_api/handlers/handler_core.dart';
import 'package:dal_commons/dal_commons.dart';
import 'package:dal_commons/dal_commons.dart' as commons;
import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart' as http;
import 'package:retry/retry.dart';

class MalConnect {
  static const _options = RetryOptions(maxAttempts: 8);
  static const _retryDuration = const Duration(seconds: 10);

  static Future<http.Response> retryGet(
    String url,
    Map<String, String> headers,
  ) async {
    final isDalLocal = url.startsWith('http://localhost:8080');
    final response = await _options.retry(
      // Make a GET request
      () async {
        if (isDalLocal) {
          var value = await HandlerCore()
              .handleRequestAsString(Uri.parse(url))
              .timeout(_retryDuration);
          return http.Response.bytes(utf8.encode(value ?? ''), 200, headers: {
            HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8'
          });
        }
        return http
            .get(Uri.parse(url), headers: headers)
            .timeout(_retryDuration);
      },
      // Retry on SocketException or TimeoutException
      retryIf: (e) {
        logDal('retrying... on $e');
        return e is SocketException || e is TimeoutException;
      },
    );
    return response;
  }

  static Future<http.Response> retryGetNoH(String url) => retryGet(url, Map());

  /// Standard Http Get Request with Auth Header
  static Future<dynamic> httpGetAsync(String url,
      {Map<String, String>? headers, bool usePlainOld = false}) async {
    if (headers == null) {
      headers = new Map();
    }
    if (!usePlainOld) {
      headers = await _malHeaders(headers);
    }

    return retryGet(url, headers);
  }

  /// Standard GetContent from Cache or API
  static Future<dynamic> getContent(
    String url, {
    Map<String, String>? headers,
    bool withNoHeaders = false,
    bool includeNsfw = true,
    bool fromCache = true,
    bool retryOnFail = true,
    bool useTimeout = false,
    Duration? timeoutDuration,
    int? timeinHours,
  }) async {
    if (user?.pref?.nsfw != null && includeNsfw) {
      String op = Uri.dataFromString(url).queryParameters.isEmpty ? "?" : "&";
      url = "$url${op}nsfw=${user.pref.nsfw ? '1' : '0'}&fromCache=$fromCache";
    }

    bool timeoutCache = false;
    dynamic cachedResult;

    if (fromCache) {
      logDal("Cache ->> $url");
      Map<String, dynamic>? _result =
          await CacheManager.instance.getCachedContent(url);
      if (_result != null) {
        cachedResult = _result;
        if (!shouldUpdateContent(
          result: _result,
          timeinHours: timeinHours ?? user.pref.cacheUpdateFrequency[homeIndex],
        )) {
          _result["url"] = url;
          _result["fromCache"] = true;
          return _result;
        }
      }
    }
    logDal("API ->> $url");
    if (headers == null) {
      headers = new Map();
    }
    if (!withNoHeaders) {
      headers = await _malHeaders(headers);
    }
    http.Response response;
    try {
      response = await _getWithOptions(
        url,
        headers,
        retryOnFail: retryOnFail,
        useTimeout: useTimeout,
        timeoutDuration: timeoutDuration,
        onTimeout: () {
          timeoutCache = true;
        },
      );
      if (response.statusCode == 200) {
        if (timeoutCache) {
          logDal('from timeoutCache --> $url');
          return cachedResult;
        } else {
          Map<String, dynamic> result =
              timeoutCache ? cachedResult : jsonDecode(response.body) ?? {};
          result["url"] = url;
          result["fromCache"] = false;
          CacheManager.instance.setCachedJson(url, result);
          result["lastUpdated"] = DateTime.now().toString();
          return result;
        }
      } else {
        return null;
      }
    } catch (e) {
      logDal(e);
      return null;
    }
  }

  static Future<http.Response> _getWithOptions(
    String url,
    Map<String, String> headers, {
    required bool retryOnFail,
    required bool useTimeout,
    Duration? timeoutDuration,
    required Function() onTimeout,
  }) async {
    final isDalLocal = url.startsWith('http://0.0.0.0:8080');
    if (retryOnFail) {
      return retryGet(url, headers);
    } else if (isDalLocal) {
      var value = await HandlerCore()
          .handleRequestAsString(Uri.parse(url))
          .timeout(_retryDuration);
      return http.Response.bytes(utf8.encode(value ?? ''), 200, headers: {
        HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8'
      });
    } else if (useTimeout) {
      return http
          .get(Uri.parse(url), headers: headers)
          .timeout(timeoutDuration!, onTimeout: () {
        onTimeout();
        return http.Response('cached', 200);
      });
    } else {
      return http.get(Uri.parse(url), headers: headers);
    }
  }

  /// The `Authorization` header value, or null when there is nothing usable to
  /// send.
  ///
  /// Single owner of the renew-then-sign step for all three verb helpers. They
  /// used to each inline their own copy, and the copies had already drifted:
  /// [httpGetAsync] built the header inside a try/catch, while `httpPutAsync` and
  /// `_headers` built it outside one. That put `tokenType! + accessToken!` - a
  /// hard null-check throw on any credential-less `AuthResponse` - on the write
  /// path's escape route to the UI, which is where a dead session surfaced as
  /// every update failing.
  static Future<String?> authorizationHeader() async {
    final auth = user.authResponse;
    if (user.status != AuthStatus.AUTHENTICATED ||
        auth == null ||
        !auth.isUsable) {
      return null;
    }
    try {
      if (MalAuth.checkIfTokenExpired(auth)) {
        if (!await MalAuth.refreshToken()) return null;
      }
    } catch (e) {
      // An expired token whose refresh could not even be attempted stays signed
      // out for this request; see the re-read below for why that is safe.
      logDal(e);
    }

    // Re-read rather than trusting `auth`: a successful refresh replaces the
    // object outright, and a rejected one clears it. Both are decided by
    // `refreshToken` returning true/false, and the `!await` above already returned
    // on false, so by this point either nothing changed (the original guard proved
    // `auth` usable) or a usable token replaced it.
    final current = user.authResponse;
    if (current == null || !current.isUsable) return null;
    return "${current.tokenType} ${current.accessToken}";
  }

  /// Applies the common MAL headers, including auth when it is available.
  static Future<Map<String, String>> _malHeaders(
      [Map<String, String>? headers]) async {
    headers ??= Map<String, String>();
    headers["X-MAL-Client-ID"] = CredMal.clientId;
    headers["Accept"] = "application/json";
    final authorization = await authorizationHeader();
    if (authorization != null) {
      headers["Authorization"] = authorization;
    }
    return headers;
  }

  static Future<Map<String, String>> get _headers async => _malHeaders();

  /// Standard Http Put Request with Auth Header
  static Future<http.Response> httpPutAsync(String url,
      {Map<String, String>? headers, Map<String, dynamic>? body}) async {
    body ??= Map<String, dynamic>();
    headers = await _malHeaders(headers);
    return http.put(Uri.parse(url), body: body, headers: headers);
  }

  static Future<http.Response> delete(String url) async {
    return http.delete(Uri.parse(url), headers: await _headers);
  }

  static Future<SearchResult?> htmlListPage(
    String url,
    String nextUrl,
    Function(Document) fromHtml, {
    bool fromCache = false,
    List<int> validCodes = const [200],
    bool withAuth = false,
  }) async {
    SearchResult? result;
    logDal('Html --> $url');
    var headers = Map<String, String>();
    if (withAuth) {
      headers = await _malHeaders(headers);
    }
    var response = await retryGet(url, headers);
    if (response == null || !validCodes.contains(response.statusCode)) {
      logDal(response.body);
    } else {
      result = fromHtml(parse(response.body));
      if (result == null) return null;
      result.fromCache = false;
      if (result.data != null && result.data!.isNotEmpty) {
        result.paging = Paging(next: nextUrl, previous: url);
      } else {
        result.paging = Paging();
      }
    }

    return result;
  }

  static Future<commons.Node?> htmlPage(
      String url, commons.Node Function(Document) fromHtml,
      {bool fromCache = false, bool withAuth = false}) async {
    commons.Node? result;
    logDal(url);
    var headers = Map<String, String>();
    if (withAuth) {
      headers = await _malHeaders(headers);
    }
    var response = await retryGet(url, headers);
    if (response.statusCode != 200) {
      logDal(response.body);
    } else {
      result = fromHtml(parse(response.body));
      result.fromCache = false;
    }

    return result;
  }

  static Future<T?> cachedHtml<T>(
    String url,
    T Function(Document) fromHtml,
    T Function(Map<String, dynamic>) fromJson, {
    bool fromCache = true,
    int? timeinHours,
  }) async {
    T? result;
    if (fromCache) {
      Map<String, dynamic> _result =
          await CacheManager.instance.getCachedContent(url);
      if (_result != null) {
        if (!shouldUpdateContent(
          result: _result,
          timeinHours: timeinHours ?? user.pref.cacheUpdateFrequency[homeIndex],
        )) {
          logDal("Cache ->> $url");
          _result["url"] = url;
          _result["fromCache"] = true;
          return fromJson(_result);
        }
      }
    }
    logDal("Hitting ->> $url");
    var response = await retryGet(url, Map());
    if (response == null || response.statusCode != 200) {
      logDal(response.body);
    } else {
      result = fromHtml(parse(response.body));
    }

    return result;
  }
}
