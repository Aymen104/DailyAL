import 'package:dailyanimelist/api/auth/auth.dart';
import 'package:dailyanimelist/api/credmal.dart';
import 'package:dailyanimelist/api/malfavorite_session.dart';
import 'package:dailyanimelist/cache/cachemanager.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Android OAuth login handled inside the app's own WebView.
///
/// The custom-tab login keeps the myanimelist.net website session in Chrome's
/// cookie jar, which the app cannot read — so favorites still need a second
/// login later. Logging in inside this WebView drops the session into the
/// shared jar instead, so [MalSessionStore.captureFromWebView] can persist it
/// and the favorite toggle never asks for credentials again.
class MalSiteLoginScreen extends StatefulWidget {
  final String url;
  const MalSiteLoginScreen({super.key, required this.url});

  @override
  State<MalSiteLoginScreen> createState() => _MalSiteLoginScreenState();
}

class _MalSiteLoginScreenState extends State<MalSiteLoginScreen> {
  final WebViewController _controller = WebViewController();
  bool _loading = true;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) async {
            final url = request.url;
            if (url.startsWith('${CredMal.callbackUrlScheme}://')) {
              final uri = Uri.parse(url);
              final code = uri.queryParameters['code'];
              if (code != null) {
                final verifier = await CacheManager.instance.getValue('cc');
                if (verifier != null && await MalAuth.onCodeReceived(code, verifier)) {
                  await MalSessionStore.captureFromWebView();
                  _completed = true;
                  if (mounted) Navigator.of(context).pop(true);
                }
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (_) {
            if (mounted && !_loading) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted && _loading) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
          onPressed: () {
            if (!_completed) Navigator.of(context).pop();
          },
        ),
        title: const Text('Sign in to MyAnimeList'),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
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