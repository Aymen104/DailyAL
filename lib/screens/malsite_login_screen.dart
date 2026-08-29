import 'package:dailyanimelist/api/credmal.dart';
import 'package:dailyanimelist/api/malfavorite.dart';
import 'package:dailyanimelist/screens/plainscreen.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Full-screen embedded browser for signing in to myanimelist.net so that
/// favorites can be synced to the real MAL account.
///
/// When the login succeeds the WebView cookie store receives the `MALCF`
/// session cookie; we read it and hand it back to [MalFavorite].
class MalSiteLoginScreen extends StatefulWidget {
  const MalSiteLoginScreen({Key? key}) : super(key: key);

  @override
  State<MalSiteLoginScreen> createState() => _MalSiteLoginScreenState();
}

class _MalSiteLoginScreenState extends State<MalSiteLoginScreen> {
  final WebViewController _controller = WebViewController();
  final WebViewCookieManager _cookieManager = WebViewCookieManager();
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: _onPageFinished,
      ));
    _controller.loadRequest(Uri.parse('${CredMal.htmlEnd}login.php'));
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _onPageFinished(String url) async {
    if (_loggedIn) return;
    try {
      final cookies = await _cookieManager
          .getCookies('https://myanimelist.net');
      final hasMalf =
          cookies.any((c) => c.name == 'MALCF' && c.value.isNotEmpty);
      final isLoggedIn =
          cookies.any((c) => c.name == 'is_logged_in' && c.value == '1');
      if (hasMalf || isLoggedIn) {
        if (!mounted) return;
        setState(() => _loggedIn = true);
        final cookieString = cookies
            .where((c) => c.value.isNotEmpty)
            .map((c) => '${c.name}=${c.value}')
            .join('; ');
        await MalFavorite.storeSessionCookie(cookieString);
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (mounted) {
          Navigator.of(context).pop(cookieString);
        }
      }
    } catch (e) {
      // Keep the user on the login page; cookies just aren't readable yet.
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
                  const Icon(Icons.check_circle,
                      color: Colors.green, size: 18),
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
    );
  }
}