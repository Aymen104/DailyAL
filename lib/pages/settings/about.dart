import 'package:dailyanimelist/api/dalapi.dart';
import 'package:dailyanimelist/constant.dart';
import 'package:dailyanimelist/generated/l10n.dart';
import 'package:dailyanimelist/pages/settings/customsettings.dart';
import 'package:dailyanimelist/pages/settings/optiontile.dart';
import 'package:dailyanimelist/util/download_manager.dart';
import 'package:dailyanimelist/widgets/custombutton.dart';
import 'package:dailyanimelist/widgets/customfuture.dart';
import 'package:dal_commons/commons.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:line_icons/line_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

String githubApiLink = 'https://api.github.com/repos/JICA98/DailyAL/releases';
String _githubHtmlLink = 'https://github.com/JICA98/DailyAL/releases';
String _malAgreement = 'https://myanimelist.net/static/apiagreement.html';

Future<String> getCurrentTag() async {
  final packageInfo = await PackageInfo.fromPlatform();
  return '${packageInfo.version}+${packageInfo.buildNumber}';
}

Future<List<GithubRelease>> getReleases() async {
  final response = await Dio().get(githubApiLink);
  final List<dynamic> list = response.data ?? [];
  return list.map((e) => GithubRelease.fromJson(e)).toList();
}

Future<GithubRelease> getLatestRelease() async {
  final response = await Dio().get('$githubApiLink/latest');
  final git = GithubRelease.fromJson(response.data ?? {});
  if (git.tagName == null) {
    throw Exception('Couldnt find release');
  }
  return git;
}

bool isUpdateAvailable(String currentTag, String latestTag) {
  try {
    return int.parse(latestTag.split("+")[1]) >
        int.parse(currentTag.split("+")[1]);
  } catch (e) {}
  return false;
}

Widget showUpdateAvailablePopup(
  GithubRelease git,
  BuildContext context,
  String tag,
) {
  final hasUpdate = isUpdateAvailable(tag, git.tagName ?? '');
  final changeLog = git.changeLog;

  if (!hasUpdate) {
    return AlertDialog(
      title: Text(S.current.No_new_updates),
      content: const SizedBox.shrink(),
      actions: [_closeButton(context)],
    );
  }

  return _UpdateDialog(release: git, changeLog: changeLog);
}

TextButton _closeButton(BuildContext context) {
  return TextButton(
    onPressed: () {
      Navigator.pop(context);
    },
    child: Text(S.current.Close),
  );
}

/// Stateful dialog that shows update info and handles download progress.
class _UpdateDialog extends StatefulWidget {
  final GithubRelease release;
  final String? changeLog;

  const _UpdateDialog({required this.release, this.changeLog});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  @override
  void initState() {
    super.initState();
    DownloadManager.instance.reset();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DownloadProgress>(
      valueListenable: DownloadManager.instance.progress,
      builder: (context, downloadProgress, _) {
        return AlertDialog(
          title: Text(S.current.Update_available),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(S.current.Whats_new,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                MarkdownBody(
                  data: widget.changeLog ?? '',
                  selectable: true,
                ),
              ],
            ),
          ),
          actions: _buildActions(context, downloadProgress),
        );
      },
    );
  }

  List<Widget> _buildActions(
      BuildContext context, DownloadProgress downloadProgress) {
    final isDownloading = downloadProgress.status == DownloadStatus.downloading;
    final isInstalling = downloadProgress.status == DownloadStatus.installing;
    final isBusy = isDownloading || isInstalling;
    final hasError = downloadProgress.status == DownloadStatus.failed;

    return [
      if ((downloadProgress.status != DownloadStatus.idle))
        SizedBox(
          width: double.maxFinite,
          child: _buildDownloadStatus(downloadProgress),
        ),
      if (hasError) const SizedBox(height: 10),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (isDownloading)
            TextButton(
              onPressed: () => DownloadManager.instance.cancel(),
              child: Text(S.current.Cancel),
            )
          else
            _closeButton(context),
          TextButton(
            onPressed: isBusy
                ? null
                : () => launchURLWithConfirmation(
                    '$_githubHtmlLink/tag/${widget.release.tagName}',
                    context: context),
            child: Text(S.current.Open),
          ),
          ShadowButton(
            onPressed: isBusy ? null : () => _startDownload(context),
            child: Text(S.current.Download_Install),
          ),
        ],
      )
    ];
  }

  Widget _buildDownloadStatus(DownloadProgress progress) {
    switch (progress.status) {
      case DownloadStatus.downloading:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              value: progress.progress == -1.0 ? null : progress.progress,
            ),
            const SizedBox(height: 8),
            Text(
              progress.progress == -1.0
                  ? S.current.Downloading_update
                  : '${S.current.Downloading_update} ${(progress.progress * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        );
      case DownloadStatus.completed:
        return Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 18),
            const SizedBox(width: 8),
            Text(S.current.Download_complete,
                style: const TextStyle(fontSize: 12)),
          ],
        );
      case DownloadStatus.installing:
        return Row(
          children: [
            const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Text(S.current.Installing_update,
                style: const TextStyle(fontSize: 12)),
          ],
        );
      case DownloadStatus.failed:
        return Row(
          children: [
            const Icon(Icons.error, color: Colors.red, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                progress.error ?? S.current.Download_failed,
                style: const TextStyle(fontSize: 12, color: Colors.red),
              ),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  void _startDownload(BuildContext context) async {
    logDal('User clicked Download & Install');
    logDal('Assets: ${widget.release.assets.map((e) => e.name).toList()}');
    final confirmed = await showConfirmationDialog(
      context: context,
      alertTitle: S.current.Update,
      desc: S.current.Update_consent,
    );
    logDal('Confirmation result: $confirmed');
    if (confirmed ?? false) {
      logDal('Starting download via manager');
      DownloadManager.instance.downloadAndInstall(widget.release, context);
    } else {
      logDal('User cancelled or dismissed dialog');
    }
  }
}

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String? _tag;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _postFirstFrame();
    });
  }

  void _postFirstFrame() async {
    _tag = await getCurrentTag();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingSliverScreen(
      titleString: S.current.About,
      children: _aboutTiles(context),
    );
  }

  List<Widget> _aboutTiles(BuildContext context) {
    return [
      OptionTile(
        text: S.current.Version,
        desc: _tag,
        iconData: Icons.info,
      ),
      OptionTile(
        text: S.current.ChangeLog,
        iconData: Icons.new_releases,
        onPressed: () => _onGetChangeLog(context),
      ),
      OptionTile(
        text: S.current.Check_for_updates,
        iconData: Icons.refresh,
        onPressed: () => _checkForUpdates(context),
      ),
      OptionTile(
        text: S.current.Manual_Install,
        iconData: Icons.system_update_alt,
        onPressed: () => _onManualInstall(context),
      ),
      OptionTile(
        text: S.current.MAL_API_Licence,
        desc: S.current.MAL_API_Licence_Desc,
        iconData: Icons.assignment_rounded,
        onPressed: () => _openMalAgreement(context),
      ),
      CFutureBuilder(
        future: DalApi.i.dalConfigFuture,
        done: (snap) {
          if (snap.data?.storeUrl == null) {
            return SB.z;
          }
          return OptionTile(
            text: S.current.Rate_Review,
            iconData: Icons.rate_review,
            desc: S.current.Rate_Review_desc,
            onPressed: () => launchURLWithConfirmation(
                snap.data?.storeUrl ?? '',
                context: context),
          );
        },
        loadingChild: SB.z,
      ),
      SB.h30,
      _buildSocialButtons(context),
      Row(
        children: [],
      )
    ].map((e) => SliverToBoxAdapter(child: e)).toList();
  }

  Widget _buildSocialButtons(BuildContext context) {
    return CFutureBuilder<Servers?>(
      future: DalApi.i.dalConfigFuture,
      done: (snapshot) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _socialButton(
              'https://github.com/JICA98/DailyAL',
              LineIcons.github,
              context,
            ),
            if (snapshot.data?.discordLink != null)
              _socialButton(
                snapshot.data?.discordLink ?? '',
                LineIcons.discord,
                context,
              ),
            if (snapshot.data?.telegramLink != null)
              _socialButton(
                snapshot.data?.telegramLink ?? '',
                LineIcons.telegram,
                context,
              ),
          ],
        );
      },
      loadingChild: SB.z,
    );
  }

  Widget _socialButton(
    String url,
    IconData icon,
    BuildContext context,
  ) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: ShadowButton(
        onPressed: () => launchURLWithConfirmation(url, context: context),
        child: Icon(icon),
      ),
    );
  }

  void _openMalAgreement(BuildContext context) {
    openFutureAndNavigate(
      text: S.current.Loading,
      future: Dio().get<String>(_malAgreement),
      isPopup: true,
      onData: (data) {
        return AlertDialog(
          content: SizedBox(
            height: 600,
            width: 400,
            child: SingleChildScrollView(child: HtmlW(data: data.data ?? '?')),
          ),
          actions: [
            _closeButton(context),
            TextButton(
              onPressed: () =>
                  launchURLWithConfirmation(_malAgreement, context: context),
              child: Text(S.current.Open),
            ),
          ],
        );
      },
      context: context,
    );
  }

  void _onManualInstall(BuildContext context) {
    openFutureAndNavigate(
      text: S.current.Loading,
      future: getReleases(),
      isPopup: true,
      onData: (releases) {
        final filtered = releases.where((r) {
          try {
            final tagName = r.tagName ?? '';
            final build = int.tryParse(tagName.split('+')[1]);
            return build != null && build > 106;
          } catch (e) {
            return false;
          }
        }).toList();

        return AlertDialog(
          title: Text(S.current.Manual_Install),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final release = filtered[index];
                return ListTile(
                  title: Text(release.tagName ?? '?'),
                  subtitle: Text(release.changeLog?.split('\n').first ?? ''),
                  onTap: () {
                    Navigator.pop(context);
                    showDialog(
                      context: context,
                      builder: (context) => _UpdateDialog(
                        release: release,
                        changeLog: release.changeLog,
                      ),
                    );
                  },
                );
              },
            ),
          ),
          actions: [_closeButton(context)],
        );
      },
      context: context,
      customError: S.current.Couldnt_find_release,
    );
  }

  void _checkForUpdates(BuildContext context) async {
    final storeUrl = (await DalApi.i.dalConfigFuture)?.storeUrl;
    if (storeUrl != null) {
      launchURLWithConfirmation(
        storeUrl,
        context: context,
      );
      return;
    }
    openFutureAndNavigate(
      text: S.current.Checking_for_updates,
      future: getLatestRelease(),
      isPopup: true,
      onData: (git) {
        return showUpdateAvailablePopup(git, context, _tag ?? '');
      },
      context: context,
      customError: S.current.Couldnt_find_release,
    );
  }

  void _onGetChangeLog(BuildContext context) {
    openFutureAndNavigate(
      text: '${S.current.Loading} ${S.current.ChangeLog}',
      future: Dio().get('$githubApiLink/tags/$_tag'),
      isPopup: true,
      onData: (data) {
        final response = GithubRelease.fromJson(data.data ?? {});
        return AlertDialog(
          title: Text(S.current.ChangeLog),
          content: SingleChildScrollView(
            child: Text(response.changeLog ?? ''),
          ),
          actions: [
            _closeButton(context),
          ],
        );
      },
      context: context,
      customError: S.current.Couldnt_find_release,
    );
  }
}

class ReleaseAsset {
  final String name;
  final String downloadUrl;

  ReleaseAsset({required this.name, required this.downloadUrl});

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) {
    return ReleaseAsset(
      name: json['name'] ?? '',
      downloadUrl: json['browser_download_url'] ?? '',
    );
  }
}

class GithubRelease {
  final String? changeLog;
  final String? tagName;
  final List<ReleaseAsset> assets;

  GithubRelease({
    this.changeLog,
    this.tagName,
    this.assets = const [],
  });

  GithubRelease.fromJson(Map<String, dynamic> json)
      : changeLog = json['body'],
        tagName = json['tag_name'],
        assets = (json['assets'] as List<dynamic>?)
                ?.map((a) => ReleaseAsset.fromJson(a as Map<String, dynamic>))
                .toList() ??
            [];
}
