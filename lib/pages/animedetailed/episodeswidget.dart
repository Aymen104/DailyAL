import 'package:dailyanimelist/api/episodemodels.dart';
import 'package:dailyanimelist/api/jikahelper.dart';
import 'package:dailyanimelist/constant.dart';
import 'package:dailyanimelist/generated/l10n.dart';
import 'package:dailyanimelist/widgets/custombutton.dart';
import 'package:dal_commons/commons.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class EpisodesWidget extends StatefulWidget {
  final int animeId;
  final double horizPadding;
  const EpisodesWidget({
    super.key,
    required this.animeId,
    required this.horizPadding,
  });

  @override
  State<EpisodesWidget> createState() => _EpisodesWidgetState();
}

class _EpisodesWidgetState extends State<EpisodesWidget> {
  final List<EpisodeV4> episodes = [];
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
    final result = await JikanHelper.getAnimeEpisodes(widget.animeId,
        page: page);
    if (!mounted) return;
    setState(() {
      episodes.addAll(result.items);
      hasMore = result.hasNext;
      page++;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (episodes.isEmpty && loading) {
      return Padding(
        padding: const EdgeInsets.all(30),
        child: loadingCenter(),
      );
    }
    if (episodes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(S.current.No_More_found),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...episodes.asMap().entries.map((e) => _episodeTile(e.key, e.value)),
          if (hasMore)
            Center(
              child: PlainButton(
                onPressed:
                    loading ? () {} : loadMore,
                child: Text(S.current.Load_More),
              ),
            ),
        ],
      ),
    );
  }

  Widget _episodeTile(int index, EpisodeV4 e) {
    final textTheme = Theme.of(context).textTheme;
    final epNumber = e.malId ?? (index + 1);
    final title = e.titleRomanji ?? e.title ?? '${S.current.Episodes} $epNumber';
    final subtitle = [
      if (e.titleJapanese != null && e.titleJapanese!.isNotBlank)
        e.titleJapanese,
      if (e.duration != null && e.duration!.isNotBlank) e.duration,
    ].join('  ·  ');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showEpisodeDialog(e),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 42,
                width: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Theme.of(context).colorScheme.surfaceVariant,
                ),
                child: Text(
                  '$epNumber',
                  style: textTheme.titleMedium,
                ),
              ),
              SB.w15,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleSmall,
                          ),
                        ),
                        if (e.filler || e.recap) ...[
                          SB.w10,
                          Text(
                            [if (e.filler) 'FILLER', if (e.recap) 'RECAP']
                                .join(' '),
                            style: textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (subtitle.isNotBlank) ...[
                      SB.h4,
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall,
                      ),
                    ],
                    if (_airedDate(e.aired) != null) ...[
                      SB.h2,
                      Text(
                        DateFormat('MMM d, y').format(_airedDate(e.aired)!),
                        style: textTheme.labelSmall?.copyWith(
                          color: textTheme.labelSmall?.color?.withOpacity(.7),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (e.score != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Row(
                    children: [
                      Icon(Icons.star, size: 16, color: Colors.amber),
                      SB.w4,
                      Text(
                        e.score.toStringAsFixed(1),
                        style: textTheme.labelSmall,
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

  DateTime? _airedDate(String? aired) {
    if (aired == null || aired.isEmpty) return null;
    return DateTime.tryParse(aired)?.toLocal();
  }

  void _showEpisodeDialog(EpisodeV4 e) {
    final epNumber = e.malId ?? 0;
    final title = e.titleRomanji ?? e.title ?? '${S.current.Episodes} $epNumber';
    openAlertDialog(
      context: context,
      title: title,
      useDefaultBtns: false,
      additionalAction: alertButton(context, S.current.Close),
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (e.titleJapanese != null && e.titleJapanese!.isNotBlank)
              Text(
                e.titleJapanese!,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            if (_airedDate(e.aired) != null) ...[
              SB.h8,
              Text('${S.current.Aired}: ' +
                  DateFormat('MMM d, y').format(_airedDate(e.aired)!)),
            ],
            if (e.duration != null && e.duration!.isNotBlank) ...[
              SB.h8,
              Text(e.duration!),
            ],
            if (e.synopsis != null && e.synopsis!.isNotBlank) ...[
              SB.h15,
              Text(
                S.current.Synopsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              SB.h8,
              Text(
                e.synopsis!,
                textAlign: TextAlign.justify,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (e.forumUrl != null && e.forumUrl!.isNotBlank) ...[
              SB.h15,
              ShadowButton(
                onPressed: () => launchURLWithConfirmation(
                  e.forumUrl!,
                  context: context,
                ),
                child: Text(
                  S.current.Discussions,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}