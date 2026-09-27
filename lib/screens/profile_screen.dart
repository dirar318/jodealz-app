import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:jodeals/services/local_db_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jodeals/theme/app_colors.dart';
import 'package:jodeals/theme/app_radius.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:jodeals/services/auth_token_store.dart';

class ProfileScreen extends StatefulWidget {
  final String baseUrl;
  final VoidCallback onLogout;
  final VoidCallback? onAccountDeleted;

  const ProfileScreen({
    super.key,
    required this.baseUrl,
    required this.onLogout,
    this.onAccountDeleted,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _userProfile;
  bool _isLoading = true;
  bool _isArabic = true;

  @override
  void initState() {
    super.initState();
    _loadLanguage();
    _loadUserProfile();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reactively update language when the app locale changes
    final locale = Localizations.localeOf(context).languageCode;
    final isArabic = locale == 'ar';
    if (_isArabic != isArabic) {
      setState(() {
        _isArabic = isArabic;
      });
    }
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final lang = prefs.getString('jodeals_app_lang') ?? 'ar';
    if (mounted) {
      setState(() {
        _isArabic = lang == 'ar';
      });
    }
  }

  Future<void> _loadUserProfile() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final profile = await LocalDbService.instance.getUserProfile();
      if (mounted) {
        setState(() {
          _userProfile = profile;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('ProfileScreen: Error loading profile: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _txt(String ar, String en) => _isArabic ? ar : en;

  bool _isDeleting = false;

  /// In-app account deletion (App Store 5.1.1(v), Google Play account
  /// deletion policy). The backend endpoint must permanently delete the
  /// account and associated personal data.
  Future<void> _confirmDeleteAccount() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(_txt('حذف الحساب نهائياً؟', 'Delete your account?'),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(_txt(
          'سيتم حذف حسابك وبياناتك الشخصية (الملف الشخصي، المفضلة، سجل النشاط) بشكل نهائي ولا يمكن التراجع عن ذلك.',
          'Your account and personal data (profile, favorites, activity history) will be permanently deleted. This cannot be undone.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_txt('إلغاء', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(_txt('حذف نهائي', 'Delete permanently')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final token = await AuthTokenStore.read();
      if (token == null) throw Exception('Not signed in');
      final response = await http.post(
        Uri.parse('${widget.baseUrl}/api/v1/auth/delete-account.php'),
        headers: {
          'Authorization': 'Bearer $token',
          'X-Auth-Token': token,
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode({'confirm': true}),
      ).timeout(const Duration(seconds: 15));

      final Map<String, dynamic>? data =
          response.body.isNotEmpty ? json.decode(response.body) as Map<String, dynamic>? : null;
      if (response.statusCode == 200 && data?['status'] == 'success') {
        (widget.onAccountDeleted ?? widget.onLogout)();
        navigator.pop();
        return;
      }
      // e.g. 409 CONTACT_SUPPORT for business accounts: show the server's reason.
      final String? serverMessage = data?['message'] as String?;
      throw _DeleteAccountException(response.statusCode == 409 ? serverMessage : null);
    } catch (e) {
      debugPrint('ProfileScreen: account deletion failed: $e');
      final String? reason = e is _DeleteAccountException ? e.message : null;
      messenger.showSnackBar(SnackBar(
        content: Text(reason ??
            _txt(
              'تعذر حذف الحساب. يرجى المحاولة لاحقاً.',
              'Could not delete your account. Please try again later.',
            )),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ));
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const Color brandRed = AppColors.primary;
    const Color brandAmber = AppColors.secondary;
    final Color textColor = AppColors.textPrimary(isDark);
    final Color subtextColor = AppColors.textSecondary(isDark);
    final Color cardBg = AppColors.card(isDark);

    return Directionality(
      textDirection: _isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.bg(isDark),
        appBar: AppBar(
          title: Text(
            _txt('الملف الشخصي', 'My Profile'),
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
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: brandRed),
              )
            : SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    // Header Section (Avatar & Name)
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            brandRed.withValues(alpha: 0.05),
                            brandAmber.withValues(alpha: 0.05)
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: brandRed.withValues(alpha: 0.1),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          Center(
                            child: Hero(
                              tag: 'profile_avatar',
                              child: Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    colors: [brandRed, brandAmber],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: brandRed.withValues(alpha: 0.2),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(3.0),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: _userProfile?['profile_image'] != null &&
                                            _userProfile!['profile_image'].toString().isNotEmpty
                                        ? Image.network(
                                            _userProfile!['profile_image'],
                                            fit: BoxFit.cover,
                                            errorBuilder: (c, e, s) => const Icon(
                                              Icons.person,
                                              size: 50,
                                              color: brandRed,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.person,
                                            size: 50,
                                            color: brandRed,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _userProfile?['name'] ?? _txt('مستخدم زائر', 'Guest User'),
                            style: GoogleFonts.cairo(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                          Text(
                            _userProfile?['email'] ?? _txt('سجل الدخول لحفظ العروض', 'Sign in to save deals'),
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: subtextColor,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Referral Code Card
                    if (_userProfile != null && _userProfile?['referral_code'] != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Card(
                          color: cardBg,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: brandRed.withValues(alpha: 0.2),
                              width: 1.5,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.card_giftcard, color: brandRed, size: 24),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _txt('رمز الدعوة الخاص بك', 'Your Referral Code'),
                                        style: GoogleFonts.cairo(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: textColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: brandRed.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _userProfile?['referral_code'] ?? '',
                                        style: GoogleFonts.inter(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: brandRed,
                                        ),
                                      ),
                                      Text(
                                        _txt('${_userProfile?['referral_usage'] ?? 0} استخدام', '${_userProfile?['referral_usage'] ?? 0} uses'),
                                        style: GoogleFonts.cairo(
                                          fontSize: 14,
                                          color: subtextColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      
                    const SizedBox(height: 16),

                    // User Details Cards
                    if (_userProfile != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Card(
                          color: cardBg,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: brandRed.withValues(alpha: 0.08),
                              width: 1.5,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                _buildDetailItem(
                                  icon: Icons.phone_android_outlined,
                                  title: _txt('رقم الهاتف', 'Phone Number'),
                                  value: _userProfile?['phone'] ?? '-',
                                  textColor: textColor,
                                  subtextColor: subtextColor,
                                ),
                                const Divider(height: 24),
                                _buildDetailItem(
                                  icon: Icons.location_on_outlined,
                                  title: _txt('العنوان', 'Address'),
                                  value: _userProfile?['address'] ?? '-',
                                  textColor: textColor,
                                  subtextColor: subtextColor,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    const SizedBox(height: 16),

                    // Settings & Actions Menu
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Card(
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
                            _buildMenuItem(
                              icon: Icons.settings_outlined,
                              title: _txt('الإعدادات', 'Settings'),
                              onTap: () async {
                                await Navigator.pushNamed(context, '/settings');
                                _loadLanguage();
                                _loadUserProfile();
                              },
                              textColor: textColor,
                            ),
                            if (_userProfile != null) ...[
                              const Divider(height: 1),
                              _buildMenuItem(
                                icon: Icons.logout_rounded,
                                title: _txt('تسجيل الخروج', 'Log Out'),
                                iconColor: Colors.red,
                                onTap: () {
                                  widget.onLogout();
                                  Navigator.pop(context);
                                },
                                textColor: Colors.red,
                              ),
                              const Divider(height: 1),
                              _buildMenuItem(
                                icon: Icons.delete_forever_outlined,
                                title: _txt('حذف الحساب', 'Delete Account'),
                                iconColor: Colors.red,
                                onTap: _isDeleting ? () {} : _confirmDeleteAccount,
                                textColor: Colors.red,
                              ),
                            ] else ...[
                              const Divider(height: 1),
                              _buildMenuItem(
                                icon: Icons.login_rounded,
                                title: _txt('تسجيل الدخول', 'Sign In'),
                                iconColor: brandRed,
                                onTap: () {
                                  Navigator.pop(context);
                                  // This will trigger webview native login redirection
                                },
                                textColor: brandRed,
                              ),
                            ]
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildDetailItem({
    required IconData icon,
    required String title,
    required String value,
    required Color textColor,
    required Color subtextColor,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: AppRadius.radiusMd,
          ),
          child: Icon(icon, color: AppColors.primary, size: 22),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: subtextColor,
                ),
              ),
              Text(
                value,
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    required Color textColor,
    Color iconColor = AppColors.primary,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(
        title,
        style: GoogleFonts.cairo(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
      trailing: Icon(
        _isArabic ? Icons.chevron_left : Icons.chevron_right,
        size: 20,
      ),
      onTap: onTap,
    );
  }
}


class _DeleteAccountException implements Exception {
  const _DeleteAccountException(this.message);
  final String? message;

  @override
  String toString() => 'DeleteAccountException($message)';
}
