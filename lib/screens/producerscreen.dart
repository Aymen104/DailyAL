import 'package:cached_network_image/cached_network_image.dart';
import 'package:dailyanimelist/api/jikahelper.dart';
import 'package:dailyanimelist/api/producermodels.dart';
import 'package:dailyanimelist/generated/l10n.dart';
import 'package:dailyanimelist/screens/generalsearchscreen.dart';
import 'package:dailyanimelist/util/responsive_helper.dart';
import 'package:dailyanimelist/widgets/background.dart';
import 'package:dailyanimelist/widgets/custombutton.dart';
import 'package:dailyanimelist/widgets/listsortfilter.dart';
import 'package:dailyanimelist/widgets/slivers.dart';
import 'package:dailyanimelist/widgets/user/contentlistwidget.dart';
import 'package:dal_commons/commons.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constant.dart';

final NumberFormat _userCountFormat = NumberFormat.compact();

class ProducerScreen extends StatefulWidget {
  final int producerId;
  final String? producerName;
  const ProducerScreen({
    super.key,
    required this.producerId,
    this.producerName,
  });

  @override
  State<ProducerScreen> createState() => _ProducerScreenState();
}

class _ProducerScreenState extends State<ProducerScreen> {
  ProducerV4? producer;
  final List<BaseNode> works = [];
  int page = 1;
  bool hasMore = true;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    getProducer();
    loadFirstPage();
  }

  Future<void> getProducer() async {
    final p = await JikanHelper.getProducerInfo(widget.producerId);
    if (mounted) {
      setState(() => producer = p);
    }
  }

  Future<void> loadFirstPage() async {
    final result = await JikanHelper.getProducerWorks(widget.producerId);
    if (!mounted) return;
    setState(() {
      if (result.data != null) works.addAll(result.data!);
      hasMore = result.data?.isNotEmpty ?? false;
      page++;
      loading = false;
    });
  }

  Future<void> loadMore() async {
    if (loading) return;
    setState(() => loading = true);
    final result =
        await JikanHelper.getProducerWorks(widget.producerId, page: page);
    if (!mounted) return;
    setState(() {
      if (result.data != null) works.addAll(result.data!);
      hasMore = result.data?.isNotEmpty ?? false;
      page++;
      loading = false;
    });
  }

  String get _producerTitle {
    return producer?.name ?? widget.producerName ?? '?';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          _appBar(innerBoxIsScrolled),
        ],
        body: producer == null ? loadingCenter() : _body(),
      ),
    );
  }

  SliverAppBar _appBar(bool innerBoxIsScrolled) {
    return SliverAppBar(
      expandedHeight: 240.0,
      pinned: true,
      title: innerBoxIsScrolled ? Text(_producerTitle) : null,
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: headerWidget(),
      ),
      actions: [
        IconButton(
          onPressed: () {
            final url = producer?.url;
            if (url != null) launchURL(url);
          },
          icon: Icon(Icons.open_in_new),
        ),
      ],
    );
  }

  Widget headerWidget() {
    return Stack(
      children: [
        if (producer?.imageUrl != null)
          SizedBox(
            child: Background(
              context: context,
              url: producer?.imageUrl,
              forceBg: true,
            ),
          ),
        Padding(
          padding: EdgeInsets.only(top: 100.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(
                width: 20,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          _producerTitle,
                          textAlign: TextAlign.start,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      if (producer?.japaneseName != null) ...[
                        SB.h5,
                        Expanded(
                          flex: 2,
                          child: Text(
                            producer?.japaneseName ?? '?',
                            textAlign: TextAlign.start,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ],
                      SB.h15,
                    ],
                  ),
                ),
              ),
              if (producer?.imageUrl != null) ...[
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Theme.of(context).colorScheme.surface, width: 3),
                  ),
                  child: ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: producer?.imageUrl ?? '',
                      fit: BoxFit.cover,
                      placeholder: (_, __) => cardLoading(
                        height: 70,
                        width: 70,
                        radius: 100,
                      ),
                    ),
                  ),
                ),
                SB.w20,
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _body() {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _infoSection()),
        if (works.isEmpty && loading)
          SliverToBoxAdapter(
            child: Padding(padding: const EdgeInsets.all(40), child: loadingCenter()),
          )
        else ...[
          SB.lh10,
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            sliver: _worksGrid(),
          ),
          if (hasMore) SliverToBoxAdapter(child: _loadMoreButton()),
          SB.lh30,
        ],
      ],
    );
  }

  Widget _infoSection() {
    final p = producer!;
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        children: [
          if (p.established != null ||
              p.favorites != null ||
              p.count != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _infoField('Established', _formatEstablished(p.established)),
                _infoField('Member Favorites',
                    p.favorites == null ? '?' : _userCountFormat.format(p.favorites)),
                _infoField('Works', p.count == null ? '?' : _userCountFormat.format(p.count)),
              ],
            ),
          if (p.about != null && p.about!.isNotEmpty) ...[
            SB.h15,
            Divider(color: Theme.of(context).dividerColor),
            SB.h10,
            Text(
              p.about!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (p.external != null && p.external!.isNotEmpty) ...[
            SB.h15,
            Divider(color: Theme.of(context).dividerColor),
            SB.h10,
            Text(
              'Available At',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SB.h10,
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: p.external!
                  .map((e) => ShadowButton(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        onPressed: () {
                          if (e.url != null) launchURL(e.url!);
                        },
                        child: Text(
                          e.name ?? '?',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.color
                      ?.withOpacity(.7),
                ),
          ),
          SB.h5,
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }

  String _formatEstablished(String? established) {
    if (established == null || established.isEmpty) return '?';
    try {
      final date = DateTime.tryParse(established);
      if (date == null) return established;
      final months = const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final month = months[date.month - 1];
      return '$month ${date.day}, ${date.year}';
    } catch (e) {
      logDal(e);
      return established;
    }
  }

  Widget _worksGrid() {
    return ContentListWithDisplayType(
      category: 'anime',
      items: works,
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
        child: PlainButton(
          onPressed: loadMore,
          child: Text(S.current.Load_More),
        ),
      ),
    );
  }
}