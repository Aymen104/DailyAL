import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:dailyanimelist/api/credmal.dart';
import 'package:dailyanimelist/api/malconnect.dart';
import 'package:dailyanimelist/api/maluser.dart';
import 'package:dailyanimelist/cache/cachemanager.dart';
import 'package:dailyanimelist/constant.dart';
import 'package:dailyanimelist/util/streamutils.dart';
import 'package:dal_api/handlers/handler_core.dart';
import 'package:dal_commons/commons.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/src/media_type.dart';

enum FeatureFlag { aireviews }

class DalApi {
  static DalApi _internal = DalApi._();
  static DalApi i = _internal;
  late Future<Servers?> _dalConfigFuture;
  late Future<String> _preferredServer;
  late Future<Map<int, ScheduleData>> _scheduleForMalIds;
  late Future<List<AnimeAutoComplete>?> _autoCompleteFuture;
  final StreamListener<bool> autoCompleteCacheLoaded = StreamListener(false);
  Map<int, ScheduleData> _scheduleForMalIdsSync = {};
  bool _debugMode = kDebugMode;

  Future<Servers?> get dalConfigFuture async {
    return _dalConfigFuture;
  }

  Future<Map<int, ScheduleData>> get scheduleForMalIds async {
    return await _scheduleForMalIds.then((value) {
      _scheduleForMalIdsSync = value;
      return value;
    });
  }

  Map<int, ScheduleData> get scheduleForMalIdsSync => _scheduleForMalIdsSync;

  void onScheduleLoaded(void Function() callback) {
    _scheduleForMalIds.then((value) {
      callback();
    });
  }

  DalApi._() {
    _dalConfigFuture = _getDalConfigFuture();
    _preferredServer = _getPreferredServer();
    _scheduleForMalIds = _getScheduleForMalIds();
    _autoCompleteFuture = _getAutoCompleteFuture();
    _autoCompleteFuture.then((_) {
      logDal('autocomplete cache loaded');
      autoCompleteCacheLoaded.update(true);
    });
  }

  void resetScheduleForMalIds() {
    _scheduleForMalIds = _getScheduleForMalIds(fromCache: false);
  }

  Future<Servers> _getDalConfigFuture() async {
    final refUrl =
        '${CredMal.appConfigUrl}/${CredMal.buildVariant.name}/serverConfigV3${_debugMode ? 'Dev' : ''}.json';
    return Servers.fromJson(
      jsonDecode(await _getConfig(refUrl)),
    );
  }

  Future<String> _getConfig(String url) async {
    try {
      return (await MalConnect.retryGetNoH(url)).body;
    } catch (e) {
      logDal(e);
      return CredMal.defaultConfig;
    }
  }

  Future<String> _getPreferredServer() async {
    final config = (await _dalConfigFuture);
    final pfServers = config?.preferredServers;
    final strategy = config?.strategy ?? 'random';
    String? preferredServer;
    if (!nullOrEmpty(pfServers)) {
      if (strategy.equals('random')) {
        preferredServer =
            pfServers?.elementAt(Random().nextInt(pfServers.length)).url;
      } else if (strategy.equals('load')) {
        pfServers?.sort((a, b) => (a.load ?? 0) - (b.load ?? 0));
        preferredServer = pfServers?.first.url;
      } else if (strategy.equals('max_load_random')) {
        final availablePfServers = pfServers
            ?.where((e) => (config?.maxLoad ?? 0) < (e.load ?? 0))
            .toList();
        preferredServer = availablePfServers
            ?.elementAt(Random().nextInt(availablePfServers.length))
            .url;
      }
    }
    return preferredServer ?? 'http://0.0.0.0:8080/';
  }

  Future<dynamic> httpGet(String endpoint,
      [fromCache = true, int? timeInhours]) async {
    return MalConnect.getContent(
      '${await _preferredServer}$endpoint',
      fromCache: fromCache,
      retryOnFail: false,
      withNoHeaders: true,
      timeinHours: timeInhours,
    );
  }

  Future<DalRenderContent> getContent(String category, int id,
      {bool fromCache = true, bool htmlOnly = false}) async {
    return DalRenderContent.fromMap(
      await httpGet('$category/$id?htmlOnly=$htmlOnly', fromCache),
      category,
    );
  }

  Future<List<String>?> getPictures(int id, String category) async {
    final Map<String, dynamic>? chara = await httpGet('$category/$id/pics');
    return chara != null
        ? ((chara['pictures'] ?? <String>[]) as List<dynamic>)
            .map<String>((e) => e)
            .toList()
        : [];
  }

  Future<FeaturedResult> searchFeaturedArticles({
    String? query,
    int page = 1,
    String? tag,
    String category = "featured",
    String additonalCategory = "anime",
    String containerName = "news-list",
    int? id,
  }) async {
    final queryParams = <String, dynamic>{
      'page': page,
      'tag': tag,
      'additonalCategory': additonalCategory,
      'containerName': containerName,
      'id': id,
      'query': query,
    };
    return FeaturedResult.fromMap(
      await httpGet('$category?${buildQueryParams(queryParams)}', true, 2),
    );
  }

  Future<DataUnion?> getCharaPeopleInfo(int id, DataUnionType type) async {
    return JikanV4Result.fromJson(type, await httpGet('${type.name}/$id')).data;
  }

  Future<dynamic> getRecomData({
    int? id,
    String category = 'anime',
    int page = 1,
  }) async {
    return JikanV4Result.fromJson(
      DataUnionType.recomm_base,
      await httpGet('recommendations?id=$id&category=$category&page=$page'),
    )?.data;
  }

  Future<int?> getRandom(String category) async {
    final result = await MalConnect.getContent(
      '${CredMal.jikanV4}random/$category?sfw=false',
      withNoHeaders: true,
      fromCache: false,
      retryOnFail: false,
    );

    if (result != null && result is Map && result.containsKey('data')) {
      return result['data']['mal_id'];
    } else {
      return null;
    }
  }

  Future<int?> getRandomFromList(String category, String status) async {
    try {
      final result = await MalUser.getMyContentList(
        category: category,
        status: status,
        username: '@me',
        limit: 500,
      );
      if (!nullOrEmpty(result.data)) {
        int limit = result.data!.length;
        var node = result.data![Random().nextInt(limit)]?.content;
        return node?.id;
      }
    } catch (e) {
      logDal(e);
    }
    return null;
  }

  Future<CharacterListData> getCharacters([int page = 1]) async {
    return CharacterListData.fromJson(await httpGet('characters?page=$page'));
  }

  Future<PeopleListData> getPeople([int page = 1]) async {
    return PeopleListData.fromJson(await httpGet('people?page=$page'));
  }

  Future<List<RecomCompare>> getRecommendations(
    String category, [
    int page = 1,
  ]) async {
    return RecomListData.fromJson(
          await httpGet('recommendations?category=$category&page=$page'),
        ).data ??
        [];
  }

  Future<List<AnimeReviewHtml>> getReviews({
    int? id,
    String? category,
    int page = 1,
  }) async {
    return ListData<AnimeReviewHtml>.fromJson(
          await httpGet('reviews?category=$category&id=$id&page=$page'),
          (v) => AnimeReviewHtml.fromJson(v),
        ).data ??
        [];
  }

  Future<List<ScheduleData>> getSchedules({
    String type = 'all',
    SeasonType? season,
    int? year,
    bool fromCache = true,
  }) async {
    return ListData<ScheduleData>.fromJson(
            await httpGet(
                'schedules?${buildQueryParams({
                      'type': type,
                      'season': season?.name,
                      'year': year
                    })}',
                fromCache),
            (p0) => ScheduleData.fromJson(p0))?.data ??
        [];
  }

  Future<Map<int, ScheduleData>> _getScheduleForMalIds({
    String type = 'all',
    SeasonType? season,
    int? year,
    bool fromCache = true,
  }) async {
    return HashMap.fromEntries((await getSchedules(
            season: season, type: type, year: year, fromCache: fromCache))
        .map((e) => MapEntry(PathUtils.getIdUrl(e.relatedLinks?.mal), e))
        .where((e) => e.key != null)
        .map((e) => MapEntry(e.key!, e.value)));
  }

  Future<SearchResult> searchInterestStacks({
    int? id,
    String? category,
    int? categoryId,
    int page = 1,
    String? type,
    String? query,
  }) async {
    final list = await searchInterestStacksAsList(
      category: category,
      categoryId: categoryId,
      id: id,
      page: page,
      query: query,
      type: type,
    );
    return SearchResult(
        data: list.map((e) => BaseNode(content: e)).toList(),
        paging: Paging(
          previous: page.toString(),
          next: (page + 1).toString(),
        ));
  }

  Future<List<InterestStack>> searchInterestStacksAsList({
    int? id,
    String? category,
    int? categoryId,
    int page = 1,
    String? type,
    String? query,
  }) async {
    final result = await _getIntrestStacks(
        InterestStackType.search, id, category, categoryId, page, type, query);
    return ListData.fromJson(
          result,
          ((p0) => InterestStack.fromJson(p0)),
        ).data ??
        [];
  }

  Future<dynamic> _getIntrestStacks(
      InterestStackType stackType,
      int? id,
      String? category,
      int? categoryId,
      int? page,
      String? type,
      String? query) async {
    return await httpGet(
      'stacks/${stackType.name}?${buildQueryParams({
            'id': id,
            'category': category,
            'categoryId': categoryId,
            'page': page,
            'type': type,
            'query': query,
          })}',
    );
  }

  Future<List<InterestStack>> getInterestStackList({
    int? id,
    String? category,
    int? categoryId,
    int page = 1,
    String? type,
  }) async {
    final result = await _getIntrestStacks(
        InterestStackType.content, id, category, categoryId, page, type, null);
    return ListData.fromJson(
          result,
          ((p0) => InterestStack.fromJson(p0)),
        ).data ??
        [];
  }

  Future<InterestStackDetailed> getInterestStackDetailed(int id) async {
    final result = await _getIntrestStacks(
        InterestStackType.detailed, id, null, null, null, null, null);
    return InterestStackDetailed.fromMap(result);
  }

  Future<UserAbout?> getUserAbout(String username) async {
    final result = await httpGet(
      'users/about?${buildQueryParams({'username': username})}',
      false,
    );
    if (result is Map) {
      var data = result['data'];
      if (data is Map) {
        var about = data['about']?.toString();
        if (about != null) {
          return UserAbout(about, data['modern'] ?? false);
        }
      }
    }
    return null;
  }

  Future<FriendV4List> getUserFriends(String username) async {
    return JikanV4Result.fromJson(
      DataUnionType.friend,
      await httpGet(
        'users/friends?${buildQueryParams({'username': username})}',
        false,
      ),
    ).data as FriendV4List;
  }

  Future<ContentAllCharData> getAllCharsAndStaff(
      String category, int id) async {
    return ContentAllCharData.fromJson(
      await httpGet('content/characters?${buildQueryParams({
            'category': category,
            'id': id
          })}'),
    );
  }

  Future<ClubDetails> getClubData(int id) async {
    return ClubDetails.fromJson(await httpGet('clubs?id=$id', false) ?? {});
  }

  Future<List<ForumHtml>> getClubTopics(int id, int offset) async {
    return _mapAsList<ForumHtml>(
      await httpGet('clubs/type?id=$id&type=forum&offset=$offset', false),
      ForumHtml.fromJson,
    );
  }

  Future<List<Member>> getClubMember(int id, int offset) async {
    return _mapAsList<Member>(
      await httpGet('clubs/type?id=$id&type=members&offset=$offset', false),
      Member.fromJson,
    );
  }

  Future<List<Comment>> getClubComments(int id, int offset) async {
    return _mapAsList<Comment>(
      await httpGet('clubs/type?id=$id&type=comments&offset=$offset', false),
      Comment.fromJson,
    );
  }

  Future<UserHistoryData> getUserHistory(String username,
      {String? type}) async {
    return UserHistoryData.fromJson(
      await httpGet(
        'users/history?${buildQueryParams({
              'username': username,
              'type': type
            })}',
        false,
      ),
    );
  }

  Future<List<GenreType>> getGenreTypes(String category) async {
    return _mapAsList<GenreType>(
      await httpGet('genres?category=$category'),
      GenreType.fromJson,
    );
  }

  Future<dynamic> _apiGET(String endpoint,
      {Map<String, String>? customHeaders}) async {
    final apiURL = await _getAPIBaseUrl();
    return MalConnect.getContent(
      '$apiURL/$endpoint',
      retryOnFail: false,
      withNoHeaders: true,
      includeNsfw: false,
      headers: _headers(customHeaders),
    );
  }

  Map<String, String> _headers([Map<String, String>? customHeaders]) {
    return {
      'Authorization': 'Bearer ${CredMal.apiSecret}',
      if (customHeaders != null) ...customHeaders,
    };
  }

  Future<AnimeGraph> getAnimeGraph(int id, [String category = 'anime']) async {
    try {
      final result = await _apiGET(
        '$category/$id/related',
      );
      if (result is Map<String, dynamic> && result.isNotEmpty) {
        final graph = AnimeGraph.fromJson(result);
        if (!nullOrEmpty(graph.nodes) && !nullOrEmpty(graph.edges)) {
          return graph;
        }
      }
    } catch (e) {
      logDal(e);
    }
    return _getAnimeGraphFromTenrai(id, category);
  }

  /// Fallback graph: builds nodes/edges from Tenrai (Jikan v4) relations when
  /// the dal-api related endpoint fails. Try dal-api first, fall back here.
  Future<AnimeGraph> _getAnimeGraphFromTenrai(int id, String category) async {
    try {
      final relations = await _tenraiGet('${CredMal.jikanV4}$category/$id/relations');
      final data = relations?['data'] as List?;
      if (data == null) throw Error.throwWithStackTrace('no relations', StackTrace.current);
      final entryIds = <int>{};
      final relationMap = <int, String>{};
      final entryCategory = <int, String>{};
      for (final rel in data) {
        if (rel is! Map<String, dynamic>) continue;
        final relation = rel['relation']?.toString() ?? 'Other';
        for (final entry in (rel['entry'] as List? ?? [])) {
          if (entry is Map<String, dynamic>) {
            final mid = entry['mal_id'];
            if (mid is int) {
              entryIds.add(mid);
              relationMap[mid] = relation;
              final entryType = entry['type']?.toString();
              entryCategory[mid] = entryType == 'manga' ? 'manga' : category;
            }
          }
        }
      }
      entryIds.add(id);
      final details = await Future.wait(
        entryIds.map(
          (eid) => _tenraiGet('${CredMal.jikanV4}${entryCategory[eid] ?? category}/$eid'),
        ),
      );
      final nodes = <GraphNode>[];
      final nodeById = <int, GraphNode>{};
      for (final j in details) {
        final node = _graphNodeFromTenrai(j);
        if (node != null && node.id != null) {
          nodeById[node.id!] = node;
          nodes.add(node);
        }
      }
      final edges = <GraphEdge>[];
      final root = nodeById[id];
      for (final eid in entryIds) {
        if (nodeById[eid] == null) continue;
        final relationType = _toGRelationType(relationMap[eid] ?? 'Other');
        if (root != null && eid != id) {
          edges.add(GraphEdge(
            source: root.id,
            target: eid,
            relationType: relationType,
          ));
        }
      }
      if (nodes.isEmpty || edges.isEmpty) {
        throw Error.throwWithStackTrace('graph empty', StackTrace.current);
      }
      return AnimeGraph(nodes: nodes, edges: edges);
    } catch (e) {
      logDal(e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> _tenraiGet(String url) async {
    final response = await MalConnect.getContent(
      url,
      withNoHeaders: true,
      retryOnFail: false,
      includeNsfw: false,
      useTimeout: true,
      timeoutDuration: const Duration(seconds: 8),
    );
    return response is Map<String, dynamic> ? response : null;
  }

  GraphNode? _graphNodeFromTenrai(Map<String, dynamic>? json) {
    if (json == null) return null;
    final seasonKey = json['season']?.toString();
    final year = json['year'];
    GStartSeason? startSeason;
    if (seasonKey != null &&
        seasonKey.isNotEmpty &&
        seasonValues.map.containsKey(seasonKey) &&
        year != null) {
      startSeason = GStartSeason(
        year: year,
        season: seasonValues.map[seasonKey]!,
      );
    }
    return GraphNode(
      id: json['mal_id'] ?? json['id'],
      title: json['title']?.toString(),
      mainPicture: GMainPicture(
        medium: json['images']?['jpg']?['image_url'],
        large: json['images']?['jpg']?['large_image_url'],
      ),
      mean: (json['score'] as num?)?.toDouble(),
      mediaType: json['type']?.toString(),
      status: json['status']?.toString(),
      startSeason: startSeason,
    );
  }

  GRelationType _toGRelationType(String relation) {
    switch (relation.toLowerCase().replaceAll(' ', '_')) {
      case 'sequel':
        return GRelationType.sequel;
      case 'prequel':
        return GRelationType.prequel;
      case 'alternative_setting':
        return GRelationType.alternative_setting;
      case 'alternative_version':
        return GRelationType.alternative_version;
      case 'side_story':
        return GRelationType.side_story;
      case 'parent_story':
        return GRelationType.parent_story;
      case 'summary':
        return GRelationType.summary;
      case 'full_story':
        return GRelationType.full_story;
      case 'spin_off':
        return GRelationType.spin_off;
      case 'character':
        return GRelationType.character;
      default:
        return GRelationType.other;
    }
  }

  Future<bool> isFeatureEnabled(FeatureFlag flag) {
    return _dalConfigFuture.then((value) {
      return value?.featureFlags?[flag.name] ?? false;
    });
  }

  Future<ContentReviewSummary?> getReviewsSummary(List<String> reviews) async {
    try {
      final apiURL = '${await _getAPIBaseUrl()}/reviews';
      logDal('Sending reviews to $apiURL');
      final response = await http.post(
        Uri.parse(apiURL),
        headers: _headers(),
        body: jsonEncode(reviews),
      );
      final body = response.body;
      return ContentReviewSummary.fromJson(jsonDecode(body));
    } catch (e) {
      logDal(e);
      return null;
    }
  }

  Future<String> getSignedImageUrl(String type, String id) async {
    final response = await _apiGET('types/$type/images/$id');
    return response['signedURL'];
  }

  Future<void> saveImage(
      String type, String id, Uint8List data, String extension) async {
    final apiURL = await _getAPIBaseUrl();
    http.MultipartRequest request = http.MultipartRequest(
      'POST',
      Uri.parse('$apiURL/types/$type/images/$id'),
    );
    request.headers.addAll({
      'Authorization': 'Bearer ${CredMal.apiSecret}',
    });
    request.files.add(
      http.MultipartFile.fromBytes(
        'image',
        data,
        filename: '$id.image',
        contentType: MediaType('image', extension),
      ),
    );
    final response = await request.send();
    if (response.statusCode != 200) {
      throw Exception('Failed to save image');
    }
  }

  Future<String> _getAPIBaseUrl() async =>
      ((await _dalConfigFuture)?.dalAPIUrl ?? CredMal.apiURL);

  Future<void> removeImage(String type, String id) async {
    final baseUrl = await _getAPIBaseUrl();
    final url = '$baseUrl/types/$type/images/$id';
    final response = await http.delete(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer ${CredMal.apiSecret}',
      },
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete image');
    }
    await CacheManager.instance.setValue(url, '');
  }

  Future<List<AnimeAutoComplete>> autoCompleteAnime(
    String text, [
    int limit = 10,
  ]) async {
    final autoCompleteList = await _autoCompleteFuture;
    if (autoCompleteList == null) {
      return _searchAnimeFromTenrai(text, limit);
    }
    final lowerCase = text.toLowerCase();
    final results = autoCompleteList
        .where((e) =>
            e.title.toLowerCase().contains(lowerCase) ||
            e.synonyms.contains(lowerCase))
        .take(limit)
        .toList();
    if (results.isEmpty) {
      return _searchAnimeFromTenrai(text, limit);
    }
    return results;
  }

  /// Fallback autocomplete: server-side Tenrai (Jikan v4) search as you type,
  /// used when the dal-api autocomplete list is unreachable. Try dal-api
  /// first, and only fall back here when the other option fails.
  Future<List<AnimeAutoComplete>> _searchAnimeFromTenrai(
      String text, int limit) async {
    try {
      final uri = Uri.parse('${CredMal.jikanV4}anime').replace(
        queryParameters: {
          'q': text,
          'limit': '$limit',
          'sfw': 'false',
        },
      );
      final response = await MalConnect.getContent(
        uri.toString(),
        withNoHeaders: true,
        retryOnFail: true,
        includeNsfw: false,
        fromCache: true,
        timeinHours: 24,
      );
      if (response == null) return [];
      final data = response['data'];
      if (data is! List) return [];
      return data
          .map((e) => e is Map<String, dynamic>
              ? AnimeAutoComplete.fromJson({
                  'title': e['title'],
                  'picture': e['images']?['jpg']?['image_url'],
                  'year': e['year'],
                  'malId': e['mal_id']?.toString(),
                  'synonyms': (e['title_synonyms'] as List?)?.join(',') ?? '',
                })
              : null)
          .whereType<AnimeAutoComplete>()
          .toList();
    } catch (e) {
      logDal(e);
      return [];
    }
  }

  Future<List<AnimeAutoComplete>?> _getAutoCompleteFuture() async {
    try {
      final cachedData = await CacheManager.instance
          .getValueForServiceAutoExpire(
              'autocomplete', 'anime', 60 * 60 * 24 * 7);
      if (cachedData != null) {
        logDal('Using cached data for autocomplete');
        return AnimeAutoComplete.fromList(jsonDecode(cachedData));
      }
      final apiURL = await _getAPIBaseUrl();
      logDal('Sending request to $apiURL for autocomplete');
      final response = await http.get(Uri.parse('${apiURL}/anime'), headers: {
        ..._headers(),
      });
      final decodedBody = utf8.decode(response.bodyBytes);
      CacheManager.instance
          .setValueForServiceAutoExpireIn('autocomplete', 'anime', decodedBody);
      return AnimeAutoComplete.fromList(jsonDecode(decodedBody));
    } catch (e) {
      logDal(e);
      return null;
    }
  }
}

class UserAbout {
  final String about;
  final bool modern;
  const UserAbout(this.about, this.modern);
}

List<T> _mapAsList<T>(data, T Function(Map<String, dynamic>) mapper) {
  if (data is Map) {
    final list = data['data'];
    if (list is List) {
      return list
          .map((e) {
            if (e == null) {
              return null;
            } else {
              return mapper(e);
            }
          })
          .where((e) => e != null)
          .map((e) => e!)
          .toList();
    }
  }
  return [];
}
