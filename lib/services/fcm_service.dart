import 'dart:io';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:jodeals/firebase_options.dart';
import 'package:jodeals/services/auth_token_store.dart';
import 'package:jodeals/services/trusted_hosts.dart';

// Top-level function for handling background Firebase messages.
// Must be annotated with @pragma('vm:entry-point') for background execution isolates.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('FCM Background: Message handled successfully: ${message.messageId}');
  } catch (e) {
    debugPrint('FCM Background: Error handling message: $e');
  }
}

class FCMService {
  static String baseUrl = 'https://jodealz.online';
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static String? _fcmToken;
  static final ValueNotifier<String?> tokenNotifier = ValueNotifier<String?>(null);
  static Function(RemoteMessage message)? _onForegroundMessage;

  /// Must be called from main() before runApp.
  static void registerBackgroundHandler() {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  /// Shows the system notification prompt (Android 13+ / iOS). Call it when
  /// the user has context for it, e.g. right after onboarding.
  static Future<void> requestPermission() async {
    try {
      final NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('FCM: Notification permission: ${settings.authorizationStatus}');
    } catch (e) {
      debugPrint('FCM: Error requesting permission: $e');
    }
  }

  // Initialize notifications and return true if successful
  static Future<bool> initialize({
    required Function(String url) onNotificationClicked,
    Function(RemoteMessage message)? onForegroundMessage,
    bool requestPermission = true,
  }) async {
    try {
      _onForegroundMessage = onForegroundMessage;

      // 1. Request Notification Permissions (Android 13+ and iOS)
      if (requestPermission) {
        await FCMService.requestPermission();
      }

      // 2. Fetch and register device FCM Token
      _fcmToken = await _messaging.getToken();
      tokenNotifier.value = _fcmToken;

      // 3. Listen to token refresh
      _messaging.onTokenRefresh.listen((token) async {
        _fcmToken = token;
        tokenNotifier.value = token;
        await updateTokenOnBackend(token);
      });

      // 4. Handle Foreground Messages (does not show head-up banner by default unless customized)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('FCM: Foreground message received: ${message.notification?.title}');
        if (_onForegroundMessage != null) {
          _onForegroundMessage!(message);
        }
      });

      // 5. Handle Background Notification Click (App in background, opened by user tap)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('FCM: Background notification clicked!');
        handleMessagePayload(message, onNotificationClicked);
      });

      // 6. Handle Terminated Notification Click (App was closed, opened by user tap)
      RemoteMessage? initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('FCM: Terminated notification clicked!');
        handleMessagePayload(initialMessage, onNotificationClicked);
      }

      return true;
    } catch (e) {
      debugPrint('FCM: Error initializing notifications: $e');
      return false;
    }
  }

  // Retrieve current FCM registration token
  static String? get token => _fcmToken;

  // Sends the refreshed token to the PHP backend
  static Future<void> updateTokenOnBackend(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Update local cache
      await prefs.setString('last_registered_fcm_token', token);

      final deviceInfo = DeviceInfoPlugin();
      String deviceId = '';
      String deviceType = Platform.isAndroid ? 'Android' : (Platform.isIOS ? 'iOS' : 'Mobile');
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? 'UnknowniOSDevice';
      }

      final authToken = await AuthTokenStore.read();

      if (deviceId.isNotEmpty) {
        debugPrint('FCM: Dispatching refreshed token to backend for device: $deviceId');
        final response = await http.post(
          Uri.parse('$baseUrl/api/update-fcm-token.php'),
          headers: {
            'Content-Type': 'application/json',
            if (authToken != null && authToken.isNotEmpty) 'Authorization': 'Bearer $authToken',
            if (authToken != null && authToken.isNotEmpty) 'X-Auth-Token': authToken,
          },
          body: json.encode({
            'device_id': deviceId,
            'fcm_token': token,
            'device_type': deviceType,
            'platform': 'mobile',
          }),
        );
        debugPrint('FCM: Token update response status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('FCM: Error updating token on backend: $e');
    }
  }

  // Extract navigation payload and route to WebView. Only JO-Dealz URLs are
  // honoured; anything else falls back to the home page.
  static void handleMessagePayload(RemoteMessage message, Function(String url) callback) {
    final String? targetUrl = message.data['url'];
    callback(TrustedHosts.sanitize(targetUrl ?? baseUrl));
  }
}
