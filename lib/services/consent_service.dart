import 'package:shared_preferences/shared_preferences.dart';

/// Stores the user's choice about optional analytics (usage/behaviour
/// tracking and performance metrics). Nothing optional is collected until the
/// user has explicitly opted in.
class ConsentService {
  ConsentService._();

  static const String _key = 'jodeals_analytics_consent';
  static bool? _analytics;

  /// null = not asked yet.
  static Future<bool?> analyticsChoice() async {
    if (_analytics != null) return _analytics;
    final prefs = await SharedPreferences.getInstance();
    _analytics = prefs.getBool(_key);
    return _analytics;
  }

  static Future<bool> analyticsAllowed() async => (await analyticsChoice()) ?? false;

  static Future<void> setAnalytics(bool allowed) async {
    _analytics = allowed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, allowed);
  }
}
