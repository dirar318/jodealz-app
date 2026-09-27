import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:jodeals/services/fcm_service.dart';
import 'package:jodeals/screens/auth/auth_screen_args.dart';
import 'package:jodeals/theme/app_colors.dart';

class RegisterScreen extends StatefulWidget {
  final String baseUrl;
  final Future<void> Function(String token) onRegisterSuccess;
  final VoidCallback onCancel;
  final String? guestId;

  const RegisterScreen({
    super.key,
    required this.baseUrl,
    required this.onRegisterSuccess,
    required this.onCancel,
    this.guestId,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _referralCodeController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  bool _isArabic = true;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic);
    _fadeController.forward();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lang = prefs.getString('jodeals_app_lang') ?? 'ar';
      if (mounted) {
        setState(() {
          _isArabic = lang == 'ar';
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _referralCodeController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  String _txt(String ar, String en) => _isArabic ? ar : en;

  bool _validatePasswordStrength(String password) {
    if (password.length < 8) return false;
    final hasLetter = RegExp(r'[a-zA-Z]').hasMatch(password);
    final hasDigit = RegExp(r'[0-9]').hasMatch(password);
    return hasLetter && hasDigit;
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) {
      HapticFeedback.heavyImpact();
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final deviceInfo = DeviceInfoPlugin();
      String deviceId = 'Unknown';
      String deviceModel = 'Unknown';
      String osVersion = 'Unknown';
      String appVersion = '1.0.0';

      try {
        if (Platform.isAndroid) {
          final androidInfo = await deviceInfo.androidInfo;
          deviceId = androidInfo.id;
          deviceModel = androidInfo.model;
          osVersion = 'Android ${androidInfo.version.release}';
        } else if (Platform.isIOS) {
          final iosInfo = await deviceInfo.iosInfo;
          deviceId = iosInfo.identifierForVendor ?? 'Unknown';
          deviceModel = iosInfo.model;
          osVersion = 'iOS ${iosInfo.systemVersion}';
        }
        final packageInfo = await PackageInfo.fromPlatform();
        appVersion = packageInfo.version;
      } catch (_) {}

      final String? fcmToken = FCMService.token;

      final response = await http.post(
        Uri.parse('${widget.baseUrl}/api/v1/auth/register.php'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode({
          'name': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'phone': _phoneController.text.trim(),
          'password': _passwordController.text,
          'referral_code': _referralCodeController.text.trim(),
          'platform': 'mobile',
          'guest_id': widget.guestId,
          'device_id': deviceId,
          'device_model': deviceModel,
          'device_type': Platform.isAndroid ? 'Android' : (Platform.isIOS ? 'iOS' : 'Mobile'),
          'os_version': osVersion,
          'app_version': appVersion,
          'fcm_token': fcmToken,
          'device_token': fcmToken,
        }),
      ).timeout(const Duration(seconds: 15));

      final responseData = json.decode(response.body);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        final token = responseData['token'];
        if (token != null) {
          HapticFeedback.lightImpact();
          await widget.onRegisterSuccess(token);
          if (mounted) Navigator.pop(context);
        } else {
          setState(() {
            _errorMessage = _txt('رمز الجلسة غير صالح من الخادم.', 'Invalid session token returned by server.');
          });
          HapticFeedback.heavyImpact();
        }
      } else {
        setState(() {
          _errorMessage = responseData['message'] ?? _txt('فشل إنشاء الحساب.', 'Registration failed.');
        });
        HapticFeedback.heavyImpact();
      }
    } catch (e) {
      setState(() {
        _errorMessage = _txt('خطأ في الاتصال بالخادم. يرجى المحاولة لاحقاً.', 'Server connection error. Please try again.');
      });
      HapticFeedback.heavyImpact();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const Color brandRed = AppColors.primary;
    const Color brandAmber = AppColors.secondary;
    final Color cardColor = isDark ? AppColors.darkCard : Colors.white;
    final Color textColor = AppColors.textPrimary(isDark);
    final Color subtitleColor = AppColors.textSecondary(isDark);
    final Color fieldColor = isDark ? AppColors.darkCard : Colors.white;
    final Color borderColor = AppColors.border(isDark);

    return Directionality(
      textDirection: _isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.bg(isDark),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.close, color: textColor),
            tooltip: _txt('إغلاق', 'Close'),
            onPressed: () {
              widget.onCancel();
              Navigator.of(context).pop();
            },
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: TextButton.icon(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    _isArabic = !_isArabic;
                  });
                },
                icon: const Icon(Icons.translate, size: 16, color: brandRed),
                label: Text(
                  _isArabic ? 'English' : 'العربية',
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold,
                    color: brandRed,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(16.0),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [brandRed, brandAmber],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(24.0),
                            boxShadow: [
                              BoxShadow(
                                color: brandRed.withValues(alpha: 0.25),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.local_offer,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _txt('إنشاء حساب جديد', 'Create Account'),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.cairo(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _txt('انضم إلينا الآن ووفر على كافة العروض', 'Join us now and save on all deals'),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          color: subtitleColor,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.08),
                            border: Border.all(color: Colors.red.withValues(alpha: 0.3), width: 1.5),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.red, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: GoogleFonts.cairo(
                                    color: Colors.red,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Card(
                        color: cardColor,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                          side: BorderSide(color: borderColor, width: 1.5),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                _txt('الاسم الكامل', 'Full Name'),
                                style: GoogleFonts.cairo(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _nameController,
                                style: GoogleFonts.cairo(fontSize: 14, color: textColor),
                                decoration: InputDecoration(
                                  hintText: _txt('مثال: أحمد علي', 'e.g. John Doe'),
                                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                                  prefixIcon: const Icon(Icons.person_outline, size: 20),
                                  filled: true,
                                  fillColor: fieldColor,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(color: borderColor),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(color: brandRed, width: 1.5),
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return _txt('الرجاء إدخال الاسم', 'Please enter your name');
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _txt('البريد الإلكتروني', 'Email Address'),
                                style: GoogleFonts.cairo(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                textDirection: TextDirection.ltr,
                                style: GoogleFonts.inter(fontSize: 14, color: textColor),
                                decoration: InputDecoration(
                                  hintText: 'yourname@domain.com',
                                  hintStyle: GoogleFonts.inter(color: Colors.grey[400], fontSize: 13),
                                  prefixIcon: const Icon(Icons.email_outlined, size: 20),
                                  filled: true,
                                  fillColor: fieldColor,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(color: borderColor),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(color: brandRed, width: 1.5),
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return _txt('الرجاء إدخال البريد الإلكتروني', 'Please enter email');
                                  }
                                  if (!RegExp(r'^[\w\.\+-]+@([\w-]+\.)+[\w-]{2,}$').hasMatch(value.trim())) {
                                    return _txt('الرجاء إدخال بريد إلكتروني صالح', 'Please enter a valid email');
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _txt('رقم الهاتف (اختياري)', 'Phone Number (Optional)'),
                                style: GoogleFonts.cairo(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                textDirection: TextDirection.ltr,
                                style: GoogleFonts.inter(fontSize: 14, color: textColor),
                                decoration: InputDecoration(
                                  hintText: '07xxxxxxxx',
                                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                                  prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                                  filled: true,
                                  fillColor: fieldColor,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(color: borderColor),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(color: brandRed, width: 1.5),
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return null; // Optional field
                                  }
                                  final cleaned = value.trim();
                                  final localPattern = RegExp(r'^07[789]\d{7}$');
                                  final intlPattern = RegExp(r'^\+9627[789]\d{7}$');
                                  if (!localPattern.hasMatch(cleaned) && !intlPattern.hasMatch(cleaned)) {
                                    return _txt(
                                      'رقم الهاتف غير صحيح. مثال: 07X XXXX XXX',
                                      'Invalid phone. Example: 07X XXXX XXX',
                                    );
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _txt('كلمة المرور', 'Password'),
                                style: GoogleFonts.cairo(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                style: GoogleFonts.inter(fontSize: 14, color: textColor),
                                decoration: InputDecoration(
                                  hintText: '••••••••',
                                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                                  prefixIcon: const Icon(Icons.lock_outline, size: 20),
                                  filled: true,
                                  fillColor: fieldColor,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(color: borderColor),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(color: brandRed, width: 1.5),
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                      color: Colors.grey[400],
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return _txt('الرجاء إدخال كلمة المرور', 'Please enter password');
                                  }
                                  if (!_validatePasswordStrength(value)) {
                                    return _txt('يجب أن تتكون كلمة المرور من 8 رموز على الأقل وتحتوي على حروف وأرقام', 'Password must be at least 8 characters long and contain both letters and numbers');
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _txt('رمز الدعوة (اختياري)', 'Referral Code (Optional)'),
                                style: GoogleFonts.cairo(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _referralCodeController,
                                style: GoogleFonts.inter(fontSize: 14, color: textColor),
                                textCapitalization: TextCapitalization.characters,
                                decoration: InputDecoration(
                                  hintText: _txt('أدخل رمز الدعوة هنا', 'Enter referral code here'),
                                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                                  prefixIcon: const Icon(Icons.card_giftcard, size: 20),
                                  filled: true,
                                  fillColor: fieldColor,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(color: borderColor),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(color: brandRed, width: 1.5),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Container(
                                height: 48,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [brandRed, brandAmber],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: brandRed.withValues(alpha: 0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _handleRegister,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    foregroundColor: Colors.white,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Text(
                                          _txt('إنشاء الحساب', 'Sign Up'),
                                          style: GoogleFonts.cairo(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _txt('لديك حساب بالفعل؟', 'Already have an account?'),
                            style: GoogleFonts.cairo(fontSize: 12, color: subtitleColor),
                          ),
                          TextButton(
                            onPressed: () {
                              final args = ModalRoute.of(context)?.settings.arguments as AuthScreenArgs?;
                              Navigator.pushReplacementNamed(
                                context,
                                '/login',
                                arguments: args,
                              );
                            },
                            child: Text(
                              _txt('تسجيل الدخول', 'Sign In'),
                              style: GoogleFonts.cairo(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: brandRed,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
