import 'package:dailyanimelist/api/jikahelper.dart';
import 'package:dailyanimelist/constant.dart';
import 'package:dailyanimelist/generated/l10n.dart';
import 'package:dailyanimelist/widgets/custombutton.dart';
import 'package:dailyanimelist/widgets/slivers.dart';
import 'package:dailyanimelist/util/responsive_helper.dart';
import 'package:dailyanimelist/screens/generalsearchscreen.dart';
import 'package:dailyanimelist/widgets/listsortfilter.dart';
import 'package:dailyanimelist/widgets/user/contentlistwidget.dart';
import 'package:dal_commons/commons.dart';
import 'package:flutter/material.dart';

class RecentAddedScreen extends StatefulWidget {
  const RecentAddedScreen({super.key});

  @override
  State<RecentAddedScreen> createState() => _RecentAddedScreenState();
}

class _RecentAddedScreenState extends State<RecentAddedScreen> {
  final List<BaseNode> items = [];
  int page = 1;
  bool hasMore = true;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadMore();
  }

  Future<void> loadMore() async {
    if (loading) return;
    setState(() => loading = true);
    final result = await JikanHelper.getRecentlyAdded(page: page);
    if (!mounted) return;
    setState(() {
      if (result.data != null) items.addAll(result.data!);
      hasMore = result.data?.isNotEmpty ?? false;
      page++;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.current.Recently_Added)),
      body: items.isEmpty && loading
          ? loadingCenter()
          : CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  sliver: _worksGrid(),
                ),
                if (hasMore) SliverToBoxAdapter(child: _loadMoreButton()),
                SB.lh30,
              ],
            ),
    );
  }

  Widget _worksGrid() {
    return ContentListWithDisplayType(
      category: 'anime',
      items: items,
      sortFilterDisplay: SortFilterDisplay.withDisplayType(
        DisplayOption(
          displayType: DisplayType.grid,
          displaySubType: DisplaySubType.compact,
          gridCrossAxisCount: ResponsiveHelper.getCrossAxisCount(context),
        ),
      ),
      showEdit: false,
      showIndex: false,
      showStatus: false,
      updateCacheOnEdit: false,
    );
  }

  Widget _loadMoreButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      child: Center(
        child: loading
            ? const CircularProgressIndicator()
            : PlainButton(
                onPressed: loadMore,
                child: Text(S.current.Load_More),
              ),
      ),
    );
  }
}