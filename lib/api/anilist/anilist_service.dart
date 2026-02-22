import 'dart:convert';

import 'package:dailyanimelist/api/anilist/anilist_models.dart';
import 'package:dailyanimelist/main.dart';
import 'package:dal_commons/dal_commons.dart';
import 'package:http/http.dart' as http;

/// AniList GraphQL API service.
class AniListService {
  static const _graphqlUrl = 'https://graphql.anilist.co';

  /// Common fragment for media list entry fields.
  static const _entryFields = '''
    id
    status
    score(format: POINT_10_DECIMAL)
    progress
    progressVolumes
    startedAt { year month day }
    completedAt { year month day }
    repeat
    notes
    private
  ''';

  // ─── Viewer ───────────────────────────────────────────────────────

  /// Fetch the currently authenticated AniList user.
  static Future<AniListUser?> getViewer([String? token]) async {
    token ??= user.anilistToken;
    if (token == null) return null;

    const query = '''
    query {
      Viewer {
        id
        name
        avatar { large medium }
      }
    }
    ''';

    final body = await _post(query, token: token);
    if (body == null) return null;
    final viewer = body['data']?['Viewer'] as Map<String, dynamic>?;
    if (viewer == null) return null;
    return AniListUser.fromJson(viewer);
  }

  // ─── Search by MAL ID ─────────────────────────────────────────────

  /// Resolve a MAL ID to an AniList media entry (includes list status).
  static Future<AniListMediaEntry?> searchMediaByMalId(
    int malId,
    String category,
  ) async {
    if (user.anilistToken == null) return null;

    final type = category == 'anime' ? 'ANIME' : 'MANGA';
    final query = '''
    query (\$malId: Int, \$type: MediaType) {
      Media(idMal: \$malId, type: \$type) {
        id
        mediaListEntry {
          $_entryFields
        }
      }
    }
    ''';

    final body = await _post(query, variables: {
      'malId': malId,
      'type': type,
    });
    if (body == null) return null;

    final media = body['data']?['Media'] as Map<String, dynamic>?;
    if (media == null) return null;
    return AniListMediaEntry.fromJson(media, category);
  }

  // ─── Save ────────────────────────────────────────────────────────

  /// Save (create/update) a media list entry on AniList.
  static Future<AniListSaveResult?> saveMediaListEntry({
    required int mediaId,
    String? status,
    double? score,
    int? progress,
    int? progressVolumes,
    String? startedAt,
    String? completedAt,
    int? repeat,
    String? notes,
    bool? private_,
    required String category,
  }) async {
    if (user.anilistToken == null) return null;

    // If status is a MAL key, convert to AniList enum
    final aniStatus = status != null
        ? (malStatusToAniList[transformStatusKey(status)] ?? status)
        : null;

    final mutation = '''
    mutation (
      \$mediaId: Int,
      \$status: MediaListStatus,
      \$score: Float,
      \$progress: Int,
      \$progressVolumes: Int,
      \$startedAt: FuzzyDateInput,
      \$completedAt: FuzzyDateInput,
      \$repeat: Int,
      \$notes: String,
      \$private: Boolean
    ) {
      SaveMediaListEntry(
        mediaId: \$mediaId,
        status: \$status,
        score: \$score,
        progress: \$progress,
        progressVolumes: \$progressVolumes,
        startedAt: \$startedAt,
        completedAt: \$completedAt,
        repeat: \$repeat,
        notes: \$notes,
        private: \$private
      ) {
        $_entryFields
      }
    }
    ''';

    final variables = <String, dynamic>{
      'mediaId': mediaId,
      if (aniStatus != null) 'status': aniStatus,
      if (score != null) 'score': score,
      if (progress != null) 'progress': progress,
      if (progressVolumes != null) 'progressVolumes': progressVolumes,
      if (startedAt != null) 'startedAt': stringToFuzzyDate(startedAt),
      if (completedAt != null) 'completedAt': stringToFuzzyDate(completedAt),
      if (repeat != null) 'repeat': repeat,
      if (notes != null) 'notes': notes,
      if (private_ != null) 'private': private_,
    };

    final body = await _post(mutation, variables: variables);
    if (body == null) return null;

    final entry = body['data']?['SaveMediaListEntry'] as Map<String, dynamic>?;
    if (entry == null) return null;
    return AniListSaveResult.fromJson(entry, category);
  }

  // ─── Delete ──────────────────────────────────────────────────────

  /// Delete a media list entry on AniList.
  static Future<bool> deleteMediaListEntry(int entryId) async {
    if (user.anilistToken == null) return false;

    const mutation = '''
    mutation (\$id: Int) {
      DeleteMediaListEntry(id: \$id) {
        deleted
      }
    }
    ''';

    final body = await _post(mutation, variables: {'id': entryId});
    return body?['data']?['DeleteMediaListEntry']?['deleted'] == true;
  }

  // ─── Convenience wrappers (MAL ID based) ──────────────────────────

  /// Resolve MAL ID → AniList media ID → save entry.
  static Future<AniListSaveResult?> updateByMalId({
    required int malId,
    required String category,
    String? status,
    double? score,
    int? progress,
    int? progressVolumes,
    String? startedAt,
    String? completedAt,
    int? repeat,
    String? notes,
    bool? private_,
  }) async {
    final entry = await searchMediaByMalId(malId, category);
    if (entry == null) {
      logDal('AniList: Could not find media for MAL ID $malId');
      return null;
    }
    return saveMediaListEntry(
      mediaId: entry.mediaId,
      status: status,
      score: score,
      progress: progress,
      progressVolumes: progressVolumes,
      startedAt: startedAt,
      completedAt: completedAt,
      repeat: repeat,
      notes: notes,
      private_: private_,
      category: category,
    );
  }

  /// Resolve MAL ID → AniList entry ID → delete.
  static Future<bool> deleteByMalId(int malId, String category) async {
    final entry = await searchMediaByMalId(malId, category);
    if (entry?.entryId == null) {
      logDal('AniList: No list entry for MAL ID $malId');
      return false;
    }
    return deleteMediaListEntry(entry!.entryId!);
  }

  // ─── User List ───────────────────────────────────────────────────

  /// Fetch the authenticated user's media list collection.
  static Future<SearchResult> getUserMediaList({
    required String category,
    String? status,
    int limit = 100,
    int page = 1,
    String? sort,
  }) async {
    if (user.anilistToken == null) return SearchResult();

    final type = category == 'anime' ? 'ANIME' : 'MANGA';
    final statusEnum = status != null
        ? (malStatusToAniList[transformStatusKey(status)] ?? status)
        : null;

    // Map sort options
    String? anilistSort;
    if (sort != null) {
      switch (sort) {
        case 'list_score':
          anilistSort = 'SCORE_DESC';
          break;
        case 'list_updated_at':
          anilistSort = 'UPDATED_TIME_DESC';
          break;
        case 'anime_title':
        case 'manga_title':
          anilistSort = 'MEDIA_TITLE_ROMAJI';
          break;
        case 'anime_start_date':
        case 'manga_start_date':
          anilistSort = 'STARTED_ON_DESC';
          break;
        default:
          anilistSort = 'UPDATED_TIME_DESC';
      }
    }

    final query = '''
    query (\$userId: Int, \$type: MediaType, \$status: MediaListStatus, \$page: Int, \$perPage: Int, \$sort: [MediaListSort]) {
      Page(page: \$page, perPage: \$perPage) {
        pageInfo {
          total
          currentPage
          lastPage
          hasNextPage
          perPage
        }
        mediaList(userId: \$userId, type: \$type, status: \$status, sort: \$sort) {
          id
          status
          score(format: POINT_10_DECIMAL)
          progress
          progressVolumes
          startedAt { year month day }
          completedAt { year month day }
          repeat
          notes
          private
          updatedAt
          media {
            id
            idMal
            title {
              romaji
              english
              native
            }
            coverImage {
              large
              medium
            }
            format
            status
            episodes
            chapters
            volumes
            averageScore
            meanScore
            genres
            startDate { year month day }
          }
        }
      }
    }
    ''';

    final viewer = await getViewer();
    if (viewer == null) return SearchResult();

    final body = await _post(query, variables: {
      'userId': viewer.id,
      'type': type,
      if (statusEnum != null) 'status': statusEnum,
      'page': page,
      'perPage': limit,
      if (anilistSort != null) 'sort': [anilistSort],
    });

    if (body == null) return SearchResult();

    final pageData = body['data']?['Page'];
    if (pageData == null) return SearchResult();

    final mediaList = pageData['mediaList'] as List?;
    if (mediaList == null) return SearchResult();

    // Convert AniList entries to BaseNode format
    final nodes = mediaList
        .map((entry) {
          final media = entry['media'];
          final malId = media['idMal'];

          if (malId == null) return null;

          // Convert AniList status to MAL status
          final aniStatus = entry['status'] as String?;
          final malStatus = category == 'anime'
              ? aniListStatusToMalAnime[aniStatus]
              : aniListStatusToMalManga[aniStatus];

          // Create a BaseNode-compatible structure
          return BaseNode.fromJson({
            'node': {
              'id': malId,
              'title': media['title']?['english'] ??
                  media['title']?['romaji'] ??
                  media['title']?['native'] ??
                  'Unknown',
              'main_picture': {
                'medium': media['coverImage']?['medium'],
                'large': media['coverImage']?['large'],
              },
              'alternative_titles': {
                'en': media['title']?['english'],
                'ja': media['title']?['native'],
              },
              'media_type': media['format'],
              'status': media['status'],
              'num_episodes': media['episodes'],
              'num_chapters': media['chapters'],
              'num_volumes': media['volumes'],
              'mean':
                  media['meanScore'] != null ? (media['meanScore'] as num) / 10.0 : null,
              'genres': media['genres']?.map((dynamic g) => {'name': g}).toList(),
              'start_date': media['startDate'] != null
                  ? '${media['startDate']['year']}-${media['startDate']['month']?.toString().padLeft(2, '0')}-${media['startDate']['day']?.toString().padLeft(2, '0')}'
                  : null,
            },
            'list_status': {
              'status': malStatus,
              'score':
                  entry['score'] != null ? (entry['score'] as num).toInt() : 0,
              'num_episodes_watched': entry['progress'] as int?,
              'num_chapters_read': entry['progress'] as int?,
              'num_volumes_read': entry['progressVolumes'] as int?,
              'is_rewatching': aniStatus == 'REPEATING',
              'is_rereading': aniStatus == 'REPEATING',
              'num_times_rewatched': entry['repeat'] as int? ?? 0,
              'num_times_reread': entry['repeat'] as int? ?? 0,
              'start_date': entry['startedAt'] != null
                  ? '${entry['startedAt']['year']}-${entry['startedAt']['month']?.toString().padLeft(2, '0')}-${entry['startedAt']['day']?.toString().padLeft(2, '0')}'
                  : null,
              'finish_date': entry['completedAt'] != null
                  ? '${entry['completedAt']['year']}-${entry['completedAt']['month']?.toString().padLeft(2, '0')}-${entry['completedAt']['day']?.toString().padLeft(2, '0')}'
                  : null,
              'comments': entry['notes'] as String?,
              'updated_at': entry['updatedAt'] != null
                  ? DateTime.fromMillisecondsSinceEpoch(
                          (entry['updatedAt'] as int) * 1000)
                      .toIso8601String()
                  : null,
            },
          });
        })
        .whereType<BaseNode>()
        .toList();

    final pageInfo = pageData['pageInfo'];
    return SearchResult(
      data: nodes,
      paging: Paging(
        next: pageInfo['hasNextPage'] == true
            ? '?page=${pageInfo['currentPage'] + 1}'
            : null,
      ),
    );
  }

  // ─── Internal ────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> _post(
    String query, {
    Map<String, dynamic>? variables,
    String? token,
  }) async {
    token ??= user.anilistToken;
    if (token == null) return null;

    try {
      final response = await http.post(
        Uri.parse(_graphqlUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'query': query,
          if (variables != null) 'variables': variables,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        logDal(
            'AniList GraphQL error ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      logDal('AniList GraphQL exception: $e');
      return null;
    }
  }
}
