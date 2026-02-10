import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nnez_yisu/services/app_log_service.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const _repoOwner = 'imbrby';
const _repoName = 'nnez-yisu';

enum UpdateDownloadChannel { mirror, github }

class AppReleaseInfo {
  const AppReleaseInfo({
    required this.tagName,
    required this.releasePageUrl,
    required this.apkUrl,
    required this.mirrorApkUrl,
    required this.fileName,
  });

  final String tagName;
  final String releasePageUrl;
  final String? apkUrl;
  final String? mirrorApkUrl;
  final String fileName;
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

class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  static const _apiLatestRelease =
      'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest';
  static const _prefAutoCheck = 'app_auto_check_update_enabled';
  static const _prefSkipTag = 'app_update_skip_tag';
  static const _prefPendingApkFiles = 'app_update_pending_apk_files';

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

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(_apiLatestRelease));
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
      String? apkUrl;
      String fileName = 'update.apk';
      for (final item in assets) {
        if (item is! Map) continue;
        final name = (item['name'] ?? '').toString();
        if (!name.toLowerCase().endsWith('.apk')) continue;
        final downloadUrl = (item['browser_download_url'] ?? '').toString();
        if (downloadUrl.isEmpty) continue;
        apkUrl = downloadUrl;
        fileName = name;
        break;
      }
      final mirrorApkUrl = apkUrl == null
          ? null
          : 'https://gh-proxy.org/$apkUrl';

      final release = AppReleaseInfo(
        tagName: tagName,
        releasePageUrl: htmlUrl,
        apkUrl: apkUrl,
        mirrorApkUrl: mirrorApkUrl,
        fileName: fileName,
      );
      return UpdateCheckResult(
        hasUpdate: true,
        currentVersionLabel: currentVersionLabel,
        latestVersionLabel: latestVersionLabel,
        message: '发现新版本: $latestVersionLabel',
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
                        context: context,
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
                        context: context,
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
    required BuildContext context,
    required AppReleaseInfo release,
    required UpdateDownloadChannel channel,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    void showMessage(String text) {
      messenger?.showSnackBar(SnackBar(content: Text(text)));
    }

    if (!Platform.isAndroid) {
      await _openReleasePage(release, channel);
      return;
    }

    final sourceUrl = channel == UpdateDownloadChannel.mirror
        ? release.mirrorApkUrl
        : release.apkUrl;

    if (sourceUrl == null || sourceUrl.isEmpty) {
      showMessage('未找到 APK 文件，已打开发布页');
      await _openReleasePage(release, channel);
      return;
    }

    final targetDir = await getTemporaryDirectory();
    final filePath = '${targetDir.path}/${release.fileName}';
    final file = File(filePath);

    showMessage('正在下载更新包...');
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(sourceUrl));
      request.headers.set('User-Agent', 'nnez-yisu');
      final response = await request.close().timeout(
        const Duration(minutes: 3),
      );
      if (response.statusCode != 200) {
        throw Exception('下载失败 (${response.statusCode})');
      }
      final sink = file.openWrite();
      await response.forEach(sink.add);
      await sink.close();

      final openResult = await OpenFilex.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );
      if (openResult.type != ResultType.done) {
        throw Exception('无法打开安装器: ${openResult.message}');
      }
      await _addPendingPackagePath(filePath);
      unawaited(_deletePackageWhenPossible(filePath));
      showMessage('已下载完成，正在打开安装器');
    } catch (error, stackTrace) {
      AppLogService.instance.error(
        'downloadAndInstall failed',
        tag: 'UPDATE',
        error: error,
        stackTrace: stackTrace,
      );
      showMessage('更新失败：${_toUserMessage(error)}');
    } finally {
      client.close(force: true);
    }
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

  Future<void> _deletePackageWhenPossible(String path) async {
    await Future<void>.delayed(const Duration(minutes: 2));
    final deleted = await _deletePackageFile(path);
    if (deleted) {
      await _removePendingPackagePath(path);
    }
  }

  Future<bool> _deletePackageFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return true;
      await file.delete();
      return true;
    } catch (_) {
      return false;
    }
  }
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
