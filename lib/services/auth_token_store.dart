import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Single source of truth for the user's session token.
///
/// The token is kept in the Keychain (iOS) / Keystore-backed storage (Android)
/// instead of SharedPreferences, so it is not stored in plaintext and is not
/// included in device backups. Tokens written by older app versions to
/// SharedPreferences are migrated on first read.
class AuthTokenStore {
  AuthTokenStore._();

  static const String _key = 'jodeals_auth_token';
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  static String? _cached;
  static bool _loaded = false;

  static Future<String?> read() async {
    if (_loaded) return _cached;
    try {
      _cached = await _storage.read(key: _key);
    } catch (e) {
      debugPrint('AuthTokenStore: secure read failed: $e');
    }
    if (_cached == null || _cached!.isEmpty) {
      await _migrateLegacyToken();
    }
    _loaded = true;
    return (_cached == null || _cached!.isEmpty) ? null : _cached;
  }

  static Future<void> _migrateLegacyToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(_key);
      if (legacy == null || legacy.isEmpty) return;
      _cached = legacy;
      await prefs.remove(_key);
      await _storage.write(key: _key, value: legacy);
    } catch (e) {
      debugPrint('AuthTokenStore: legacy migration failed: $e');
    }
  }

  static Future<void> write(String token) async {
    _cached = token;
    _loaded = true;
    try {
      await _storage.write(key: _key, value: token);
    } catch (e) {
      debugPrint('AuthTokenStore: write failed: $e');
    }
  }

  static Future<void> clear() async {
    _cached = null;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
    try {
      await _storage.delete(key: _key);
    } catch (e) {
      debugPrint('AuthTokenStore: clear failed: $e');
    }
  }
}
