import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:jodeals/services/consent_service.dart';
import 'package:jodeals/services/fcm_service.dart';

/// Registers the device for push notifications and — only when the user has
/// opted in via [ConsentService] — sends usage analytics (screens, deal and
/// category views, load times, crashes, device/network details).
class AnonymousTrackingService {
  static const String _baseUrl = 'https://jodealz.online';

  static final AnonymousTrackingService _instance = AnonymousTrackingService._internal();
  factory AnonymousTrackingService() => _instance;
  AnonymousTrackingService._internal();

  String? _deviceUuid;
  bool _analyticsAllowed = false;
  // Promotional notifications are opt-in (App Store Guideline 4.5.4).
  Map<String, dynamic> _cachedPreferences = {
    'new_deals_enabled': 1,
    'discounts_enabled': 1,
    'category_updates_enabled': 1,
    'marketing_enabled': 0,
  };

  String get deviceUuid => _deviceUuid ?? 'unknown_device';

  // Initialize tracking
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _analyticsAllowed = await ConsentService.analyticsAllowed();

      // 1. Get or generate Device UUID
      _deviceUuid = prefs.getString('anonymous_device_uuid');
      if (_deviceUuid == null) {
        _deviceUuid = await _generateDeviceUuid();
        if (_deviceUuid != null) {
          await prefs.setString('anonymous_device_uuid', _deviceUuid!);
        }
      }

      // 2. Perform background registration & sync
      // Run asynchronously so we do not block app startup
      _syncDeviceData();
    } catch (e) {
      debugPrint('AnonymousTrackingService: Initialization error: $e');
    }
  }

  /// Call after the user changes their analytics choice.
  Future<void> onConsentChanged() async {
    _analyticsAllowed = await ConsentService.analyticsAllowed();
    if (_deviceUuid != null) _syncDeviceData();
  }

  // Generate unique device UUID based on hardware info or fallback to UUID
  Future<String> _generateDeviceUuid() async {
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor ?? DateTime.now().millisecondsSinceEpoch.toString();
      }
    } catch (e) {
      debugPrint('AnonymousTrackingService: Error getting device ID: $e');
    }
    return 'anon_${DateTime.now().millisecondsSinceEpoch}_${_getRandomString(8)}';
  }

  String _getRandomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rnd = DateTime.now().microsecondsSinceEpoch;
    return List.generate(length, (index) => chars[(rnd + index) % chars.length]).join();
  }

  // Startup sync: registers the device for push; adds device/network details
  // only with analytics consent. Location is never collected here.
  Future<void> _syncDeviceData() async {
    if (_deviceUuid == null) return;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final String? fcmToken = FCMService.token;
      final String platform = Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'unknown');

      final Map<String, dynamic> payload = {
        'device_id': _deviceUuid,
        'fcm_token': fcmToken,
        'platform': platform,
        'app_version': packageInfo.version,
        'language': Platform.localeName.split('_').first,
      };

      if (_analyticsAllowed) {
        final deviceInfo = DeviceInfoPlugin();
        if (Platform.isAndroid) {
          final androidInfo = await deviceInfo.androidInfo;
          payload['manufacturer'] = androidInfo.manufacturer;
          payload['device_model'] = androidInfo.model;
          payload['os_version'] = androidInfo.version.release;
        } else if (Platform.isIOS) {
          final iosInfo = await deviceInfo.iosInfo;
          payload['manufacturer'] = 'Apple';
          payload['device_model'] = iosInfo.utsname.machine;
          payload['os_version'] = iosInfo.systemVersion;
        }
        payload['timezone'] = DateTime.now().timeZoneName;
        try {
          final results = await Connectivity().checkConnectivity();
          payload['network_type'] = results.contains(ConnectivityResult.wifi)
              ? 'WiFi'
              : results.contains(ConnectivityResult.mobile)
                  ? 'Cellular'
                  : 'Unknown';
        } catch (_) {}
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/api/register-device.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      );

      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_registered_auth_token', 'GUEST');
        if (fcmToken != null) {
          await prefs.setString('last_registered_fcm_token', fcmToken);
        }
        // Sync preferences locally
        _fetchPreferencesFromServer();
      } else {
        debugPrint('AnonymousTrackingService: Sync failed with status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('AnonymousTrackingService: Sync exception: $e');
    }
  }

  String? _lastTrackedScreen;

  // Fetch notification preferences from server
  Future<void> _fetchPreferencesFromServer() async {
    if (_deviceUuid == null) return;
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/update-device-preferences.php?device_id=$_deviceUuid'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && data['preferences'] != null) {
          _cachedPreferences = Map<String, dynamic>.from(data['preferences']);
        }
      }
    } catch (e) {
      debugPrint('AnonymousTrackingService: Error fetching preferences: $e');
    }
  }

  // Get cached preferences
  Map<String, dynamic> getPreferences() {
    return _cachedPreferences;
  }

  // Update notification preferences on server
  Future<bool> updatePreferences({
    required bool newDeals,
    required bool discounts,
    required bool categoryUpdates,
    required bool marketing,
  }) async {
    if (_deviceUuid == null) return false;
    try {
      final payload = {
        'device_id': _deviceUuid,
        'new_deals_enabled': newDeals ? 1 : 0,
        'discounts_enabled': discounts ? 1 : 0,
        'category_updates_enabled': categoryUpdates ? 1 : 0,
        'marketing_enabled': marketing ? 1 : 0,
      };

      final response = await http.post(
        Uri.parse('$_baseUrl/api/update-device-preferences.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      );

      if (response.statusCode == 200) {
        _cachedPreferences = {
          'new_deals_enabled': newDeals ? 1 : 0,
          'discounts_enabled': discounts ? 1 : 0,
          'category_updates_enabled': categoryUpdates ? 1 : 0,
          'marketing_enabled': marketing ? 1 : 0,
        };
        debugPrint('AnonymousTrackingService: Preferences updated successfully.');
        return true;
      }
    } catch (e) {
      debugPrint('AnonymousTrackingService: Error updating preferences: $e');
    }
    return false;
  }

  // Update last visited screen
  Future<void> updateLastScreen(String screenName) async {
    if (_deviceUuid == null || !_analyticsAllowed) return;
    if (_lastTrackedScreen == screenName) return;
    _lastTrackedScreen = screenName;
    try {
      final payload = {
        'device_id': _deviceUuid,
        'last_screen': screenName,
      };

      http.post(
        Uri.parse('$_baseUrl/api/register-device.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      ).then((response) {
        if (response.statusCode != 200) {
          debugPrint('AnonymousTrackingService: Last screen update failed: ${response.statusCode}');
        }
      }).catchError((err) {
        debugPrint('AnonymousTrackingService: Last screen update error: $err');
      });
    } catch (e) {
      debugPrint('AnonymousTrackingService: Last screen update exception: $e');
    }
  }

  // Track page, category, or deal view behavior
  Future<void> trackBehavior({
    required String interestType, // 'view_category', 'view_deal', 'favorite_category'
    required String itemId,
  }) async {
    if (_deviceUuid == null || !_analyticsAllowed) return;
    try {
      final payload = {
        'device_id': _deviceUuid,
        'interest_type': interestType,
        'item_id': itemId,
      };

      // Send behavior asynchronously
      http.post(
        Uri.parse('$_baseUrl/api/track-device-behavior.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      ).then((response) {
        if (response.statusCode != 200) {
          debugPrint('AnonymousTrackingService: Behavior tracking failed: ${response.statusCode}');
        }
      }).catchError((err) {
        debugPrint('AnonymousTrackingService: Behavior tracking post error: $err');
      });
    } catch (e) {
      debugPrint('AnonymousTrackingService: Behavior tracking exception: $e');
    }
  }

  // Track app load performance
  Future<void> trackLoadTime(double seconds) async {
    if (_deviceUuid == null || !_analyticsAllowed) return;
    try {
      final payload = {
        'device_id': _deviceUuid,
        'load_time': seconds,
      };

      http.post(
        Uri.parse('$_baseUrl/api/track-device-performance.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      ).then((response) {
        if (response.statusCode != 200) {
          debugPrint('AnonymousTrackingService: Performance tracking failed: ${response.statusCode}');
        }
      }).catchError((err) {
        debugPrint('AnonymousTrackingService: Performance tracking error: $err');
      });
    } catch (e) {
      debugPrint('AnonymousTrackingService: Performance tracking exception: $e');
    }
  }

  // Track app crash
  Future<void> trackCrash() async {
    if (_deviceUuid == null || !_analyticsAllowed) return;
    try {
      final payload = {
        'device_id': _deviceUuid,
        'crash_occurred': true,
      };

      // Since the app might be unstable or closing, fire and ignore response
      await http.post(
        Uri.parse('$_baseUrl/api/track-device-performance.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 2));
    } catch (e) {
      // Fail silently on crash logging
    }
  }
}
