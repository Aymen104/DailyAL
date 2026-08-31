import 'package:dailyanimelist/api/malfavorite.dart';
import 'package:dailyanimelist/constant.dart';
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

  Future<void> _toggle() async {
    if (_busy) return;
    final add = _isFav != true;
    setState(() => _busy = true);

    if (!mounted) return;
    final outcome = await runMalToggle(
      context,
      type: widget.type,
      id: widget.id,
      add: add,
      autoLogin: true,
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
      showToast('Sign in to MyAnimeList first, then tap the heart again.');
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