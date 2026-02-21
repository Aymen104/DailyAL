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
    score(format: POINT_10)
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
    final viewer = body['data']?['Viewer'];
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

    final media = body['data']?['Media'];
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
    final aniStatus =
        status != null ? (malStatusToAniList[status] ?? status) : null;

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

    final entry = body['data']?['SaveMediaListEntry'];
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
