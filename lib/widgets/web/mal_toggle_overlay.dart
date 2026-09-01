import 'dart:async';

import 'package:dailyanimelist/api/auth/auth.dart';
import 'package:dailyanimelist/api/credmal.dart';
import 'package:dailyanimelist/cache/cachemanager.dart';
import 'package:dailyanimelist/widgets/web/mal_site_login_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// reCAPTCHA v3 site key used by MyAnimeList's favorite toggle.
const String malRecaptchaSiteKey = '6Ld_1aIZAAAAAF6bNdR67ICKIaeXLKlbhE7t2Qz4';

/// Raw outcome of the in-WebView favorite toggle request.
class MalToggleOutcome {
  final int status;
  final String body;
  const MalToggleOutcome(this.status, this.body);

  bool get looksLikeLoginPage =>
      status == 200 && body.contains('login.php') ||
      body.trimLeft().startsWith('<') && body.contains('myanimelist.net');
}

/// Runs the MAL "toggle favorite" operation inside a full-size WebView.
///
/// The myanimelist.net `/favorite/{type}/{id}.json` endpoint needs the site
/// session cookie (HttpOnly, so it cannot be read from Dart) plus a fresh
/// reCAPTCHA v3 token. Both the login and the toggle happen in THIS one
/// WebView, guaranteeing the session and the fetch share the same cookie jar.
Future<MalToggleOutcome?> runMalToggle(
  BuildContext context, {
  required String type,
  required int id,
  required bool add,
  bool autoLogin = false,
}) {
  return showDialog<MalToggleOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (_) => MalToggleOverlay(
      type: type,
      id: id,
      add: add,
      autoLogin: autoLogin,
    ),
  );
}

enum _Phase { check, favoriting, needsLogin }

class MalToggleOverlay extends StatefulWidget {
  /// `character` or `people`.
  final String type;
  final int id;
  final bool add;
  /// When true, the overlay is allowed to show the favorite/sign-in flow on a
  /// not-yet-logged-in session. Defaults to false — callers opt in.
  final bool autoLogin;
  const MalToggleOverlay({
    Key? key,
    required this.type,
    required this.id,
    required this.add,
    this.autoLogin = false,
  }) : super(key: key);

  /// Fires inside the WebView after page load and reports whether the cookie
  /// jar holds a live MAL session. mymessages.php redirects to a login/login-required
  /// page when logged out; when logged in it returns the user's messages page.
  /// This DIAGNOSTIC variant additionally dumps the first ~130 chars of the
  /// fetched page plus a set of marker checks so the exact logged-out page the
  /// WebView receives can be identified. logged=true iff no login markers.
  /// Posted on [ProbeBridge].
  static const String sessionProbe =
      '''(function(){try{fetch('https://myanimelist.net/mymessages.php',{credentials:'include'}).then(function(r){return r.text().then(function(t){var lp=(t.indexOf('login.php')>=0);var un=(t.indexOf('loginUserName')>=0);var bl=(t.indexOf('class="btn-login"')>=0);var ml=(t.indexOf('id="malLogin"')>=0);var lg=(t.indexOf('MyAnimeList')>=0);var head=t.substring(0,130).replace(/\\s+/g,' ');var logged=!(lp||un||ml);ProbeBridge.postMessage('SESH status='+r.status+' len='+t.length+' logged='+logged+' lp='+lp+' un='+un+' bl='+bl+' ml='+ml+' lg='+lg+' head=<'+head+'>');});}).catch(function(e){ProbeBridge.postMessage('SESH ERR '+e);});}catch(e2){ProbeBridge.postMessage('SESH EXC '+e2);}})();''';

  @override
  State<MalToggleOverlay> createState() => _MalToggleOverlayState();
}

class _MalToggleOverlayState extends State<MalToggleOverlay> {
  final WebViewController _controller = WebViewController();
  Timer? _timeout;
  bool _sent = false;
  bool _logged = false;
  _Phase _phase = _Phase.check;
  String _status = 'Syncing with MyAnimeList\u2026';

  late final String _baseUrl =
      '${CredMal.htmlEnd}${widget.type == 'people' ? 'people' : 'character'}/${widget.id}';

  late final String _toggleJs = '''(function(){
  var key = window.GRECAPTCHA_SITE_KEY || '$malRecaptchaSiteKey';
  var type = '${widget.type}';
  var id = ${widget.id};
  var add = ${widget.add};
  var debug = [];
  function done(t){ ResultBridge.postMessage(t); }
  function dump(label, val){ debug.push(label + ':' + (val === null || val === void 0 ? 'null' : String(val))); }
  function ensureLoaded(cb, tries){
    tries = tries || 0;
    if (window.grecaptcha) { cb(); return; }
    if (tries > 3) { dump('grecaptcha','NOT_LOADED'); done('TNOLIB@@' + debug.join('|')); return; }
    var s = document.createElement('script');
    s.src = 'https://www.google.com/recaptcha/api.js?render=' + key;
    s.async = true;
    s.onload = function(){ dump('grecaptcha','loaded'); cb(); };
    s.onerror = function(){ dump('scriptErr', tries); setTimeout(function(){ ensureLoaded(cb, tries + 1); }, 2500); };
    document.head.appendChild(s);
  }
  function callTokenThen(){
    if (window.grecaptcha && window.grecaptcha.ready) {
      grecaptcha.ready(function(){
        try {
          grecaptcha.execute(key, {action:'social'}).then(function(token){
            dump('tokenLen', token.length);
            fetch('https://myanimelist.net/favorite/' + type + '/' + id + '.json', {
              method: add ? 'POST' : 'DELETE',
              credentials: 'include',
              headers: {'Content-Type': 'application/x-www-form-urlencoded'},
              body: 'g-recaptcha-response=' + encodeURIComponent(token)
            }).then(function(r){
              return r.text().then(function(t){ done('T' + r.status + '@@' + t + '@@DBG' + debug.join('|')); });
            }).catch(function(e){ done('T0@@network@@DBG' + debug.join('|')); });
          }).catch(function(e){ dump('executeErr', String(e && e.message)); setTimeout(callTokenThen, 2000); });
        } catch (e) { dump('execExc', String(e)); setTimeout(callTokenThen, 2000); }
      });
    } else { setTimeout(callTokenThen, 400); }
  }
  setTimeout(function(){ ensureLoaded(function(){ setTimeout(callTokenThen, 300); }, 0); }, 400);
})();''';

  void _log(String message) => debugPrint('[MalToggle] $message');

  /// Whether [url] is (any of) MAL's login pages.
  static bool _isLoginUrl(String url) {
    final u = url.toLowerCase();
    return u.contains('login.php') ||
        u.contains('login-mal-dialog') ||
        (u.endsWith('myanimelist.net/') || u.endsWith('myanimelist.net'));
  }

  /// The user completed a real login: the WebView left the login form.
  void _onLeftLoginPage() {
    _log('user navigation away from login page -> authenticated, retrying');
    _sent = false; // a previous needs-auth attempt may have consumed the bridge
    _phase = _Phase.favoriting;
    _status = 'Signed in. Syncing with MyAnimeList\u2026';
    if (mounted) setState(() {});
    // The login happened inside this WebView, so the session now lives in the
    // app-global Android cookie store — every future overlay auto-syncs.
    _controller.loadRequest(Uri.parse(_baseUrl));
  }

  @override
  void initState() {
    super.initState();
    final probe = MalToggleOverlay.sessionProbe;
    _timeout = Timer(const Duration(seconds: 120), () {
      _log('timeout fired, sent=$_sent phase=$_phase');
      if (!_sent && mounted) Navigator.of(context).pop();
    });
    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) {
          _log('pageStarted url=$url phase=$_phase');
          if (_phase == _Phase.needsLogin && !_isLoginUrl(url)) {
            _onLeftLoginPage();
          }
        },
        onPageFinished: (url) {
          _log('pageFinished url=$url phase=$_phase');
          if (_phase == _Phase.check || _phase == _Phase.favoriting) {
            _phase = _Phase.favoriting;
            _status = 'Syncing with MyAnimeList\u2026';
            if (mounted) setState(() {});
            _controller.runJavaScript(_toggleJs);
            _controller.runJavaScript(probe);
          } else if (_phase == _Phase.needsLogin) {
            // The overlay's own WebView stays on the entry page while the
            // full-screen site sign-in (MalSiteSignInScreen) seeds the shared
            // cookie jar. A successful login is detected via the session probe,
            // not by URL watching. Just keep probing here.
            _controller.runJavaScript(probe);
            _status = 'Sign in to MyAnimeList to sync favorites.';
            if (mounted) setState(() {});
          }
        },
        onWebResourceError: (error) {
          _log('resourceError code=${error.errorCode} desc=${error.description} '
              'frame=${error.isForMainFrame} phase=$_phase');
        },
      ))
      ..addJavaScriptChannel(
        'ResultBridge',
        onMessageReceived: (JavaScriptMessage message) {
          _onResult(message.message);
        },
      )
      ..addJavaScriptChannel(
        'ProbeBridge',
        onMessageReceived: (JavaScriptMessage message) {
          _log('sessionProbe=${message.message}');
          final m = message.message;
          if (m.startsWith('SESH ')) {
            _logged = m.contains('logged=true');
            if (_logged && _phase == _Phase.needsLogin) {
              _onLeftLoginPage();
            }
          }
        },
      );
    _log('loading $_baseUrl add=${widget.add}');
    _controller.loadRequest(Uri.parse(_baseUrl));
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  void _onResult(String message) {
    _log('bridge message=$message phase=$_phase');
    if (_sent) return;
    // toggle result: T<status>@@<body>
    if (!message.startsWith('T')) return;
    _sent = true;
    final split = message.indexOf('@@');
    final int status;
    final String body;
    if (split <= 3) {
      status = 0;
      body = message;
    } else {
      status = int.tryParse(message.substring(1, split)) ?? 0;
      body = message.substring(split + 2);
    }
    final dbgMarker = body.indexOf('@@DBG');
    final String dbg;
    final String cleanBody;
    if (dbgMarker >= 0) {
      dbg = body.substring(dbgMarker + 5);
      cleanBody = body.substring(0, dbgMarker);
    } else {
      dbg = '';
      cleanBody = body;
    }
    _log('toggleResult status=$status dbg=$dbg bodyLen=${cleanBody.length} bodyHead=${cleanBody.length > 80 ? cleanBody.substring(0, 80) : cleanBody}');
    final looksLikeHtmlPage =
        cleanBody.trimLeft().startsWith('<') && cleanBody.contains('myanimelist.net');
    final needsLogin =
        status == 401 || status == 0 ||
        (status == 200 && looksLikeHtmlPage) ||
        (looksLikeHtmlPage && (cleanBody.contains('login') || cleanBody.contains('recaptcha')));
    if (needsLogin) {
      if (_phase == _Phase.needsLogin) {
        // The user logged in but the toggle still fell back to the login page —
        // reCAPTCHA is likely unusable in this WebView. Stop looping.
        if (mounted) {
          Navigator.of(context).pop(MalToggleOutcome(status, cleanBody));
        }
        return;
      }
      _phase = _Phase.needsLogin;
      _status = 'Sign in to MyAnimeList to sync favorites.';
      debugPrint('[MalToggle] needs auth, opening full-screen site sign-in');
      if (mounted) setState(() {});
      _startSiteSignIn();
      return;
    }
    if (mounted) Navigator.of(context).pop(MalToggleOutcome(status, cleanBody));
  }

  /// Grants access exactly the way DailyAL already does (see the in-app OAuth
  /// authorization screen): it opens the myanimelist.net OAuth v2 consent page
  /// inside the app's own WebView. The user signs in there, so the site session
  /// cookie lands in the shared app-global cookie jar, and the OAuth `code` is
  /// exchanged for the API token. Once it succeeds the favorite toggle retries
  /// with a valid site session and no separate login.
  Future<void> _startSiteSignIn() async {
    if (!mounted) return;
    try {
      final cc = MalAuth.codeChallenge(127);
      final url = '${CredMal.oauthEndPoint}'
          '?response_type=code&client_id=${CredMal.clientId}'
          '&code_challenge=$cc&state=OAuthLogin&redirect_uri=${CredMal.redirectUri}';
      await CacheManager.instance.setValue('cc', cc);
      final loggedIn = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => MalSiteLoginScreen(url: url),
        ),
      );
      if (!mounted) return;
      if (loggedIn == true) {
        // OAuth exchanged the code: the app holds the API token and the shared
        // jar holds the myanimelist.net site session. Retry the favorite.
        _log('oauth sign-in succeeded; site session seeded, retrying toggle');
        _sent = false; // a previous needs-auth attempt may have consumed it
        _phase = _Phase.favoriting;
        _status = 'Signed in. Syncing with MyAnimeList\u2026';
        if (mounted) setState(() {});
        _controller.loadRequest(Uri.parse(_baseUrl));
      } else {
        _log('oauth sign-in cancelled');
        if (_phase == _Phase.needsLogin) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      _log('oauth sign-in error: $e');
      if (_phase == _Phase.needsLogin) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 48),
      constraints: const BoxConstraints(maxWidth: 900, maxHeight: 2000),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    _phase == _Phase.needsLogin
                        ? Icons.login
                        : Icons.favorite_border,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _status,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  if (_phase == _Phase.needsLogin)
                    TextButton(
                      onPressed: _startSiteSignIn,
                      child: const Text('Sign in'),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Cancel',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: WebViewWidget(controller: _controller),
              ),
            ),
          ),
        ],
      ),
    );
  }
}