import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:jodeals/theme/app_colors.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onSplashFinished;

  const SplashScreen({super.key, required this.onSplashFinished});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _breathController;

  late Animation<double> _logoTranslate;
  late Animation<double> _cardOpacity;
  late Animation<double> _cardScale;
  late Animation<double> _bgDecorationsOpacity;
  late Animation<double> _contentOpacity;
  late Animation<double> _contentTranslate;
  late Animation<double> _loaderOpacity;

  late Animation<double> _breathAnimation;

  @override
  void initState() {
    super.initState();

    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _breathAnimation = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(
        parent: _breathController,
        curve: Curves.easeInOut,
      ),
    );

    _logoTranslate = Tween<double>(begin: 0.0, end: -40.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.15, 0.65, curve: Curves.easeInOutCubic),
      ),
    );

    _cardOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.20, 0.60, curve: Curves.easeIn),
      ),
    );

    _cardScale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.20, 0.65, curve: Curves.easeOutBack),
      ),
    );

    _bgDecorationsOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.25, 0.70, curve: Curves.easeOut),
      ),
    );

    _contentOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.45, 0.85, curve: Curves.easeIn),
      ),
    );

    _contentTranslate = Tween<double>(begin: 20.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.45, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    _loaderOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.60, 0.90, curve: Curves.easeIn),
      ),
    );

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _mainController.forward();
      }
    });

    Future.delayed(const Duration(milliseconds: 1300), () {
      if (mounted) {
        widget.onSplashFinished();
      }
    });
  }

  @override
  void dispose() {
    _mainController.dispose();
    _breathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Color brandRed = AppColors.primary;
    const Color brandAmber = AppColors.secondary;

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color backgroundColor = AppColors.bg(isDark);
    final Color textColor = AppColors.textPrimary(isDark);
    final Color subtextColor = AppColors.textSecondary(isDark);
    final Color cardColor = AppColors.card(isDark);

    final Size screenSize = MediaQuery.of(context).size;
    final double screenHeight = screenSize.height;
    final double screenWidth = screenSize.width;

    final bool isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.lightBg,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: backgroundColor,
        body: Stack(
          alignment: Alignment.center,
          children: [
            // 1. Ambient Background Orbs
            AnimatedBuilder(
              animation: _mainController,
              builder: (context, child) {
                return Opacity(
                  opacity: _bgDecorationsOpacity.value,
                  child: child,
                );
              },
              child: AnimatedBuilder(
                animation: _breathAnimation,
                builder: (context, child) {
                  return Stack(
                    children: [
                      Positioned(
                        top: -80 * _breathAnimation.value,
                        right: -80 * _breathAnimation.value,
                        child: Container(
                          width: 300 * _breathAnimation.value,
                          height: 300 * _breathAnimation.value,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: brandRed.withValues(alpha: isDark ? 0.03 : 0.04),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: -100 * _breathAnimation.value,
                        left: -100 * _breathAnimation.value,
                        child: Container(
                          width: 350 * _breathAnimation.value,
                          height: 350 * _breathAnimation.value,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: brandAmber.withValues(alpha: isDark ? 0.03 : 0.04),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            // 2. Central Logo Card
            AnimatedBuilder(
              animation: _mainController,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, _logoTranslate.value),
                  child: Transform.scale(
                    scale: _cardScale.value,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: cardColor.withValues(alpha: _cardOpacity.value),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: _cardOpacity.value > 0.1
                            ? [
                                BoxShadow(
                                  color: isDark
                                      ? Colors.black.withValues(alpha: 0.25 * _cardOpacity.value)
                                      : brandRed.withValues(alpha: 0.12 * _cardOpacity.value),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ]
                            : [],
                      ),
                      alignment: Alignment.center,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Image.asset(
                          'assets/images/logo-mark.webp',
                          width: 70,
                          height: 70,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 70,
                              height: 70,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [brandRed, brandAmber],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: const Icon(
                                Icons.local_fire_department,
                                color: Colors.white,
                                size: 36,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            // 3. Staggered Text and Subtitle
            Positioned(
              top: (screenHeight / 2) + 40,
              child: AnimatedBuilder(
                animation: _mainController,
                builder: (context, child) {
                  return Opacity(
                    opacity: _contentOpacity.value,
                    child: Transform.translate(
                      offset: Offset(0, _contentTranslate.value),
                      child: child,
                    ),
                  );
                },
                child: SizedBox(
                  width: screenWidth * 0.85,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isArabic ? 'جو ديلز' : 'JO-Dealz',
                        style: isArabic
                            ? GoogleFonts.cairo(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                color: textColor,
                                height: 1.3,
                              )
                            : GoogleFonts.poppins(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: textColor,
                                letterSpacing: 0.5,
                              ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isArabic
                            ? 'اكتشف أفضل العروض في الأردن'
                            : 'Discover Jordan\'s Best Deals',
                        textAlign: TextAlign.center,
                        style: isArabic
                            ? GoogleFonts.cairo(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: subtextColor,
                                height: 1.4,
                              )
                            : GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: subtextColor,
                                letterSpacing: 0.2,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 4. Loading Spinner at the bottom
            Positioned(
              bottom: screenHeight * 0.1,
              child: AnimatedBuilder(
                animation: _mainController,
                builder: (context, child) {
                  return Opacity(
                    opacity: _loaderOpacity.value,
                    child: child,
                  );
                },
                child: const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(brandRed),
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
