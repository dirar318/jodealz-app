import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'local_db_service.dart';

/// Result type for profile sync operations.
enum ProfileSyncResult {
  /// Profile fetched and cached successfully.
  success,
  /// Token is invalid or expired — the user should be logged out.
  unauthorized,
  /// A transient error occurred (network, 5xx) — do NOT log the user out.
  transientError,
}

class CacheService {
  static final CacheService instance = CacheService._init();

  CacheService._init();

  static const String _dealsSyncKey = 'last_synced_deals_time';
  static const String _categoriesSyncKey = 'last_synced_categories_time';

  // Durations
  static const Duration dealsCacheDuration = Duration(hours: 2);
  static const Duration categoriesCacheDuration = Duration(hours: 24);

  final _db = LocalDbService.instance;

  /// Check if deals cache is expired or empty
  Future<bool> isDealsCacheExpired() async {
    final lastSyncedStr = await _db.getMetadata(_dealsSyncKey);
    if (lastSyncedStr == null) return true;
    final lastSynced = DateTime.tryParse(lastSyncedStr);
    if (lastSynced == null) return true;
    
    // Check count to make sure we actually have data
    final count = await _db.getDealsCount();
    if (count == 0) return true;

    return DateTime.now().difference(lastSynced) > dealsCacheDuration;
  }

  /// Check if categories cache is expired or empty
  Future<bool> isCategoriesCacheExpired() async {
    final lastSyncedStr = await _db.getMetadata(_categoriesSyncKey);
    if (lastSyncedStr == null) return true;
    final lastSynced = DateTime.tryParse(lastSyncedStr);
    if (lastSynced == null) return true;

    final categories = await _db.getCategories();
    if (categories.isEmpty) return true;

    return DateTime.now().difference(lastSynced) > categoriesCacheDuration;
  }

  /// Sync deals and categories from server using paginated sync API.
  /// Iterates over all pages until has_more is false.
  Future<void> syncDealsAndCategories(String baseUrl, {String? token}) async {
    try {
      debugPrint('CacheService: Starting paginated sync from server...');

      final headers = {
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        if (token != null && token.isNotEmpty) 'X-Auth-Token': token,
        'Accept': 'application/json',
      };

      final lastSyncedStr = await _db.getMetadata(_dealsSyncKey);
      String? sinceParam;
      if (lastSyncedStr != null) {
        final lastSynced = DateTime.tryParse(lastSyncedStr);
        if (lastSynced != null) {
          final sinceTime = lastSynced.subtract(const Duration(minutes: 5));
          sinceParam = sinceTime.toIso8601String().replaceAll('T', ' ').substring(0, 19);
        }
      }

      int page = 1;
      const int pageLimit = 50;
      bool hasMore = true;
      int totalSynced = 0;

      while (hasMore) {
        String url = '$baseUrl/api/v1/sync.php?page=$page&limit=$pageLimit';
        if (sinceParam != null) {
          url += '&since=${Uri.encodeComponent(sinceParam)}';
        }

        final response = await http.get(Uri.parse(url), headers: headers)
            .timeout(const Duration(seconds: 30));

        if (response.statusCode != 200) {
          debugPrint('CacheService: Sync page $page failed (HTTP ${response.statusCode})');
          break;
        }

        final data = json.decode(response.body);
        if (data['status'] != 'success') {
          debugPrint('CacheService: Sync API error: ${data['message']}');
          break;
        }

        // Save deals batch
        final deals = data['deals'] as List<dynamic>? ?? [];
        if (deals.isNotEmpty) {
          await _db.saveDeals(deals);
          totalSynced += deals.length;
        }

        // On first page, save lookup tables
        if (page == 1) {
          final categories = data['categories'] as List<dynamic>? ?? [];
          final List<Map<String, dynamic>> parsedCategories = categories.map((cat) {
            return {
              'id': int.tryParse(cat['id'].toString()) ?? 0,
              'name_en': cat['name_en']?.toString() ?? '',
              'name_ar': cat['name_ar']?.toString() ?? '',
              'icon': cat['icon']?.toString() ?? '',
            };
          }).toList();
          if (parsedCategories.isNotEmpty) {
            await _db.saveCategories(parsedCategories);
            await _db.saveMetadata(_categoriesSyncKey, DateTime.now().toIso8601String());
          }
        }

        hasMore = data['has_more'] == true;
        page++;

        debugPrint('CacheService: Synced page ${page - 1} — ${deals.length} deals | has_more: $hasMore');
      }

      await _db.saveMetadata(_dealsSyncKey, DateTime.now().toIso8601String());
      debugPrint('CacheService: Paginated sync complete — $totalSynced deals synced across ${page - 1} pages.');
    } catch (e) {
      debugPrint('CacheService: Error during paginated sync: $e');
    }
  }

  /// Sync user profile from server.
  /// Returns [ProfileSyncResult.success] on success,
  /// [ProfileSyncResult.unauthorized] on 401 (token invalid/expired → force logout),
  /// [ProfileSyncResult.transientError] on any other error (network issue, 5xx → do NOT logout).
  Future<ProfileSyncResult> syncUserProfile(String baseUrl, String token) async {
    try {
      debugPrint('CacheService: Syncing user profile...');
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/profile.php'),
        headers: {
          'Authorization': 'Bearer $token',
          'X-Auth-Token': token,
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && data['profile'] != null) {
          await _db.saveUserProfile(data['profile']);
          debugPrint('CacheService: User profile synced.');
          return ProfileSyncResult.success;
        }
        // 200 but unexpected body — don't treat as auth failure
        return ProfileSyncResult.transientError;
      } else if (response.statusCode == 401) {
        debugPrint('CacheService: Sync profile unauthorized (401) — token is invalid/expired.');
        return ProfileSyncResult.unauthorized;
      } else {
        // 5xx, 404, or other server-side issues — transient, don't logout
        debugPrint('CacheService: Sync profile failed with HTTP ${response.statusCode} — treating as transient error.');
        return ProfileSyncResult.transientError;
      }
    } catch (e) {
      // Network error, timeout, etc. — do NOT force logout
      debugPrint('CacheService: Error syncing user profile (transient): $e');
      return ProfileSyncResult.transientError;
    }
  }

  /// Get last sync duration text (e.g. "Synced 10 minutes ago")
  Future<String> getLastSyncedText(bool isArabic) async {
    final lastSyncedStr = await _db.getMetadata(_dealsSyncKey);
    if (lastSyncedStr == null) {
      return isArabic ? 'لم يتم المزامنة بعد' : 'Never synced';
    }
    final lastSynced = DateTime.tryParse(lastSyncedStr);
    if (lastSynced == null) {
      return isArabic ? 'لم يتم المزامنة بعد' : 'Never synced';
    }

    final diff = DateTime.now().difference(lastSynced);
    if (diff.inMinutes < 1) {
      return isArabic ? 'تمت المزامنة الآن' : 'Synced just now';
    } else if (diff.inMinutes < 60) {
      return isArabic 
          ? 'منذ ${diff.inMinutes} دقيقة' 
          : 'Synced ${diff.inMinutes} mins ago';
    } else {
      final hours = diff.inHours;
      return isArabic 
          ? 'منذ $hours ساعة' 
          : 'Synced $hours hours ago';
    }
  }
}
