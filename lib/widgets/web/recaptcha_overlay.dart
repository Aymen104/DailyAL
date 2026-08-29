import 'dart:async';

import 'package:dailyanimelist/api/credmal.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// reCAPTCHA v3 site key used by MyAnimeList's favorite toggle.
const String malRecaptchaSiteKey = '6Ld_1aIZAAAAAF6bNdR67ICKIaeXLKlbhE7t2Qz4';

/// Shared token cache so consecutive favorites don't need a fresh webview.
String? _cachedToken;
DateTime? _cachedTokenAt;

/// Obtains a fresh `g-recaptcha-response` token for the "social" action.
///
/// Runs Google's reCAPTCHA v3 inside a tiny hidden WebView on the
/// `myanimelist.net` origin (same mechanism the website's favorite toggle
/// uses). The token is valid for ~2 minutes, so a valid result is reused
/// instead of spawning another WebView.
Future<String?> obtainRecaptchaToken(BuildContext context) async {
  if (_cachedToken != null &&
      _cachedTokenAt != null &&
      DateTime.now().difference(_cachedTokenAt!) <
          const Duration(minutes: 1, seconds: 30)) {
    return _cachedToken;
  }
  final token = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const RecaptchaTokenOverlay(),
  );
  if (token != null && token.isNotEmpty) {
    _cachedToken = token;
    _cachedTokenAt = DateTime.now();
  }
  return token;
}

class RecaptchaTokenOverlay extends StatefulWidget {
  const RecaptchaTokenOverlay({Key? key}) : super(key: key);

  @override
  State<RecaptchaTokenOverlay> createState() => _RecaptchaTokenOverlayState();
}

class _RecaptchaTokenOverlayState extends State<RecaptchaTokenOverlay> {
  final WebViewController _controller = WebViewController();
  Timer? _timeout;
  bool _sent = false;
  bool _mainLoaded = false;

  static const _executeJs = '''
(function(){
  var key = '$malRecaptchaSiteKey';
  function done(t){ RecaptchaBridge.postMessage(t); }
  function ensureLoaded(cb){
    if (window.grecaptcha) { cb(); return; }
    var s = document.createElement('script');
    s.src = 'https://www.google.com/recaptcha/api.js?render=' + key;
    s.async = true;
    s.onload = cb;
    s.onerror = function(){ setTimeout(function(){ ensureLoaded(cb); }, 3000); };
    document.head.appendChild(s);
  }
  function tryRun(){
    if (window.grecaptcha && window.grecaptcha.ready) {
      try {
        grecaptcha.ready(function(){
          grecaptcha.execute(key, {action:'social'}).then(function(t){ done(t); })
            .catch(function(){ setTimeout(tryRun, 2000); });
        });
      } catch(e){ setTimeout(tryRun, 2000); }
    } else { setTimeout(tryRun, 1200); }
  }
  setTimeout(function(){ ensureLoaded(function(){ setTimeout(tryRun, 300); }); }, 500);
})();''';

  @override
  void initState() {
    super.initState();
    _timeout = Timer(const Duration(seconds: 25), () {
      if (!_sent && mounted) {
        Navigator.of(context).pop();
      }
    });
    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) {
          _mainLoaded = true;
          _controller.runJavaScript(_executeJs);
        },
        onWebResourceError: (error) {
          if (!_sent && mounted && !_mainLoaded && error.isForMainFrame == true) {
            Navigator.of(context).pop();
          }
        },
      ))
      ..addJavaScriptChannel(
        'RecaptchaBridge',
        onMessageReceived: (JavaScriptMessage message) {
          _onToken(message.message);
        },
      );
    _controller.loadRequest(Uri.parse('${CredMal.htmlEnd}'));
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  void _onToken(String token) {
    if (_sent || token.isEmpty) return;
    _sent = true;
    if (mounted) {
      Navigator.of(context).pop(token);
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
              'Securing with Google reCAPTCHA\u2026',
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