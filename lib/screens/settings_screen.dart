import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jodeals/services/local_db_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:jodeals/services/anonymous_tracking_service.dart';
import 'package:jodeals/main.dart' show JoDealsApp;
import 'package:jodeals/theme/app_colors.dart';
import 'package:jodeals/services/consent_service.dart';

class SettingsScreen extends StatefulWidget {
  final String baseUrl;

  const SettingsScreen({
    super.key,
    required this.baseUrl,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isArabic = true;
  String _appVersion = '1.0.0';
  bool _isClearingCache = false;
  bool _newDealsEnabled = true;
  bool _discountsEnabled = true;
  bool _categoryUpdatesEnabled = true;
  bool _marketingEnabled = false;
  bool _analyticsEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final lang = prefs.getString('jodeals_app_lang') ?? 'ar';
    final info = await PackageInfo.fromPlatform();
    final prefsMap = AnonymousTrackingService().getPreferences();
    final analytics = await ConsentService.analyticsAllowed();
    if (mounted) {
      setState(() {
        _isArabic = lang == 'ar';
        _appVersion = '${info.version}+${info.buildNumber}';
        _newDealsEnabled = (prefsMap['new_deals_enabled'] ?? 1) == 1;
        _discountsEnabled = (prefsMap['discounts_enabled'] ?? 1) == 1;
        _categoryUpdatesEnabled = (prefsMap['category_updates_enabled'] ?? 1) == 1;
        _marketingEnabled = (prefsMap['marketing_enabled'] ?? 0) == 1;
        _analyticsEnabled = analytics;
      });
    }
  }

  Future<void> _updateNotificationPreference(String key, bool val) async {
    setState(() {
      if (key == 'new_deals') _newDealsEnabled = val;
      if (key == 'discounts') _discountsEnabled = val;
      if (key == 'category_updates') _categoryUpdatesEnabled = val;
      if (key == 'marketing') _marketingEnabled = val;
    });

    final success = await AnonymousTrackingService().updatePreferences(
      newDeals: _newDealsEnabled,
      discounts: _discountsEnabled,
      categoryUpdates: _categoryUpdatesEnabled,
      marketing: _marketingEnabled,
    );

    if (!success) {
      setState(() {
        if (key == 'new_deals') _newDealsEnabled = !val;
        if (key == 'discounts') _discountsEnabled = !val;
        if (key == 'category_updates') _categoryUpdatesEnabled = !val;
        if (key == 'marketing') _marketingEnabled = !val;
      });
      _showSnackBar(_txt('فشل تحديث التفضيلات', 'Failed to update preferences'), isError: true);
    }
  }

  Future<void> _changeLanguage(String langCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jodeals_app_lang', langCode);
    setState(() {
      _isArabic = langCode == 'ar';
    });
    // Propagate locale change to the entire app immediately
    JoDealsApp.setLocale(langCode);
    _showSnackBar(_txt('تم تغيير اللغة بنجاح', 'Language updated successfully'));
  }

  Future<void> _clearCache() async {
    setState(() {
      _isClearingCache = true;
    });
    try {
      final db = LocalDbService.instance;
      // Clear deals and categories table in sqflite
      final database = await db.database;
      await database.delete('deals');
      await database.delete('categories');
      await database.delete('sync_metadata');
      
      _showSnackBar(_txt('تم مسح ذاكرة التخزين المؤقت بنجاح', 'Cache cleared successfully'));
    } catch (e) {
      _showSnackBar(_txt('فشل مسح ذاكرة التخزين', 'Failed to clear cache'), isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isClearingCache = false;
        });
      }
    }
  }

  String _txt(String ar, String en) => _isArabic ? ar : en;

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.cairo(fontSize: 13, color: Colors.white)),
        backgroundColor: isError ? const Color(0xFFFF4D4D) : const Color(0xFF10B981),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const Color brandRed = AppColors.primary;
    final Color textColor = AppColors.textPrimary(isDark);
    final Color subtextColor = AppColors.textSecondary(isDark);
    final Color cardBg = AppColors.card(isDark);

    return Directionality(
      textDirection: _isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.bg(isDark),
        appBar: AppBar(
          title: Text(
            _txt('الإعدادات', 'Settings'),
            style: GoogleFonts.cairo(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: textColor,
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: BackButton(color: textColor),
        ),
        body: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section 1: Preferences
              _buildSectionHeader(_txt('التفضيلات', 'Preferences'), subtextColor),
              const SizedBox(height: 8),
              Card(
                color: cardBg,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: brandRed.withValues(alpha: 0.08),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.translate, color: brandRed),
                      title: Text(
                        _txt('لغة التطبيق', 'App Language'),
                        style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: textColor),
                      ),
                      trailing: DropdownButton<String>(
                        value: _isArabic ? 'ar' : 'en',
                        underline: const SizedBox.shrink(),
                        icon: const Icon(Icons.keyboard_arrow_down, color: brandRed),
                        items: [
                          DropdownMenuItem(
                            value: 'ar',
                            child: Text('العربية', style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold)),
                          ),
                          DropdownMenuItem(
                            value: 'en',
                            child: Text('English', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold)),
                          ),
                        ],
                        onChanged: (lang) {
                          if (lang != null) {
                            _changeLanguage(lang);
                          }
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.notifications_active_outlined, color: brandRed),
                      title: Text(
                        _txt('إشعارات التطبيق', 'App Notifications'),
                        style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: textColor),
                      ),
                      trailing: const Icon(Icons.settings_outlined, size: 20),
                      onTap: () => openAppSettings(),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      activeThumbColor: brandRed,
                      title: Text(_txt('عروض جديدة', 'New Deals'), style: GoogleFonts.cairo(fontSize: 13, color: textColor, fontWeight: FontWeight.w600)),
                      subtitle: Text(_txt('إشعار عند توفر عروض جديدة مضافة حديثاً', 'Notify when new deals are published'), style: GoogleFonts.cairo(fontSize: 10, color: subtextColor)),
                      value: _newDealsEnabled,
                      onChanged: (val) => _updateNotificationPreference('new_deals', val),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      activeThumbColor: brandRed,
                      title: Text(_txt('خصومات وحملات', 'Discounts & Campaigns'), style: GoogleFonts.cairo(fontSize: 13, color: textColor, fontWeight: FontWeight.w600)),
                      subtitle: Text(_txt('خصومات كبرى وعروض حصرية لفترة محدودة', 'Big discounts and limited-time campaigns'), style: GoogleFonts.cairo(fontSize: 10, color: subtextColor)),
                      value: _discountsEnabled,
                      onChanged: (val) => _updateNotificationPreference('discounts', val),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      activeThumbColor: brandRed,
                      title: Text(_txt('تحديثات الفئات', 'Category Updates'), style: GoogleFonts.cairo(fontSize: 13, color: textColor, fontWeight: FontWeight.w600)),
                      subtitle: Text(_txt('إشعار عند إضافة فئات أو تصنيفات جديدة', 'Notify when new categories are added'), style: GoogleFonts.cairo(fontSize: 10, color: subtextColor)),
                      value: _categoryUpdatesEnabled,
                      onChanged: (val) => _updateNotificationPreference('category_updates', val),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      activeThumbColor: brandRed,
                      title: Text(_txt('إعلانات تسويقية', 'Marketing Announcements'), style: GoogleFonts.cairo(fontSize: 13, color: textColor, fontWeight: FontWeight.w600)),
                      subtitle: Text(_txt('أخبار تسويقية وتحديثات مهمة حول الخدمة', 'Marketing news and service updates'), style: GoogleFonts.cairo(fontSize: 10, color: subtextColor)),
                      value: _marketingEnabled,
                      onChanged: (val) => _updateNotificationPreference('marketing', val),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      activeThumbColor: brandRed,
                      title: Text(_txt('مشاركة بيانات الاستخدام', 'Share Usage Data'), style: GoogleFonts.cairo(fontSize: 13, color: textColor, fontWeight: FontWeight.w600)),
                      subtitle: Text(_txt('الصفحات والعروض التي تشاهدها وأداء التطبيق لتحسين الخدمة', 'Pages and deals you view and app performance, to improve the service'), style: GoogleFonts.cairo(fontSize: 10, color: subtextColor)),
                      value: _analyticsEnabled,
                      onChanged: (val) async {
                        setState(() => _analyticsEnabled = val);
                        await ConsentService.setAnalytics(val);
                        await AnonymousTrackingService().onConsentChanged();
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Section 2: Storage & Cache
              _buildSectionHeader(_txt('التخزين والمزامنة', 'Storage & Sync'), subtextColor),
              const SizedBox(height: 8),
              Card(
                color: cardBg,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: brandRed.withValues(alpha: 0.08),
                    width: 1.5,
                  ),
                ),
                child: ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined, color: Colors.red),
                  title: Text(
                    _txt('مسح ذاكرة التخزين المؤقت', 'Clear Cached Deals'),
                    style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: textColor),
                  ),
                  subtitle: Text(
                    _txt('مسح الصفقات المحفوظة أوفلاين', 'Remove offline cached deals data'),
                    style: GoogleFonts.cairo(fontSize: 11, color: subtextColor),
                  ),
                  trailing: _isClearingCache
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: brandRed),
                        )
                      : const Icon(Icons.chevron_right, size: 20),
                  onTap: _isClearingCache ? null : _clearCache,
                ),
              ),

              const SizedBox(height: 24),

              // Section 3: Legal & About
              _buildSectionHeader(_txt('حول التطبيق', 'About App'), subtextColor),
              const SizedBox(height: 8),
              Card(
                color: cardBg,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: brandRed.withValues(alpha: 0.08),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.info_outline, color: brandRed),
                      title: Text(
                        _txt('شروط الاستخدام', 'Terms of Service'),
                        style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: textColor),
                      ),
                      trailing: const Icon(Icons.open_in_new, size: 16, color: brandRed),
                      onTap: () async {
                        final uri = Uri.parse('${widget.baseUrl}/terms');
                        if (await canLaunchUrl(uri)) await launchUrl(uri);
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.privacy_tip_outlined, color: brandRed),
                      title: Text(
                        _txt('سياسة الخصوصية', 'Privacy Policy'),
                        style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: textColor),
                      ),
                      trailing: const Icon(Icons.open_in_new, size: 16, color: brandRed),
                      onTap: () async {
                        final uri = Uri.parse('${widget.baseUrl}/privacy');
                        if (await canLaunchUrl(uri)) await launchUrl(uri);
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.phone_outlined, color: brandRed),
                      title: Text(
                        _txt('اتصل بنا', 'Contact Us'),
                        style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: textColor),
                      ),
                      trailing: const Icon(Icons.open_in_new, size: 16, color: brandRed),
                      onTap: () async {
                        final uri = Uri.parse('${widget.baseUrl}/contact');
                        if (await canLaunchUrl(uri)) await launchUrl(uri);
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Version Info Footer
              Center(
                child: Text(
                  '${_txt("النسخة", "Version")} $_appVersion',
                  style: GoogleFonts.inter(fontSize: 12, color: subtextColor, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        title,
        style: GoogleFonts.cairo(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
