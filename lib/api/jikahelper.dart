import 'dart:convert';

import 'package:dailyanimelist/api/credmal.dart';
import 'package:dailyanimelist/api/episodemodels.dart';
import 'package:dailyanimelist/api/jikan_models.dart';
import 'package:dailyanimelist/api/malconnect.dart';
import 'package:dailyanimelist/api/producermodels.dart';
import 'package:dailyanimelist/api/topmodels.dart';
import 'package:dailyanimelist/constant.dart';
import 'package:dailyanimelist/enums.dart';
import 'package:dailyanimelist/main.dart';
import 'package:dailyanimelist/cache/cachemanager.dart';
import 'package:dailyanimelist/screens/generalsearchscreen.dart';
import 'package:dailyanimelist/widgets/search/filtermodal.dart';
import 'package:dal_commons/commons.dart';
import 'package:dal_commons/dal_commons.dart';

class JikanHelper {
  static Future<SearchResult> getGenre({
    int id = 1,
    String category = "anime",
    bool fromCache = true,
    int page = 1,
    Function(dynamic)? onError,
  }) async {
    final genre = convertGenre(MalGenre(id: id), category);
    final filter = (category.equals("anime")
        ? CustomFilters.genresAnimeFilter
        : CustomFilters.genresMangaFilter)
      ..includedOptions = [genre];
    return await jikanSearch(
      '',
      category: category,
      filters: {'genres': filter},
      fromCache: fromCache,
      pageNumber: page,
    );
  }

  static Future<JikanV4Result<UserProfileV4>> getUserInfo(
      {bool fromCache = false,
      String? username,
      Function(dynamic)? onError}) async {
    return JikanV4Result.fromJson(
      DataUnionType.user,
      (await MalConnect.getContent('${CredMal.jikanV4}users/$username/full',
          withNoHeaders: true)),
    );
  }

  static Future<JikanV4Result<About>> getUserAbout(String username) async {
    return JikanV4Result.fromJson(
        DataUnionType.about,
        (await MalConnect.getContent('${CredMal.jikanV4}users/$username/about',
            withNoHeaders: true)));
  }

  static Future<ClubV4List> getUserClubs(String username) async {
    return JikanV4Result.fromJson(
            DataUnionType.club,
            (await MalConnect.getContent(
                '${CredMal.jikanV4}users/$username/clubs',
                withNoHeaders: true)))
        .data as ClubV4List;
  }

  static Future<UserFavV4> getUserFavorites(String username) async {
    return JikanV4Result.fromJson(
            DataUnionType.favorites,
            (await MalConnect.getContent(
                '${CredMal.jikanV4}users/$username/favorites',
                withNoHeaders: true)))
        .data as UserFavV4;
  }

  static Future<UserUpdateList> getUserUpdates(String category, int id) async {
    return JikanV4Result.fromJson(
            DataUnionType.userupdates,
            (await MalConnect.getContent(
                '${CredMal.jikanV4}$category/$id/userupdates',
                withNoHeaders: true)))
        .data as UserUpdateList;
  }

  static Future<Club?> getClubInfo(int id) async {
    return JikanV4Result.fromJson(
            DataUnionType.clubinfo,
            (await MalConnect.getContent('${CredMal.jikanV4}clubs/$id',
                withNoHeaders: true)))
        .data as Club?;
  }

  static Future<AnimeVideoV4?> getAnimeVideos(int id) async {
    return JikanV4Result.fromJson(
            DataUnionType.animevideo,
            (await MalConnect.getContent(
              '${CredMal.jikanV4}anime/$id/videos',
              withNoHeaders: true,
              useTimeout: true,
              retryOnFail: false,
              timeoutDuration: const Duration(seconds: 2),
            )))
        .data as AnimeVideoV4?;
  }

  static Future<JikanAnimeStatistics?> getAnimeScoreStatistics(int id) async {
    try {
      final url = '${CredMal.jikanV4}anime/$id/statistics';
      logDal('Fetching score statistics from: $url');

      final response = await MalConnect.getContent(
        url,
        withNoHeaders: true,
        useTimeout: true,
        retryOnFail: false,
        timeoutDuration: const Duration(seconds: 10),
      );

      if (response != null && response is Map<String, dynamic>) {
        logDal('Score statistics response received, parsing...');
        // MalConnect.getContent already returns decoded JSON, no need to jsonDecode
        final stats = JikanAnimeStatistics.fromJson(response['data']);
        logDal('Score statistics parsed successfully: ${stats.scores?.length ?? 0} scores');
        return stats;
      } else {
        logDal('Score statistics response is null or invalid type');
      }
      return null;
    } catch (e, stackTrace) {
      logDal('Error fetching anime statistics: $e\n$stackTrace');
      return null;
    }
  }

  static const useNewApiFields = ['genre', 'genres_exclude'];

  static Future<SearchResult> jikanSearch(String query,
      {String category = "character",
      bool fromCache = false,
      int pageNumber = 1,
      required Map<String, FilterOption> filters,
      Function(dynamic)? onError}) async {
    String custom = filterUrlBuilder(filters, category: category) ?? '';
    String url =
        "get-jikan-search-$category-for-$query-$pageNumber-${custom ?? ""}";
    if (fromCache) {
      var _result = SearchResult.fromJson(
          await CacheManager.instance.getCachedContent(url));
      if (_result?.data != null &&
          !shouldUpdateContent(
              result: _result,
              timeinHours: user.pref.cacheUpdateFrequency[homeIndex]) &&
          _result.data!.isNotEmpty) {
        return _result;
      }
    }
    var searchResult = SearchResult();
    try {
      String v4Url =
          '${CredMal.jikanV4}$category?q=${query ?? ''}&page=$pageNumber$custom';
      logDal(v4Url);
      var response = await MalConnect.retryGet(v4Url, Map());
      if (response != null && response.statusCode == 200) {
        Map<String, dynamic> result = jsonDecode(response.body) ?? {};
        return SearchResult(
            data: (result["data"] ?? <BaseNode>[])
                .map<BaseNode>((e) => _fromMap(e, category))
                .toList(),
            paging: pageNumber == null
                ? Paging()
                : Paging(next: (pageNumber + 1).toString()));
      }
    } catch (e) {
      logDal(e);
    }

    CacheManager.instance.setCachedJson(url, searchResult);
    return searchResult;
  }

  static BaseNode _fromMap(dynamic e, String category) {
    var images = e["images"];
    String? url;
    if (images != null) {
      var jpg = images["jpg"];
      if (jpg != null) {
        url = jpg["image_url"];
      }
    }
    final Node node;

    if (e is Map<String, dynamic> && contentTypes.contains(category)) {
      final jikanAnime = JikanAnime.fromJson(e);
      node = AnimeDetailed.fromJikanJson(jikanAnime);
    } else {
      node = Node(
        id: e["mal_id"],
        title: e["title"] ?? e['name'],
        mainPicture: Picture(
          large: url,
          medium: url,
        ),
      );
    }

    return BaseNode(content: node);
  }

  static String? filterUrlBuilder(Map<String, FilterOption>? filters,
      {String category = "anime"}) {
    if (filters == null || filters.isEmpty) return null;
    String url = "";
    for (var entry in filters.entries) {
      String field = entry.key;
      FilterOption option = entry.value;
      switch (option.type) {
        case FilterType.multiple:
          String temp = "";
          if (option.includedOptions!.isNotEmpty) {
            for (var element in (option.includedOptions ?? [])) {
              temp +=
                  getApiValue(option.apiValues, option.values, element) + ",";
            }
            temp = temp.substring(0, temp.length - 1);
            url += "&$field=$temp";
          }
          if (option.excludedOptions != null &&
              option.excludedOptions!.isNotEmpty) {
            String excludeTemp = "";
            for (var element in option.excludedOptions!) {
              excludeTemp +=
                  getApiValue(option.apiValues, option.values, element) + ",";
            }
            excludeTemp = excludeTemp.substring(0, excludeTemp.length - 1);
            url += "&${option.excludeFieldName}=$excludeTemp";
          }
          break;
        default:
          String? value;
          if (option.apiValues != null) {
            value = getApiValue(option.apiValues, option.values, option.value);
          }
          url += "&$field=${value ?? option.value}";
      }
    }
    if (["anime", "manga"].contains(category) &&
        !url.contains("order_by") &&
        !url.contains("score")) {
      url += "&order_by=members&sort=desc";
    }
    return url;
  }

  static String getApiValue(apiValues, values, value) {
    try {
      return apiValues.elementAt(values.indexOf(value)).toString();
    } catch (e) {}
    return '';
  }

  static Future<SearchResult?> getAnimeReviews(int id) async {
    final url = CredMal.htmlEnd + 'anime/$id/_/reviews';
    return MalConnect.htmlListPage(url, '', (p0) => null);
  }

  /// Get a company (producer/studio/licensor) details from the Jikan-compatible
  /// (Tenrai) `/producers/{id}/full` endpoint. Mirrors the MAL company page:
  /// name, established date, favorites, work count, about/biography, official
  /// links.
  static Future<ProducerV4> getProducerInfo(int id,
      {Function(dynamic)? onError}) async {
    try {
      final url = '${CredMal.jikanV4}producers/$id/full';
      logDal('Fetching producer info from: $url');
      final response = await MalConnect.getContent(url,
          withNoHeaders: true);
      if (response != null && response is Map<String, dynamic>) {
        final data = response['data'];
        if (data is Map<String, dynamic>) {
          return ProducerV4.fromJson(data);
        }
      }
      return ProducerV4(malId: id);
    } catch (e) {
      logDal('Error fetching producer info: $e');
      onError?.call(e);
      return ProducerV4(malId: id);
    }
  }

  /// Get all anime a company is credited on (producer/studio/licensor roles),
  /// paginated. Uses order_by=start_date&sort=desc like MAL's works page.
  static Future<SearchResult> getProducerWorks(int id, {int page = 1}) async {
    try {
      final v4Url =
          '${CredMal.jikanV4}anime?producers=$id&page=$page&order_by=start_date&sort=desc';
      logDal(v4Url);
      var response = await MalConnect.retryGet(v4Url, Map());
      if (response != null && response.statusCode == 200) {
        Map<String, dynamic> result = jsonDecode(response.body) ?? {};
        final items = (result["data"] ?? <BaseNode>[]);
        return SearchResult(
          data: (items as List)
              .map<BaseNode>((e) => _fromMap(e, 'anime'))
              .toList(),
          paging: Paging(next: (page + 1).toString()),
        );
      }
    } catch (e) {
      logDal(e);
    }
    return SearchResult();
  }

  /// Get the episode list of an anime from the Jikan-compatible (Tenrai)
  /// `/anime/{id}/episodes` endpoint.
  static Future<AnimeEpisodesResult> getAnimeEpisodes(int id,
      {int page = 1}) async {
    try {
      final v4Url = '${CredMal.jikanV4}anime/$id/episodes?page=$page';
      logDal(v4Url);
      var response = await MalConnect.retryGet(v4Url, Map());
      if (response != null && response.statusCode == 200) {
        return AnimeEpisodesResult.fromJson(jsonDecode(response.body));
      }
    } catch (e) {
      logDal(e);
    }
    return const AnimeEpisodesResult();
  }

  /// Get the MAL top characters or top people ranking. Jikan/Tenrai payloads
  /// have no `rank` field, so it is derived from the page index (25/page).
  static Future<TopRankedPage> getTopRanked(String charaCategory,
      {int page = 1}) async {
    try {
      final endpoint = charaCategory.equals('person') ? 'people' : 'characters';
      final v4Url = '${CredMal.jikanV4}top/$endpoint?page=$page';
      logDal(v4Url);
      var response = await MalConnect.retryGet(v4Url, Map());
      if (response != null && response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>? ?? {};
        final items = body["data"] as List? ?? [];
        final pagination = body["pagination"] as Map<String, dynamic>?;
        final baseRank = (page - 1) * 25;
        return TopRankedPage(
          items: List.generate(items.length, (i) {
            final e = items[i];
            return TopRankedItem.fromJson(
              e is Map<String, dynamic> ? e : {},
              rank: baseRank + i + 1,
            );
          }),
          hasNext: pagination?["has_next_page"] == true,
        );
      }
    } catch (e) {
      logDal(e);
    }
    return const TopRankedPage();
  }

  /// Get the most recently added anime. MAL ids are monotonic, so
  /// `order_by=mal_id&sort=desc` returns the newest additions first.
  static Future<SearchResult> getRecentlyAdded({int page = 1}) async {
    try {
      final v4Url =
          '${CredMal.jikanV4}anime?order_by=mal_id&sort=desc&page=$page';
      logDal(v4Url);
      var response = await MalConnect.retryGet(v4Url, Map());
      if (response != null && response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>? ?? {};
        final items = body["data"] as List? ?? [];
        final pagination = body["pagination"] as Map<String, dynamic>?;
        return SearchResult(
          data: (items as List)
              .map<BaseNode>((e) => _fromMap(e, 'anime'))
              .toList(),
          paging: Paging(
              next: pagination?["has_next_page"] == true
                  ? (page + 1).toString()
                  : null),
        );
      }
    } catch (e) {
      logDal(e);
    }
    return SearchResult();
  }

  /// Get the producer/studio directory (list of companies), paginated, with
  /// optional name search.
  static Future<ProducersPage> getProducersList(
      {int page = 1, String query = ''}) async {
    try {
      final v4Url = '${CredMal.jikanV4}producers?page=$page&limit=25'
          '${query.isNotEmpty ? '&q=${Uri.encodeComponent(query)}' : ''}';
      logDal(v4Url);
      var response = await MalConnect.retryGet(v4Url, Map());
      if (response != null && response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>? ?? {};
        final items = (body["data"] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map((e) => ProducerV4.fromJson(e))
            .toList();
        final pagination = body["pagination"] as Map<String, dynamic>?;
        return ProducersPage(
          items: items,
          hasNext: pagination?["has_next_page"] == true,
        );
      }
    } catch (e) {
      logDal(e);
    }
    return const ProducersPage();
  }
}

class ProducersPage {
  final List<ProducerV4> items;
  final bool hasNext;

  const ProducersPage({this.items = const [], this.hasNext = false});
}
