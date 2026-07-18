import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nnez_yisu/services/app_log_service.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path_util;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const appUpdateRepository = String.fromEnvironment('APP_UPDATE_REPOSITORY');

String? get appUpdateRepositoryUrl {
  final repo = appUpdateRepository.trim();
  if (repo.isEmpty) return null;
  return 'https://github.com/$repo';
}

enum UpdateDownloadChannel { mirror, github }

enum UpdateDownloadPhase { idle, downloading, completed, failed }

class UpdateDownloadState {
  const UpdateDownloadState({
    this.phase = UpdateDownloadPhase.idle,
    this.fileName = '',
    this.receivedBytes = 0,
    this.totalBytes,
    this.message = '',
    this.savedLocation = '',
  });

  final UpdateDownloadPhase phase;
  final String fileName;
  final int receivedBytes;
  final int? totalBytes;
  final String message;
  final String savedLocation;

  double? get progress {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0, 1);
  }
}

class AppReleaseInfo {
  const AppReleaseInfo({
    required this.tagName,
    required this.releasePageUrl,
    required this.downloadUrl,
    required this.mirrorDownloadUrl,
    required this.fileName,
    required this.packagePlatform,
  });

  final String tagName;
  final String releasePageUrl;
  final String? downloadUrl;
  final String? mirrorDownloadUrl;
  final String fileName;
  final String packagePlatform;
}

class UpdateCheckResult {
  const UpdateCheckResult({
    required this.hasUpdate,
    required this.currentVersionLabel,
    required this.latestVersionLabel,
    required this.message,
    this.release,
  });

  final bool hasUpdate;
  final String currentVersionLabel;
  final String latestVersionLabel;
  final String message;
  final AppReleaseInfo? release;
}

class AppUpdateService extends ChangeNotifier {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  static const _prefAutoCheck = 'app_auto_check_update_enabled';
  static const _prefSkipTag = 'app_update_skip_tag';
  static const _prefPendingApkFiles = 'app_update_pending_apk_files';
  static const _downloadChannel = MethodChannel('com.brby.yisu/update');

  UpdateDownloadState _downloadState = const UpdateDownloadState();
  UpdateDownloadState get downloadState => _downloadState;

  HttpClient? _activeDownloadClient;
  AppReleaseInfo? _lastDownloadRelease;
  UpdateDownloadChannel? _lastDownloadChannel;
  String? _installerPath;
  List<String> _currentPackageCleanupRefs = const <String>[];
  bool _downloadRunning = false;
  bool _cancelRequested = false;
  Timer? _bannerDismissTimer;

  Future<void> cleanupPendingPackages() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = List<String>.from(
      prefs.getStringList(_prefPendingApkFiles) ?? const <String>[],
    );
    if (pending.isEmpty) return;
    final remain = <String>[];
    for (final path in pending) {
      final deleted = await _deletePackageFile(path);
      if (!deleted) remain.add(path);
    }
    if (remain.isEmpty) {
      await prefs.remove(_prefPendingApkFiles);
    } else {
      await prefs.setStringList(_prefPendingApkFiles, remain);
    }
  }

  Future<bool> isAutoCheckEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefAutoCheck) ?? false;
  }

  Future<void> setAutoCheckEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAutoCheck, enabled);
  }

  Future<void> setSkippedTag(String? tagName) async {
    final prefs = await SharedPreferences.getInstance();
    if (tagName == null || tagName.isEmpty) {
      await prefs.remove(_prefSkipTag);
      return;
    }
    await prefs.setString(_prefSkipTag, tagName);
  }

  Future<UpdateCheckResult> checkForUpdate({
    bool ignoreSkippedTag = false,
  }) async {
    final info = await PackageInfo.fromPlatform();
    final currentVersionRaw = '${info.version}+${info.buildNumber}';
    final currentVersion = _ParsedVersion.parse(currentVersionRaw);
    final currentVersionLabel = _versionLabel(info.version, info.buildNumber);
    final latestReleaseUri = _latestReleaseUri();
    if (latestReleaseUri == null) {
      return UpdateCheckResult(
        hasUpdate: false,
        currentVersionLabel: currentVersionLabel,
        latestVersionLabel: '',
        message: '未配置更新仓库',
      );
    }

    final client = HttpClient();
    try {
      final request = await client.getUrl(latestReleaseUri);
      request.headers.set('Accept', 'application/vnd.github.v3+json');
      request.headers.set('User-Agent', 'nnez-yisu');
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        return UpdateCheckResult(
          hasUpdate: false,
          currentVersionLabel: currentVersionLabel,
          latestVersionLabel: '',
          message: '检查失败 (${response.statusCode})',
        );
      }

      final data = jsonDecode(body) as Map<String, dynamic>;
      final tagName = (data['tag_name'] ?? '').toString().trim();
      if (tagName.isEmpty) {
        return UpdateCheckResult(
          hasUpdate: false,
          currentVersionLabel: currentVersionLabel,
          latestVersionLabel: '',
          message: '检查失败（无版本号）',
        );
      }

      final latestVersion = _ParsedVersion.parse(tagName);
      final latestVersionLabel = tagName.startsWith('v')
          ? tagName
          : 'v$tagName';

      final normalizedCurrent = _normalizeVersionLikeText(currentVersionRaw);
      final normalizedLatest = _normalizeVersionLikeText(tagName);
      if (normalizedCurrent.isNotEmpty &&
          normalizedCurrent == normalizedLatest) {
        return UpdateCheckResult(
          hasUpdate: false,
          currentVersionLabel: currentVersionLabel,
          latestVersionLabel: latestVersionLabel,
          message: '已是最新版本',
        );
      }

      if (latestVersion == null || currentVersion == null) {
        return UpdateCheckResult(
          hasUpdate: false,
          currentVersionLabel: currentVersionLabel,
          latestVersionLabel: latestVersionLabel,
          message: '检查失败（版本号格式不支持）',
        );
      }

      if (latestVersion.compareCoreTo(currentVersion) <= 0) {
        return UpdateCheckResult(
          hasUpdate: false,
          currentVersionLabel: currentVersionLabel,
          latestVersionLabel: latestVersionLabel,
          message: '已是最新版本',
        );
      }

      final prefs = await SharedPreferences.getInstance();
      final skippedTag = prefs.getString(_prefSkipTag);
      if (!ignoreSkippedTag && skippedTag != null && skippedTag == tagName) {
        return UpdateCheckResult(
          hasUpdate: false,
          currentVersionLabel: currentVersionLabel,
          latestVersionLabel: latestVersionLabel,
          message: '已跳过该版本',
        );
      }

      final htmlUrl = (data['html_url'] ?? '').toString();
      final assets = (data['assets'] is List)
          ? (data['assets'] as List)
          : const <dynamic>[];
      final selectedAsset = _selectAssetForCurrentPlatform(assets);
      final downloadUrl = selectedAsset?.downloadUrl;
      final fileName = selectedAsset?.fileName ?? '';
      final mirrorDownloadUrl = downloadUrl == null
          ? null
          : 'https://gh-proxy.org/$downloadUrl';

      final release = AppReleaseInfo(
        tagName: tagName,
        releasePageUrl: htmlUrl,
        downloadUrl: downloadUrl,
        mirrorDownloadUrl: mirrorDownloadUrl,
        fileName: fileName,
        packagePlatform: selectedAsset?.platformLabel ?? _platformLabel(),
      );
      return UpdateCheckResult(
        hasUpdate: true,
        currentVersionLabel: currentVersionLabel,
        latestVersionLabel: latestVersionLabel,
        message: selectedAsset == null
            ? '发现新版本: $latestVersionLabel（当前平台无安装包）'
            : '发现新版本: $latestVersionLabel',
        release: release,
      );
    } catch (error, stackTrace) {
      AppLogService.instance.error(
        'checkForUpdate failed',
        tag: 'UPDATE',
        error: error,
        stackTrace: stackTrace,
      );
      return UpdateCheckResult(
        hasUpdate: false,
        currentVersionLabel: currentVersionLabel,
        latestVersionLabel: '',
        message: '检查失败',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<void> showUpdateDialog(
    BuildContext context,
    UpdateCheckResult result,
  ) async {
    final release = result.release;
    if (release == null) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('发现新版本'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '最新版本: ${result.latestVersionLabel}\n'
              '当前版本: ${result.currentVersionLabel}',
            ),
            if (release.downloadUrl == null) ...[
              const SizedBox(height: 8),
              Text('当前设备（${release.packagePlatform}）暂无独立安装包，将跳转发布页下载。'),
            ],
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () async {
                await setSkippedTag(release.tagName);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('跳过本次更新'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      if (ctx.mounted) Navigator.pop(ctx);
                      await downloadAndInstall(
                        release: release,
                        channel: UpdateDownloadChannel.mirror,
                      );
                    },
                    child: const Text('镜像更新'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () async {
                      if (ctx.mounted) Navigator.pop(ctx);
                      await downloadAndInstall(
                        release: release,
                        channel: UpdateDownloadChannel.github,
                      );
                    },
                    child: const Text('GitHub'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> downloadAndInstall({
    required AppReleaseInfo release,
    required UpdateDownloadChannel channel,
  }) async {
    if (_downloadRunning) return;

    final sourceUrl = channel == UpdateDownloadChannel.mirror
        ? release.mirrorDownloadUrl
        : release.downloadUrl;

    if (sourceUrl == null || sourceUrl.isEmpty) {
      _setDownloadState(
        UpdateDownloadState(
          phase: UpdateDownloadPhase.failed,
          fileName: release.fileName,
          message: '当前平台没有可直接下载的安装包，请前往发布页。',
        ),
      );
      await _openReleasePage(release, channel);
      return;
    }

    final fileName = _safeFileName(
      release.fileName.isEmpty
          ? _defaultFileNameForCurrentPlatform()
          : release.fileName,
    );
    await _cleanupCurrentPackage();
    _lastDownloadRelease = release;
    _lastDownloadChannel = channel;
    _downloadRunning = true;
    _cancelRequested = false;
    _installerPath = null;
    File? partialFile;
    IOSink? sink;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    _activeDownloadClient = client;
    _setDownloadState(
      UpdateDownloadState(
        phase: UpdateDownloadPhase.downloading,
        fileName: fileName,
        message: channel == UpdateDownloadChannel.mirror
            ? '正在通过镜像下载'
            : '正在从 GitHub 下载',
      ),
    );

    try {
      final request = await client.getUrl(Uri.parse(sourceUrl));
      request.headers.set('User-Agent', 'nnez-yisu');
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != 200) {
        throw Exception('下载失败 (${response.statusCode})');
      }
      final totalBytes = response.contentLength > 0
          ? response.contentLength
          : null;
      partialFile = await _createPartialDownloadFile(fileName);
      sink = partialFile.openWrite();
      var receivedBytes = 0;
      var lastReportedAt = DateTime.fromMillisecondsSinceEpoch(0);
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        if (_cancelRequested) throw const _DownloadCancelled();
        sink.add(chunk);
        receivedBytes += chunk.length;
        final now = DateTime.now();
        if (now.difference(lastReportedAt) >=
                const Duration(milliseconds: 120) ||
            receivedBytes == totalBytes) {
          lastReportedAt = now;
          _setDownloadState(
            UpdateDownloadState(
              phase: UpdateDownloadPhase.downloading,
              fileName: fileName,
              receivedBytes: receivedBytes,
              totalBytes: totalBytes,
              message: channel == UpdateDownloadChannel.mirror
                  ? '正在通过镜像下载'
                  : '正在从 GitHub 下载',
            ),
          );
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;

      final finalized = await _finalizeDownload(
        partialFile: partialFile,
        fileName: fileName,
      );

      if (Platform.isAndroid) {
        _installerPath = partialFile.path;
      } else {
        _installerPath = finalized.installerPath;
      }
      _currentPackageCleanupRefs = <String>{
        partialFile.path,
        finalized.cleanupReference,
      }.where((value) => value.isNotEmpty).toList();
      for (final reference in _currentPackageCleanupRefs) {
        await _addPendingPackagePath(reference);
      }

      _setDownloadState(
        UpdateDownloadState(
          phase: UpdateDownloadPhase.completed,
          fileName: fileName,
          receivedBytes: receivedBytes,
          totalBytes: totalBytes ?? receivedBytes,
          message: '下载完成，可以安装新版本',
          savedLocation: Platform.isAndroid
              ? finalized.displayLocation
              : _displayDownloadLocation(finalized.displayLocation),
        ),
      );
    } on _DownloadCancelled {
      await _deleteIfExists(partialFile);
      _setDownloadState(const UpdateDownloadState());
    } catch (error, stackTrace) {
      await _deleteIfExists(partialFile);
      AppLogService.instance.error(
        'downloadAndInstall failed',
        tag: 'UPDATE',
        error: error,
        stackTrace: stackTrace,
      );
      if (_cancelRequested) {
        _setDownloadState(const UpdateDownloadState());
      } else {
        _setDownloadState(
          UpdateDownloadState(
            phase: UpdateDownloadPhase.failed,
            fileName: fileName,
            message: _toUserMessage(error),
          ),
        );
      }
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client.close(force: true);
      _activeDownloadClient = null;
      _downloadRunning = false;
    }
  }

  Future<void> retryDownload() async {
    final release = _lastDownloadRelease;
    final channel = _lastDownloadChannel;
    if (release == null || channel == null || _downloadRunning) return;
    await downloadAndInstall(release: release, channel: channel);
  }

  void cancelDownload() {
    if (!_downloadRunning) return;
    _cancelRequested = true;
    _activeDownloadClient?.close(force: true);
  }

  void dismissDownloadBanner() {
    if (_downloadRunning) return;
    _bannerDismissTimer?.cancel();
    _setDownloadState(const UpdateDownloadState());
  }

  Future<void> installDownloadedPackage() async {
    final installerPath = _installerPath;
    if (installerPath == null || installerPath.isEmpty) {
      _setDownloadState(
        UpdateDownloadState(
          phase: UpdateDownloadPhase.failed,
          fileName: _downloadState.fileName,
          message: '安装包已不存在，请重新下载。',
        ),
      );
      return;
    }
    final file = File(installerPath);
    if (!await file.exists()) {
      _installerPath = null;
      _setDownloadState(
        UpdateDownloadState(
          phase: UpdateDownloadPhase.failed,
          fileName: _downloadState.fileName,
          message: '安装包已不存在，请重新下载。',
        ),
      );
      return;
    }

    final openResult = Platform.isAndroid
        ? await OpenFilex.open(
            installerPath,
            type: 'application/vnd.android.package-archive',
          )
        : await OpenFilex.open(installerPath);
    if (openResult.type != ResultType.done) {
      _setDownloadState(
        UpdateDownloadState(
          phase: UpdateDownloadPhase.completed,
          fileName: _downloadState.fileName,
          receivedBytes: _downloadState.receivedBytes,
          totalBytes: _downloadState.totalBytes,
          savedLocation: _downloadState.savedLocation,
          message: '无法打开安装程序：${openResult.message}',
        ),
      );
      return;
    }
    unawaited(
      _deletePackagesWhenPossible(
        List<String>.from(_currentPackageCleanupRefs),
      ),
    );
  }

  void _setDownloadState(UpdateDownloadState state) {
    _bannerDismissTimer?.cancel();
    _downloadState = state;
    notifyListeners();
    final delay = switch (state.phase) {
      UpdateDownloadPhase.completed => const Duration(seconds: 15),
      UpdateDownloadPhase.failed => const Duration(seconds: 10),
      _ => null,
    };
    if (delay != null) {
      _bannerDismissTimer = Timer(delay, () {
        if (!_downloadRunning && _downloadState.phase == state.phase) {
          _downloadState = const UpdateDownloadState();
          notifyListeners();
        }
      });
    }
  }

  Future<void> _cleanupCurrentPackage() async {
    for (final reference in _currentPackageCleanupRefs) {
      if (await _deletePackageFile(reference)) {
        await _removePendingPackagePath(reference);
      }
    }
    _currentPackageCleanupRefs = const <String>[];
    _installerPath = null;
  }

  Future<void> _openReleasePage(
    AppReleaseInfo release,
    UpdateDownloadChannel channel,
  ) async {
    final targetUrl = channel == UpdateDownloadChannel.mirror
        ? 'https://gh-proxy.org/${release.releasePageUrl}'
        : release.releasePageUrl;
    final uri = Uri.tryParse(targetUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<File> _createPartialDownloadFile(String fileName) async {
    final Directory directory;
    if (Platform.isAndroid || Platform.isIOS) {
      directory = await getTemporaryDirectory();
    } else {
      directory = await _resolveDesktopDownloadDirectory();
    }
    await directory.create(recursive: true);
    final file = File(path_util.join(directory.path, '.$fileName.download'));
    await _deleteIfExists(file);
    return file;
  }

  Future<_FinalizedDownload> _finalizeDownload({
    required File partialFile,
    required String fileName,
  }) async {
    if (Platform.isAndroid) {
      final raw = await _downloadChannel.invokeMapMethod<String, dynamic>(
        'saveToDownloads',
        <String, dynamic>{
          'sourcePath': partialFile.path,
          'fileName': fileName,
          'mimeType': 'application/vnd.android.package-archive',
        },
      );
      final location = raw?['location']?.toString() ?? 'Download/$fileName';
      final cleanupReference =
          raw?['uri']?.toString() ?? raw?['path']?.toString() ?? '';
      if (cleanupReference.isEmpty) {
        throw Exception('安装包已下载，但无法确认 Download 保存位置。');
      }
      return _FinalizedDownload(
        installerPath: partialFile.path,
        displayLocation: location,
        cleanupReference: cleanupReference,
      );
    }

    final downloadDirectory = await _resolveDesktopDownloadDirectory();
    final targetFile = File(path_util.join(downloadDirectory.path, fileName));
    await _deleteIfExists(targetFile);
    final savedFile = await partialFile.rename(targetFile.path);
    return _FinalizedDownload(
      installerPath: savedFile.path,
      displayLocation: savedFile.path,
      cleanupReference: savedFile.path,
    );
  }

  Future<Directory> _resolveDesktopDownloadDirectory() async {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return downloads;
    return getApplicationSupportDirectory();
  }

  static String _safeFileName(String raw) {
    final name = path_util.basename(raw.trim());
    return name.isEmpty ? _defaultFileNameForCurrentPlatform() : name;
  }

  static String _displayDownloadLocation(String path) {
    if (path.isEmpty) return '';
    final fileName = path_util.basename(path);
    return fileName.isEmpty ? path : 'Download/$fileName';
  }

  static Future<void> _deleteIfExists(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static String _defaultFileNameForCurrentPlatform() {
    if (Platform.isAndroid) return 'update.apk';
    if (Platform.isWindows) return 'yisu-windows.zip';
    if (Platform.isMacOS) return 'yisu-macos.zip';
    if (Platform.isLinux) return 'yisu-linux.zip';
    return 'update.bin';
  }

  static _ReleaseAsset? _selectAssetForCurrentPlatform(List<dynamic> assets) {
    if (Platform.isAndroid) {
      return _pickAssetByExtensions(assets, const <String>['.apk'], 'Android');
    }
    if (Platform.isWindows) {
      return _pickAssetByExtensions(assets, const <String>[
        '.zip',
        '.exe',
        '.msix',
      ], 'Windows');
    }
    if (Platform.isMacOS) {
      return _pickAssetByExtensions(assets, const <String>[
        '.dmg',
        '.pkg',
        '.zip',
      ], 'macOS');
    }
    if (Platform.isLinux) {
      return _pickAssetByExtensions(assets, const <String>[
        '.AppImage',
        '.deb',
        '.rpm',
        '.tar.gz',
        '.zip',
      ], 'Linux');
    }
    return null;
  }

  static _ReleaseAsset? _pickAssetByExtensions(
    List<dynamic> assets,
    List<String> extensions,
    String platformLabel,
  ) {
    for (final item in assets) {
      if (item is! Map) continue;
      final name = (item['name'] ?? '').toString();
      final lowerName = name.toLowerCase();
      final matched = extensions.any(
        (extension) => lowerName.endsWith(extension.toLowerCase()),
      );
      if (!matched) continue;
      final url = (item['browser_download_url'] ?? '').toString();
      if (url.isEmpty) continue;
      return _ReleaseAsset(
        fileName: name,
        downloadUrl: url,
        platformLabel: platformLabel,
      );
    }
    return null;
  }

  static String _platformLabel() {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isIOS) return 'iOS';
    return '当前平台';
  }

  static Uri? _latestReleaseUri() {
    final repo = appUpdateRepository.trim();
    if (repo.isEmpty || !repo.contains('/')) return null;
    return Uri.https('api.github.com', '/repos/$repo/releases/latest');
  }

  static String _versionLabel(String version, String buildNumber) {
    if (buildNumber.isEmpty) return 'v$version';
    return 'v$version+$buildNumber';
  }

  static String _toUserMessage(Object error) {
    final raw = error.toString();
    return raw.replaceFirst(RegExp(r'^Exception:\s*'), '');
  }

  static String _normalizeVersionLikeText(String raw) {
    var value = raw.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      value = value.substring(1);
    }
    final match = RegExp(r'(\d+\.\d+\.\d+(?:\+\d+)?)').firstMatch(value);
    if (match != null) return match.group(1)!;
    return value;
  }

  Future<void> _addPendingPackagePath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = List<String>.from(
      prefs.getStringList(_prefPendingApkFiles) ?? const <String>[],
    );
    if (!pending.contains(path)) {
      pending.add(path);
      await prefs.setStringList(_prefPendingApkFiles, pending);
    }
  }

  Future<void> _removePendingPackagePath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = List<String>.from(
      prefs.getStringList(_prefPendingApkFiles) ?? const <String>[],
    );
    pending.remove(path);
    if (pending.isEmpty) {
      await prefs.remove(_prefPendingApkFiles);
    } else {
      await prefs.setStringList(_prefPendingApkFiles, pending);
    }
  }

  Future<void> _deletePackagesWhenPossible(List<String> references) async {
    await Future<void>.delayed(const Duration(minutes: 2));
    for (final reference in references) {
      final deleted = await _deletePackageFile(reference);
      if (deleted) {
        await _removePendingPackagePath(reference);
      }
    }
  }

  Future<bool> _deletePackageFile(String path) async {
    try {
      if (Platform.isAndroid && path.startsWith('content://')) {
        return await _downloadChannel.invokeMethod<bool>(
              'deleteDownload',
              <String, dynamic>{'uri': path},
            ) ??
            false;
      }
      final file = File(path);
      if (!await file.exists()) return true;
      await file.delete();
      return true;
    } catch (_) {
      return false;
    }
  }
}

class UpdateDownloadBanner extends StatelessWidget {
  const UpdateDownloadBanner({
    super.key,
    required this.service,
    this.applySafeArea = true,
  });

  final AppUpdateService service;
  final bool applySafeArea;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final state = service.downloadState;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.12),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: state.phase == UpdateDownloadPhase.idle
              ? const SizedBox.shrink(key: ValueKey('update-idle'))
              : _buildBanner(context, state),
        );
      },
    );
  }

  Widget _buildBanner(BuildContext context, UpdateDownloadState state) {
    final banner = Align(
      key: ValueKey(state.phase),
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: _UpdateDownloadBannerCard(state: state, service: service),
      ),
    );
    if (!applySafeArea) return banner;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: banner,
    );
  }
}

class _UpdateDownloadBannerCard extends StatelessWidget {
  const _UpdateDownloadBannerCard({required this.state, required this.service});

  final UpdateDownloadState state;
  final AppUpdateService service;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDownloading = state.phase == UpdateDownloadPhase.downloading;
    final isCompleted = state.phase == UpdateDownloadPhase.completed;
    final icon = isDownloading
        ? Icons.downloading_rounded
        : isCompleted
        ? Icons.inventory_2_outlined
        : Icons.cloud_off_outlined;
    final title = isDownloading
        ? '正在下载 ${state.fileName}'
        : isCompleted
        ? '安装包已就绪'
        : '下载没有完成';

    return Semantics(
      liveRegion: true,
      label: '$title，${state.message}',
      child: Material(
        elevation: 8,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.18),
        color: const Color(0xFFFFFCF5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.2)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isCompleted
                      ? const Color(0xFFE2F0E9)
                      : const Color(0xFFF3E8C8),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: isCompleted
                      ? colorScheme.primary
                      : const Color(0xFF8A651A),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      state.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (isDownloading) ...[
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: state.progress,
                        minHeight: 5,
                        borderRadius: BorderRadius.circular(99),
                        backgroundColor: const Color(0xFFE8E2D5),
                        color: colorScheme.primary,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _progressLabel(state),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (isCompleted && state.savedLocation.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        '已保存到 ${state.savedLocation}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isDownloading)
                TextButton(
                  onPressed: service.cancelDownload,
                  child: const Text('取消'),
                )
              else ...[
                if (isCompleted)
                  FilledButton.icon(
                    onPressed: service.installDownloadedPackage,
                    icon: const Icon(Icons.install_mobile_outlined, size: 18),
                    label: const Text('安装'),
                  )
                else
                  TextButton.icon(
                    onPressed: service.retryDownload,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('重试'),
                  ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: service.dismissDownloadBanner,
                  icon: const Icon(Icons.close),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _progressLabel(UpdateDownloadState state) {
    final received = _formatBytes(state.receivedBytes);
    final total = state.totalBytes;
    if (total == null || total <= 0) return '已下载 $received';
    final percent = ((state.progress ?? 0) * 100).round();
    return '$received / ${_formatBytes(total)} · $percent%';
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class _FinalizedDownload {
  const _FinalizedDownload({
    required this.installerPath,
    required this.displayLocation,
    required this.cleanupReference,
  });

  final String installerPath;
  final String displayLocation;
  final String cleanupReference;
}

class _DownloadCancelled implements Exception {
  const _DownloadCancelled();
}

class _ReleaseAsset {
  const _ReleaseAsset({
    required this.fileName,
    required this.downloadUrl,
    required this.platformLabel,
  });

  final String fileName;
  final String downloadUrl;
  final String platformLabel;
}

class _ParsedVersion implements Comparable<_ParsedVersion> {
  const _ParsedVersion({
    required this.major,
    required this.minor,
    required this.patch,
    required this.build,
  });

  final int major;
  final int minor;
  final int patch;
  final int build;

  static _ParsedVersion? parse(String raw) {
    var normalized = raw.trim();
    if (normalized.startsWith('v') || normalized.startsWith('V')) {
      normalized = normalized.substring(1);
    }

    final plusIndex = normalized.indexOf('+');
    final versionPart = plusIndex >= 0
        ? normalized.substring(0, plusIndex)
        : normalized;
    final buildPart = plusIndex >= 0 ? normalized.substring(plusIndex + 1) : '';

    final versionNumbers = RegExp(r'\d+')
        .allMatches(versionPart)
        .map((m) => int.tryParse(m.group(0) ?? '') ?? 0)
        .toList();
    final major = versionNumbers.isNotEmpty ? versionNumbers[0] : 0;
    final minor = versionNumbers.length > 1 ? versionNumbers[1] : 0;
    final patch = versionNumbers.length > 2 ? versionNumbers[2] : 0;
    if (versionNumbers.length < 3) return null;

    final buildMatch = RegExp(r'\d+').firstMatch(buildPart);
    final build = buildMatch == null
        ? (versionNumbers.length > 3 ? versionNumbers[3] : 0)
        : (int.tryParse(buildMatch.group(0) ?? '') ?? 0);

    return _ParsedVersion(
      major: major,
      minor: minor,
      patch: patch,
      build: build,
    );
  }

  @override
  int compareTo(_ParsedVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    return build.compareTo(other.build);
  }

  int compareCoreTo(_ParsedVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }
}
