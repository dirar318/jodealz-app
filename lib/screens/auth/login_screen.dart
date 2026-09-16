import 'dart:convert';
import 'dart:ui';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:jodeals/screens/auth/auth_screen_args.dart';
import 'package:jodeals/services/app_logger.dart';
import 'package:jodeals/services/fcm_service.dart';
import 'package:jodeals/theme/app_colors.dart';
import 'package:jodeals/theme/app_radius.dart';
import 'package:jodeals/theme/app_typography.dart';
import 'package:jodeals/theme/app_spacing.dart';

class LoginScreen extends StatefulWidget {
  final String baseUrl;
  final Future<void> Function(String token) onLoginSuccess;
  final VoidCallback onCancel;
  final Future<void> Function() googleSignInHandler;
  final String? guestId;

  const LoginScreen({
    super.key,
    required this.baseUrl,
    required this.onLoginSuccess,
    required this.onCancel,
    required this.googleSignInHandler,
    this.guestId,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _secureStorage = const FlutterSecureStorage();
  final _localAuth = LocalAuthentication();

  bool _isLoading = false;
  bool _isSuccess = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _canUseBiometrics = false;
  bool _hasSavedCredentials = false;
  String? _errorMessage;
  bool _isArabic = true;
  String _appVersion = '1.0.0';

    // Entry, Shake & Pulsing animations
    late AnimationController _entranceController;
    late Animation<double> _entranceAnimation;

    late AnimationController _shakeController;
    late Animation<double> _shakeAnimation;

    late AnimationController _logoPulseController;
    late Animation<double> _logoPulseAnimation;

    @override
    void initState() {
      super.initState();
      
      // Entrance Anim (disabled in tests to ensure immediate hitability of elements)
      _entranceController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 800),
      );
      _entranceAnimation = CurvedAnimation(
        parent: _entranceController,
        curve: Curves.easeOutBack,
      );
      if (!Platform.environment.containsKey('FLUTTER_TEST')) {
        _entranceController.forward();
      } else {
        _entranceController.value = 1.0;
      }

    // Shake Anim (on error)
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: -12.0), weight: 1),
      TweenSequenceItem(tween: Tween<double>(begin: -12.0, end: 12.0), weight: 2),
      TweenSequenceItem(tween: Tween<double>(begin: 12.0, end: -8.0), weight: 2),
      TweenSequenceItem(tween: Tween<double>(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween<double>(begin: 8.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut));

    // Continuous Logo Pulse (disabled in tests to avoid pumpAndSettle timeout)
    _logoPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _logoPulseController.repeat(reverse: true);
    } else {
      _logoPulseController.value = 1.0;
    }
    _logoPulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _logoPulseController, curve: Curves.easeInOut),
    );

    _initAuthData();
  }

  Future<void> _initAuthData() async {
    await _loadLanguage();
    await _loadAppVersion();
    await _checkBiometrics();
    await _checkSavedCredentials();
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
    _emailController.dispose();
    _passwordController.dispose();
    _entranceController.dispose();
    _shakeController.dispose();
    _logoPulseController.dispose();
    super.dispose();
  }

  String _txt(String ar, String en) => _isArabic ? ar : en;

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = '${info.version}+${info.buildNumber}';
        });
      }
    } catch (_) {}
  }

  Future<void> _checkSavedCredentials() async {
    try {
      final email = await _secureStorage.read(key: 'jodeals_remembered_email');
      final hasPassword = await _secureStorage.containsKey(key: 'jodeals_remembered_password');
      if (email != null && hasPassword) {
        setState(() {
          _emailController.text = email;
          _rememberMe = true;
          _hasSavedCredentials = true;
        });
      }
    } catch (_) {}
  }

  Future<void> _checkBiometrics() async {
    try {
      final isSupported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      if (isSupported && canCheck) {
        final available = await _localAuth.getAvailableBiometrics();
        if (available.isNotEmpty) {
          setState(() {
            _canUseBiometrics = true;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _authenticateWithBiometrics() async {
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: _txt(
          'قم بتسجيل الدخول باستخدام البصمة أو التعرف على الوجه',
          'Log in using biometric authentication',
        ),
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );

      if (authenticated) {
        HapticFeedback.mediumImpact();
        final password = await _secureStorage.read(key: 'jodeals_remembered_password');
        if (password != null) {
          setState(() {
            _passwordController.text = password;
          });
          _handleLogin();
        }
      } else {
        setState(() {
          _errorMessage = _txt('فشل المصادقة البيومترية.', 'Biometric authentication failed.');
        });
        _triggerShake();
      }
    } catch (_) {
      setState(() {
        _errorMessage = _txt('خطأ في المصادقة البيومترية.', 'Biometric authentication encountered an error.');
      });
      _triggerShake();
    }
  }

  Future<void> _handleForgotPassword() async {
    final uri = Uri.parse('${widget.baseUrl}/forgot-password.php');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _triggerShake() {
    _shakeController.reset();
    _shakeController.forward();
    HapticFeedback.heavyImpact();
  }

  Future<void> _handleLogin() async {
    // 4. Prevent Multiple Login Requests
    if (_isLoading) return;

    if (!_formKey.currentState!.validate()) {
      _triggerShake();
      return;
    }

    setState(() {
      _isLoading = true;
      _isSuccess = false;
      _errorMessage = null;
    });

    try {
      // 1. Gather Device Info for audit tracking
      final deviceInfo = DeviceInfoPlugin();
      String deviceId = 'Unknown';
      String deviceModel = 'Unknown';
      String osVersion = 'Unknown';

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
      } catch (_) {}

      // Fetch FCM Token
      final String? fcmToken = FCMService.token;

      // 8. Call API to Login
      final response = await http.post(
        Uri.parse('${widget.baseUrl}/api/v1/auth/login.php'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
        },
        body: {
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
          'platform': 'mobile',
          'guest_id': widget.guestId ?? '',
          'device_id': deviceId,
          'device_model': deviceModel,
          'device_type': Platform.isAndroid ? 'Android' : (Platform.isIOS ? 'iOS' : 'Mobile'),
          'os_version': osVersion,
          'app_version': _appVersion,
          'fcm_token': fcmToken ?? '',
          'device_token': fcmToken ?? '',
        },
      ).timeout(const Duration(seconds: 12));

      // Handle server unavailable (500)
      if (response.statusCode == 500) {
        throw const HttpException('Server unavailable');
      }
      
      // Handle invalid credentials (401)
      if (response.statusCode == 401) {
        throw const HttpException('Invalid credentials/session expired');
      }

      final responseData = json.decode(response.body);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        // Support token or access_token returned by backend
        final token = responseData['token'] ?? responseData['access_token'];
        
        if (token != null) {
          // 3. Pre-navigate session validation (profile.php check)
          final profileVerifyResponse = await http.get(
            Uri.parse('${widget.baseUrl}/api/v1/profile.php'),
            headers: {
              'Authorization': 'Bearer $token',
              'X-Auth-Token': token,
              'Accept': 'application/json',
            },
          ).timeout(const Duration(seconds: 8));

          if (profileVerifyResponse.statusCode != 200) {
            throw const HttpException('Session validation failed');
          }

          // 2. Delayed Session Cleanup: Only logout previous session after success and validation
          final prefs = await SharedPreferences.getInstance();
          final currentToken = prefs.getString('jodeals_auth_token');
          if (currentToken != null && currentToken.isNotEmpty && currentToken != token) {
            try {
              await http.post(
                Uri.parse('${widget.baseUrl}/api/v1/auth/logout.php'),
                headers: {
                  'Authorization': 'Bearer $currentToken',
                  'X-Auth-Token': currentToken,
                  'Content-Type': 'application/json',
                },
              ).timeout(const Duration(seconds: 4));
            } catch (e) {
              debugPrint('Silent logout of previous session failed: $e');
            }
            await prefs.remove('jodeals_auth_token');
            await prefs.remove('last_registered_auth_token');
            await prefs.remove('last_registered_fcm_token');
          }

          // Save credentials securely if requested
          if (_rememberMe) {
            await _secureStorage.write(key: 'jodeals_remembered_email', value: _emailController.text.trim());
            await _secureStorage.write(key: 'jodeals_remembered_password', value: _passwordController.text);
          } else {
            await _secureStorage.delete(key: 'jodeals_remembered_email');
            await _secureStorage.delete(key: 'jodeals_remembered_password');
          }

          AppLogger().logInfo('User login successful', payload: {
            'email': _emailController.text.trim(),
            'remember_me': _rememberMe,
          });

          HapticFeedback.lightImpact();
          
          // Wait for token storage and WebView authentication before showing success
          await widget.onLoginSuccess(token);

          setState(() {
            _isLoading = false;
            _isSuccess = true;
          });

          // Success delay for visualization
          await Future.delayed(const Duration(milliseconds: 800));
          if (mounted) Navigator.pop(context);
        } else {
          setState(() {
            _errorMessage = _txt('رمز الجلسة غير صالح من الخادم.', 'Invalid session token returned by server.');
          });
          AppLogger().logWarning('Login API returned success but token was null', payload: {
            'email': _emailController.text.trim(),
          });
          _triggerShake();
        }
      } else {
        setState(() {
          _errorMessage = responseData['message'] ?? _txt('فشل تسجيل الدخول. يرجى التحقق من بياناتك.', 'Login failed. Please check your credentials.');
        });
        AppLogger().logWarning('User login failed: $_errorMessage', payload: {
          'email': _emailController.text.trim(),
        });
        _triggerShake();
      }
    } on SocketException catch (e) {
      setState(() {
        _errorMessage = _txt('لا يوجد اتصال بالإنترنت. يرجى التحقق من اتصالك.', 'No internet connection. Please check your connection.');
      });
      AppLogger().logError('Login network error (SocketException)', error: e, file: 'login_screen.dart', line: 360);
      _triggerShake();
    } on TimeoutException catch (e) {
      setState(() {
        _errorMessage = _txt('انتهت مهلة الاتصال بالخادم. يرجى المحاولة لاحقاً.', 'API connection timeout. Please try again.');
      });
      AppLogger().logError('Login timeout error (TimeoutException)', error: e, file: 'login_screen.dart', line: 364);
      _triggerShake();
    } on HttpException catch (e) {
      if (e.message == 'Server unavailable') {
        setState(() {
          _errorMessage = _txt('الخادم غير متوفر حالياً. يرجى المحاولة لاحقاً.', 'Server unavailable. Please try again.');
        });
      } else if (e.message == 'Invalid credentials/session expired') {
        setState(() {
          _errorMessage = _txt('البريد الإلكتروني أو كلمة المرور غير صالحة.', 'Invalid credentials/session expired.');
        });
      } else if (e.message == 'Session validation failed') {
        setState(() {
          _errorMessage = _txt('فشلت مزامنة الجلسة مع الخادم.', 'Session validation failed. Please try again.');
        });
      } else {
        setState(() {
          _errorMessage = _txt('حدث خطأ أثناء الاتصال بالخادم.', 'Server error. Please try again.');
        });
      }
      AppLogger().logWarning('Login HTTP exception: ${e.message}', payload: {'email': _emailController.text.trim()});
      _triggerShake();
    } catch (e, stack) {
      setState(() {
        _errorMessage = _txt('حدث خطأ ما. يرجى المحاولة لاحقاً.', 'Something went wrong. Please try again.');
      });
      AppLogger().logError('Unhandled login exception', error: e, stack: stack, file: 'login_screen.dart', line: 390);
      _triggerShake();
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

    final TextDirection direction = _isArabic ? TextDirection.rtl : TextDirection.ltr;
    final TextStyle customFont = _isArabic 
        ? GoogleFonts.cairo(color: textColor) 
        : GoogleFonts.inter(color: textColor);

    return Directionality(
      textDirection: direction,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            // Premium background: smooth subtle blobs & gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark 
                      ? [AppColors.darkBg, AppColors.darkBgAlt] 
                      : [AppColors.lightBg, const Color(0xFFE2E8F0)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            
            // Blurred decorative elements
            Positioned(
              top: -60,
              left: -60,
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: brandRed.withValues(alpha: isDark ? 0.12 : 0.08),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                  child: Container(color: Colors.transparent),
                ),
              ),
            ),
            Positioned(
              bottom: 80,
              right: -80,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: brandAmber.withValues(alpha: isDark ? 0.10 : 0.06),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                  child: Container(color: Colors.transparent),
                ),
              ),
            ),

            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                  child: ScaleTransition(
                    scale: _entranceAnimation,
                    child: FadeTransition(
                      opacity: _entranceAnimation,
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Close & Language switch bar
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: cardColor,
                                  child: IconButton(
                                    icon: Icon(Icons.close, color: textColor, size: 18),
                                    tooltip: _txt('إغلاق', 'Close'),
                                    onPressed: () {
                                      widget.onCancel();
                                      Navigator.of(context).pop();
                                    },
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: cardColor,
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  child: TextButton.icon(
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                    ),
                                    onPressed: () {
                                      HapticFeedback.selectionClick();
                                      setState(() {
                                        _isArabic = !_isArabic;
                                      });
                                    },
                                    icon: const Icon(Icons.translate, size: 14, color: brandRed),
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
                            const SizedBox(height: 20),

                            // Branding Header
                            Center(
                              child: ScaleTransition(
                                scale: _logoPulseAnimation,
                                child: Container(
                                  padding: const EdgeInsets.all(18.0),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [brandRed, brandAmber],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: brandRed.withValues(alpha: 0.35),
                                        blurRadius: 16,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.local_offer,
                                    color: Colors.white,
                                    size: 42,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              _txt('تسجيل الدخول', 'Sign In'),
                              textAlign: TextAlign.center,
                              style: customFont.copyWith(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _txt('اكتشف ووفر على وجباتك المفضلة', 'Discover and save on dining deals'),
                              textAlign: TextAlign.center,
                              style: customFont.copyWith(
                                fontSize: 13,
                                color: subtitleColor,
                              ),
                            ),
                            const SizedBox(height: 24),

                            if (_errorMessage != null) ...[
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.08),
                                  border: Border.all(color: Colors.red.withValues(alpha: 0.25), width: 1),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline, color: Colors.red, size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _errorMessage!,
                                        style: customFont.copyWith(
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

                            // Glassmorphic Input Form Card
                            AnimatedBuilder(
                              animation: _shakeAnimation,
                              builder: (context, child) {
                                return Transform.translate(
                                  offset: Offset(_shakeAnimation.value, 0),
                                  child: child,
                                );
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: cardColor,
                                  borderRadius: BorderRadius.circular(28),
                                  border: Border.all(color: borderColor, width: 1.5),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    )
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(28),
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                                    child: Padding(
                                      padding: const EdgeInsets.all(24.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          // Email Input
                                          Text(
                                            _txt('البريد الإلكتروني', 'Email Address'),
                                            style: customFont.copyWith(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          TextFormField(
                                            controller: _emailController,
                                            keyboardType: TextInputType.emailAddress,
                                            textInputAction: TextInputAction.next,
                                            textDirection: TextDirection.ltr,
                                            style: GoogleFonts.inter(fontSize: 14, color: textColor),
                                            decoration: InputDecoration(
                                              hintText: 'yourname@domain.com',
                                              hintStyle: GoogleFonts.inter(color: Colors.grey[400], fontSize: 13),
                                              prefixIcon: const Icon(Icons.email_outlined, size: 20, color: brandRed),
                                              filled: true,
                                              fillColor: fieldColor,
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(16),
                                                borderSide: BorderSide.none,
                                              ),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(16),
                                                borderSide: BorderSide(color: borderColor),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(16),
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
                                          const SizedBox(height: 18),

                                          // Password Input
                                          Text(
                                            _txt('كلمة المرور', 'Password'),
                                            style: customFont.copyWith(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          TextFormField(
                                            controller: _passwordController,
                                            obscureText: _obscurePassword,
                                            textInputAction: TextInputAction.done,
                                            textDirection: TextDirection.ltr,
                                            style: GoogleFonts.inter(fontSize: 14, color: textColor),
                                            decoration: InputDecoration(
                                              hintText: '••••••••',
                                              hintStyle: GoogleFonts.inter(color: Colors.grey[400], fontSize: 13),
                                              prefixIcon: const Icon(Icons.lock_outline, size: 20, color: brandRed),
                                              filled: true,
                                              fillColor: fieldColor,
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(16),
                                                borderSide: BorderSide.none,
                                              ),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(16),
                                                borderSide: BorderSide(color: borderColor),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(16),
                                                borderSide: const BorderSide(color: brandRed, width: 1.5),
                                              ),
                                              suffixIcon: IconButton(
                                                icon: Icon(
                                                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                                  color: Colors.grey[500],
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
                                              return null;
                                            },
                                            onFieldSubmitted: (_) => _handleLogin(),
                                          ),
                                          const SizedBox(height: 14),

                                          // Remember Me & Forgot Password
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                children: [
                                                  SizedBox(
                                                    width: 24,
                                                    height: 24,
                                                    child: Checkbox(
                                                      value: _rememberMe,
                                                      activeColor: brandRed,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      onChanged: (bool? value) {
                                                        setState(() {
                                                          _rememberMe = value ?? false;
                                                        });
                                                      },
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  GestureDetector(
                                                    onTap: () {
                                                      setState(() {
                                                        _rememberMe = !_rememberMe;
                                                      });
                                                    },
                                                    child: Text(
                                                      _txt('تذكرني', 'Remember Me'),
                                                      style: customFont.copyWith(fontSize: 12),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              GestureDetector(
                                                onTap: _handleForgotPassword,
                                                child: Text(
                                                  _txt('نسيت كلمة المرور؟', 'Forgot Password?'),
                                                  style: customFont.copyWith(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: brandRed,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 22),

                                          // Login Button & Biometrics Action Row
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Container(
                                                  height: 52,
                                                  decoration: BoxDecoration(
                                                    gradient: const LinearGradient(
                                                      colors: [brandRed, brandAmber],
                                                      begin: Alignment.topLeft,
                                                      end: Alignment.bottomRight,
                                                    ),
                                                    borderRadius: BorderRadius.circular(16),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: brandRed.withValues(alpha: 0.35),
                                                        blurRadius: 12,
                                                        offset: const Offset(0, 5),
                                                      ),
                                                    ],
                                                  ),
                                                  child: ElevatedButton(
                                                    onPressed: (_isLoading || _isSuccess) ? null : _handleLogin,
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: Colors.transparent,
                                                      foregroundColor: Colors.white,
                                                      shadowColor: Colors.transparent,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius: BorderRadius.circular(16),
                                                      ),
                                                    ),
                                                    child: _isSuccess
                                                        ? const Icon(Icons.check_circle_outline, color: Colors.white, size: 24)
                                                        : _isLoading
                                                            ? const SizedBox(
                                                                height: 22,
                                                                width: 22,
                                                                child: CircularProgressIndicator(
                                                                  strokeWidth: 2.5,
                                                                  color: Colors.white,
                                                                ),
                                                              )
                                                            : Text(
                                                                _txt('تسجيل الدخول', 'Sign In'),
                                                                style: customFont.copyWith(
                                                                  fontSize: 15,
                                                                  fontWeight: FontWeight.bold,
                                                                  color: Colors.white,
                                                                ),
                                                              ),
                                                  ),
                                                ),
                                              ),
                                              if (_canUseBiometrics && _hasSavedCredentials) ...[
                                                const SizedBox(width: 12),
                                                Container(
                                                  width: 52,
                                                  height: 52,
                                                  decoration: BoxDecoration(
                                                    color: fieldColor,
                                                    border: Border.all(color: borderColor, width: 1.5),
                                                    borderRadius: BorderRadius.circular(16),
                                                  ),
                                                  child: IconButton(
                                                    icon: Icon(
                                                      Theme.of(context).platform == TargetPlatform.iOS
                                                          ? Icons.face_unlock_rounded
                                                          : Icons.fingerprint,
                                                      color: brandRed,
                                                      size: 26,
                                                    ),
                                                    tooltip: _txt('تسجيل دخول بالبصمة', 'Biometric Sign In'),
                                                    onPressed: (_isLoading || _isSuccess) ? null : _authenticateWithBiometrics,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Or Separator
                            Row(
                              children: [
                                Expanded(child: Divider(color: borderColor.withValues(alpha: 0.5))),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                  child: Text(
                                    _txt('أو تسجيل الدخول عبر', 'Or sign in with'),
                                    style: customFont.copyWith(fontSize: 12, color: subtitleColor),
                                  ),
                                ),
                                Expanded(child: Divider(color: borderColor.withValues(alpha: 0.5))),
                              ],
                            ),
                            const SizedBox(height: 18),

                            // Google Login Button (Premium & styled)
                            OutlinedButton(
                              onPressed: (_isLoading || _isSuccess)
                                  ? null
                                  : () async {
                                      HapticFeedback.lightImpact();
                                      setState(() {
                                        _isLoading = true;
                                        _errorMessage = null;
                                      });
                                      final navigator = Navigator.of(context);
                                      try {
                                        await widget.googleSignInHandler();
                                        if (mounted) navigator.pop();
                                      } catch (e) {
                                        setState(() {
                                          _errorMessage = _txt('فشل تسجيل الدخول عبر Google.', 'Google login failed.');
                                          _isLoading = false;
                                        });
                                        _triggerShake();
                                      }
                                    },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                side: BorderSide(color: borderColor, width: 1.5),
                                backgroundColor: cardColor,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Image.network(
                                    'https://upload.wikimedia.org/wikipedia/commons/c/c1/Google_%22G%22_logo.svg',
                                    height: 18,
                                    width: 18,
                                    errorBuilder: (context, error, stackTrace) =>
                                        const Icon(Icons.g_mobiledata, color: brandRed),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    _txt('تسجيل الدخول عبر Google', 'Sign in with Google'),
                                    style: customFont.copyWith(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Guest Session CTA with limitations badge
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: borderColor.withValues(alpha: 0.3), width: 1),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () {
                                  widget.onCancel();
                                  Navigator.of(context).pop();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.person_outline_rounded, color: brandAmber, size: 20),
                                          const SizedBox(width: 10),
                                          Text(
                                            _txt('المتابعة كزائر', 'Continue as Guest'),
                                            style: customFont.copyWith(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: brandAmber.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          _txt('محدود', 'Limited'),
                                          style: GoogleFonts.cairo(
                                            color: brandAmber,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      )
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),

                            // Register Redirection CTA
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _txt('ليس لديك حساب؟', 'Don\'t have an account?'),
                                  style: customFont.copyWith(fontSize: 13, color: subtitleColor),
                                ),
                                TextButton(
                                  onPressed: () {
                                    HapticFeedback.lightImpact();
                                    final args = ModalRoute.of(context)?.settings.arguments as AuthScreenArgs?;
                                    Navigator.pushReplacementNamed(
                                      context,
                                      '/register',
                                      arguments: args,
                                    );
                                  },
                                  child: Text(
                                    _txt('سجل الآن', 'Sign Up Now'),
                                    style: customFont.copyWith(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: brandRed,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            
                            // Merchant Portal CTA
                            const SizedBox(height: 4),
                            TextButton.icon(
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                Navigator.pop(context, '/admin/login.php');
                              },
                              icon: const Icon(Icons.storefront_rounded, size: 16, color: brandAmber),
                              label: Text(
                                _txt(
                                  'هل أنت شريك تجاري؟ سجل دخولك من بوابة الشركاء',
                                  'Are you a business partner? Log in to the Merchant Portal',
                                ),
                                style: customFont.copyWith(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: subtitleColor,
                                ),
                              ),
                            ),
                            const Divider(height: 24),

                            // Terms & Privacy
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                InkWell(
                                  onTap: () async {
                                    final uri = Uri.parse('${widget.baseUrl}/terms');
                                    if (await canLaunchUrl(uri)) await launchUrl(uri);
                                  },
                                  child: Text(
                                    _txt('الشروط والأحكام', 'Terms of Use'),
                                    style: customFont.copyWith(fontSize: 10, color: subtitleColor),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text('•', style: TextStyle(color: subtitleColor, fontSize: 10)),
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: () async {
                                    final uri = Uri.parse('${widget.baseUrl}/privacy');
                                    if (await canLaunchUrl(uri)) await launchUrl(uri);
                                  },
                                  child: Text(
                                    _txt('سياسة الخصوصية', 'Privacy Policy'),
                                    style: customFont.copyWith(fontSize: 10, color: subtitleColor),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '${_txt("نسخة التطبيق", "App Version")} $_appVersion',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(fontSize: 9, color: subtitleColor.withValues(alpha: 0.6)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

