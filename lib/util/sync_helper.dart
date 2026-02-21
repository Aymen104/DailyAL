import 'package:dailyanimelist/api/anilist/anilist_models.dart';
import 'package:dailyanimelist/api/maluser.dart';
import 'package:dailyanimelist/constant.dart';
import 'package:dal_commons/dal_commons.dart';
import 'package:flutter/material.dart';

class SyncHelper {
  static void showSyncOptions({
    required BuildContext context,
    required dynamic contentDetailed,
    required String category,
    required int? malId,
    required String? anilistStatus,
    required double? anilistScore,
    required int? anilistProgress,
    required int? anilistProgressVolumes,
    required String? anilistStartDate,
    required String? anilistCompletedDate,
    required int? anilistRepeat,
    required String? anilistNotes,
    required Function(
      String? newStatus,
      double? newScore,
      int? newProgress,
      int? newProgressVolumes,
      String? newStartDate,
      String? newCompletedDate,
      int? newRepeat,
      String? newNotes,
    ) onSyncedToAniList,
    required Future<void> Function() onSyncedToMal,
    required Future<void> Function({
      String? status,
      double? score,
      int? progress,
      int? progressVolumes,
      String? startedAt,
      String? completedAt,
      int? repeat,
      String? notes,
      bool? private_,
    }) saveAniListEntry,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        bool isSyncingMalToAni = false;
        bool isSyncingAniToMal = false;

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Sync Data', textAlign: TextAlign.center),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSyncOption(
                      context,
                      'assets/images/mal-icon.png',
                      'assets/images/anilist.png',
                      'MAL',
                      'AniList',
                      isSyncingMalToAni,
                      () async {
                        if (isSyncingMalToAni || isSyncingAniToMal) return;
                        setState(() {
                          isSyncingMalToAni = true;
                        });
                        await _syncToAniList(
                          category: category,
                          contentDetailed: contentDetailed,
                          onSyncedToAniList: onSyncedToAniList,
                          saveAniListEntry: saveAniListEntry,
                        );
                        if (context.mounted) {
                          setState(() {
                            isSyncingMalToAni = false;
                          });
                          Navigator.pop(context);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildSyncOption(
                      context,
                      'assets/images/anilist.png',
                      'assets/images/mal-icon.png',
                      'AniList',
                      'MAL',
                      isSyncingAniToMal,
                      () async {
                        if (isSyncingMalToAni || isSyncingAniToMal) return;
                        setState(() {
                          isSyncingAniToMal = true;
                        });
                        await _syncToMal(
                          malId: malId,
                          category: category,
                          anilistStatus: anilistStatus,
                          anilistScore: anilistScore,
                          anilistProgress: anilistProgress,
                          anilistProgressVolumes: anilistProgressVolumes,
                          anilistStartDate: anilistStartDate,
                          anilistCompletedDate: anilistCompletedDate,
                          anilistRepeat: anilistRepeat,
                          anilistNotes: anilistNotes,
                          onSyncedToMal: onSyncedToMal,
                        );
                        if (context.mounted) {
                          setState(() {
                            isSyncingAniToMal = false;
                          });
                          Navigator.pop(context);
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static Widget _buildSyncOption(
    BuildContext context,
    String sourceIcon,
    String targetIcon,
    String sourceText,
    String targetText,
    bool isLoading,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: Theme.of(context).dividerColor.withOpacity(0.5)),
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(sourceIcon,
                        width: 24, height: 24, fit: BoxFit.contain),
                    const SizedBox(width: 8),
                    Text(sourceText,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Icon(Icons.arrow_forward_rounded,
                          size: 20,
                          color: Theme.of(context).textTheme.bodySmall?.color),
                    ),
                    Image.asset(targetIcon,
                        width: 24, height: 24, fit: BoxFit.contain),
                    const SizedBox(width: 8),
                    Text(targetText,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
        ),
      ),
    );
  }

  static Future<void> _syncToAniList({
    required String category,
    required dynamic contentDetailed,
    required Function(
      String? newStatus,
      double? newScore,
      int? newProgress,
      int? newProgressVolumes,
      String? newStartDate,
      String? newCompletedDate,
      int? newRepeat,
      String? newNotes,
    ) onSyncedToAniList,
    required Future<void> Function({
      String? status,
      double? score,
      int? progress,
      int? progressVolumes,
      String? startedAt,
      String? completedAt,
      int? repeat,
      String? notes,
      bool? private_,
    }) saveAniListEntry,
  }) async {
    final malStatus = contentDetailed?.myListStatus;
    if (malStatus == null) {
      showToast('No MAL data to sync');
      return;
    }
    final isAnime = category.equals('anime');

    String? formatMalDate(dynamic dateObj) {
      if (dateObj == null) return null;
      if (dateObj is String) return dateObj;
      if (dateObj is DateTime)
        return dateObj.toIso8601String().split('T').first;
      return null;
    }

    String? newStatus = malStatus.status != null
        ? malStatusToAniList[transformStatusKey(malStatus.status)]
        : null;
    double? newScore = malStatus.score?.toDouble();
    int? newProgress;
    int? newProgressVolumes;
    int? newRepeat;

    if (isAnime) {
      newProgress = malStatus.numEpisodesWatched;
      newProgressVolumes = null;
      newRepeat = malStatus.numTimesRewatched;
    } else {
      newProgress = malStatus.numChaptersRead;
      newProgressVolumes = malStatus.numVolumesRead;
      newRepeat = malStatus.numTimesReread;
    }

    String? newStartDate = formatMalDate(malStatus.startDate);
    String? newCompletedDate = formatMalDate(malStatus.finishDate);
    String? newNotes = malStatus.comments;

    onSyncedToAniList(
      newStatus,
      newScore,
      newProgress,
      newProgressVolumes,
      newStartDate,
      newCompletedDate,
      newRepeat,
      newNotes,
    );

    await saveAniListEntry(
      status: newStatus,
      score: newScore,
      progress: newProgress,
      progressVolumes: newProgressVolumes,
      startedAt: newStartDate,
      completedAt: newCompletedDate,
      repeat: newRepeat,
      notes: newNotes,
    );
    showToast('Synced to AniList');
  }

  static Future<void> _syncToMal({
    required int? malId,
    required String category,
    required String? anilistStatus,
    required double? anilistScore,
    required int? anilistProgress,
    required int? anilistProgressVolumes,
    required String? anilistStartDate,
    required String? anilistCompletedDate,
    required int? anilistRepeat,
    required String? anilistNotes,
    required Future<void> Function() onSyncedToMal,
  }) async {
    final id = malId;
    if (id == null) return;
    if (anilistStatus == null) {
      showToast('No AniList data to sync');
      return;
    }

    final isAnime = category.equals('anime');
    final newStatus = isAnime
        ? aniListStatusToMalAnime[anilistStatus]
        : aniListStatusToMalManga[anilistStatus];

    bool success = false;
    showToast('Syncing to MAL...');
    if (isAnime) {
      final res = await MalUser.updateMyAnimeListStatus(
        id,
        status: newStatus,
        score: anilistScore?.toInt(),
        numEpisodesWatched: anilistProgress,
        startDate: anilistStartDate,
        endDate: anilistCompletedDate,
        comments: anilistNotes,
        numTimesRewatched: anilistRepeat,
      );
      success = res != null;
    } else {
      final res = await MalUser.updateMyMangaListStatus(
        id,
        status: newStatus,
        score: anilistScore?.toInt(),
        numChaptersRead: anilistProgress,
        numVolumesRead: anilistProgressVolumes,
        startDate: anilistStartDate,
        endDate: anilistCompletedDate,
        comments: anilistNotes,
        numTimesReread: anilistRepeat,
      );
      success = res != null;
    }

    if (success) {
      showToast('Synced to MAL');
      await onSyncedToMal();
    } else {
      showToast('Failed to sync to MAL');
    }
  }
}
