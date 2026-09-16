import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// A premium, performance-optimized ApiService utilizing native [HttpClient]
/// with support for in-memory caching, request deduplication, and automatic GZIP compression.
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  ApiService._internal();

  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);

  // In-memory cache store
  final Map<String, _CacheEntry> _cache = {};

  // Deduplication map to collapse identical concurrent requests into one future
  final Map<String, Future<String>> _activeRequests = {};

  /// Performs a cached, deduplicated GET request.
  /// [url] the target endpoint URL.
  /// [cacheDuration] optional custom cache lifetime. Defaults to 5 minutes if not provided.
  /// [forceRefresh] if true, bypasses cache checks.
  Future<String> get(
    String url, {
    Duration cacheDuration = const Duration(minutes: 5),
    bool forceRefresh = false,
    Map<String, String>? headers,
  }) async {
    final String cacheKey = _generateCacheKey(url, headers);

    if (!forceRefresh) {
      final cached = _cache[cacheKey];
      if (cached != null && !cached.isExpired) {
        debugPrint('ApiService: Cache HIT for key: $cacheKey');
        return cached.data;
      }
    }

    // Request Deduplication: If the request is already in-flight, return the existing future.
    if (_activeRequests.containsKey(cacheKey)) {
      debugPrint('ApiService: Deduplication HIT. Sharing future for: $cacheKey');
      return _activeRequests[cacheKey]!;
    }

    final Future<String> requestFuture = _executeRequest(url, headers, cacheKey, cacheDuration);
    _activeRequests[cacheKey] = requestFuture;

    try {
      final response = await requestFuture;
      return response;
    } finally {
      _activeRequests.remove(cacheKey);
    }
  }

  /// Clears the in-memory cache
  void clearCache() {
    _cache.clear();
    debugPrint('ApiService: Cache cleared');
  }

  String _generateCacheKey(String url, Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) return url;
    return '$url|${headers.hashCode}';
  }

  Future<String> _executeRequest(
    String url,
    Map<String, String>? headers,
    String cacheKey,
    Duration cacheDuration,
  ) async {
    try {
      final uri = Uri.parse(url);
      final request = await _client.getUrl(uri);

      // Explicitly request GZIP/Deflate compressed responses
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'gzip, deflate');
      if (headers != null) {
        headers.forEach((key, value) {
          request.headers.set(key, value);
        });
      }

      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Request failed with status code ${response.statusCode}',
          uri: uri,
        );
      }

      // Check if response is compressed. Dart HttpClient handles GZIP decompression automatically
      // if autoUncompress is true, but we double-check compression headers to verify compliance.
      final String encoding = response.headers.value(HttpHeaders.contentEncodingHeader) ?? '';
      debugPrint('ApiService: Response encoding for $url is: "$encoding"');

      final String responseBody = await response.transform(utf8.decoder).join();

      // Store response in cache
      _cache[cacheKey] = _CacheEntry(
        data: responseBody,
        expiry: DateTime.now().add(cacheDuration),
      );

      return responseBody;
    } catch (e) {
      debugPrint('ApiService: Network error for URL: $url - $e');
      rethrow;
    }
  }
}

class _CacheEntry {
  final String data;
  final DateTime expiry;

  _CacheEntry({required this.data, required this.expiry});

  bool get isExpired => DateTime.now().isAfter(expiry);
}
