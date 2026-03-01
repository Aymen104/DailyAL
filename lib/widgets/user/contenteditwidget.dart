import 'dart:ui';

import 'package:dailyanimelist/api/anilist/anilist_models.dart';
import 'package:dailyanimelist/api/anilist/anilist_service.dart';
import 'package:dailyanimelist/api/dalapi.dart';
import 'package:dailyanimelist/api/malapi.dart';
import 'package:dailyanimelist/api/maluser.dart';
import 'package:dailyanimelist/cache/cachemanager.dart';
import 'package:dailyanimelist/enums.dart';
import 'package:dailyanimelist/generated/l10n.dart';
import 'package:dailyanimelist/screens/homescreen.dart';
import 'package:dailyanimelist/user/user.dart';
import 'package:dailyanimelist/util/error/error_reporting.dart';
import 'package:dailyanimelist/util/sync_helper.dart';
import 'package:dailyanimelist/widgets/custombutton.dart';
import 'package:dailyanimelist/widgets/loading/expandedwidget.dart';
import 'package:dailyanimelist/widgets/search/filtermodal.dart';
import 'package:dailyanimelist/widgets/selectbottom.dart';
import 'package:dailyanimelist/widgets/will_pop_widget.dart';
import 'package:dal_commons/commons.dart';
import 'package:dal_commons/dal_commons.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:html_unescape/html_unescape.dart';

import '../../constant.dart';
import '../../main.dart';
import '../togglebutton.dart';

enum EditMode { floating, full }

enum EpisodeSelectMode { text, bar }

enum ActiveAccount { mal, anilist }

class ContentEditWidget extends StatefulWidget {
  final int? id;
  final dynamic contentDetailed;
  final String category;
  final bool isCacheRefreshed;
  final bool showAdditional;
  final bool updateCache;
  final bool applyPopScope;
  final ValueChanged<bool>? onUpdate;
  final ValueChanged<dynamic>? onListStatusChange;
  final VoidCallback? onDelete;
  final EditMode editMode;
  final bool applyHero;

  ContentEditWidget({
    this.id,
    this.contentDetailed,
    required this.category,
    this.onUpdate,
    this.onListStatusChange,
    this.updateCache = false,
    this.showAdditional = false,
    this.isCacheRefreshed = false,
    this.applyPopScope = false,
    this.applyHero = true,
    this.onDelete,
    this.editMode = EditMode.full,
  });

  @override
  _ContentEditWidgetState createState() => _ContentEditWidgetState();
}

class _ContentEditWidgetState extends State<ContentEditWidget> {
  bool showAddOptions = false;
  bool modifyStatus = false;
  bool modifyStars = false;
  bool modifyEpisodes = false;
  bool modifyChapters = false;
  bool modifyVolumes = false;
  bool initComplete = false;
  bool cacheUpdated = false;
  bool showAdvancedEdit = false;
  var modifyReStatus = false;
  String? statusValue;
  int? starValue;
  dynamic contentDetailed;
  late TextEditingController episodeController, chapterController, volumesController, privateNoteController;

  bool modifyStartDate = false;

  bool modifyFinishDate = false;

  bool modifyPriority = false;
  bool modifyComments = false;
  bool modifyTags = false;

  bool isReStatusOpen = true;
  bool isDatesOpen = false;
  bool isOthersOpen = false;
  bool isListStatusOpen = true;
  bool animationPending = false;
  DateTime? startDate, finishDate;
  ScheduleData? _scheduleData;
  EpisodeSelectMode _episodeSelectMode = EpisodeSelectMode.bar;
  ActiveAccount _activeAccount = ActiveAccount.mal;

  // ─── Separate AniList state ──────────────────────────────────────
  AniListMediaEntry? _anilistEntry;
  bool _anilistLoading = false;
  bool _anilistSaving = false;
  String? _alStatus;
  double? _alScore;
  int? _alProgress;
  int? _alProgressVolumes;
  String? _alStartDate;
  String? _alCompletedDate;
  int? _alRepeat;
  String? _alNotes;
  bool _alPrivate = false;

  Map<String, bool> accordions = {
    S.current.Your_List_Status: true,
    S.current.Dates_Priority: false,
    S.current.Others: false,
  };

  final ItemScrollController itemScrollController = ItemScrollController();
  final ItemScrollController _alScoreScrollController = ItemScrollController();
  bool _loading = false;
  final ItemScrollController _episodeScrollController = ItemScrollController();

  @override
  void initState() {
    super.initState();
    reset();
    contentDetailed = widget.contentDetailed;
    _loadPrivateNote();
    showAddOptions = isFloating && user.status == AuthStatus.AUTHENTICATED;
    if (widget.updateCache && user.status == AuthStatus.AUTHENTICATED) {
      cacheUpdated = false;
      updateCache();
    } else {
      cacheUpdated = true;
    }

    accordions[(widget.category.equals('anime') ? 'Rewatch' : 'Reread') + ' Status'] = true;

    _setScheduleData();

    // Restore persisted account toggle
    if (user.pref.preferAniList && user.isAniListConnected) {
      _activeAccount = ActiveAccount.anilist;
      _fetchAniListEntry();
      // Also ensure MAL data is loaded for when user switches back
      if (contentDetailed?.myListStatus == null && !widget.updateCache) {
        cacheUpdated = false;
        updateCache();
      }
    }
  }

  void _setScheduleData() async {
    final preferred = await CacheManager.instance.getValueForService('edit', 'episodeSelectPref');
    if (preferred != null) {
      _episodeSelectMode = preferred == 'text' ? EpisodeSelectMode.text : EpisodeSelectMode.bar;
    }
    if (widget.category.equals('anime') && _id != null) {
      _scheduleData = DalApi.i.scheduleForMalIdsSync[_id];
      if (_totalEpisodeCount == null) {
        _episodeSelectMode = EpisodeSelectMode.text;
      }
    }
    if (mounted) {
      setState(() {});
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _episodeSelectMode == EpisodeSelectMode.bar) {
        try {
          _scrollToEpisodeCount();
        } catch (e) {
          logDal(e);
          if (e is Error) {
            ErrorReporting.reportError(e);
          }
        }
      }
    });
  }

  void _loadPrivateNote() async {
    // Try loading with category-specific key first
    String? note = await CacheManager.instance.getValueForService('private_note', "${widget.category} - $_id");

    // Fallback: try loading legacy key (without category) if specific one doesn't exist
    if (note == null) {
      note = await CacheManager.instance.getValueForService('private_note', "$_id");
      // If legacy note exists, save it with new key format for future
      if (note != null) {
        CacheManager.instance.setValueForService('private_note', "${widget.category} - $_id", note);
      }
    }

    if (note != null && mounted) {
      privateNoteController.text = note;
    }
  }

  void _savePrivateNote() {
    if (_id != null) {
      // Save with category to avoid ID collisions between Anime and Manga
      CacheManager.instance.setValueForService('private_note', "${widget.category} - $_id", privateNoteController.text);
    }
  }

  @override
  void dispose() {
    _savePrivateNote();
    privateNoteController.dispose();
    episodeController.dispose();
    chapterController.dispose();
    volumesController.dispose();
    super.dispose();
  }

  int? get _id {
    if (widget.id != null) {
      return widget.id;
    }
    if (contentDetailed is BaseNode) {
      return contentDetailed?.content?.id;
    } else {
      return contentDetailed?.id;
    }
  }

  reset() {
    episodeController = new TextEditingController(text: "0");
    chapterController = new TextEditingController(text: "0");
    volumesController = new TextEditingController(text: "0");
    privateNoteController = new TextEditingController();
    statusValue = null;
    starValue = null;
  }

  onAdvancedEdit() {}

  updateCache() async {
    try {
      var field =
          "num_episodes,my_list_status{status,score,num_episodes_watched,num_watched_episodes,num_chapters_read,num_volumes_read,is_rewatching,is_rereading,num_times_rewatched,num_times_reread,priority,rewatch_value,reread_value,start_date,finish_date,tags,comments}";
      var content = contentDetailed;
      if (contentDetailed is BaseNode) {
        content = contentDetailed?.content;
      }
      contentDetailed = widget.category.equals("anime")
          ? await MalApi.getAnimeDetails(content.id, fields: [field])
          : await MalApi.getMangaDetails(content.id, fields: [field]);
      checkForUpdatesDuringBuild();
      if (mounted) {
        setState(() {
          cacheUpdated = true;
        });
      }
    } catch (e) {
      showToast(S.current.Couldnt_Update);
    }
  }

  void updateParent(bool result) {
    if (widget.onUpdate != null) {
      widget.onUpdate!(result);
    }
  }

  void updateListStatus(status) {
    if (widget.onListStatusChange != null) {
      widget.onListStatusChange!(status);
    }
  }

  updateEpisodeCount({int? episodes, int? add}) async {
    bool result = false;
    int _episodes = episodes ?? (int.tryParse(episodeController.text) ?? 0);
    _episodes += add ?? 0;
    String? watchStatus;
    String? _endDate;
    String? _startDate;
    if (_episodes < 0) {
      showToast(S.current.Negative_episode_not_allowed);
      return;
    }
    var content = contentDetailed;
    if (contentDetailed is BaseNode) {
      content = contentDetailed?.content;
    }

    try {
      if ((content is AnimeDetailed) && content?.numEpisodes != null && (content.numEpisodes != 0)) {
        if (_episodes > content.numEpisodes!) {
          showToast(S.current.Maximum_reached);
          return;
        }
        if (_episodes == content.numEpisodes) {
          watchStatus = "completed";
          // Auto-populate finish date when auto-completing via episode count
          if (user.pref.autoAddStartEndDate && content.myListStatus?.finishDate == null) {
            _endDate = DateFormat("yyyy-MM-dd").format(DateTime.now());
          }
        }
      }
      // Auto-populate start date when first episode is watched
      if ((content is AnimeDetailed) &&
          user.pref.autoAddStartEndDate &&
          _episodes > 0 &&
          content.myListStatus?.startDate == null) {
        _startDate = DateFormat("yyyy-MM-dd").format(DateTime.now());
      }
    } catch (e) {}

    if (mounted)
      setState(() {
        modifyEpisodes = true;
      });

    var status = await MalUser.updateMyAnimeListStatus(content.id,
        numEpisodesWatched: _episodes, status: watchStatus, endDate: _endDate, startDate: _startDate);
    if (status != null) {
      result = true;
      updateListStatus(status);
      if (mounted)
        setState(() {
          modifyEpisodes = false;
          episodeController.text = status.numEpisodesWatched.toString();
          statusValue = status.status;
        });
    } else {
      showToast(S.current.Couldnt_Update);
      if (mounted)
        setState(() {
          modifyEpisodes = false;
        });
    }
    updateParent(result);
  }

  updateVolumeCount({int? volumes, int? add}) async {
    bool result = false;
    int _volumes = volumes ?? (int.tryParse(volumesController.text) ?? 0);
    _volumes += add ?? 0;
    if (_volumes < 0) {
      showToast(S.current.Negative_volumes_not_allowed);
      return;
    }

    if ((contentDetailed is MangaDetailed) &&
        contentDetailed?.numVolumes != null &&
        contentDetailed.numVolumes != 0 &&
        _volumes > contentDetailed.numVolumes) {
      showToast(S.current.Maximum_reached);
      return;
    }

    if (mounted)
      setState(() {
        modifyVolumes = true;
      });
    var content = contentDetailed;
    if (contentDetailed is BaseNode) {
      content = contentDetailed?.content;
    }
    var status = await MalUser.updateMyMangaListStatus(content.id, numVolumesRead: _volumes);
    if (status != null) {
      result = true;
      updateListStatus(status);
      if (mounted)
        setState(() {
          modifyVolumes = false;
          volumesController.text = status.numVolumesRead.toString();
        });
    } else {
      showToast(S.current.Couldnt_Update);
      if (mounted)
        setState(() {
          modifyVolumes = false;
        });
    }
    updateParent(result);
  }

  updateChapterCount({int? chapters, int? add}) async {
    bool result = false;
    int _chapters = chapters ?? (int.tryParse(chapterController.text) ?? 0);
    _chapters += add ?? 0;
    if (_chapters < 0) {
      showToast(S.current.Negative_chapters_not_allowed);
      return;
    }

    if ((contentDetailed is MangaDetailed) &&
        contentDetailed?.numChapters != null &&
        contentDetailed.numChapters != 0 &&
        _chapters > contentDetailed.numChapters) {
      showToast(S.current.Maximum_reached);
      return;
    }

    if (mounted)
      setState(() {
        modifyChapters = true;
      });
    var content = contentDetailed;
    if (contentDetailed is BaseNode) {
      content = contentDetailed?.content;
    }
    var status = await MalUser.updateMyMangaListStatus(content.id, numChaptersRead: _chapters);
    if (status != null) {
      result = true;
      updateListStatus(status);
      if (mounted)
        setState(() {
          modifyChapters = false;
          chapterController.text = status.numChaptersRead.toString();
        });
    } else {
      showToast(S.current.Couldnt_Update);
      if (mounted)
        setState(() {
          modifyChapters = false;
        });
    }
    updateParent(result);
  }

  Future<void> updateWatchingStatus(String value) async {
    bool result = false;
    int? _episodes;
    String? _startDate, _endDate;
    if (value.equals(statusValue)) {
      return;
    }
    if (!await hasConnection()) {
      showToast(S.current.No_Connection);
      return;
    }
    if (mounted)
      setState(() {
        modifyStatus = true;
      });

    var content = contentDetailed;
    if (contentDetailed is BaseNode) {
      content = contentDetailed?.content;
    }

    if ((content is AnimeDetailedMixin)) {
      if (content?.numEpisodes != null && (content.numEpisodes != 0) && value.equals("completed")) {
        _episodes = content.numEpisodes;
      }
    }
    if (content is AnimeDetailed && user.pref.autoAddStartEndDate) {
      if (value.equals("watching") && content.myListStatus?.startDate == null) {
        _startDate = DateFormat("yyyy-MM-dd").format(DateTime.now());
      }
      if (value.equals("completed") && content.myListStatus?.finishDate == null) {
        _endDate = DateFormat("yyyy-MM-dd").format(DateTime.now());
      }
    }

    var status;

    if (widget.category.equals("anime")) {
      status = await MalUser.updateMyAnimeListStatus(
        content.id,
        status: value,
        numEpisodesWatched: _episodes,
        endDate: _endDate,
        startDate: _startDate,
      );
    } else {
      status = await MalUser.updateMyMangaListStatus(content.id, status: value);
    }
    if (status != null) {
      result = true;
      updateListStatus(status);
      if (mounted)
        setState(() {
          modifyStatus = false;
          statusValue = status.status;
          if (status is MyAnimeListStatus) {
            episodeController.text = status.numEpisodesWatched.toString();
            startDate = status.startDate;
            finishDate = status.finishDate;
          }
        });
    } else {
      showToast(S.current.Couldnt_Update);
      if (mounted)
        setState(() {
          modifyStatus = false;
        });
    }
    updateParent(result);
  }

  void updateRatingStatus(int value) async {
    bool result = false;
    if (value == starValue) {
      return;
    }
    if (!await hasConnection()) {
      showToast(S.current.No_Connection);
      return;
    }
    if (mounted)
      setState(() {
        modifyStars = true;
      });
    var content = contentDetailed;
    if (contentDetailed is BaseNode) {
      content = contentDetailed?.content;
    }

    var status;
    if (widget.category.equals("anime")) {
      status = await MalUser.updateMyAnimeListStatus(content.id, score: value);
    } else {
      status = await MalUser.updateMyMangaListStatus(content.id, score: value);
    }
    if (status != null) {
      result = true;
      updateListStatus(status);
      if (mounted)
        setState(() {
          modifyStars = false;
          starValue = status.score;
        });
    } else {
      showToast(S.current.Couldnt_Update);
      if (mounted)
        setState(() {
          modifyStars = false;
        });
    }
    updateParent(result);
  }

  checkForUpdatesDuringBuild() {
    if (_activeAccount == ActiveAccount.anilist) {
      starValue = _alScore?.round();
      statusValue = _alStatus;
    } else {
      starValue = contentDetailed?.myListStatus?.score?.round();
      statusValue = contentDetailed?.myListStatus?.status;
    }
    initComplete = true;
    try {
      if (widget.category.equals("anime")) {
        if (_activeAccount == ActiveAccount.anilist) {
          episodeController.text = _alProgress?.toString() ?? "0";
        } else {
          episodeController.text = (contentDetailed?.myListStatus?.numEpisodesWatched == null
                  ? "0"
                  : contentDetailed?.myListStatus?.numEpisodesWatched?.toString()) ??
              '';
        }
      } else {
        if (_activeAccount == ActiveAccount.anilist) {
          chapterController.text = _alProgress?.toString() ?? "0";
          volumesController.text = _alProgressVolumes?.toString() ?? "0";
        } else {
          chapterController.text = (contentDetailed?.myListStatus?.numChaptersRead == null
                  ? "0"
                  : contentDetailed?.myListStatus?.numChaptersRead?.toString()) ??
              '';
          volumesController.text = (contentDetailed?.myListStatus?.numVolumesRead == null
                  ? "0"
                  : contentDetailed?.myListStatus?.numVolumesRead?.toString()) ??
              '';
        }
      }
    } catch (e) {
      logDal(e);
      if (e is Error) {
        ErrorReporting.reportError(e);
      }
    }
  }

  updateAdvancedStatus(
      {bool? isRewatching,
      bool? isRereading,
      int? timesRewatched,
      int? timesReread,
      int? rewatchValue,
      int? rereadValue,
      String? startDate,
      int? priority,
      String? comments,
      String? tags,
      required Function onDone,
      String? finishDate}) async {
    if (mounted) setState(() {});
    FocusScope.of(context).unfocus();
    var status;
    bool result = false;
    var content = contentDetailed;
    if (contentDetailed is BaseNode) {
      content = contentDetailed?.content;
    }
    if (widget.category.equals("anime")) {
      status = await MalUser.updateMyAnimeListStatus(content.id,
          endDate: finishDate,
          isRewatching: isRewatching,
          numTimesRewatched: timesRewatched,
          priority: priority,
          comments: comments,
          tags: tags,
          rewatchValue: rewatchValue,
          startDate: startDate);
    } else {
      status = await MalUser.updateMyMangaListStatus(content.id,
          isRereading: isRereading,
          numTimesReread: timesReread,
          priority: priority,
          comments: comments,
          tags: tags,
          endDate: finishDate,
          startDate: startDate,
          rereadValue: rereadValue);
    }
    onDone();
    if (status != null) {
      result = true;
      contentDetailed?.myListStatus = status;
      updateListStatus(status);
    } else {
      showToast(S.current.Couldnt_Update);
    }
    if (mounted) setState(() {});
    updateParent(result);
  }

  Future<void> deleteFromList() async {
    var result = await showConfirmationDialog(
      context: context,
      alertTitle: S.current.Item_delete_confi,
      desc: S.current.Item_delete_desc,
    );
    if (!(result ?? false)) {
      return;
    }
    _loading = true;
    if (mounted) setState(() {});
    var content = contentDetailed;
    if (contentDetailed is BaseNode) {
      content = contentDetailed?.content;
    }
    if (await MalUser.deleteFromList(content.id, category: widget.category)) {
      showAdvancedEdit = false;
      isListStatusOpen = true;
      contentDetailed.myListStatus = null;
      reset();
      if (widget.onDelete != null) widget.onDelete!();
      updateParent(true);
    } else {
      updateParent(false);
      showToast(S.current.Couldnt_Delete);
    }
    onAdvancedEdit();
    _loading = false;
    if (mounted) setState(() {});
  }

  bool get isFloating => widget.editMode == EditMode.floating;

  @override
  Widget build(BuildContext context) {
    if (starValue == null && !initComplete && widget.isCacheRefreshed) {
      contentDetailed = widget.contentDetailed;
      checkForUpdatesDuringBuild();
    }
    var _build = Container(
      alignment: Alignment.bottomCenter,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // additionalWidget,
            _heroWithTag("bottomnavbar")
          ],
        ),
      ),
    );

    if (widget.applyPopScope)
      return WillPopWidget(
          child: _build,
          onWillPop: () async {
            if (showAdvancedEdit) {
              if (mounted)
                setState(() {
                  showAdvancedEdit = false;
                });
              return false;
            }
            return true;
          });
    else
      return _build;
  }

  Widget _heroWithTag(String tag) {
    if (widget.applyHero) {
      return Hero(tag: tag, child: animatedContainer);
    } else {
      return animatedContainer;
    }
  }

  Widget get animatedContainer => AnimatedContainer(
        duration: Duration(milliseconds: 400),
        curve: Curves.easeIn,
        padding: EdgeInsets.symmetric(horizontal: isFloating && widget.category.equals("anime") ? 7 : 2, vertical: 0),
        constraints: BoxConstraints(minHeight: isFloating ? 120 : 100),
        child: Card(
          elevation: 4,
          margin: EdgeInsets.zero,
          child: Material(
            child: editChild,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );

  Widget get editChild => ((contentDetailed == null || !widget.isCacheRefreshed) || !cacheUpdated || _loading)
      ? Center(child: loadingCenter())
      : (!showAddOptions && contentDetailed.myListStatus?.status == null)
          ? Container(
              width: double.infinity,
              height: 60,
              child: Center(
                  child: PlainButton(
                onPressed: () {
                  if (user.status != AuthStatus.AUTHENTICATED) {
                    gotoPage(
                        context: context,
                        newPage: HomeScreen(
                          pageIndex: 2,
                        ));
                  } else if (mounted) {
                    _addToList();
                  }
                },
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                child: Text(
                  user.status != AuthStatus.AUTHENTICATED ? S.current.Login_Add_to_List : S.current.Add_to_List,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16),
                ),
              )),
            )
          : contentStatusWidget();

  void _addToList() async {
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }
    bool isAnime = widget.category.equals('anime');
    var pref = user.pref.animeMangaPagePreferences;
    String status = isAnime ? pref.defaultAnimeAddToListSelected : pref.defaultMangaAddToListSelected;
    await updateWatchingStatus(status);
    showAddOptions = true;
    _loading = false;
    setState(() {});
  }

  Widget get additionalWidget => widget.showAdditional
      ? Container(
          width: 60,
          height: 20,
          child: PlainButton(
            onPressed: () {
              Navigator.pop(context);
            },
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.only(topRight: Radius.circular(14), topLeft: Radius.circular(14))),
            child: Icon(
              Icons.keyboard_arrow_down,
              size: 24,
            ),
          ),
        )
      : const SizedBox();

  Widget contentStatusWidget() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onVerticalDragUpdate: (details) {
            if (animationPending) {
              return;
            }
            animationPending = true;
            Future.delayed(const Duration(milliseconds: 300)).then((value) => animationPending = false);
            if (mounted)
              setState(() {
                if (details.delta.dy < 0) {
                  showAdvancedEdit = true;
                } else {
                  showAdvancedEdit = false;
                }
                onAdvancedEdit();
                isListStatusOpen = true;
              });
          },
          child: Container(
            width: double.infinity,
            height: 20,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                if (mounted)
                  setState(() {
                    showAdvancedEdit = !showAdvancedEdit;
                    isListStatusOpen = true;
                  });
                onAdvancedEdit();
              },
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 1, horizontal: 10),
                child: Icon(
                  (!showAdvancedEdit ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
                  size: 20,
                ),
              ),
            ),
          ),
        ),
        !widget.showAdditional
            ? const SizedBox()
            : Padding(
                padding: EdgeInsets.symmetric(vertical: 7),
                child: title(
                    ((contentDetailed is Node)
                        ? (contentDetailed?.title ?? "Title ?")
                        : (widget?.contentDetailed?.content?.title ?? "Title ?")),
                    align: TextAlign.center),
              ),
        ExpandedSection(
            expand: showAdvancedEdit,
            child: sectionHeading(S.current.Your_List_Status, isOpen: showAdvancedEdit, onChange: () {
              if (mounted)
                setState(() {
                  showAdvancedEdit = !showAdvancedEdit;
                });
              onAdvancedEdit();
            })),
        _activeAccount == ActiveAccount.anilist
            ? _anilistEditView()
            : (widget.category.equals("anime") ? animeStatusWidget() : mangaStatusWidget()),
        if (_activeAccount == ActiveAccount.mal)
          ExpandedSection(
            expand: showAdvancedEdit,
            child: advancedWidget,
          ),
        _bottomBar,
        SB.h30,
      ],
    );
  }

  // ─── AniList independent view ───────────────────────────────

  /// Fetch the AniList entry for the current content.
  Future<void> _fetchAniListEntry() async {
    final id = _id;
    if (id == null) return;
    if (mounted)
      setState(() {
        _anilistLoading = true;
      });
    final entry = await AniListService.searchMediaByMalId(id, widget.category);
    if (mounted) {
      setState(() {
        _anilistLoading = false;
        _anilistEntry = entry;
        if (entry != null && entry.hasEntry) {
          _alStatus = entry.status;
          _alScore = entry.score;
          _alProgress = entry.progress;
          _alProgressVolumes = entry.progressVolumes;
          _alStartDate = entry.startedAt;
          _alCompletedDate = entry.completedAt;
          _alRepeat = entry.repeat;
          _alNotes = entry.notes;
          _alPrivate = entry.private_ ?? false;
        }
      });
    }
  }

  /// Save AniList entry with current state.
  Future<void> _saveAniListEntry({
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
    final id = _id;
    if (id == null) return;
    if (mounted)
      setState(() {
        _anilistSaving = true;
      });
    final result = await AniListService.updateByMalId(
      malId: id,
      category: widget.category,
      status: status ?? _alStatus,
      score: score ?? _alScore,
      progress: progress ?? _alProgress,
      progressVolumes: progressVolumes ?? _alProgressVolumes,
      startedAt: startedAt ?? _alStartDate,
      completedAt: completedAt ?? _alCompletedDate,
      repeat: repeat ?? _alRepeat,
      notes: notes ?? _alNotes,
      private_: private_ ?? _alPrivate,
    );
    if (mounted) {
      setState(() {
        _anilistSaving = false;
        if (result != null) {
          _alStatus = result.status ?? _alStatus;
          _alScore = result.score ?? _alScore;
          _alProgress = result.progress ?? _alProgress;
          _alProgressVolumes = result.progressVolumes ?? _alProgressVolumes;
          _alStartDate = result.startedAt ?? _alStartDate;
          _alCompletedDate = result.completedAt ?? _alCompletedDate;
          _alRepeat = result.repeat ?? _alRepeat;
          _alNotes = result.notes ?? _alNotes;
          _alPrivate = result.private_ ?? _alPrivate;
        } else {
          showToast(S.current.Couldnt_Update);
        }
      });
    }
    updateParent(result != null);
  }

  /// Delete from AniList.
  Future<void> _deleteAniListEntry() async {
    final id = _id;
    if (id == null) return;
    final ok = await AniListService.deleteByMalId(id, widget.category);
    if (ok) {
      if (mounted)
        setState(() {
          _anilistEntry = null;
          _alStatus = null;
          _alScore = null;
          _alProgress = null;
          _alProgressVolumes = null;
          _alStartDate = null;
          _alCompletedDate = null;
          _alRepeat = null;
          _alNotes = null;
          _alPrivate = false;
        });
      showToast('Deleted from AniList');
    } else {
      showToast(S.current.Couldnt_Update);
    }
    updateParent(ok);
  }

  /// Build the independent AniList edit pane.
  Widget _anilistEditView() {
    if (_anilistLoading) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(child: loadingCenter()),
      );
    }

    final statusMap = aniListStatusDisplayMap;
    final isAnime = widget.category.equals('anime');
    final unescape = HtmlUnescape();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Your List Status (Always visible, like MAL) ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: expandedChild(
                      isAnime ? S.current.Status : S.current.Reading_Status,
                      statusWidget_al(statusMap),
                    ),
                  ),
                  SB.w20,
                  Expanded(
                    child: expandedChild(
                      isAnime
                          ? S.current.Episodes_seen
                          : "${S.current.Chapters} " +
                              ((!(contentDetailed is MangaDetailed) ||
                                      contentDetailed?.numChapters == null ||
                                      contentDetailed.numChapters == 0)
                                  ? S.current.Read
                                  : "(${contentDetailed.numChapters})"),
                      _buildAlProgressWidget(isAnime),
                    ),
                  ),
                  if (!isAnime) ...[
                    SB.w20,
                    Expanded(
                      child: expandedChild(
                        "${S.current.Volumes} " +
                            ((!(contentDetailed is MangaDetailed) ||
                                    contentDetailed?.numVolumes == null ||
                                    contentDetailed.numVolumes == 0)
                                ? S.current.Read
                                : "(${contentDetailed.numVolumes})"),
                        _buildAlVolumeWidget(),
                      ),
                    ),
                  ]
                ],
              ),
              SB.h5,
              _alScoreBarWidget(),
              SB.h20,
            ],
          ),
        ),

        ExpandedSection(
          expand: showAdvancedEdit,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Dates ──
              sectionHeading(
                S.current
                    .Dates_Priority, // Prioriy is excluded since AniList doesn't have it natively, but heading kept for consistency
                isOpen: accordions[S.current.Dates_Priority] ?? false,
                onChange: () {
                  if (mounted)
                    setState(() {
                      accordions[S.current.Dates_Priority] = !(accordions[S.current.Dates_Priority] ?? false);
                    });
                },
              ),
              ExpandedSection(
                expand: accordions[S.current.Dates_Priority] ?? false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      field(
                        S.current.Start_Date,
                        _buildAlDatePicker(
                          value: _alStartDate,
                          onChanged: (v) {
                            _alStartDate = v;
                            _saveAniListEntry(startedAt: v);
                          },
                        ),
                      ),
                      field(
                        S.current.Finish_Date,
                        _buildAlDatePicker(
                          value: _alCompletedDate,
                          onChanged: (v) {
                            _alCompletedDate = v;
                            _saveAniListEntry(completedAt: v);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Others (Rewatch, Notes, Private) ──
              sectionHeading(
                S.current.Others,
                isOpen: accordions[S.current.Others] ?? false,
                onChange: () {
                  if (mounted)
                    setState(() {
                      accordions[S.current.Others] = !(accordions[S.current.Others] ?? false);
                    });
                },
              ),
              ExpandedSection(
                expand: accordions[S.current.Others] ?? false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Rewatch / Reread (Moved here from its own section)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            field(
                              isAnime ? S.current.Times_Rewatched : S.current.Times_Reread,
                              _buildAlNumberField(
                                value: _alRepeat ?? 0,
                                onChanged: (v) {
                                  _alRepeat = v;
                                  _saveAniListEntry(repeat: v);
                                },
                              ),
                            ),
                            field(
                              'Private',
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 5),
                                child: SizedBox(
                                  height: 45.0,
                                  child: ShadowButton(
                                    onPressed: () {
                                      _alPrivate = !_alPrivate;
                                      _saveAniListEntry(private_: _alPrivate);
                                      if (mounted) setState(() {});
                                    },
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          _alPrivate ? Icons.lock : Icons.public,
                                          size: 16,
                                        ),
                                        SB.w10,
                                        Text(_alPrivate ? 'Private' : 'Public'),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Notes
                      field(
                        'Notes',
                        TextFormFilter(
                          onFieldSubmitted: (v) {
                            _alNotes = v;
                            _saveAniListEntry(notes: v);
                          },
                          option: FilterOption(
                            value: unescape.convert(_alNotes ?? '').replaceAll("<br />", ""),
                            fieldName: "Notes",
                            openTextFormAsModal: true,
                          ),
                        ),
                        null,
                        100.0,
                        CrossAxisAlignment.start,
                        const EdgeInsets.only(left: 20, bottom: 8),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _alScoreBarWidget() {
    final double rawValue = _alScore ?? 0.0;
    final keys = List.generate(21, (i) => i / 2); // 0.0, 0.5, ... 10.0

    // Find closest valid score or default to 0
    int initIndex = keys.indexWhere((k) => (k - rawValue).abs() < 0.1);
    if (initIndex == -1) initIndex = 0;

    String scoreLabel = '';
    if (rawValue != 0.0) {
      if (rawValue % 1 == 0 && myStarMap.containsKey(rawValue.toInt())) {
        scoreLabel = ' · ${myStarMap[rawValue.toInt()]}';
      } else {
        scoreLabel = ' · $rawValue';
      }
    }

    return Column(
      children: [
        SB.h20,
        Text('${S.current.Score}$scoreLabel'),
        SB.h15,
        SizedBox(
          height: 45.0,
          child: _anilistSaving
              ? loadingCenter()
              : ScrollablePositionedList.builder(
                  itemScrollController: _alScoreScrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  initialAlignment: 0.5,
                  padding: const EdgeInsets.symmetric(horizontal: 160.0, vertical: 2.0), // match mal padding
                  initialScrollIndex: initIndex,
                  itemCount: keys.length,
                  itemBuilder: (context, i) {
                    final v = keys[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: ShadowButton(
                        onPressed: () {
                          _alScoreScrollController.scrollTo(
                            index: i,
                            alignment: 0.5,
                            duration: const Duration(milliseconds: 200),
                          );
                          _alScore = v;
                          _saveAniListEntry(score: _alScore);
                        },
                        child: Text(v == 0.0 ? S.current.Select : (v % 1 == 0 ? v.toInt().toString() : v.toString())),
                        padding: EdgeInsets.zero,
                        shape: ((_alScore ?? 0.0) - v).abs() < 0.1
                            ? RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(32),
                                side: BorderSide(color: Theme.of(context).dividerColor, width: 1.0))
                            : RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// AniList status dropdown (separate from MAL's statusWidget).
  Widget statusWidget_al(Map<String, String> statusMap) {
    return SizedBox(
      height: 50,
      child: SelectButton(
        options: statusMap.keys.toList(),
        displayValues: statusMap.values.toList(),
        selectedOption: _alStatus,
        useShadowChild: true,
        popupText: 'Status',
        onChanged: (v) {
          _alStatus = v;
          _saveAniListEntry(status: v);
        },
      ),
    );
  }

  Widget _buildAlProgressWidget(bool isAnime) {
    return plusMinusWidget(
      (val) {
        final newVal = (val ?? 0).clamp(0, 99999);
        _alProgress = newVal;
        _saveAniListEntry(progress: newVal);
      },
      modify: _anilistSaving,
      initialValue: (_alProgress ?? 0).toString(),
    );
  }

  Widget _buildAlVolumeWidget() {
    return plusMinusWidget(
      (val) {
        final newVal = (val ?? 0).clamp(0, 99999);
        _alProgressVolumes = newVal;
        _saveAniListEntry(progressVolumes: newVal);
      },
      modify: _anilistSaving,
      initialValue: (_alProgressVolumes ?? 0).toString(),
    );
  }

  Widget _buildAlDatePicker({
    required String? value,
    required ValueChanged<String> onChanged,
  }) {
    DateTime? dateValue;
    if (value != null) {
      dateValue = DateTime.tryParse(value);
    }
    return SelectDate(
      onChangedFormatted: onChanged,
      selectDate: dateValue,
    );
  }

  Widget _buildAlNumberField({
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return plusMinusWidget(
      (val) => onChanged((val ?? 0).clamp(0, 9999)),
      modify: _anilistSaving,
      initialValue: value.toString(),
    );
  }

  Widget sectionHeading(String heading,
      {bool isOpen = true, VoidCallback? onChange, MainAxisAlignment mainAxisAlignment = MainAxisAlignment.start}) {
    return InkWell(
      onTap: () {
        if (onChange != null) onChange();
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: mainAxisAlignment == MainAxisAlignment.start ? 10 : 0, vertical: 10),
        child: Row(
          mainAxisAlignment: mainAxisAlignment,
          children: [
            if (onChange != null)
              IconButton(
                  onPressed: () {
                    onChange();
                  },
                  icon: Icon(isOpen ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right)),
            title(
              heading,
              align: TextAlign.center,
              fontSize: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget get advancedWidget => Form(
        child: Container(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              sectionHeading((widget.category.equals('anime') ? 'Rewatch' : 'Reread') + ' Status',
                  isOpen: isReStatusOpen, onChange: () {
                if (mounted)
                  setState(() {
                    isReStatusOpen = !isReStatusOpen;
                  });
              }),
              ExpandedSection(
                expand: isReStatusOpen,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: rewatchWidget,
                ),
              ),
              if (user.pref.animeMangaPagePreferences.showPrivateNotes)
                Padding(
                  padding: EdgeInsets.only(top: 10, bottom: 20, right: 15, left: 15),
                  child: field(
                      S.current.Private_Note,
                      TextFormField(
                        controller: privateNoteController,
                        minLines: 5,
                        maxLines: null,
                        scrollPhysics: const AlwaysScrollableScrollPhysics(),
                        decoration: InputDecoration(
                          hintText: S.current.Private_Note_Hint,
                          helperText: S.current.Private_Note_Local_Only,
                          prefixIcon: Icon(Icons.lock_outline),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      S.current.Private_Note_Desc,
                      null,
                      CrossAxisAlignment.start,
                      EdgeInsets.only(left: 20, bottom: 8)),
                ),
              sectionHeading(S.current.Dates_Priority, isOpen: isDatesOpen, onChange: () {
                if (mounted)
                  setState(() {
                    isDatesOpen = !isDatesOpen;
                  });
              }),
              ExpandedSection(
                expand: isDatesOpen,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: dateStatusWidget,
                ),
              ),
              sectionHeading(S.current.Others, isOpen: isOthersOpen, onChange: () {
                if (mounted)
                  setState(() {
                    isOthersOpen = !isOthersOpen;
                  });
              }),
              ExpandedSection(
                expand: isOthersOpen,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: othersWidget,
                ),
              ),
              SB.h20
            ],
          ),
        ),
      );

  Widget get othersWidget {
    final unescape = HtmlUnescape();
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        field(
            S.current.Comments,
            _modifyWidget(
              modifyComments,
              TextFormFilter(
                onFieldSubmitted: (value) {
                  modifyComments = true;
                  updateAdvancedStatus(
                      comments: value,
                      onDone: () {
                        modifyComments = false;
                      });
                },
                option: FilterOption(
                    value: unescape.convert(contentDetailed?.myListStatus?.comments ?? '').replaceAll("<br />", ""),
                    fieldName: "Comments",
                    openTextFormAsModal: true),
              ),
            ),
            null,
            100.0,
            CrossAxisAlignment.start,
            EdgeInsets.only(left: 20, bottom: 8)),
        Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: field(
                S.current.Tags,
                _modifyWidget(
                  modifyTags,
                  TextFormFilter(
                      onFieldSubmitted: (value) {
                        modifyTags = true;
                        updateAdvancedStatus(
                            tags: value,
                            onDone: () {
                              modifyTags = false;
                            });
                      },
                      option: FilterOption(
                          value: unescape.convert(
                            (contentDetailed?.myListStatus?.tags != null &&
                                    contentDetailed.myListStatus.tags.isNotEmpty)
                                ? contentDetailed?.myListStatus?.tags[0]
                                : '',
                          ),
                          fieldName: "Tags")),
                ),
                null,
                null,
                CrossAxisAlignment.start,
                EdgeInsets.only(left: 20, bottom: 8))),
      ],
    );
  }

  Widget get _bottomBar {
    final showToggle = user.isAniListConnected && user.status == AuthStatus.AUTHENTICATED;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          if (showToggle) _accountToggleChip,
          if (showToggle) ...[
            SB.w10,
            IconButton(
              onPressed: () {
                SyncHelper.showSyncOptions(
                  context: context,
                  contentDetailed: contentDetailed,
                  category: widget.category,
                  malId: _id,
                  anilistStatus: _alStatus,
                  anilistScore: _alScore,
                  anilistProgress: _alProgress,
                  anilistProgressVolumes: _alProgressVolumes,
                  anilistStartDate: _alStartDate,
                  anilistCompletedDate: _alCompletedDate,
                  anilistRepeat: _alRepeat,
                  anilistNotes: _alNotes,
                  onSyncedToAniList: (newStatus, newScore, newProgress, newProgressVolumes, newStartDate,
                      newCompletedDate, newRepeat, newNotes) {
                    setState(() {
                      _alStatus = newStatus;
                      _alScore = newScore ?? _alScore; // Keep current score if null
                      _alProgress = newProgress;
                      _alProgressVolumes = newProgressVolumes;
                      _alStartDate = newStartDate;
                      _alCompletedDate = newCompletedDate;
                      _alRepeat = newRepeat;
                      _alNotes = newNotes;
                    });
                  },
                  onSyncedToMal: () async {
                    await updateCache();
                    if (mounted) {
                      setState(() {
                        checkForUpdatesDuringBuild();
                      });
                    }
                  },
                  saveAniListEntry: _saveAniListEntry,
                  loadMalData: () async {
                    await updateCache();
                    if (mounted) {
                      setState(() {
                        checkForUpdatesDuringBuild();
                      });
                    }
                  },
                  loadAniListData: () async {
                    await _fetchAniListEntry();
                    if (mounted) {
                      setState(() {
                        checkForUpdatesDuringBuild();
                      });
                    }
                  },
                  getLatestAniListData: () {
                    return {
                      'status': _alStatus,
                      'score': _alScore,
                      'progress': _alProgress,
                      'progressVolumes': _alProgressVolumes,
                      'startDate': _alStartDate,
                      'completedDate': _alCompletedDate,
                      'repeat': _alRepeat,
                      'notes': _alNotes,
                    };
                  },
                );
              },
              icon: const Icon(Icons.sync),
            ),
          ],
          const Spacer(),
          ShadowButton(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            onPressed: () {
              if (_activeAccount == ActiveAccount.anilist) {
                _deleteAniListEntry();
              } else {
                deleteFromList();
              }
            },
            child: iconAndText(Icons.delete, S.current.Delete_from_List),
          ),
          SB.w10,
        ],
      ),
    );
  }

  Widget get _accountToggleChip => Padding(
        padding: const EdgeInsets.only(left: 6),
        child: SegmentedButton<ActiveAccount>(
          segments: <ButtonSegment<ActiveAccount>>[
            ButtonSegment<ActiveAccount>(
              value: ActiveAccount.mal,
              icon: Image.asset(
                'assets/images/mal-icon.png',
                width: 20,
                height: 20,
              ),
            ),
            ButtonSegment<ActiveAccount>(
              value: ActiveAccount.anilist,
              icon: Image.asset(
                'assets/images/anilist.png',
                width: 20,
                height: 20,
              ),
            ),
          ],
          selected: {_activeAccount},
          showSelectedIcon: false,
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onSelectionChanged: (Set<ActiveAccount> selection) {
            if (mounted) {
              setState(() {
                _activeAccount = selection.first;
              });
              // Persist preference
              user.pref.preferAniList = _activeAccount == ActiveAccount.anilist;
              user.setIntance(updateAuth: false);
              // Fetch AniList data when switching to it
              if (_activeAccount == ActiveAccount.anilist && _anilistEntry == null) {
                _fetchAniListEntry();
              }
              // Fetch MAL data when switching to it if not already loaded
              if (_activeAccount == ActiveAccount.mal && contentDetailed?.myListStatus == null && !cacheUpdated) {
                updateCache();
              }
            }
          },
        ),
      );

  Widget get dateStatusWidget => Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          field(
            S.current.Start_Date,
            _modifyWidget(
              modifyStartDate,
              SelectDate(
                onChangedFormatted: (value) {
                  modifyStartDate = true;
                  updateAdvancedStatus(
                      startDate: value,
                      onDone: () {
                        modifyStartDate = false;
                      });
                },
                selectDate: startDate ?? contentDetailed?.myListStatus?.startDate,
              ),
            ),
          ),
          field(
            S.current.Finish_Date,
            _modifyWidget(
              modifyFinishDate,
              SelectDate(
                onChangedFormatted: (value) {
                  modifyFinishDate = true;
                  updateAdvancedStatus(
                      finishDate: value,
                      onDone: () {
                        modifyFinishDate = false;
                      });
                },
                selectDate: finishDate ?? contentDetailed?.myListStatus?.finishDate,
              ),
            ),
          ),
          field(
              S.current.Priority,
              _modifyWidget(
                  modifyPriority,
                  SelectButton(
                    iconToUse: Icons.arrow_drop_down,
                    onChanged: (value) {
                      modifyPriority = true;
                      updateAdvancedStatus(
                          priority: int.tryParse(value),
                          onDone: () {
                            modifyPriority = false;
                          });
                    },
                    showSelectWhenNull: true,
                    displayValues: [S.current.Low, S.current.Medium, S.current.High],
                    selectedOption: contentDetailed?.myListStatus?.priority?.toString(),
                    options: List.generate(3, (i) => (i).toString()),
                  )),
              S.current.Priority_level_qn)
        ],
      );

  Widget get rewatchWidget => Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          field(
              (widget.category.equals('anime') ? S.current.Rewatching : S.current.Rereading),
              _modifyWidget(
                  modifyReStatus,
                  ToggleButton(
                    padding: EdgeInsets.zero,
                    toggleValue: widget.category.equals('anime')
                        ? (contentDetailed?.myListStatus?.isRewatching ?? false)
                        : (contentDetailed?.myListStatus?.isRereading ?? false),
                    onToggled: (value) {
                      modifyReStatus = true;
                      if (widget.category.equals('anime')) {
                        updateAdvancedStatus(
                            isRewatching: value,
                            onDone: () {
                              modifyReStatus = false;
                            });
                      } else {
                        updateAdvancedStatus(
                            isRereading: value,
                            onDone: () {
                              modifyReStatus = false;
                            });
                      }
                    },
                  ))),
          field(
            (widget.category.equals('anime') ? S.current.Times_Rewatched : S.current.Times_Reread),
            plusMinusWidget(
              (value) {
                modifyReStatus = true;
                if (widget.category.equals('anime')) {
                  updateAdvancedStatus(
                      timesRewatched: (value),
                      onDone: () {
                        modifyReStatus = false;
                      });
                } else {
                  updateAdvancedStatus(
                      timesReread: (value),
                      onDone: () {
                        modifyReStatus = false;
                      });
                }
              },
              initialValue: widget.category.equals('anime')
                  ? ((contentDetailed?.myListStatus?.numTimesRewatched ?? 0)?.toString())
                  : ((contentDetailed?.myListStatus?.numTimesReread ?? 0)?.toString()),
              modify: modifyReStatus,
              onSubmit: (value) {
                modifyReStatus = true;
                if (widget.category.equals('anime')) {
                  updateAdvancedStatus(
                      timesRewatched: int.tryParse(value),
                      onDone: () {
                        modifyReStatus = false;
                      });
                } else {
                  updateAdvancedStatus(
                      timesReread: int.tryParse(value),
                      onDone: () {
                        modifyReStatus = false;
                      });
                }
              },
            ),
          ),
          field(
            (widget.category.equals('anime') ? S.current.Rewatch : S.current.Reread) + S.current.Value,
            _modifyWidget(
                modifyReStatus,
                SelectButton(
                  iconToUse: Icons.arrow_drop_down,
                  onChanged: (value) {
                    modifyReStatus = true;
                    if (widget.category.equals('anime')) {
                      updateAdvancedStatus(
                          rewatchValue: int.tryParse(value),
                          onDone: () {
                            modifyReStatus = false;
                          });
                    } else {
                      updateAdvancedStatus(
                          rereadValue: int.tryParse(value),
                          onDone: () {
                            modifyReStatus = false;
                          });
                    }
                  },
                  showSelectWhenNull: true,
                  displayValues: [
                    S.current.Very_Low,
                    S.current.Low,
                    S.current.Medium,
                    S.current.High,
                    S.current.Very_High
                  ],
                  selectedOption: widget.category.equals('anime')
                      ? contentDetailed?.myListStatus?.rewatchValue?.toString()
                      : contentDetailed?.myListStatus?.rereadValue?.toString(),
                  options: List.generate(5, (i) => (i).toString()),
                )),
          )
        ],
      );

  Widget field(String text, Widget child,
      [String? toolTip,
      double? height = 40,
      CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.center,
      EdgeInsetsGeometry padding = EdgeInsets.zero]) {
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Wrap(
          children: [
            Padding(
              padding: padding,
              child: title(text),
            ),
            if (toolTip != null)
              ToolTipButton(
                message: toolTip,
                child: Icon(Icons.info, size: 12),
                padding: EdgeInsets.only(left: 5, top: 2),
              )
          ],
        ),
        const SizedBox(height: 10),
        Container(height: height, child: child)
      ],
    );
  }

  Widget _modifyWidget(bool modify, Widget child) {
    return modify
        ? Container(
            height: 40,
            // padding: EdgeInsets.only(top: 7),
            child: Center(
              child: loadingCenter(),
            ),
          )
        : child;
  }

  Widget animeStatusWidget() {
    return Container(
        padding: EdgeInsets.symmetric(horizontal: 5, vertical: 0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (_episodeSelectMode == EpisodeSelectMode.bar) SB.w20,
                Expanded(child: expandedChild(S.current.Status, statusWidget())),
                SB.w20,
                if (_episodeSelectMode == EpisodeSelectMode.text)
                  Expanded(
                      child: Column(
                    children: [
                      SB.h10,
                      _episodeTextHeader(),
                      SB.h10,
                      SizedBox(width: double.infinity, child: _episodesWidget()),
                    ],
                  )),
              ],
            ),
            if (_episodeSelectMode == EpisodeSelectMode.bar) _episodeBarWidget(),
            _scoreBarWidget(),
            SB.h20,
          ],
        ));
  }

  Widget expandedChild(String text, Widget child) {
    return Column(
      children: [
        SB.h10,
        Text(text),
        SB.h10,
        SizedBox(width: double.infinity, child: child),
      ],
    );
  }

  Widget _scoreBarWidget() {
    final value = myStarMap[starValue];
    final keys = myStarMap.keys.toList();
    return Column(
      children: [
        SB.h20,
        Text('${S.current.Score}${value == null ? '' : ' · ${value}'}'),
        SB.h15,
        SizedBox(
          height: 45.0,
          child: modifyStars
              ? loadingCenter()
              : ScrollablePositionedList.builder(
                  itemScrollController: itemScrollController,
                  scrollDirection: Axis.horizontal,
                  physics: ClampingScrollPhysics(),
                  initialAlignment: 0.5,
                  padding: EdgeInsets.symmetric(horizontal: 160.0, vertical: 2.0),
                  initialScrollIndex: keys.indexOf(starValue ?? 0),
                  itemCount: keys.length,
                  itemBuilder: (context, e) => _buildScoreButton(keys, e, context),
                ),
        ),
      ],
    );
  }

  Padding _buildScoreButton(List<int> keys, int e, BuildContext context) {
    final value = keys[e];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: ShadowButton(
        onPressed: () async {
          itemScrollController.scrollTo(
            index: e,
            alignment: 0.5,
            duration: const Duration(milliseconds: 200),
          );
          updateRatingStatus(value);
        },
        child: Text(value == 0 ? S.current.Select : value.toString()),
        padding: EdgeInsets.zero,
        shape: value == starValue
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(32),
                side: BorderSide(color: Theme.of(context).dividerColor, width: 1.0))
            : RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      ),
    );
  }

  Widget mangaStatusWidget() {
    return Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Column(
              children: [
                expandedChild(
                  S.current.Reading_Status,
                  statusWidget(),
                ),
                SB.h5,
                Row(
                  children: [
                    Expanded(
                      child: expandedChild(
                          "${S.current.Chapters} " +
                              ((!(contentDetailed is MangaDetailed) ||
                                      contentDetailed?.numChapters == null ||
                                      contentDetailed.numChapters == 0)
                                  ? S.current.Read
                                  : "(${contentDetailed.numChapters})"),
                          chaptersWidget()),
                    ),
                    SB.w20,
                    Expanded(
                      child: expandedChild(
                          "${S.current.Volumes} " +
                              ((!(contentDetailed is MangaDetailed) ||
                                      contentDetailed?.numVolumes == null ||
                                      contentDetailed.numVolumes == 0)
                                  ? S.current.Read
                                  : "(${contentDetailed.numVolumes})"),
                          volumesWidget()),
                    ),
                  ],
                ),
                _scoreBarWidget(),
                SB.h20,
              ],
            ),
          ],
        ));
  }

  Widget _episodeBarWidget() {
    final count = _totalEpisodeCount ?? 1;
    return Column(
      children: [
        SB.h20,
        _episodeTextHeader(),
        SB.h15,
        SizedBox(
          height: 45.0,
          child: modifyEpisodes
              ? loadingCenter()
              : ScrollablePositionedList.builder(
                  itemScrollController: _episodeScrollController,
                  scrollDirection: Axis.horizontal,
                  physics: ClampingScrollPhysics(),
                  initialAlignment: 0.5,
                  initialScrollIndex: _episodeCount(),
                  padding: EdgeInsets.symmetric(horizontal: 160.0, vertical: 2.0),
                  itemCount: count,
                  itemBuilder: (context, e) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: ShadowButton(
                          onPressed: () async {
                            _episodeScrollController.scrollTo(
                              index: e,
                              alignment: 0.5,
                              duration: const Duration(milliseconds: 200),
                            );
                            updateEpisodeCount(episodes: e + 1);
                          },
                          child: Text((e + 1).toString()),
                          padding: EdgeInsets.zero,
                          shape: (e + 1) == _episodeCount()
                              ? RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(32),
                                  side: BorderSide(color: Theme.of(context).dividerColor, width: 1.0))
                              : RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(32),
                                ),
                        ),
                      )),
        ),
      ],
    );
  }

  Row _episodeTextHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SB.w20,
        Text(S.current.Episodes_seen),
        SB.w5,
        ToolTipButton(
          onTap: () {
            if (mounted)
              setState(() {
                if (_episodeSelectMode == EpisodeSelectMode.text) {
                  _episodeSelectMode = EpisodeSelectMode.bar;
                  _scrollToEpisodeCount();
                } else {
                  _episodeSelectMode = EpisodeSelectMode.text;
                }
                CacheManager.instance.setValueForService('edit', 'episodeSelectPref', _episodeSelectMode.name);
              });
          },
          child: Icon(Icons.change_circle, size: 18),
          message: S.current.Update,
        ),
        SB.w20,
      ],
    );
  }

  void _scrollToEpisodeCount() {
    const duration = const Duration(milliseconds: 200);
    Future.delayed(duration).then(
      (value) {
        if (mounted && _episodeScrollController.isAttached) {
          try {
            _episodeScrollController.scrollTo(
              index: _episodeCount(),
              alignment: 0.6,
              duration: duration,
            );
          } catch (e) {
            // Ignore scroll errors if list is not ready
          }
        }
      },
    );
  }

  int? get _totalEpisodeCount {
    int totalEpisodes = 0;
    if (contentDetailed is AnimeDetailed) {
      totalEpisodes = contentDetailed?.numEpisodes ?? 0;
    }
    if (contentDetailed is BaseNode) {
      totalEpisodes = contentDetailed?.content?.numEpisodes ?? 0;
    }
    if (_scheduleData != null) {
      totalEpisodes = _scheduleData?.episode ?? 0;
    }
    if (totalEpisodes == 0) {
      totalEpisodes = _calculateEpisodes();
    }
    if (totalEpisodes == 0) {
      return null;
    }
    return totalEpisodes;
  }

  int _calculateEpisodes() {
    int totalEpisodes = 0;
    if (contentDetailed is AnimeDetailed) {
      var animeDetailed = contentDetailed as AnimeDetailed;
      totalEpisodes = animeDetailed.calculateTotalEpisodes();
    }
    return totalEpisodes;
  }

  int _episodeCount() {
    return episodeController.text.isNotEmpty ? int.tryParse(episodeController.text) ?? 0 : 0;
  }

  Widget _episodesWidget() {
    return Container(
      // width: 150,
      height: 50,
      child: ShadowButton(
        onPressed: () {},
        padding: EdgeInsets.symmetric(horizontal: 3.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              onPressed: () {
                if (!modifyEpisodes) updateEpisodeCount(add: -1);
              },
              icon: Icon(Icons.remove),
            ),
            Flexible(
              child: SizedBox(
                child: modifyEpisodes
                    ? Center(
                        child: loadingCenter(),
                      )
                    : TextFormField(
                        keyboardType: TextInputType.number,
                        onFieldSubmitted: (value) {
                          updateEpisodeCount(episodes: int.tryParse(value));
                        },
                        controller: episodeController,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                            contentPadding: EdgeInsets.zero,
                            enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                              style: BorderStyle.none,
                            )),
                            focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                              style: BorderStyle.none,
                            )),
                            border: OutlineInputBorder(
                                borderSide: BorderSide(
                              style: BorderStyle.none,
                            ))),
                      ),
              ),
            ),
            IconButton(
              padding: EdgeInsets.zero,
              onPressed: () {
                if (!modifyEpisodes) updateEpisodeCount(add: 1);
              },
              icon: Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }

  Widget volumesWidget() {
    return Container(
      // width: 150,
      height: 50,
      child: ShadowButton(
        onPressed: () {},
        padding: EdgeInsets.symmetric(horizontal: 3.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              onPressed: () {
                if (!modifyVolumes) updateVolumeCount(add: -1);
              },
              icon: Icon(Icons.remove),
            ),
            Flexible(
              child: SizedBox(
                child: modifyVolumes
                    ? Center(
                        child: loadingCenter(),
                      )
                    : TextFormField(
                        keyboardType: TextInputType.number,
                        onFieldSubmitted: (value) {
                          updateVolumeCount(volumes: int.tryParse(value));
                        },
                        controller: volumesController,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                            contentPadding: EdgeInsets.zero,
                            enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                              style: BorderStyle.none,
                            )),
                            focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                              style: BorderStyle.none,
                            )),
                            border: OutlineInputBorder(
                                borderSide: BorderSide(
                              style: BorderStyle.none,
                            ))),
                      ),
              ),
            ),
            IconButton(
              padding: EdgeInsets.zero,
              onPressed: () {
                if (!modifyVolumes) updateVolumeCount(add: 1);
              },
              icon: Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }

  Widget chaptersWidget() {
    return Container(
      // width: 150,
      height: 50,
      child: ShadowButton(
        onPressed: () {},
        padding: EdgeInsets.symmetric(horizontal: 3.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              onPressed: () {
                if (!modifyChapters) updateChapterCount(add: -1);
              },
              icon: Icon(Icons.remove),
            ),
            Flexible(
              child: SizedBox(
                child: modifyChapters
                    ? Center(
                        child: loadingCenter(),
                      )
                    : TextFormField(
                        keyboardType: TextInputType.number,
                        onFieldSubmitted: (value) {
                          updateChapterCount(chapters: int.tryParse(value));
                        },
                        controller: chapterController,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                            contentPadding: EdgeInsets.zero,
                            enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                              style: BorderStyle.none,
                            )),
                            focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                              style: BorderStyle.none,
                            )),
                            border: OutlineInputBorder(
                                borderSide: BorderSide(
                              style: BorderStyle.none,
                            ))),
                      ),
              ),
            ),
            IconButton(
              padding: EdgeInsets.zero,
              onPressed: () {
                if (!modifyChapters) updateChapterCount(add: 1);
              },
              icon: Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }

  // MAL status widget (unchanged – keeps its own cache/state)
  Widget statusWidget() {
    final Widget child;
    Map<String, String> myStatusMap = widget.category.equals("anime") ? myAnimeStatusMap : myMangaStatusMap;
    if (modifyStatus)
      child = Center(
        child: loadingCenter(),
      );
    else
      child = SelectButton(
        options: myStatusMap.keys.toList(),
        displayValues: myStatusMap.values.toList(),
        selectedOption: statusValue,
        useShadowChild: true,
        popupText: S.current.Status,
        onChanged: (value) => updateWatchingStatus(value),
      );
    return SizedBox(
      height: 50,
      child: child,
    );
  }

  Widget plusMinusWidget(
    ValueChanged<int?> onChange, {
    required bool modify,
    Function(String)? onSubmit,
    String? initialValue,
    TextInputType keyboardType = TextInputType.number,
  }) {
    return Container(
      height: 50,
      width: 120.0,
      child: ShadowButton(
        onPressed: () {},
        padding: EdgeInsets.symmetric(horizontal: 3.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              onPressed: () {
                onChange((int.tryParse(initialValue ?? "1") ?? 1) - 1);
              },
              icon: Icon(Icons.remove),
            ),
            Flexible(
              child: SizedBox(
                child: modify
                    ? Center(
                        child: loadingCenter(),
                      )
                    : TextFormField(
                        initialValue: initialValue,
                        keyboardType: keyboardType,
                        onFieldSubmitted: (value) {
                          onChange((int.tryParse(value) ?? 1) - 1);
                        },
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                            contentPadding: EdgeInsets.zero,
                            enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                              style: BorderStyle.none,
                            )),
                            focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                              style: BorderStyle.none,
                            )),
                            border: OutlineInputBorder(
                                borderSide: BorderSide(
                              style: BorderStyle.none,
                            ))),
                      ),
              ),
            ),
            IconButton(
              padding: EdgeInsets.zero,
              onPressed: () {
                onChange((int.tryParse(initialValue ?? "0") ?? 0) + 1);
              },
              icon: Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }
}
