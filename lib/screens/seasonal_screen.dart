import 'package:dailyanimelist/api/auth/auth.dart';
import 'package:dailyanimelist/api/malapi.dart';
import 'package:dailyanimelist/constant.dart';
import 'package:dailyanimelist/enums.dart';
import 'package:dailyanimelist/generated/l10n.dart';
import 'package:dailyanimelist/screens/generalsearchscreen.dart';
import 'package:dailyanimelist/widgets/custombutton.dart';
import 'package:dailyanimelist/widgets/listsortfilter.dart';
import 'package:dailyanimelist/widgets/slivers.dart';
import 'package:dailyanimelist/widgets/user/contentbuilder.dart';
import 'package:dal_commons/dal_commons.dart';
import 'package:flutter/material.dart';
import 'package:line_icons/line_icon.dart';
import 'package:line_icons/line_icons.dart';
import 'package:dailyanimelist/util/responsive_helper.dart';
import 'package:dailyanimelist/main.dart';

class SeasonalConstants {
  static const totalYears = 64;
  static final maxYear = DateTime.now().year + 1;
}

class _Season {
  final int year;
  final SeasonType seasonType;
  final String display;

  _Season(this.year, this.seasonType, this.display);
}

class SeasonalScreen extends StatefulWidget {
  final SeasonType seasonType;
  final int year;
  final SortType? sortType;

  const SeasonalScreen({
    Key? key,
    required this.seasonType,
    required this.year,
    this.sortType,
  }) : super(key: key);

  @override
  State<SeasonalScreen> createState() => _SeasonalScreenState();
}

class _SeasonalScreenState extends State<SeasonalScreen>
    with TickerProviderStateMixin {
  static final tabsLength = yearList.length;
  static final seasonList = seasonMapCaps.values.toList().reversed.toList();
  static final yearList = List.generate(SeasonalConstants.totalYears,
          (index) => (SeasonalConstants.maxYear - index).toString())
      .expand((year) => seasonList
          .map((e) => _Season(
              int.parse(year), seasonMapInverse[e.toLowerCase()]!, '$e $year'))
          .toList())
      .toList();
  static final seasonImage = {
    SeasonType.FALL: 'assets/images/fall.jpg',
    SeasonType.SPRING: 'assets/images/cherry.jpg',
    SeasonType.SUMMER: 'assets/images/summer.jpg',
    SeasonType.WINTER: 'assets/images/winter.png',
  };
  static final seasonMap = SeasonType.values.asMap();
  late int currentYearIndex;
  late int currentSeasonIndex;
  int currPageIndex = 0;
  late String imageUrl;
  late String refKey;
  SortOption? _sortOption;
  int get pageLimit => 500;
  bool _isRefreshing = false;

  SortFilterDisplay? _globalSortFilter;
  bool get _isGlobalFilter =>
      user.pref.animeMangaPagePreferences.globalSeasonalFilter;

  @override
  void initState() {
    super.initState();
    currentSeasonIndex = widget.seasonType.index;
    currentYearIndex = widget.year;
    _sortOption = _getSortOption();
    refKey = MalAuth.codeChallenge(10);
    setImageUrl();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isGlobalFilter && _globalSortFilter == null) {
      _loadGlobalSortFilter();
    }
  }

  void _loadGlobalSortFilter() async {
    final isTablet = ResponsiveHelper.isTabletOrLarger(context);
    final defObj = SortFilterDisplay(
      sort: SortOption(name: 'Updated At', value: 'list_updated_at'),
      displayOption: DisplayOption(
        displayType: isTablet ? DisplayType.grid : user.pref.defaultDisplayType,
        displaySubType:
            isTablet ? DisplaySubType.compact : DisplaySubType.comfortable,
        gridCrossAxisCount: ResponsiveHelper.getCrossAxisCount(context),
      ),
      filterOutputs: {},
    );
    _globalSortFilter = await SortFilterDisplay.fromCache(
        'UserContentBuilderSeasonal_Screen', 'anime-@me', defObj);
    _globalSortFilter = _globalSortFilter!.copyWith(category: 'anime');
    if (_sortOption != null) {
      _globalSortFilter = _globalSortFilter!.copyWith(sort: _sortOption!);
    }
    if (mounted) setState(() {});
  }

  SortOption? _getSortOption() {
    var sortType = widget.sortType;
    if (sortType != null) {
      if (sortType == SortType.AnimeScore) {
        return scoreOption();
      } else if (sortType == SortType.AnimeNumListUsers) {
        return numListUsersOption();
      }
    }
    return null;
  }

  @override
  void dispose() {
    super.dispose();
  }

  int getInitialIndex() {
    final seasonsLength = seasonList.length;
    final int yearOffset = (currentYearIndex - SeasonalConstants.maxYear).abs();
    return yearOffset * seasonsLength +
        (seasonsLength - 1 - currentSeasonIndex).abs();
  }

  void setImageUrl() {
    imageUrl = seasonImage[seasonMap[currentSeasonIndex]]!;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DefaultTabController(
        length: tabsLength,
        initialIndex: getInitialIndex(),
        child: NestedScrollView(
          headerSliverBuilder: (_, __) => [_buildAppBar()],
          body: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return TabBarView(
      physics: const NeverScrollableScrollPhysics(),
      children: yearList.map((e) => _buildStateFullSeason(e)).toList(),
    );
  }

  SliverAppBarWrapper _buildAppBar() {
    return SliverAppBarWrapper(
      title: Text(S.current.Seasonal),
      implyLeading: true,
      toolbarHeight: 120,
      expandedHeight: 120,
      snap: false,
      flexSpace: _backgroundImage(),
      bottom: _buildTabBar(),
      actions: _buildActions,
    );
  }

  List<Widget> get _buildActions {
    return [
      if (_isGlobalFilter && _globalSortFilter != null)
        ToolTipButton(
          message: S.current.Filter,
          onTap: () {
            showSortFilterDisplayModal(
              context: context,
              sortFilterDisplay: _globalSortFilter!.clone(),
              onSortFilterChange: (value) {
                _globalSortFilter = value.clone();
                value.toCache('UserContentBuilderSeasonal_Screen', 'anime-@me');
                if (mounted) setState(() {});
              },
            );
          },
          child: Icon(
            _globalSortFilter!.filterOutputs.isEmpty
                ? LineIcons.filter
                : filterLengthIcon(_globalSortFilter!.filterOutputs.length),
          ),
        ),
      ToolTipButton(
        message: S.current.Search_Bar_Text,
        onTap: () => gotoPage(
            context: context,
            newPage: GeneralSearchScreen(
              showBackButton: true,
              autoFocus: false,
            )),
        child: Icon(Icons.search),
      ),
      SB.w20,
    ];
  }

  Opacity _backgroundImage() {
    return Opacity(
      opacity: .2,
      child: Image.asset(
        imageUrl,
        fit: BoxFit.cover,
      ),
    );
  }

  TabBar _buildTabBar() {
    return TabBar(
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      onTap: _onTabChange,
      indicatorSize: TabBarIndicatorSize.label,
      tabs: yearList.map((e) => Tab(text: e.display)).toList(),
    );
  }

  void _onTabChange(int index) {
    final date = DateTime.now();
    final _season = yearList[index];
    currentSeasonIndex = _season.seasonType.index;
    currentYearIndex = _season.year;
    setImageUrl();
    if (mounted) setState(() {});
    logDal('Date-${DateTime.now().difference(date)}');
  }

  Future<List<BaseNode>> seasonalFuture(
    _Season e,
    CustomSearchInput input,
  ) async {
    SearchResult seasonalAnime = await _seasonSearchResult(e, input);
    return getSortedFilteredData(
      seasonalAnime.data ?? [],
      false,
      input.sortFilterDisplay,
      'anime',
    );
  }

  Future<SearchResult> _seasonSearchResult(
      _Season e, CustomSearchInput input) async {
    var list = getFieldsFromSortFilter(true, input.sortFilterDisplay, 'anime');
    final seasonalAnime = await MalApi.getSeasonalAnime(
      e.seasonType,
      e.year,
      fields: [MalApi.listDetailedFields, MalApi.userAnimeFields, ...list],
      offset: input.offset,
      limit: pageLimit,
      fromCache: input.fromCache,
    );
    return seasonalAnime;
  }

  Widget _buildStateFullSeason(_Season e) {
    if (_isGlobalFilter && _globalSortFilter == null)
      return loadingCenterColored;

    return UserContentBuilder(
      username: '@me',
      category: 'anime',
      pageSize: pageLimit,
      optionsCacheKey: 'Seasonal_Screen',
      customFuture: (input) => seasonalFuture(e, input),
      sortOption: _sortOption,
      sortFilterDisplay: _isGlobalFilter ? _globalSortFilter : null,
      disableOwnFilter: _isGlobalFilter,
      refreshKey:
          _isGlobalFilter ? _globalSortFilter.hashCode.toString() : null,
    );
  }
}
