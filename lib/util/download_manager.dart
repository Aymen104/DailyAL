import 'dart:io';

import 'package:dailyanimelist/constant.dart';
import 'package:dailyanimelist/generated/l10n.dart';
import 'package:dailyanimelist/pages/settings/about.dart';
import 'package:dal_commons/dal_commons.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

enum DownloadStatus { idle, downloading, completed, failed, installing }

class DownloadProgress {
  final DownloadStatus status;
  final double progress;
  final String? error;
  final String? filePath;

  const DownloadProgress({
    this.status = DownloadStatus.idle,
    this.progress = 0.0,
    this.error,
    this.filePath,
  });

  DownloadProgress copyWith({
    DownloadStatus? status,
    double? progress,
    String? error,
    String? filePath,
  }) {
    return DownloadProgress(
      status: status ?? this.status,
      progress: progress ??
          ((status == DownloadStatus.downloading && this.progress == -1.0)
              ? -1.0
              : this.progress),
      error: error ?? this.error,
      filePath: filePath ?? this.filePath,
    );
  }
}

class DownloadManager {
  static final DownloadManager instance = DownloadManager._();
  DownloadManager._();

  final ValueNotifier<DownloadProgress> progress =
      ValueNotifier(const DownloadProgress());

  CancelToken? _cancelToken;

  /// Returns the platform-specific asset download URL from a GitHub release.
  Future<String?> getAssetUrl(GithubRelease release) async {
    final assets = release.assets;
    logDal('getAssetUrl: checking ${assets.length} assets');
    if (assets.isEmpty) return null;

    if (Platform.isAndroid) {
      return await _getAndroidAssetUrl(assets, release.tagName ?? '');
    } else if (Platform.isLinux) {
      return _findAssetUrl(assets, 'DailyAL-x86_64.AppImage') ??
          _buildFallbackUrl(release.tagName, 'DailyAL-x86_64.AppImage');
    } else if (Platform.isWindows) {
      return _findAssetUrl(assets, 'DailyAL-Windows-x64.msix') ??
          _buildFallbackUrl(release.tagName, 'DailyAL-Windows-x64.msix');
    }
    return null;
  }

  Future<String?> _getAndroidAssetUrl(
      List<ReleaseAsset> assets, String tagName) async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final abis = androidInfo.supportedAbis;

      // Map Android ABI to the APK filename pattern
      const abiToApk = {
        'arm64-v8a': 'app-arm64-v8a-release.apk',
        'armeabi-v7a': 'app-armeabi-v7a-release.apk',
        'x86_64': 'app-x86_64-release.apk',
      };

      // Try each supported ABI in order of preference
      for (final abi in abis) {
        final apkName = abiToApk[abi];
        if (apkName != null) {
          final url = _findAssetUrl(assets, apkName);
          if (url != null) return url;
        }
      }
    } catch (e) {
      logDal('Failed to detect architecture: $e');
    }

    // Fallback to universal APK
    return _findAssetUrl(assets, 'app-release.apk') ??
        _buildFallbackUrl(tagName, 'app-release.apk');
  }

  String? _findAssetUrl(List<ReleaseAsset> assets, String name) {
    try {
      return assets.firstWhere((a) => a.name == name).downloadUrl;
    } catch (_) {
      return null;
    }
  }

  String _buildFallbackUrl(String? tagName, String assetName) {
    return 'https://github.com/JICA98/DailyAL/releases/download/$tagName/$assetName';
  }

  /// Download the update and trigger installation.
  Future<void> downloadAndInstall(
      GithubRelease release, BuildContext context) async {
    logDal('downloadAndInstall called for ${release.tagName}');
    final url = await getAssetUrl(release);
    logDal('Asset URL resolved: $url');
    if (url == null) {
      progress.value = DownloadProgress(
        status: DownloadStatus.failed,
        error: S.current.Download_failed,
      );
      return;
    }

    final fileName = url.split('/').last;
    logDal('File name: $fileName');

    try {
      // Get temp directory for download
      final dir = await _getDownloadDir();
      logDal('Download directory: ${dir.path}');
      final filePath = '${dir.path}/$fileName';

      // Clean up any previous download
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }

      _cancelToken = CancelToken();
      progress.value = DownloadProgress(
        status: DownloadStatus.downloading,
        progress: 0.0,
      );
      logDal('Starting Dio download...');

      await Dio().download(
        url,
        filePath,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (total <= 0) {
            progress.value = DownloadProgress(
              status: DownloadStatus.downloading,
              progress: -1.0, // Indeterminate
              filePath: filePath,
            );
          } else {
            progress.value = DownloadProgress(
              status: DownloadStatus.downloading,
              progress: received / total,
              filePath: filePath,
            );
          }
        },
      );

      logDal('Download complete. File at: $filePath');
      progress.value = DownloadProgress(
        status: DownloadStatus.completed,
        progress: 1.0,
        filePath: filePath,
      );

      // Trigger install
      await _installUpdate(filePath, context);
    } on DioException catch (e) {
      logDal('Dio error: $e');
      if (e.type == DioExceptionType.cancel) {
        progress.value = const DownloadProgress();
        return;
      }
      progress.value = DownloadProgress(
        status: DownloadStatus.failed,
        error: '${S.current.Download_failed}: ${e.message}',
      );
    } catch (e) {
      logDal('General error: $e');
      progress.value = DownloadProgress(
        status: DownloadStatus.failed,
        error: '${S.current.Download_failed}: $e',
      );
    }
  }

  Future<Directory> _getDownloadDir() async {
    if (Platform.isAndroid) {
      final extDir = await getExternalCacheDirectories();
      final dir = Directory('${extDir!.first.path}/updates');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    } else {
      final dir = await getTemporaryDirectory();
      final updateDir = Directory('${dir.path}/updates');
      if (!await updateDir.exists()) {
        await updateDir.create(recursive: true);
      }
      return updateDir;
    }
  }

  Future<void> _installUpdate(String filePath, BuildContext context) async {
    progress.value = DownloadProgress(
      status: DownloadStatus.installing,
      progress: 1.0,
      filePath: filePath,
    );

    if (Platform.isAndroid) {
      await _installAndroid(filePath);
    } else if (Platform.isLinux) {
      await _installLinux(filePath);
    } else if (Platform.isWindows) {
      await _installWindows(filePath);
    }
  }

  Future<void> _installAndroid(String filePath) async {
    // Check/request install permission on Android 8+
    if (await Permission.requestInstallPackages.status.isDenied) {
      final result = await Permission.requestInstallPackages.request();
      if (!result.isGranted) {
        progress.value = DownloadProgress(
          status: DownloadStatus.failed,
          error: '${S.current.Download_failed}: Install permission denied',
          filePath: filePath,
        );
        return;
      }
    } else if (await Permission
        .requestInstallPackages.status.isPermanentlyDenied) {
      progress.value = DownloadProgress(
        status: DownloadStatus.failed,
        error:
            '${S.current.Download_failed}: Install permission permanently denied. Please enable it in settings.',
        filePath: filePath,
      );
      await openAppSettings();
      return;
    }

    final result = await OpenFilex.open(filePath,
        type: 'application/vnd.android.package-archive');
    logDal('OpenFilex result: ${result.type}, message: ${result.message}');
    if (result.type != ResultType.done) {
      progress.value = DownloadProgress(
        status: DownloadStatus.failed,
        error:
            '${S.current.Download_failed}: ${result.message} (${result.type})',
        filePath: filePath,
      );
    }
  }

  Future<void> _installLinux(String filePath) async {
    // Make AppImage executable
    await Process.run('chmod', ['+x', filePath]);
    showToast('${S.current.Update_saved_to}: $filePath');
  }

  Future<void> _installWindows(String filePath) async {
    // Open the downloaded file (MSIX or folder)
    final result = await OpenFilex.open(filePath);
    if (result.type != ResultType.done) {
      showToast('${S.current.Update_saved_to}: $filePath');
    }
  }

  void cancel() {
    _cancelToken?.cancel();
    _cancelToken = null;
    progress.value = const DownloadProgress();
  }

  void reset() {
    _cancelToken = null;
    progress.value = const DownloadProgress();
  }
}
