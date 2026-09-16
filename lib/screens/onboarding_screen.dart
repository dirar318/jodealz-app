import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import 'package:jodeals/theme/app_colors.dart';
import 'package:jodeals/theme/app_radius.dart';
import 'package:jodeals/theme/app_spacing.dart';
import 'package:jodeals/theme/app_typography.dart';
import 'package:jodeals/widgets/app_button.dart';

class OnboardingScreen extends StatefulWidget {
  final Future<bool> Function() onGoogleLogin;
  final VoidCallback onEmailLogin;
  final Future<void> Function() onGuestLogin;

  const OnboardingScreen({
    super.key,
    required this.onGoogleLogin,
    required this.onEmailLogin,
    required this.onGuestLogin,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late VideoPlayerController _videoController;
  bool _isVideoInitialized = false;
  bool _isLoading = false;
  double _contentOpacity = 0.0;

  @override
  void initState() {
    super.initState();
    _initVideoPlayer();

    // Fade-in UI content after a brief delay
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() {
          _contentOpacity = 1.0;
        });
      }
    });
  }

  Future<void> _initVideoPlayer() async {
    _videoController = VideoPlayerController.asset('assets/videos/intro.mp4');
    try {
      await _videoController.initialize();
      await _videoController.setLooping(true);
      await _videoController.setVolume(0.0); // Muted
      await _videoController.play();
      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('OnboardingScreen: Failed to initialize video: $e');
    }
  }

  @override
  void dispose() {
    _videoController.dispose();
    super.dispose();
  }

  // Returns language-specific text
  String _txt(BuildContext context, String ar, String en) {
    try {
      final locale = Localizations.localeOf(context).languageCode;
      return locale == 'en' ? en : ar;
    } catch (_) {
      return ar; // Fallback to Arabic
    }
  }

  bool _isArabic(BuildContext context) {
    try {
      return Localizations.localeOf(context).languageCode == 'ar';
    } catch (_) {
      return true;
    }
  }

  Future<void> _handleAction(Future<void> Function() action) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });

    try {
      await action();
    } catch (e) {
      // Silently ignore user-initiated cancellations (e.g. closing Google Sign-In dialog)
      final errStr = e.toString().toLowerCase();
      final isCancellation = errStr.contains('cancel') ||
          errStr.contains('sign_in_cancelled') ||
          errStr.contains('sign_in_failed') ||
          errStr.contains('network_error') == false && errStr.contains('aborted');

      if (!isCancellation && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _txt(
                context,
                'حدث خطأ أثناء الاتصال. يرجى التحقق من الشبكة والمحاولة مرة أخرى.',
                'A network/connection error occurred. Please check your connection and try again.',
              ),
              style: GoogleFonts.cairo(fontSize: 13, color: Colors.white),
            ),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.radiusMd),
          ),
        );
      }
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
    final bool ar = _isArabic(context);
    final textStyle = ar ? GoogleFonts.cairo() : GoogleFonts.inter();
    final titleStyle = ar ? GoogleFonts.cairo() : GoogleFonts.inter();

    return PopScope(
      canPop: false, // Prevent dismissing onboarding via system back button
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // 1. Full-screen Video Background
            if (_isVideoInitialized)
              SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: _videoController.value.size.width,
                    height: _videoController.value.size.height,
                    child: VideoPlayer(_videoController),
                  ),
                ),
              )
            else
              // Fallback black background with loading while video loads
              const SizedBox.expand(
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Colors.black),
                ),
              ),

            // 2. Premium Dark Gradient Overlay
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.1),
                      Colors.black.withValues(alpha: 0.5),
                      Colors.black.withValues(alpha: 0.85),
                      Colors.black,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.3, 0.7, 1.0],
                  ),
                ),
              ),
            ),

            // 3. Welcome UI & Buttons
            SafeArea(
              child: AnimatedOpacity(
                opacity: _contentOpacity,
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeInOut,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(),

                      // App Logo (from assets)
                      Center(
                        child: Hero(
                          tag: 'app-logo',
                          child: Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha: 0.3),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Image.asset(
                              'assets/images/app-icon.png',
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) => const Icon(
                                Icons.local_offer_rounded,
                                color: AppColors.primary,
                                size: 40,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Welcome Title
                      Text(
                        _txt(context, 'مرحباً بك في جو ديلز', 'Welcome to JoDeals'),
                        style: titleStyle.copyWith(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: ar ? 0 : 0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),

                      // Description Text
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text(
                          _txt(
                            context,
                            'اكتشف أفضل العروض والخصومات الحصرية في الأردن ووفر أكثر كل يوم.',
                            'Discover the best deals and exclusive offers across Jordan. Save more every day.',
                          ),
                          style: textStyle.copyWith(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.8),
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 40),

                      // Google Sign In Button
                      _buildAuthButton(
                        icon: Image.asset(
                          'assets/images/google-logo.png', // Fallback to icon if missing
                          width: 22,
                          height: 22,
                          errorBuilder: (context, error, stack) => const Icon(
                            Icons.g_mobiledata_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        label: _txt(context, 'المتابعة باستخدام Google', 'Continue with Google'),
                        backgroundColor: Colors.white,
                        textColor: const Color(0xFF1E293B),
                        onPressed: () => _handleAction(() async {
                          final success = await widget.onGoogleLogin();
                          if (!success && mounted) {
                            throw Exception('Google Sign-In failed or was cancelled.');
                          }
                        }),
                      ),
                      const SizedBox(height: 14),

                      // Email Button
                      _buildAuthButton(
                        icon: const Icon(Icons.mail_outline_rounded, color: Colors.white, size: 20),
                        label: _txt(context, 'تسجيل الدخول بالبريد الإلكتروني', 'Continue with Email'),
                        backgroundColor: AppColors.primary,
                        textColor: Colors.white,
                        onPressed: widget.onEmailLogin,
                      ),
                      const SizedBox(height: 14),

                      // Guest Button
                      _buildAuthButton(
                        icon: const Icon(Icons.person_outline_rounded, color: AppColors.secondary, size: 20),
                        label: _txt(context, 'المتابعة كزائر', 'Continue as Guest'),
                        backgroundColor: Colors.white.withValues(alpha: 0.15),
                        textColor: Colors.white,
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.25), width: 1.2),
                        onPressed: () => _handleAction(widget.onGuestLogin),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),

            // 4. Loading indicator overlay
            if (_isLoading)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.65),
                  child: Center(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B).withValues(alpha: 0.9),
                          borderRadius: AppRadius.radiusLg,
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 38,
                              height: 38,
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                                strokeWidth: 3.5,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              _txt(context, 'جاري التحميل...', 'Loading...'),
                              style: textStyle.copyWith(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
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

  Widget _buildAuthButton({
    required Widget icon,
    required String label,
    required Color backgroundColor,
    required Color textColor,
    required VoidCallback onPressed,
    BorderSide? borderSide,
  }) {
    final bool ar = _isArabic(context);
    return Container(
      height: 52,
      decoration: BoxDecoration(
        borderRadius: AppRadius.radiusMd,
        boxShadow: backgroundColor == Colors.white
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                )
              ]
            : null,
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: textColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.radiusMd,
            side: borderSide ?? BorderSide.none,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 12),
            Text(
              label,
              style: ar
                  ? GoogleFonts.cairo(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    )
                  : GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

