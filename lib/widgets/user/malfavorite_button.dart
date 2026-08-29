import 'package:dailyanimelist/api/malfavorite.dart';
import 'package:dailyanimelist/constant.dart';
import 'package:dailyanimelist/screens/malsite_login_screen.dart';
import 'package:dailyanimelist/widgets/web/mal_toggle_overlay.dart';
import 'package:flutter/material.dart';

/// Heart toggle ("Add to Favorites / Remove from Favorites") that syncs with a
/// real MyAnimeList account — same as the MAL website button.
class MalFavoriteButton extends StatefulWidget {
  /// `character` or `people`.
  final String type;
  final int id;
  const MalFavoriteButton({
    Key? key,
    required this.type,
    required this.id,
  }) : super(key: key);

  @override
  State<MalFavoriteButton> createState() => _MalFavoriteButtonState();
}

class _MalFavoriteButtonState extends State<MalFavoriteButton> {
  bool? _isFav;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final fav = await MalFavorite.isFavorited(widget.type, widget.id);
    if (mounted) {
      setState(() => _isFav = fav);
    }
  }

  Future<bool> _promptSignIn() async {
    if (!mounted) return false;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add to favorites'),
        content: const Text(
          'Favorites are synced to your MyAnimeList account. '
          'Sign in to myanimelist.net to continue.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
    if (go != true) return false;
    if (!mounted) return false;
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const MalSiteLoginScreen()),
    );
    return ok == true;
  }

  Future<void> _toggle() async {
    if (_busy) return;
    final add = _isFav != true;
    setState(() => _busy = true);

    if (!await MalFavorite.hasSiteLogin()) {
      setState(() => _busy = false);
      final signedIn = await _promptSignIn();
      if (!signedIn || !mounted) return;
      setState(() => _busy = true);
    }

    if (!mounted) return;
    final outcome = await runMalToggle(
      context,
      type: widget.type,
      id: widget.id,
      add: add,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (outcome == null) {
      showToast("Couldn't sync with MyAnimeList. Try again.");
      return;
    }
    final result = MalFavorite.fromOutcome(outcome, wasAdded: add);
    if (result.ok) {
      setState(() => _isFav = add);
      showToast(
          add ? 'Added to favorites successfully!' : 'Removed from favorites.');
    } else if (result.needsAuth) {
      await MalFavorite.setSiteLogin(false);
      showToast(result.message ?? 'Please sign in again.');
      final signedIn = await _promptSignIn();
      if (signedIn && mounted) _toggle();
    } else {
      showToast(result.message ?? "Couldn't update favorites.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFav = _isFav == true;
    return IconButton(
      tooltip: isFav ? 'Remove from Favorites' : 'Add to Favorites',
      onPressed: _busy ? null : _toggle,
      icon: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              isFav ? Icons.favorite : Icons.favorite_border,
              color: isFav ? Colors.redAccent : null,
            ),
    );
  }
}