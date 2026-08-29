import 'package:cached_network_image/cached_network_image.dart';
import 'package:dailyanimelist/api/jikahelper.dart';
import 'package:dailyanimelist/api/topmodels.dart';
import 'package:dailyanimelist/constant.dart';
import 'package:dailyanimelist/generated/l10n.dart';
import 'package:dailyanimelist/screens/characterscreen.dart';
import 'package:dailyanimelist/widgets/custombutton.dart';
import 'package:dailyanimelist/widgets/loading/loadingcard.dart';
import 'package:dailyanimelist/widgets/shimmecolor.dart';
import 'package:dal_commons/commons.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final NumberFormat _rankFavorites = NumberFormat.compact();

class TopRankedScreen extends StatefulWidget {
  final String charaCategory;
  final String appbarTitle;
  const TopRankedScreen({
    super.key,
    this.charaCategory = "character",
    required this.appbarTitle,
  });

  @override
  State<TopRankedScreen> createState() => _TopRankedScreenState();
}

class _TopRankedScreenState extends State<TopRankedScreen> {
  final List<TopRankedItem> items = [];
  int page = 1;
  bool hasMore = true;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    loadMore();
  }

  Future<void> loadMore() async {
    if (loading) return;
    setState(() => loading = true);
    final result =
        await JikanHelper.getTopRanked(widget.charaCategory, page: page);
    if (!mounted) return;
    setState(() {
      items.addAll(result.items);
      hasMore = result.hasNext;
      page++;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.appbarTitle)),
      body: items.isEmpty && loading
          ? loadingCenter()
          : CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(10),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _itemTile(items[index]),
                      childCount: items.length,
                    ),
                  ),
                ),
                if (hasMore)
                  SliverToBoxAdapter(child: _loadMoreSection()),
                SB.lh30,
              ],
            ),
    );
  }

  Widget _loadMoreSection() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: CircularProgressIndicator(),
              )
            : PlainButton(
                onPressed: loadMore,
                child: Text(S.current.Load_More),
              ),
      ),
    );
  }

  Widget _itemTile(TopRankedItem item) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => gotoPage(
          context: context,
          newPage: CharacterScreen(
            charaCategory: widget.charaCategory,
            id: item.id,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                alignment: Alignment.center,
                child: Column(
                  children: [
                    if (item.rank <= 3)
                      Icon(
                        Icons.emoji_events,
                        size: 18,
                        color: Colors.amber,
                      ),
                    Text(
                      '#${item.rank}',
                      style: textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              SB.w10,
              ClipRRect(
                borderRadius: borderRadius,
                child: CachedNetworkImage(
                  imageUrl: item.imageUrl ?? '',
                  width: 70,
                  height: 100,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => const ShimmerColor(
                    LoadingCard(width: 70, height: 100),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    width: 70,
                    height: 100,
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    child: const Icon(Icons.person),
                  ),
                ),
              ),
              SB.w15,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name ?? '?',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall,
                    ),
                    if (item.animeTitle != null &&
                        item.animeTitle!.isNotBlank) ...[
                      SB.h6,
                      Text(
                        item.animeTitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall,
                      ),
                    ],
                    SB.h6,
                    Row(
                      children: [
                        Icon(
                          Icons.favorite,
                          size: 16,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        SB.w6,
                        Text(
                          _rankFavorites.format(item.favorites ?? 0),
                          style: textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}