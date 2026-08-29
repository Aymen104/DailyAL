import 'package:cached_network_image/cached_network_image.dart';
import 'package:dailyanimelist/api/jikahelper.dart';
import 'package:dailyanimelist/api/producermodels.dart';
import 'package:dailyanimelist/constant.dart';
import 'package:dailyanimelist/generated/l10n.dart';
import 'package:dailyanimelist/screens/producerscreen.dart';
import 'package:dailyanimelist/widgets/custombutton.dart';
import 'package:dailyanimelist/widgets/loading/loadingcard.dart';
import 'package:dailyanimelist/widgets/shimmecolor.dart';
import 'package:dal_commons/commons.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';

final NumberFormat _dirFormat = NumberFormat.compact();

class ProducerDirectoryScreen extends StatefulWidget {
  const ProducerDirectoryScreen({super.key});

  @override
  State<ProducerDirectoryScreen> createState() =>
      _ProducerDirectoryScreenState();
}

class _ProducerDirectoryScreenState extends State<ProducerDirectoryScreen> {
  static final radius = 12.0;
  static final borderRadius = BorderRadius.circular(radius);
  final List<ProducerV4> producers = [];
  final TextEditingController _queryController = TextEditingController();
  Timer? _debounce;
  int page = 1;
  bool hasMore = true;
  bool loading = false;
  String query = '';

  @override
  void initState() {
    super.initState();
    loadMore();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  Future<void> loadMore() async {
    if (loading) return;
    setState(() => loading = true);
    final result = await JikanHelper.getProducersList(page: page, query: query);
    if (!mounted) return;
    setState(() {
      producers.addAll(result.items);
      hasMore = result.hasNext;
      page++;
      loading = false;
    });
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _resetAndSearch(value.trim());
    });
  }

  void _resetAndSearch(String value) {
    setState(() {
      query = value;
      producers.clear();
      page = 1;
      hasMore = true;
    });
    loadMore();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.current.Producers)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              controller: _queryController,
              onChanged: _onQueryChanged,
              decoration: InputDecoration(
                hintText: S.current.Search,
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
            ),
          ),
          Expanded(child: _producersList()),
        ],
      ),
    );
  }

  Widget _producersList() {
    if (producers.isEmpty && loading) return loadingCenter();
    if (producers.isEmpty) {
      return Center(child: Text(S.current.No_More_found));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      itemCount: producers.length + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= producers.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
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
        return _producerTile(producers[index]);
      },
    );
  }

  Widget _producerTile(ProducerV4 producer) {
    final textTheme = Theme.of(context).textTheme;
    final name = producer.name ?? '?';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => gotoPage(
          context: context,
          newPage: ProducerScreen(
            producerId: producer.malId ?? 0,
            producerName: name,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: borderRadius,
                child: producer.imageUrl != null &&
                        producer.imageUrl!.isNotBlank
                    ? CachedNetworkImage(
                        imageUrl: producer.imageUrl!,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const ShimmerColor(
                          LoadingCard(width: 60, height: 60),
                        ),
                        errorWidget: (_, __, ___) => _noLogo(textTheme),
                      )
                    : _noLogo(textTheme),
              ),
              SB.w15,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall,
                    ),
                    if (producer.count != null) ...[
                      SB.h5,
                      Text(
                        '${_dirFormat.format(producer.count)} Works',
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _noLogo(TextTheme textTheme) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: borderRadius,
      ),
      child: Icon(Icons.business, color: textTheme.bodySmall?.color),
    );
  }
}