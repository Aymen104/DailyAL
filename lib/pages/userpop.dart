import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dailyanimelist/api/auth/auth.dart';
import 'package:dailyanimelist/constant.dart';
import 'package:dailyanimelist/generated/l10n.dart';
import 'package:dailyanimelist/main.dart';
import 'package:dailyanimelist/pages/settings/userprefsetting.dart';
import 'package:dailyanimelist/pages/settings_page.dart';
import 'package:dailyanimelist/pages/side_bar.dart';
import 'package:dailyanimelist/screens/user_profile.dart';
import 'package:dailyanimelist/user/user.dart';
import 'package:dailyanimelist/util/streamutils.dart';
import 'package:dailyanimelist/widgets/custombutton.dart';
import 'package:dailyanimelist/widgets/customfuture.dart';
import 'package:dailyanimelist/widgets/fadingeffect.dart';
import 'package:dailyanimelist/widgets/shimmecolor.dart';
import 'package:dailyanimelist/widgets/slivers.dart';
import 'package:dal_commons/commons.dart';
import 'package:flutter/material.dart';

class UserPopSlideOpenPage extends StatefulWidget {
  final UserProf? userProf;
  final VoidCallback? onUiChange;
  final String? username;
  const UserPopSlideOpenPage({
    super.key,
    this.userProf,
    this.onUiChange,
    this.username,
  });

  @override
  State<UserPopSlideOpenPage> createState() => _UserPopSlideOpenPageState();
}

class _UserPopSlideOpenPageState extends State<UserPopSlideOpenPage> {
  bool _isFullScreen = false;
  StreamListener<bool> _imageListener = StreamListener(false);
  UserProf? userProf;
  late String _bgImageRefKey;
  late PageController _pageController;
  late StreamListener<int> _pageListner;
  String category = 'anime';
  List<UserProfileType> get _profileHeaders => profileHeaders;
  DraggableScrollableController _draggableScrollableController =
      DraggableScrollableController();

  @override
  void initState() {
    userProf = widget.userProf;
    _bgImageRefKey = MalAuth.codeChallenge(10);
    _pageController = PageController(initialPage: 0);
    _pageListner = StreamListener(0);
    super.initState();
  }

  Future<String?> _getProfileImageUrlFuture(int? id) async {
    if (id == null) {
      return Future.value(null);
    } else {
      return UserProfService.i.getProfileBGDownloadUrl(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (notification) {
        final bool isSheetFullScreen = notification.extent >= 0.99;
        if (_isFullScreen != isSheetFullScreen) {
          setState(() {
            _isFullScreen = isSheetFullScreen;
          });
        }
        return true;
      },
      child: DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.5,
        maxChildSize: 1.0,
        expand: false,
        shouldCloseOnMinExtent: true,
        controller: _draggableScrollableController,
        builder: (BuildContext context, ScrollController scrollController) {
          final header =
              [_buildHeader(userProf, context)].map((e) => SliverWrapper(e));
          final body = _body(userProf?.name ?? '', scrollController);
          return Material(
            borderRadius: _isFullScreen
                ? BorderRadius.zero
                : BorderRadius.only(
                    topLeft: Radius.circular(32.0),
                    topRight: Radius.circular(32.0),
                  ),
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                if (userProf != null) ...header else ..._buildHeaderShimmer(),
                SB.lh10,
                SliverWrapper(_headerWidget()),
                SliverFillRemaining(
                  hasScrollBody: true,
                  child: body,
                )
              ],
            ),
          );
        },
      ),
    );
  }

  PreferredSizeWidget _headerWidget() {
    return profileHeaderWidget(
      pageController: _pageController,
      pageListner: _pageListner,
      profileHeaders: _profileHeaders,
    );
  }

  Widget _body(String username, ScrollController scrollController) {
    return PageView.builder(
      onPageChanged: (value) => _pageListner.update(value),
      controller: _pageController,
      itemCount: _profileHeaders.length,
      itemBuilder: (context, index) =>
          _profileHeaders[index].widget(username, true, scrollController),
    );
  }

  Widget _buildHeader(UserProf? userProf, BuildContext context) {
    return StateFullFutureWidget<String?>(
      refKey: _bgImageRefKey,
      future: () => _getProfileImageUrlFuture(userProf?.id),
      loadingChild: _buildHeaderWithImage(userProf, null),
      done: (snapshot) => _buildHeaderWithImage(userProf, snapshot.data),
    );
  }

  Widget _buildHeaderWithImage(UserProf? userProf, String? imageData) {
    return Stack(
      children: [
        if (imageData != null)
          SizedBox(
            height: 180.0,
            width: double.infinity,
            child: conditional(
              on: !_isFullScreen,
              parent: (child) => ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(32.0),
                  topRight: Radius.circular(32.0),
                ),
                child: child,
              ),
              child: CachedNetworkImage(
                imageUrl: imageData,
                fit: BoxFit.cover,
                placeholder: (context, url) => loadingCenterColored,
                errorWidget: (context, url, error) => Icon(Icons.error),
              ),
            ),
          ),
        if (imageData != null)
          SizedBox(
            height: 180.0,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _blackBGforText(0),
              ],
            ),
          ),
        SizedBox(
          height: 180.0,
          child: Builder(builder: (context) {
            return Center(
              child: Container(
                height: 100.0,
                width: 100.0,
                margin: const EdgeInsets.only(top: 60.0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).splashColor,
                    width: 4.0,
                  ),
                ),
                child: CircleAvatar(
                  backgroundImage: NetworkImage(userProf?.picture ?? ""),
                ),
              ),
            );
          }),
        ),
        _dragPill(imageData),
      ],
    );
  }

  Widget _blackBGforText(double borderRadius) {
    return SizedBox(
      height: 120,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: CustomPaint(
          foregroundPainter: FadingEffect(
            color: Colors.black,
            start: 5,
            end: 255,
          ),
          child: SB.z,
        ),
      ),
    );
  }

  List<Widget> _buildHeaderShimmer() {
    return [
      SB.h120,
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: ShimmerColor(Row(
            children: [
              Container(
                height: 35,
                width: 35,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: Colors.white),
              ),
              SB.w20,
              Text(S.current.Loading_Profile),
            ],
          ))),
      SB.h10,
      Divider(
        thickness: 1.0,
        color: Theme.of(context).cardColor,
      ),
    ].map((e) => SliverWrapper(e)).toList();
  }

  Widget _profileBgEditWidget(String? data) {
    if (user.status != AuthStatus.AUTHENTICATED) return SB.z;
    return StreamBuilder<bool>(
        initialData: _imageListener.initialData,
        stream: _imageListener.stream,
        builder: (context, sp) {
          final ongoingOperation = sp.data ?? false;
          if (ongoingOperation)
            return SizedBox(
              height: 35,
              width: 35,
              child: ShadowButton(
                onPressed: () {},
                child: loadingCenterColored,
                padding: EdgeInsets.zero,
              ),
            );
          return SizedBox(
            child: ShadowButton(
              child: iconAndText(
                  data == null ? Icons.edit : Icons.close,
                  data == null
                      ? S.current.Set_Profile_BG
                      : S.current.Remove_Profile_BG),
              onPressed: () {
                _imageListener.update(true);
                if (data == null)
                  _onSetBG();
                else {
                  _removeBG();
                }
              },
            ),
          );
        });
  }

  Widget _dragPill(String? data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SB.h10,
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: Icon(Icons.settings),
                onPressed: () {
                  gotoPage(
                      context: context,
                      newPage: SettingsPage(
                        onUiChange: () {
                          if (widget.onUiChange != null) widget.onUiChange!();
                        },
                      ));
                },
              ),
              if (!_isFullScreen)
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withValues(alpha: 0.5),
                          spreadRadius: 1,
                          blurRadius: 5,
                          offset: Offset(0, 3), // changes position of shadow
                        ),
                      ],
                    ),
                  ),
                )
              else
                _profileBgEditWidget(data),
              IconButton(
                icon: Icon(
                  Icons.close,
                  weight: 25.0,
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _removeBG() async {
    if (!(await showConfirmationDialog(
        context: context, alertTitle: S.current.Remove_the_Bg))) {
      _imageListener.update(false);
      return;
    }
    if (await _onRemoveBg()) {
      _bgImageRefKey = MalAuth.codeChallenge(10);
      showToast(S.current.Profile_bg_removed);
    } else {
      showToast(S.current.Error_removing_image);
    }
    if (mounted) setState(() {});
    _imageListener.update(false);
  }

  void _onSetBG() {
    setNewBg(
      (path) async {
        if (await _uploadFile(path)) {
          _bgImageRefKey = MalAuth.codeChallenge(10);
          showToast(S.current.Profile_bg_set);
        } else {
          showToast(S.current.Error_uploading_image);
        }
        if (mounted) setState(() {});
        _imageListener.update(false);
      },
      limitInBytes: 1024 * 1024 * 2.0,
      onError: () => _imageListener.update(false),
    );
  }

  Future<bool> _onRemoveBg() async {
    try {
      final userProf = await UserProfService.i.userProf;
      if (userProf == null) return false;
      final id = userProf.id;
      if (id == null) return false;
      await UserProfService.i.removeImage(id);
      return true;
    } catch (e) {
      logDal(e);
    }

    return false;
  }

  Future<bool> _uploadFile(String path) async {
    try {
      final userProf = await UserProfService.i.userProf;
      if (userProf == null) return false;
      final id = userProf.id;
      final name = userProf.name;
      if (id == null || name == null) return false;
      final bgFile = File(path);
      var uri = Uri.file(path);
      final map = {'jpeg': 'jpg', 'jpg': 'jpg', 'png': 'png', 'gif': 'gif'};
      final extension =
          map[uri.pathSegments.last.split(".").last.toLowerCase()];
      if (extension == null) {
        showToast(S.current.Invalid_extension);
        return false;
      }
      final bytes = await bgFile.readAsBytes();
      await UserProfService.i.saveImage(id, bytes, extension);
      return true;
    } catch (e) {
      logDal(e);
    }

    return false;
  }
}
