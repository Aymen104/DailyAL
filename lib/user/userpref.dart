import 'dart:math';

import 'package:dailyanimelist/screens/contentdetailedscreen.dart';
import 'package:dailyanimelist/screens/generalsearchscreen.dart';
import 'package:dailyanimelist/user/anime_manga_pref.dart';
import 'package:dailyanimelist/user/hompagepref.dart';
import 'package:dal_commons/commons.dart';
import 'package:flutter/services.dart';

class UserPreferences {
  List<int> cacheUpdateFrequency;
  bool firstTime;
  bool showBg;
  bool showCountDownInDetailed;
  bool detailsExpanded;
  bool nsfw;
  bool keepPagesInMemory;
  bool showPriority;
  bool showOnlyLastQuote;
  bool autoTranslateSynopsis;
  bool autoAddStartEndDate;
  bool showAiringInfo;
  bool showDubStatus;
  String dubLanguage;
  String dubIconStyle;
  String dubMinSourceCount;
  bool showAnimeMangaCard;
  NotifPref notifPref;
  List<HomePageApiPref> hpApiPrefList;
  List<int> userchart;
  int homePageItemsPerCategory;
  String userLanguage;
  Brightness brightness;
  bool isRtl;
  String? bgPath;
  bool showAnimeMangaBg;
  DisplayType defaultDisplayType;
  FirstTimePref firstTimePref;
  String userPageAnimeSortType;
  String userPageMangaSortType;
  HomePageTileSize homePageTileSize;
  TitleLang preferredAnimeTitle;
  AnimeMangaPagePreferences animeMangaPagePreferences;
  int startUpPage; // Deprecated, kept for migration
  int startUpPageMobile; // Startup page for phone (0-4)
  int startUpPageTablet; // Startup page for tablet (0-7)
  LinkType preferredLinkType;
  bool allowYoutubePlayer;
  String preferredFont;
  bool preferAniList;
  UserPreferences({
    required this.firstTime,
    required this.homePageTileSize,
    required this.showCountDownInDetailed,
    required this.cacheUpdateFrequency,
    required this.homePageItemsPerCategory,
    required this.showBg,
    required this.detailsExpanded,
    required this.keepPagesInMemory,
    required this.nsfw,
    required this.showPriority,
    required this.userchart,
    required this.userLanguage,
    required this.showAiringInfo,
    required this.showDubStatus,
    required this.dubLanguage,
    required this.dubIconStyle,
    required this.dubMinSourceCount,
    required this.isRtl,
    required this.brightness,
    required this.showAnimeMangaBg,
    required this.bgPath,
    required this.hpApiPrefList,
    required this.autoTranslateSynopsis,
    required this.showOnlyLastQuote,
    required this.autoAddStartEndDate,
    required this.defaultDisplayType,
    required this.notifPref,
    required this.userPageAnimeSortType,
    required this.userPageMangaSortType,
    required this.firstTimePref,
    required this.preferredAnimeTitle,
    required this.animeMangaPagePreferences,
    required this.startUpPage,
    required this.startUpPageMobile,
    required this.startUpPageTablet,
    required this.showAnimeMangaCard,
    required this.preferredLinkType,
    required this.allowYoutubePlayer,
    required this.preferredFont,
    required this.preferAniList,
  });

  factory UserPreferences.fromJson(Map<String, dynamic>? json) {
    List<int>? _cacheUpdateFrequency;
    List<HomePageApiPref>? _hpApiPrefList;
    List<int>? _userchart;
    int? _homePageItemsPerCategory;
    NotifPref _notifPref = NotifPref();
    bool _detailsExpanded = true,
        _nsfw = false,
        _keepPagesInMemory = false,
        _showOnlyLastQuote = true,
        _autoAddStartEndDate = true,
        _showAiringInfo = false,
        _showDubStatus = false;
    String _dubLanguage = 'english',
        _dubIconStyle = '0',
        _dubMinSourceCount = '1';
    Brightness _brightness = Brightness.dark;
    bool _showPriority = false,
        _autoTranslateSynopsis = false,
        _isRtl = false,
        showAnimeMangaBg = true,
        _showBg = true;
    String? _userLanguage, _bgPath;
    AnimeMangaPagePreferences? _animeMangaPagePreferences;
    if (json != null) {
      if (_cacheUpdateFrequency == null) {
        _cacheUpdateFrequency = List.from(json["cacheUpdateFrequency"] as Iterable<dynamic> ?? [])
            .map((e) => int.parse(e.toString()))
            .toList();
      }

      if (json.containsKey("show_bg")) {
        _showBg = json["show_bg"] as bool ?? true;
      }

      if (json.containsKey("notifPref")) {
        _notifPref = NotifPref.fromJson(json["notifPref"] as Map<String, dynamic>?);
      }

      if (json.containsKey("detailsExpanded")) {
        _detailsExpanded = json["detailsExpanded"] as bool ?? true;
      }

      if (json.containsKey("nsfw")) {
        _nsfw = json["nsfw"] as bool ?? false;
      }

      if (json.containsKey("keepPagesInMemory")) {
        _keepPagesInMemory = json["keepPagesInMemory"] as bool ?? true;
      }

      if (json.containsKey("hpApiPrefList_v6")) {
        _hpApiPrefList = List.from(json["hpApiPrefList_v6"] as Iterable<dynamic>)
            .map((e) => HomePageApiPref.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      if (json.containsKey("userChart")) {
        _userchart = json["userChart"] != null
            ? List<int>.from(json["userChart"] as Iterable<dynamic>)
            : [-1, -1, -1, -1, -1];
      }

      if (json.containsKey("homePageItemsPerCategory")) {
        _homePageItemsPerCategory = json["homePageItemsPerCategory"] as int? ?? 14;
      }

      if (json.containsKey("showPriority")) {
        _showPriority = json["showPriority"] as bool ?? false;
      }
      if (json.containsKey("userLanguage")) {
        _userLanguage = json["userLanguage"] as String?;
      }

      if (json.containsKey("autoTranslateSynopsis")) {
        _autoTranslateSynopsis = json["autoTranslateSynopsis"] as bool ?? false;
      }
      if (json.containsKey("isRtl")) {
        _isRtl = json["isRtl"] as bool ?? false;
      }
      if (json.containsKey("showOnlyLastQuote")) {
        _showOnlyLastQuote = json["showOnlyLastQuote"] as bool ?? true;
      }
      if (json.containsKey("brightness")) {
        _brightness =
            (json["brightness"] as bool ?? false) ? Brightness.light : Brightness.dark;
      }
      if (json.containsKey("bgPath")) {
        _bgPath = json["bgPath"] as String?;
      }
      if (json.containsKey("autoAddStartEndDate")) {
        _autoAddStartEndDate = json["autoAddStartEndDate"] as bool ?? true;
      }
      if (json.containsKey("showAiringInfo_v2")) {
        _showAiringInfo = json["showAiringInfo_v2"] as bool ?? false;
      }
      if (json.containsKey("showDubStatus")) {
        _showDubStatus = json["showDubStatus"] as bool ?? false;
      }
      if (json.containsKey("dubLanguage")) {
        _dubLanguage = json["dubLanguage"] as String ?? 'english';
      }
      if (json.containsKey("dubIconStyle")) {
        _dubIconStyle = json["dubIconStyle"] as String ?? '0';
      }
      if (json.containsKey("dubMinSourceCount")) {
        _dubMinSourceCount = json["dubMinSourceCount"] as String ?? '1';
      }
      if (json.containsKey("showAnimeMangaBg")) {
        showAnimeMangaBg = json['showAnimeMangaBg'] as bool ?? showAnimeMangaBg;
      }
      if (json.containsKey('animeMangaPagePreferences')) {
        try {
          _animeMangaPagePreferences = AnimeMangaPagePreferences.fromJson(
              json['animeMangaPagePreferences'] as Map<String, dynamic>);
        } catch (e) {
          logDal(e);
        }
      }
    }
    return json != null
        ? UserPreferences(
            showCountDownInDetailed: json['showCountDownInDetailed'] as bool? ?? true,
            firstTime: json["first_time"] as bool? ?? true,
            cacheUpdateFrequency: _cacheUpdateFrequency ?? [8, 2, 1],
            showBg: _showBg,
            detailsExpanded: _detailsExpanded,
            nsfw: _nsfw,
            userLanguage: _userLanguage ?? "en_US",
            showPriority: _showPriority,
            userchart: _userchart ?? [-1, -1, -1, -1, -1],
            keepPagesInMemory: _keepPagesInMemory,
            homePageItemsPerCategory: _homePageItemsPerCategory ?? 14,
            hpApiPrefList: _hpApiPrefList ?? [],
            autoTranslateSynopsis: _autoTranslateSynopsis,
            isRtl: _isRtl,
            showOnlyLastQuote: _showOnlyLastQuote,
            bgPath: _bgPath,
            autoAddStartEndDate: _autoAddStartEndDate,
            brightness: _brightness,
            notifPref: _notifPref,
            showAiringInfo: _showAiringInfo,
            showDubStatus: _showDubStatus,
            dubLanguage: _dubLanguage,
            dubIconStyle: _dubIconStyle,
            dubMinSourceCount: _dubMinSourceCount,
            showAnimeMangaBg: showAnimeMangaBg,
            userPageAnimeSortType:
                json['userPageAnimeSortType'] as String? ?? 'list_updated_at',
            userPageMangaSortType:
                json['userPageMangaSortType'] as String? ?? 'list_updated_at',
            defaultDisplayType:
                DisplayType.values.elementAt(json['defaultDisplayType'] as int? ?? 0),
            homePageTileSize: json['homePageTileSize'] != null
                ? HomePageTileSize.values.elementAt(json['homePageTileSize'] as int)
                : HomePageTileSize.l,
            firstTimePref: FirstTimePref.fromJson(json['firstTimePref'] as Map<String, dynamic>?),
            preferredAnimeTitle: TitleLang.values
                .elementAt(json['preferredAnimeTitle'] as int? ?? TitleLang.ro.index),
            startUpPage: min(json['startUpPage'] as int? ?? 0, 7),
            // Migrate from old startUpPage if new fields don't exist
            startUpPageMobile: min(
                json['startUpPageMobile'] as int? ?? (min(json['startUpPage'] as int? ?? 0, 4)),
                4),
            startUpPageTablet:
                min(json['startUpPageTablet'] as int? ?? (json['startUpPage'] as int? ?? 0), 7),
            preferredLinkType: LinkType.values.firstWhere(
              (e) => e.name == json['preferredLinkType'] as String?,
              orElse: () => LinkType.streaming,
            ),
            allowYoutubePlayer: json['allowYoutubePlayer'] as bool ?? false,
            showAnimeMangaCard: json['showAnimeMangaCard'] as bool ?? false,
            preferredFont: json['preferredFont'] as String ?? 'Poppins',
            preferAniList: json['preferAniList'] as bool ?? false,
            animeMangaPagePreferences: _animeMangaPagePreferences ??
                AnimeMangaPagePreferences.defaultObject())
        : UserPreferences(
            showCountDownInDetailed: true,
            firstTime: true,
            cacheUpdateFrequency: [8, 2, 1],
            notifPref: NotifPref.fromJson(null),
            nsfw: _nsfw,
            brightness: _brightness,
            userLanguage: _userLanguage ?? "en_US",
            showPriority: _showPriority,
            bgPath: _bgPath,
            homePageItemsPerCategory: _homePageItemsPerCategory ?? 14,
            userchart: _userchart ?? [-1, -1, -1, -1, -1],
            hpApiPrefList: _hpApiPrefList ?? [],
            keepPagesInMemory: _keepPagesInMemory,
            isRtl: false,
            autoAddStartEndDate: _autoAddStartEndDate,
            showOnlyLastQuote: _showOnlyLastQuote,
            detailsExpanded: _detailsExpanded,
            autoTranslateSynopsis: _autoTranslateSynopsis,
            showBg: _showBg,
            showAiringInfo: _showAiringInfo,
            showDubStatus: _showDubStatus,
            dubLanguage: _dubLanguage,
            dubIconStyle: _dubIconStyle,
            dubMinSourceCount: _dubMinSourceCount,
            defaultDisplayType: DisplayType.list_vert,
            showAnimeMangaBg: showAnimeMangaBg,
            userPageAnimeSortType: 'list_updated_at',
            userPageMangaSortType: 'list_updated_at',
            firstTimePref: FirstTimePref(),
            homePageTileSize: HomePageTileSize.l,
            preferredAnimeTitle: TitleLang.ro,
            startUpPage: 0,
            startUpPageMobile: 0,
            startUpPageTablet: 0,
            preferredLinkType: LinkType.streaming,
            showAnimeMangaCard: false,
            allowYoutubePlayer: false,
            preferredFont: 'Poppins',
            preferAniList: false,
            animeMangaPagePreferences:
                AnimeMangaPagePreferences.defaultObject(),
          );
  }
  Map<String, dynamic> toJson() {
    return {
      'showCountDownInDetailed': showCountDownInDetailed,
      'userPageMangaSortType': userPageMangaSortType,
      'userPageAnimeSortType': userPageAnimeSortType,
      "homePageItemsPerCategory": homePageItemsPerCategory,
      "userChart": userchart,
      "hpApiPrefList_v6": hpApiPrefList,
      "first_time": firstTime,
      "cacheUpdateFrequency": cacheUpdateFrequency,
      "show_bg": showBg,
      "notifPref": notifPref.toJson(),
      "keepPagesInMemory": keepPagesInMemory,
      "nsfw": nsfw,
      "showPriority": showPriority,
      "isRtl": isRtl,
      "detailsExpanded": detailsExpanded,
      "userLanguage": userLanguage,
      "autoTranslateSynopsis": autoTranslateSynopsis,
      "showOnlyLastQuote": showOnlyLastQuote,
      "bgPath": bgPath,
      "showAiringInfo_v2": showAiringInfo,
      "showDubStatus": showDubStatus,
      "dubLanguage": dubLanguage,
      "dubIconStyle": dubIconStyle,
      "dubMinSourceCount": dubMinSourceCount,
      "autoAddStartEndDate": autoAddStartEndDate,
      "defaultDisplayType": defaultDisplayType.index,
      'showAnimeMangaBg': showAnimeMangaBg,
      "firstTimePref": firstTimePref.toJson(),
      "brightness": (brightness) != Brightness.dark,
      'homePageTileSize': homePageTileSize.index,
      'preferredAnimeTitle': preferredAnimeTitle.index,
      'animeMangaPagePreferences': animeMangaPagePreferences,
      'showAnimeMangaCard': showAnimeMangaCard,
      'startUpPage': startUpPage,
      'startUpPageMobile': startUpPageMobile,
      'startUpPageTablet': startUpPageTablet,
      'allowYoutubePlayer': allowYoutubePlayer,
      'preferredLinkType': preferredLinkType.name,
      'preferredFont': preferredFont,
      'preferAniList': preferAniList,
    };
  }
}

class NotifPref {
  DateTime? daySubscribed;
  bool onDailyAnimeReleases;
  bool onWatchingListUpdated;
  bool onPTWGoesToWatching;
  bool preferLargeImage;

  NotifPref(
      {this.daySubscribed,
      this.onDailyAnimeReleases = true,
      this.onPTWGoesToWatching = true,
      this.onWatchingListUpdated = true,
      this.preferLargeImage = true});

  factory NotifPref.fromJson(Map<String, dynamic>? json) {
    DateTime? _daySubscribed;
    bool? _onDailyAnimeReleases,
        _onWatchingListUpdated,
        _onPTWGoesToWatching,
        _preferLargeImage;

    if (json != null) {
      if (json.containsKey("day_subscribed")) {
        _daySubscribed = DateTime.tryParse(json["day_subscribed"] as String? ?? "");
      }

      if (json.containsKey("onDailyAnimeReleases")) {
        _onDailyAnimeReleases = json["onDailyAnimeReleases"] as bool? ?? true;
      }

      if (json.containsKey("onPTWGoesToWatching")) {
        _onPTWGoesToWatching = json["onPTWGoesToWatching"] as bool? ?? true;
      }

      if (json.containsKey("onWatchingListUpdated")) {
        _onWatchingListUpdated = json["onWatchingListUpdated"] as bool? ?? true;
      }
      if (json.containsKey("preferLargeImage")) {
        _preferLargeImage = json["preferLargeImage"] as bool? ?? true;
      }
    }

    return json == null
        ? NotifPref()
        : NotifPref(
            daySubscribed: _daySubscribed,
            onDailyAnimeReleases: _onDailyAnimeReleases ?? true,
            onPTWGoesToWatching: _onPTWGoesToWatching ?? true,
            onWatchingListUpdated: _onWatchingListUpdated ?? true,
            preferLargeImage: _preferLargeImage ?? true,
          );
  }

  Map<String, dynamic> toJson() => {
        "day_subscribed": daySubscribed?.toString(),
        'preferLargeImage': preferLargeImage,
        "onDailyAnimeReleases": onDailyAnimeReleases,
        "onWatchingListUpdated": onWatchingListUpdated,
        "onPTWGoesToWatching": onPTWGoesToWatching,
      };
}

class FirstTimePref {
  bool bg;
  bool news;
  bool themeV3;
  bool homePageSize;
  bool prefferedTitle;
  bool startUpPage;

  FirstTimePref({
    this.bg = true,
    this.news = true,
    this.homePageSize = true,
    this.prefferedTitle = true,
    this.themeV3 = true,
    this.startUpPage = true,
  });

  factory FirstTimePref.fromJson(Map<String, dynamic>? json) {
    return json == null
        ? FirstTimePref()
        : FirstTimePref(
            bg: json['bg'] as bool? ?? true,
            news: json['news'] as bool? ?? true,
            homePageSize: json['homePageSize'] as bool? ?? true,
            prefferedTitle: json['prefferedTitle'] as bool? ?? true,
            themeV3: json['themeV3'] as bool? ?? true,
            startUpPage: json['startUpPage'] as bool? ?? true,
          );
  }

  Map<String, dynamic> toJson() => {
        "bg": bg,
        "news": news,
        "homePageSize": homePageSize,
        'prefferedTitle': prefferedTitle,
        'themeV3': themeV3,
        'startUpPage': startUpPage,
      };
}
