import 'package:dal_commons/dal_commons.dart';

/// AniList viewer profile.
class AniListUser {
  final int id;
  final String name;
  final String? avatarLarge;
  final String? avatarMedium;

  AniListUser({
    required this.id,
    required this.name,
    this.avatarLarge,
    this.avatarMedium,
  });

  factory AniListUser.fromJson(Map<String, dynamic> json) => AniListUser(
        id: json['id'],
        name: json['name'],
        avatarLarge: json['avatar']?['large'],
        avatarMedium: json['avatar']?['medium'],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'avatar': {'large': avatarLarge, 'medium': avatarMedium},
      };
}

// ─── Status Mappings ────────────────────────────────────────────────

/// Helper function to transform status strings to map keys
String transformStatusKey(String? status) {
  if (status == null) return '';
  return status.replaceAll(RegExp(r'[\s_]'), '').toLowerCase();
}

/// Maps MAL status keys → AniList MediaListStatus enum values.
const malStatusToAniList = <String, String>{
  'watching': 'CURRENT',
  'reading': 'CURRENT',
  'completed': 'COMPLETED',
  'onhold': 'PAUSED',
  'dropped': 'DROPPED',
  'plantowatch': 'PLANNING',
  'plantoread': 'PLANNING',
};

/// Reverse: AniList → MAL (anime).
const aniListStatusToMalAnime = <String, String>{
  'CURRENT': 'watching',
  'COMPLETED': 'completed',
  'PAUSED': 'on_hold',
  'DROPPED': 'dropped',
  'PLANNING': 'plan_to_watch',
  'REPEATING': 'watching',
};

/// Reverse: AniList → MAL (manga).
const aniListStatusToMalManga = <String, String>{
  'CURRENT': 'reading',
  'COMPLETED': 'completed',
  'PAUSED': 'on_hold',
  'DROPPED': 'dropped',
  'PLANNING': 'plan_to_read',
  'REPEATING': 'reading',
};

/// AniList status display maps
const aniListStatusDisplayMap = <String, String>{
  'CURRENT': 'Current',
  'COMPLETED': 'Completed',
  'PAUSED': 'Paused',
  'DROPPED': 'Dropped',
  'PLANNING': 'Planning',
  'REPEATING': 'Repeating',
};

// ─── Media Entry ────────────────────────────────────────────────────

/// Result of searching for a media by MAL ID – includes the AniList media ID
/// and the user's current list entry (if any).
class AniListMediaEntry {
  final int mediaId;
  final int? entryId;
  final String? status;
  final double? score;
  final int? progress;
  final int? progressVolumes;
  final String? startedAt;
  final String? completedAt;
  final int? repeat;
  final String? notes;
  final bool? private_;

  AniListMediaEntry({
    required this.mediaId,
    this.entryId,
    this.status,
    this.score,
    this.progress,
    this.progressVolumes,
    this.startedAt,
    this.completedAt,
    this.repeat,
    this.notes,
    this.private_,
  });

  factory AniListMediaEntry.fromJson(
      Map<String, dynamic> json, String category) {
    final entry = json['mediaListEntry'];
    return AniListMediaEntry(
      mediaId: json['id'],
      entryId: entry?['id'],
      status: entry?['status'],
      score: (entry?['score'] as num?)?.toDouble(),
      progress: entry?['progress'],
      progressVolumes: entry?['progressVolumes'],
      startedAt: _fuzzyDateToString(entry?['startedAt']),
      completedAt: _fuzzyDateToString(entry?['completedAt']),
      repeat: entry?['repeat'],
      notes: entry?['notes'],
      private_: entry?['private'],
    );
  }

  /// Whether the user has this entry on their list.
  bool get hasEntry => entryId != null;

  /// Display status label.
  String get statusDisplay =>
      aniListStatusDisplayMap[status] ?? status ?? 'Not on list';
}

/// Convert AniList FuzzyDate {year, month, day} to "yyyy-MM-dd" or null.
String? _fuzzyDateToString(Map<String, dynamic>? fuzzyDate) {
  if (fuzzyDate == null) return null;
  final y = fuzzyDate['year'];
  final m = fuzzyDate['month'];
  final d = fuzzyDate['day'];
  if (y == null) return null;
  return '${y.toString().padLeft(4, '0')}-'
      '${(m ?? 1).toString().padLeft(2, '0')}-'
      '${(d ?? 1).toString().padLeft(2, '0')}';
}

/// Parse "yyyy-MM-dd" to AniList FuzzyDateInput {year, month, day}.
Map<String, int>? stringToFuzzyDate(String? dateStr) {
  if (dateStr == null || dateStr.isEmpty) return null;
  try {
    final parts = dateStr.split('-');
    return {
      'year': int.parse(parts[0]),
      'month': int.parse(parts[1]),
      'day': int.parse(parts[2]),
    };
  } catch (e) {
    logDal('stringToFuzzyDate error: $e');
    return null;
  }
}

// ─── Save Result ────────────────────────────────────────────────────

/// Subset of fields returned after a SaveMediaListEntry mutation.
class AniListSaveResult {
  final int id;
  final String? status;
  final double? score;
  final int? progress;
  final int? progressVolumes;
  final String? startedAt;
  final String? completedAt;
  final int? repeat;
  final String? notes;
  final bool? private_;

  AniListSaveResult({
    required this.id,
    this.status,
    this.score,
    this.progress,
    this.progressVolumes,
    this.startedAt,
    this.completedAt,
    this.repeat,
    this.notes,
    this.private_,
  });

  factory AniListSaveResult.fromJson(
      Map<String, dynamic> json, String category) {
    return AniListSaveResult(
      id: json['id'],
      status: json['status'],
      score: (json['score'] as num?)?.toDouble(),
      progress: json['progress'],
      progressVolumes: json['progressVolumes'],
      startedAt: _fuzzyDateToString(json['startedAt']),
      completedAt: _fuzzyDateToString(json['completedAt']),
      repeat: json['repeat'],
      notes: json['notes'],
      private_: json['private'],
    );
  }
}
