import 'package:dailyanimelist/api/malfavorite.dart';
import 'package:dailyanimelist/screens/plainscreen.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Full-screen embedded browser for signing in to myanimelist.net so that
/// favorites can be synced to the real MAL account.
///
/// The session cookie is HttpOnly, so success is detected with an in-page
/// probe: an unauthenticated `fetch` of /mymessages.php redirects to login.php,
/// while an authenticated one does not.
class MalSiteLoginScreen extends StatefulWidget {
  const MalSiteLoginScreen({Key? key}) : super(key: key);

  @override
  State<MalSiteLoginScreen> createState() => _MalSiteLoginScreenState();
}

class _MalSiteLoginScreenState extends State<MalSiteLoginScreen> {
  final WebViewController _controller = WebViewController();
  bool _loggedIn = false;

  static const _probeJs = '''
(function(){
  fetch('https://myanimelist.net/mymessages.php', {credentials:'include', redirect:'follow'})
    .then(function(r){ AuthBridge.postMessage(r.url.indexOf('login.php') !== -1 ? 'NO' : 'YES'); })
    .catch(function(){ AuthBridge.postMessage('NO'); });
})();''';

  @override
  void initState() {
    super.initState();
    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) {
          _controller.runJavaScript(_probeJs);
        },
      ))
      ..addJavaScriptChannel(
        'AuthBridge',
        onMessageReceived: (JavaScriptMessage message) {
          if (message.message == 'YES') {
            _finish();
          }
        },
      );
    _controller.loadRequest(Uri.parse('https://myanimelist.net/login.php'));
  }

  Future<void> _finish() async {
    if (_loggedIn) return;
    setState(() => _loggedIn = true);
    await MalFavorite.setSiteLogin(true);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TitlebarScreen(
      Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              'Sign in to your MyAnimeList account. Your likes are saved to '
              'your MAL profile, exactly like the "Add to Favorites" button '
              'on the website.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            if (_loggedIn)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Signed in successfully',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            const SizedBox(height: 12),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: WebViewWidget(controller: _controller),
              ),
            ),
          ],
        ),
      ),
      appbarTitle: 'MyAnimeList Sign in',
      actions: [
        IconButton(
          tooltip: 'Done',
          onPressed: _finish,
          icon: const Icon(Icons.done),
        ),
      ],
    );
  }
}