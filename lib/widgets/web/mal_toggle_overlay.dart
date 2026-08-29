import 'dart:async';

import 'package:dailyanimelist/api/credmal.dart';
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

/// Runs the MAL "toggle favorite" operation inside a tiny WebView.
///
/// The myanimelist.net `/favorite/{type}/{id}.json` endpoint needs the site
/// session cookie (`HttpOnly`, so not readable from Dart) plus a fresh
/// reCAPTCHA v3 token. Instead of capturing either, we let the WebView do the
/// whole request: the page loads on the `myanimelist.net` origin, so a
/// same-origin `fetch()` with `credentials: 'include'` reuses the WebView's own
/// cookie jar (shared app-wide on Android).
Future<MalToggleOutcome?> runMalToggle(
  BuildContext context, {
  required String type,
  required int id,
  required bool add,
}) {
  return showDialog<MalToggleOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (_) => MalToggleOverlay(
      type: type,
      id: id,
      add: add,
    ),
  );
}

class MalToggleOverlay extends StatefulWidget {
  /// `character` or `people`.
  final String type;
  final int id;
  final bool add;
  const MalToggleOverlay({
    Key? key,
    required this.type,
    required this.id,
    required this.add,
  }) : super(key: key);

  @override
  State<MalToggleOverlay> createState() => _MalToggleOverlayState();
}

class _MalToggleOverlayState extends State<MalToggleOverlay> {
  final WebViewController _controller = WebViewController();
  Timer? _timeout;
  bool _sent = false;
  bool _mainLoaded = false;

  late final String _toggleJs = '''
(function(){
  var key = '$malRecaptchaSiteKey';
  var type = '${widget.type}';
  var id = ${widget.id};
  var add = ${widget.add};
  var sep = '@@';
  function done(t){ ResultBridge.postMessage(t); }
  function ensureLoaded(cb){
    if (window.grecaptcha) { cb(); return; }
    var s = document.createElement('script');
    s.src = 'https://www.google.com/recaptcha/api.js?render=' + key;
    s.async = true;
    s.onload = cb;
    s.onerror = function(){ setTimeout(function(){ ensureLoaded(cb); }, 3000); };
    document.head.appendChild(s);
  }
  function callTokenThen(){
    if (window.grecaptcha && window.grecaptcha.ready) {
      grecaptcha.ready(function(){
        grecaptcha.execute(key, {action:'social'}).then(function(token){
          fetch('https://myanimelist.net/favorite/' + type + '/' + id + '.json', {
            method: add ? 'POST' : 'DELETE',
            credentials: 'include',
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: 'g-recaptcha-response=' + encodeURIComponent(token)
          }).then(function(r){
            return r.text().then(function(t){ done(r.status + sep + t); });
          }).catch(function(e){ done('0' + sep + 'network'); });
        }).catch(function(){ setTimeout(callTokenThen, 2000); });
      });
    } else { setTimeout(callTokenThen, 400); }
  }
  setTimeout(function(){ ensureLoaded(function(){ setTimeout(callTokenThen, 300); }); }, 400);
})();''';

  @override
  void initState() {
    super.initState();
    _timeout = Timer(const Duration(seconds: 30), () {
      if (!_sent && mounted) {
        Navigator.of(context).pop();
      }
    });
    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) {
          _mainLoaded = true;
          _controller.runJavaScript(_toggleJs);
        },
        onWebResourceError: (error) {
          if (!_sent && mounted && !_mainLoaded && error.isForMainFrame == true) {
            Navigator.of(context).pop();
          }
        },
      ))
      ..addJavaScriptChannel(
        'ResultBridge',
        onMessageReceived: (JavaScriptMessage message) {
          _onResult(message.message);
        },
      );
    final page = widget.type == 'people' ? 'people' : 'character';
    _controller.loadRequest(Uri.parse('${CredMal.htmlEnd}$page/${widget.id}'));
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  void _onResult(String message) {
    if (_sent || message.isEmpty) return;
    _sent = true;
    final split = message.indexOf('@@');
    final int status;
    final String body;
    if (split <= 0) {
      status = 0;
      body = message;
    } else {
      status = int.tryParse(message.substring(0, split)) ?? 0;
      body = message.substring(split + 2);
    }
    if (mounted) {
      Navigator.of(context).pop(MalToggleOutcome(status, body));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Syncing with MyAnimeList\u2026',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 1,
              height: 1,
              child: WebViewWidget(controller: _controller),
            ),
          ],
        ),
      ),
    );
  }
}