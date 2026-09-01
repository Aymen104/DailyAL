import 'dart:async';

import 'package:dailyanimelist/widgets/web/mal_toggle_overlay.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Full-screen in-app sign-in to the MyAnimeList *website*.
///
/// Unlike [MalSiteLoginScreen] (an OAuth flow), this is a plain site login: it
/// loads `login.php` and, once the user signs in, the myanimelist.net session
/// cookie lands in the shared app-global WebView cookie store — the exact jar
/// the favorite-toggle WebView reuses. The screen watches that session in
/// real time and pops itself the moment login succeeds.
///
/// The official OAuth API has no favorites endpoint for characters/people, so
/// favorites must ride on the website session cookie; this screen is how that
/// cookie gets seeded for a user who wasn't signed into the site yet.
class MalSiteSignInScreen extends StatefulWidget {
  const MalSiteSignInScreen({super.key});

  @override
  State<MalSiteSignInScreen> createState() => _MalSiteSignInScreenState();
}

class _MalSiteSignInScreenState extends State<MalSiteSignInScreen> {
  final WebViewController _controller = WebViewController();
  bool _loading = true;
  Timer? _probeTimer;
  int _probeTick = 0;

  @override
  void initState() {
    super.initState();
    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted && !_loading) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted && _loading) setState(() => _loading = false);
            _armProbe();
          },
        ),
      )
      ..addJavaScriptChannel(
        'ProbeBridge',
        onMessageReceived: (JavaScriptMessage message) {
          final m = message.message;
          debugPrint('[MalToggle] siteSignIn probe=$m');
          if (m.startsWith('SESH ') && m.contains('logged=true') && mounted) {
            _probeTimer?.cancel();
            Navigator.of(context).maybePop(true);
          }
        },
      )
      ..loadRequest(Uri.parse('https://myanimelist.net/login.php'));
  }

  /// Run the shared session probe a few times to auto-detect a fresh login.
  void _armProbe() {
    // If login already succeeded before we mounted (or is detected), we're done.
    Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        _controller.runJavaScript(MalToggleOverlay.sessionProbe);
      }
    });
    // Also run it a few times in case the probe result races a slow nav.
    _probeTimer?.cancel();
    _probeTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) {
        _probeTimer?.cancel();
        return;
      }
      if (_probeTick++ > 40) {
        // ~2 min: give up auto-detection; user can use the manual Done button.
        _probeTimer?.cancel();
        return;
      }
      _controller.runJavaScript(MalToggleOverlay.sessionProbe);
    });
  }

  @override
  void dispose() {
    _probeTimer?.cancel();
    super.dispose();
  }

  void _finish() {
    _probeTimer?.cancel();
    Navigator.of(context).maybePop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
          onPressed: () => Navigator.of(context).maybePop(false),
        ),
        title: const Text('Sign in to MyAnimeList'),
        actions: [
          TextButton(
            onPressed: _finish,
            child: const Text('I\u2019ve signed in'),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: const Text(
                  'Sign in below, then we\u2019ll sync favorites automatically. '
                  'The session is reused by the app, so you won\u2019t need to log '
                  'in again for future favorites.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              Expanded(
                child: WebViewWidget(controller: _controller),
              ),
            ],
          ),
          if (_loading)
            const Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(minHeight: 3),
            ),
        ],
      ),
    );
  }
}
