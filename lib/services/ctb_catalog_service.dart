import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_constants.dart';
import '../data/ctb_articles.dart';

HttpClient _defaultCtbClientFactory() => HttpClient();

class CtbCatalogLoadResult {
  const CtbCatalogLoadResult({
    required this.articles,
    required this.statusMessage,
  });

  final List<CtbArticle> articles;
  final String statusMessage;
}

class CtbCatalogService {
  CtbCatalogService({
    Future<SharedPreferences> Function()? preferencesProvider,
    HttpClient Function()? httpClientFactory,
  })  : _preferencesProvider =
            preferencesProvider ?? SharedPreferences.getInstance,
        _httpClientFactory = httpClientFactory ?? _defaultCtbClientFactory;

  static const String _cacheKey = 'agenda_trabalho_ctb_cache_v1';
  static const String _updatedAtKey = 'agenda_trabalho_ctb_cache_updated_at_v1';

  final Future<SharedPreferences> Function() _preferencesProvider;
  final HttpClient Function() _httpClientFactory;

  Future<CtbCatalogLoadResult> loadArticles() async {
    final prefs = await _preferencesProvider();
    final cachedRaw = prefs.getString(_cacheKey);
    final cachedArticles =
        cachedRaw == null || cachedRaw.isEmpty ? <CtbArticle>[] : decodeCtbArticles(cachedRaw);

    final activeArticles =
        cachedArticles.isNotEmpty ? cachedArticles : fallbackCtbArticles;
    final lastUpdated = DateTime.tryParse(prefs.getString(_updatedAtKey) ?? '');
    final shouldRefresh = lastUpdated == null ||
        DateTime.now().difference(lastUpdated) >= ctbRefreshInterval ||
        activeArticles.length < 300;

    if (!shouldRefresh) {
      return CtbCatalogLoadResult(
        articles: activeArticles,
        statusMessage:
            'Base local carregada com ${activeArticles.length} artigos.',
      );
    }

    HttpClient? client;
    try {
      client = _httpClientFactory();
      client.connectionTimeout = const Duration(seconds: 12);

      final request = await client
          .getUrl(Uri.parse(ctbOfficialUrl))
          .timeout(const Duration(seconds: 12));
      request.headers.set(HttpHeaders.userAgentHeader, 'agenda-trabalho-app');

      final response = await request.close().timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Falha HTTP ${response.statusCode}');
      }

      final html = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 12));
      final parsedArticles = parseCtbArticlesFromHtml(html);
      if (parsedArticles.length < 300) {
        throw const FormatException('Quantidade insuficiente de artigos');
      }

      await prefs.setString(_cacheKey, encodeCtbArticles(parsedArticles));
      await prefs.setString(_updatedAtKey, DateTime.now().toIso8601String());

      return CtbCatalogLoadResult(
        articles: parsedArticles,
        statusMessage:
            'Base oficial atualizada com ${parsedArticles.length} artigos.',
      );
    } catch (_) {
      final fallbackArticles =
          activeArticles.isNotEmpty ? activeArticles : fallbackCtbArticles;
      final message = fallbackArticles.length >= 300
          ? 'Sem internet no momento. Usando cache com ${fallbackArticles.length} artigos.'
          : 'Sem internet. Exibindo base reduzida do CTB.';

      return CtbCatalogLoadResult(
        articles: fallbackArticles,
        statusMessage: message,
      );
    } finally {
      client?.close(force: true);
    }
  }
}
