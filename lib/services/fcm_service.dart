import 'dart:io';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:jodeals/firebase_options.dart';

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

  // Initialize notifications and return true if successful
  static Future<bool> initialize({
    required Function(String url) onNotificationClicked,
    Function(RemoteMessage message)? onForegroundMessage,
  }) async {
    try {
      _onForegroundMessage = onForegroundMessage;

      // Register background handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // 1. Request Notification Permissions (Android 13+ and iOS)
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('FCM: User denied notification permissions');
      } else {
        debugPrint('FCM: Notification permissions granted: ${settings.authorizationStatus}');
      }

      // 2. Fetch and register device FCM Token
      _fcmToken = await _messaging.getToken();
      tokenNotifier.value = _fcmToken;
      debugPrint('FCM: Device Token: $_fcmToken');

      // 3. Listen to token refresh
      _messaging.onTokenRefresh.listen((token) async {
        _fcmToken = token;
        tokenNotifier.value = token;
        debugPrint('FCM: Token refreshed: $token');
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

      final authToken = prefs.getString('jodeals_auth_token');

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

  // Extract navigation payload and route to WebView
  static void handleMessagePayload(RemoteMessage message, Function(String url) callback) {
    debugPrint('FCM: Payload data: ${message.data}');
    // Check if the payload contains a "url" key
    final String? targetUrl = message.data['url'];
    if (targetUrl != null && targetUrl.isNotEmpty) {
      String target = targetUrl;
      // Normalize relative paths to absolute URLs using baseUrl
      if (!target.startsWith('http://') && !target.startsWith('https://')) {
        if (target.startsWith('/')) {
          target = '$baseUrl$target';
        } else {
          target = '$baseUrl/$target';
        }
      }
      // Direct Webview navigation
      callback(target);
    } else {
      // Default to home page
      callback(baseUrl);
    }
  }
}
