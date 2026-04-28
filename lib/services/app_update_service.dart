import 'dart:convert';
import 'dart:io';

import '../config/app_constants.dart';

HttpClient _defaultHttpClientFactory() => HttpClient();

class AppReleaseInfo {
  const AppReleaseInfo({
    required this.version,
    required this.apkUrl,
  });

  final String version;
  final String apkUrl;
}

class AppUpdateService {
  AppUpdateService({
    HttpClient Function()? httpClientFactory,
  }) : _httpClientFactory = httpClientFactory ?? _defaultHttpClientFactory;

  final HttpClient Function() _httpClientFactory;

  List<int> extractVersionParts(String raw) {
    final normalized = raw.trim().toLowerCase().replaceFirst(RegExp(r'^v'), '');
    final matches = RegExp(r'\d+')
        .allMatches(normalized)
        .map((match) => int.parse(match.group(0)!))
        .toList();
    return matches.isEmpty ? [0] : matches;
  }

  int compareVersions(String local, String remote) {
    final localParts = extractVersionParts(local);
    final remoteParts = extractVersionParts(remote);
    final maxLength =
        localParts.length > remoteParts.length ? localParts.length : remoteParts.length;

    for (var index = 0; index < maxLength; index++) {
      final left = index < localParts.length ? localParts[index] : 0;
      final right = index < remoteParts.length ? remoteParts[index] : 0;
      if (left != right) {
        return left < right ? -1 : 1;
      }
    }

    return 0;
  }

  Future<AppReleaseInfo> fetchLatestRelease({
    String fallbackApkUrl = defaultApkInstallUrl,
  }) async {
    HttpClient? client;
    try {
      client = _httpClientFactory();
      client.connectionTimeout = const Duration(seconds: 12);

      final request = await client
          .getUrl(
            Uri.parse(
              'https://api.github.com/repos/Simei007/Agenda-de-Trabalho/releases/latest',
            ),
          )
          .timeout(const Duration(seconds: 12));

      request.headers
          .set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      request.headers.set(HttpHeaders.userAgentHeader, 'agenda-trabalho-app');

      final response = await request.close().timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Falha HTTP ${response.statusCode}');
      }

      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 12));
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Resposta invalida do servidor');
      }

      final version = (decoded['tag_name'] ?? '').toString().trim();
      if (version.isEmpty) {
        throw const FormatException('Release sem tag');
      }

      var apkUrl = fallbackApkUrl;
      final assets = decoded['assets'];
      if (assets is List) {
        for (final asset in assets) {
          if (asset is! Map) continue;
          final name = (asset['name'] ?? '').toString().toLowerCase();
          final downloadUrl = (asset['browser_download_url'] ?? '').toString();
          if (downloadUrl.isEmpty) continue;
          if (name == 'app-release.apk' ||
              downloadUrl.toLowerCase().endsWith('/app-release.apk')) {
            apkUrl = downloadUrl;
            break;
          }
        }
      }

      return AppReleaseInfo(
        version: version,
        apkUrl: apkUrl,
      );
    } finally {
      client?.close(force: true);
    }
  }
}
