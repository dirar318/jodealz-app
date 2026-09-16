import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// A premium, robust client-side logging service that batches and transmits
/// application logs, warnings, and unhandled errors to the backend logs.php API.
class AppLogger {
  static final AppLogger _instance = AppLogger._internal();
  factory AppLogger() => _instance;

  AppLogger._internal();

  String _baseUrl = 'https://jodealz.online'; // Default fallback
  String _appVersion = '1.0.0';
  String _deviceId = 'Unknown';
  String _deviceModel = 'Unknown';
  String _osVersion = 'Unknown';
  bool _initialized = false;

  /// Initialize the logger with device info and base URL
  Future<void> init({required String baseUrl}) async {
    if (_initialized) return;
    _baseUrl = baseUrl;

    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {}

    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        _deviceId = androidInfo.id;
        _deviceModel = androidInfo.model;
        _osVersion = 'Android ${androidInfo.version.release}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        _deviceId = iosInfo.identifierForVendor ?? 'Unknown';
        _deviceModel = iosInfo.model;
        _osVersion = 'iOS ${iosInfo.systemVersion}';
      }
    } catch (_) {}

    _initialized = true;
    logInfo('Logger initialized', payload: {
      'device_id': _deviceId,
      'device_model': _deviceModel,
      'os_version': _osVersion,
      'app_version': _appVersion,
    });
  }

  /// Sends a log message to logs.php endpoint
  Future<void> sendLog({
    required String message,
    required String severity,
    String errorType = 'Mobile Application Log',
    String? file,
    int? line,
    String? trace,
    Map<String, dynamic>? payload,
  }) async {
    if (!_initialized) {
      debugPrint('AppLogger not initialized yet. Message: $message');
      return;
    }

    // Do not log logging activities themselves to avoid infinite loop
    if (message.contains('/api/v1/logs.php')) return;

    final url = Uri.parse('$_baseUrl/api/v1/logs.php');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jodeals_auth_token');

      final Map<String, String> headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-Mobile-OS': Platform.isAndroid ? 'Android' : 'iOS',
        'X-Mobile-Version': _appVersion,
      };

      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
        headers['X-Auth-Token'] = token;
      }

      final Map<String, dynamic> mergedPayload = {
        ...?payload,
        'device_id': _deviceId,
        'device_model': _deviceModel,
        'os_version': _osVersion,
        'app_version': _appVersion,
      };

      final body = json.encode({
        'error_type': errorType,
        'severity': severity,
        'message': message,
        'file': file,
        'line': line,
        'trace': trace,
        'payload': mergedPayload,
      });

      // Execute network POST request silently in the background
      http.post(url, headers: headers, body: body).timeout(
        const Duration(seconds: 5),
        onTimeout: () => http.Response('{"status":"error","message":"Timeout"}', 408),
      ).then((response) {
        if (response.statusCode != 200) {
          debugPrint('AppLogger failed to send log: ${response.statusCode} | ${response.body}');
        }
      }).catchError((err) {
        debugPrint('AppLogger error sending log: $err');
      });
    } catch (e) {
      debugPrint('AppLogger exception during log generation: $e');
    }
  }

  /// Log informational message
  void logInfo(String message, {Map<String, dynamic>? payload}) {
    debugPrint('[INFO] $message');
    sendLog(message: message, severity: 'info', payload: payload);
  }

  /// Log warning message
  void logWarning(String message, {Map<String, dynamic>? payload}) {
    debugPrint('[WARNING] $message');
    sendLog(message: message, severity: 'warning', payload: payload);
  }

  /// Log error message
  void logError(String message, {dynamic error, StackTrace? stack, String? file, int? line, Map<String, dynamic>? payload}) {
    debugPrint('[ERROR] $message. Error: $error');
    final Map<String, dynamic> errorPayload = {
      ...?payload,
      'error_details': error?.toString(),
    };
    sendLog(
      message: message,
      severity: 'error',
      errorType: error?.runtimeType.toString() ?? 'Mobile Application Error',
      file: file,
      line: line,
      trace: stack?.toString(),
      payload: errorPayload,
    );
  }

  /// Log fatal application crash
  void logFatal(String message, {dynamic error, StackTrace? stack, String? file, int? line, Map<String, dynamic>? payload}) {
    debugPrint('[FATAL] $message. Error: $error');
    final Map<String, dynamic> errorPayload = {
      ...?payload,
      'error_details': error?.toString(),
    };
    sendLog(
      message: message,
      severity: 'fatal',
      errorType: error?.runtimeType.toString() ?? 'Mobile Unhandled Fatal Exception',
      file: file,
      line: line,
      trace: stack?.toString(),
      payload: errorPayload,
    );
  }
}
