import 'dart:async';
import 'dart:ui';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:jodeals/screens/splash_screen.dart';
import 'package:jodeals/screens/webview_container.dart';
import 'package:jodeals/screens/profile_screen.dart';
import 'package:jodeals/screens/settings_screen.dart';
import 'package:jodeals/services/deep_link_service.dart';
import 'package:jodeals/services/fcm_service.dart';
import 'package:jodeals/services/app_logger.dart';
import 'package:jodeals/firebase_options.dart';
import 'package:jodeals/screens/auth/login_screen.dart';
import 'package:jodeals/screens/auth/register_screen.dart';
import 'package:jodeals/screens/auth/auth_screen_args.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:jodeals/services/anonymous_tracking_service.dart';
import 'package:jodeals/services/consent_service.dart';
import 'package:jodeals/services/trusted_hosts.dart';
import 'package:jodeals/widgets/privacy_consent_sheet.dart';
import 'package:jodeals/screens/onboarding_screen.dart';
import 'package:jodeals/theme/app_theme.dart';
import 'package:jodeals/theme/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // debugPrint writes to the device log in release builds too; tokens,
  // device IDs and URLs must not end up in logcat / Console.
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // Fonts are bundled in assets/fonts; never download them at runtime.
  GoogleFonts.config.allowRuntimeFetching = false;
  LicenseRegistry.addLicense(() async* {
    for (final family in const ['cairo', 'inter', 'poppins']) {
      final license = await rootBundle.loadString('assets/fonts/OFL-$family.txt');
      yield LicenseEntryWithLineBreaks(['google_fonts'], license);
    }
  });

  // ── Read SharedPreferences once at startup ────────────────────────────────
  // Shared by JoDealzApp (locale) and AppController (URL lang param) so we
  // avoid multiple platform-channel round-trips to the prefs store.
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final String savedLang = prefs.getString('jodeals_app_lang') ?? 'ar';
  final bool isFirstLaunch = prefs.getBool('jodeals_first_launch') ?? true;

  // ── Pre-warm Firebase before runApp so it doesn't block the widget tree ──
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Must be registered before runApp so pushes that arrive while the app is
  // terminated are handled.
  FCMService.registerBackgroundHandler();

  // Tune global image cache limits for smooth scrolling and low memory usage
  PaintingBinding.instance.imageCache.maximumSizeBytes = 50 * 1024 * 1024; // 50MB max RAM image cache
  PaintingBinding.instance.imageCache.maximumSize = 100; // 100 decoded images max in RAM

  // Enforce portrait orientation (fire-and-forget, does not need to be awaited)
  unawaited(SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]));

  // ── Defer heavy background services until after the first frame ───────────
  // This keeps startup fast: Firebase + prefs read are the only blocking work
  // above. Everything else runs after the UI is visible.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // Wait 2 s so the WebView has a head-start before competing for I/O
    Future.delayed(const Duration(seconds: 2), () {
      AnonymousTrackingService().initialize();
      AppLogger().init(baseUrl: 'https://jodealz.online');
    });
  });

  // Crash reports (symbolicated via uploaded R8 mappings / dSYMs). Disabled
  // in debug so development crashes don't pollute the dashboard.
  unawaited(FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode));

  // Capture global Flutter framework exceptions
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    AppLogger().logFatal(
      'Global Flutter exception',
      error: details.exception,
      stack: details.stack,
      file: details.library,
    );
    AnonymousTrackingService().trackCrash();
  };

  // Capture global asynchronous platform exceptions
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    AppLogger().logFatal(
      'Global asynchronous exception',
      error: error,
      stack: stack,
    );
    AnonymousTrackingService().trackCrash();
    return true;
  };

  runApp(JoDealzApp(
    key: JoDealzApp.appKey,
    initialLang: savedLang,
    isFirstLaunch: isFirstLaunch,
  ));
}

class JoDealzApp extends StatefulWidget {
  const JoDealzApp({
    super.key,
    required this.initialLang,
    required this.isFirstLaunch,
  });

  final String initialLang;
  final bool isFirstLaunch;

  /// Global key so that SettingsScreen can trigger a locale change app-wide.
  // ignore: library_private_types_in_public_api
  static final GlobalKey<_JoDealzAppState> appKey = GlobalKey<_JoDealzAppState>();

  /// Call this from SettingsScreen after saving a new language to SharedPreferences.
  static void setLocale(String langCode) {
    appKey.currentState?._applyLocale(langCode);
  }

  @override
  State<JoDealzApp> createState() => _JoDealzAppState();
}

class _JoDealzAppState extends State<JoDealzApp> {
  late Locale _locale;

  @override
  void initState() {
    super.initState();
    // Use the value already read in main() — no extra SharedPreferences call
    _locale = (widget.initialLang == 'en') ? const Locale('en') : const Locale('ar');
  }

  void _applyLocale(String langCode) {
    final newLocale = (langCode == 'en') ? const Locale('en') : const Locale('ar');
    if (mounted && _locale != newLocale) {
      setState(() {
        _locale = newLocale;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JO-Dealz',
      debugShowCheckedModeBanner: false,
      // ── Locale & RTL/LTR ────────────────────────────────────────────────────
      locale: _locale,
      supportedLocales: const [
        Locale('ar'), // Arabic (RTL) – default
        Locale('en'), // English (LTR)
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // ── Themes ──────────────────────────────────────────────────────────────
      theme: AppTheme.lightTheme(_locale.languageCode),
      themeMode: ThemeMode.light,
      // ── Routes ──────────────────────────────────────────────────────────────
      home: AppController(
        initialLang: widget.initialLang,
        isFirstLaunch: widget.isFirstLaunch,
      ),
      onGenerateRoute: (settings) {
        if (settings.name == '/login') {
          final args = settings.arguments as AuthScreenArgs?;
          return _createFadeSlideRoute(
            LoginScreen(
              baseUrl: args?.baseUrl ?? 'https://jodealz.online',
              onLoginSuccess: args?.onSuccess ?? (token) async {},
              onCancel: args?.onCancel ?? () => Navigator.pop(context),
              googleSignInHandler: args?.googleSignInHandler ?? () async {},
              appleSignInHandler: args?.appleSignInHandler,
              guestId: args?.guestId,
            ),
            settings,
          );
        }
        if (settings.name == '/register') {
          final args = settings.arguments as AuthScreenArgs?;
          return _createFadeSlideRoute(
            RegisterScreen(
              baseUrl: args?.baseUrl ?? 'https://jodealz.online',
              onRegisterSuccess: args?.onSuccess ?? (token) async {},
              onCancel: args?.onCancel ?? () => Navigator.pop(context),
              guestId: args?.guestId,
            ),
            settings,
          );
        }
        if (settings.name == '/profile') {
          final args = settings.arguments as Map<String, dynamic>?;
          return _createFadeSlideRoute(
            ProfileScreen(
              baseUrl: args?['baseUrl'] ?? 'https://jodealz.online',
              onLogout: args?['onLogout'] ?? () {},
              onAccountDeleted: args?['onAccountDeleted'],
            ),
            settings,
          );
        }
        if (settings.name == '/settings') {
          final args = settings.arguments as Map<String, dynamic>?;
          return _createFadeSlideRoute(
            SettingsScreen(
              baseUrl: args?['baseUrl'] ?? 'https://jodealz.online',
            ),
            settings,
          );
        }
        return null;
      },
      onUnknownRoute: (settings) {
        return _createFadeSlideRoute(
          AppController(
            initialLang: widget.initialLang,
            isFirstLaunch: widget.isFirstLaunch,
          ),
          settings,
        );
      },
    );
  }


  PageRouteBuilder _createFadeSlideRoute(Widget page, RouteSettings settings) {
    return PageRouteBuilder(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(0.0, 0.08); // Slight elegant slide up
        const end = Offset.zero;
        final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: Curves.easeInOut));
        final offsetAnimation = animation.drive(tween);
        final fadeAnimation = animation.drive(Tween<double>(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)));

        return FadeTransition(
          opacity: fadeAnimation,
          child: SlideTransition(
            position: offsetAnimation,
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }
}



class AppController extends StatefulWidget {
  const AppController({
    super.key,
    required this.initialLang,
    required this.isFirstLaunch,
  });

  final String initialLang;
  final bool isFirstLaunch;

  @override
  State<AppController> createState() => _AppControllerState();
}

class _AppControllerState extends State<AppController> {
  bool _showSplash = true;
  double _splashOpacity = 1.0;
  bool _logoAnimationFinished = false;
  bool _pageLoaded = false;
  bool _hasTimeout = false;
  bool _showOnboarding = false;
  String _targetUrl = 'https://jodealz.online?lang=ar&app=1';
  final GlobalKey<WebViewContainerState> _webViewKey = GlobalKey<WebViewContainerState>();
  RemoteMessage? _foregroundNotification;
  Timer? _foregroundDismissTimer;

  bool _isLangLoaded = false;

  @override
  void dispose() {
    _foregroundDismissTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Use values pre-loaded in main() — no SharedPreferences calls needed here
    _showOnboarding = widget.isFirstLaunch;
    _targetUrl = 'https://jodealz.online?lang=${widget.initialLang}&app=1';
    _isLangLoaded = true;
    _initApp();
  }

  Future<void> _initApp() async {
    _initAppFeatures();

    // Set a maximum splash timeout (2 s) to prevent getting stuck if the page
    // is slow to respond
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && !_pageLoaded && !_hasTimeout) {
        setState(() {
          _hasTimeout = true;
        });
        _tryDismissSplash();
      }
    });
  }



  void _handleNavigation(String url) {
    // Deep links and push payloads are untrusted input: only JO-Dealz URLs are
    // loaded in the app WebView.
    final String target = TrustedHosts.sanitize(url);
    if (_webViewKey.currentState != null) {
      _webViewKey.currentState?.loadUrl(target);
    } else {
      setState(() {
        _targetUrl = target;
      });
    }
  }

  Future<void> _initAppFeatures() async {
    // 1. Initialize Deep Linking listener immediately (non-blocking)
    DeepLinkService.initialize(onLinkReceived: _handleNavigation);

    // 2. Firebase is already initialized in main() — skip initializeApp here.
    //    Delay FCM setup until after page load so the WebView gets full I/O
    //    bandwidth. On first launch the notification permission is requested
    //    only after onboarding, so the system prompt has context.
    Future.delayed(const Duration(seconds: 4), () async {
      if (!mounted) return;
      try {
        await FCMService.initialize(
          requestPermission: !_showOnboarding,
          onNotificationClicked: _handleNavigation,
          onForegroundMessage: (RemoteMessage message) {
            try {
              FlutterRingtonePlayer().playNotification();
            } catch (e) {
              debugPrint('AppController: Error playing notification sound: $e');
            }
            if (mounted) {
              setState(() {
                _foregroundNotification = message;
              });

              // Auto dismiss after 6 seconds
              _foregroundDismissTimer?.cancel();
              _foregroundDismissTimer = Timer(const Duration(seconds: 6), () {
                if (mounted && _foregroundNotification == message) {
                  setState(() {
                    _foregroundNotification = null;
                  });
                }
              });
            }
          },
        );
      } catch (e) {
        debugPrint('Firebase: FCM initialization failed: $e');
      }
    });
  }

  void _onLogoAnimationFinished() {
    if (mounted) {
      setState(() {
        _logoAnimationFinished = true;
      });
      _tryDismissSplash();
    }
  }

  void _onPageLoaded() {
    if (mounted && !_pageLoaded) {
      setState(() {
        _pageLoaded = true;
      });
      _tryDismissSplash();
    }
  }

  void _tryDismissSplash() {
    if (_logoAnimationFinished && (_pageLoaded || _hasTimeout)) {
      if (mounted && _showSplash && _splashOpacity > 0.0) {
        setState(() {
          _splashOpacity = 0.0;
        });
        // Remove SplashScreen widget completely from the tree after the fade animation (500ms)
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            setState(() {
              _showSplash = false;
            });
            if (!_showOnboarding) _askAnalyticsConsentIfNeeded();
          }
        });
      }
    }
  }

  /// Called once the user leaves onboarding (any sign-in method or guest).
  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('jodeals_first_launch', false);
    if (mounted) {
      setState(() {
        _showOnboarding = false;
      });
    }
    await _askAnalyticsConsentIfNeeded();
    await FCMService.requestPermission();
  }

  bool _consentPromptShown = false;

  Future<void> _askAnalyticsConsentIfNeeded() async {
    if (_consentPromptShown || !mounted) return;
    if (await ConsentService.analyticsChoice() != null) return;
    _consentPromptShown = true;
    if (!mounted) return;
    final bool allowed = await showPrivacyConsentSheet(context);
    await ConsentService.setAnalytics(allowed);
    AnonymousTrackingService().onConsentChanged();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        // The WebViewContainer is always active and loading in the background
        if (_isLangLoaded)
          WebViewContainer(
            key: _webViewKey,
            initialUrl: _targetUrl,
            onPageLoaded: _onPageLoaded,
          )
        else
          Container(
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          ),

        // Onboarding overlay after splash finishes
        if (!_showSplash && _showOnboarding)
          OnboardingScreen(
            onGoogleLogin: () async {
              final success = await _webViewKey.currentState?.handleGoogleSignIn() ?? false;
              if (success) await _completeOnboarding();
              return success;
            },
            onAppleLogin: () async {
              final success = await _webViewKey.currentState?.handleAppleSignIn() ?? false;
              if (success) await _completeOnboarding();
              return success;
            },
            onEmailLogin: () async {
              final navigator = Navigator.of(context);
              final guestId = await _webViewKey.currentState?.getGuestId();
              if (!mounted) return;
              navigator.pushNamed(
                '/login',
                arguments: AuthScreenArgs(
                  baseUrl: TrustedHosts.baseUrl,
                  onSuccess: (token) async {
                    await _webViewKey.currentState?.syncSessionToWebView(token);
                    await _webViewKey.currentState?.registerDeviceWithBackend(token);
                    await _completeOnboarding();
                  },
                  onCancel: () {
                    // Stay on onboarding screen
                  },
                  googleSignInHandler: () async {
                    final success = await _webViewKey.currentState?.handleGoogleSignIn() ?? false;
                    if (success) await _completeOnboarding();
                  },
                  appleSignInHandler: () async {
                    final success = await _webViewKey.currentState?.handleAppleSignIn() ?? false;
                    if (success) await _completeOnboarding();
                    return success;
                  },
                  guestId: guestId,
                ),
              );
            },
            onGuestLogin: () async {
              await _webViewKey.currentState?.registerDeviceWithBackend(null);
              await _completeOnboarding();
            },
          ),

        // SplashScreen overlay that fades out
        if (_showSplash)
          IgnorePointer(
            ignoring: _splashOpacity == 0.0,
            child: AnimatedOpacity(
              opacity: _splashOpacity,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
              child: SplashScreen(onSplashFinished: _onLogoAnimationFinished),
            ),
          ),

        // Branded sliding foreground push notification banner
        if (_foregroundNotification != null)
          _buildForegroundNotificationBanner(isDark),
      ],
    );
  }

  Widget _buildForegroundNotificationBanner(bool isDark) {
    final notification = _foregroundNotification?.notification;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final title = notification?.title ?? (isArabic ? 'إشعار' : 'Notification');
    final body = notification?.body ?? '';
    final imageUrl = _foregroundNotification?.data['image_url'];
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 16,
      right: 16,
      child: GestureDetector(
        onTap: () {
          if (_foregroundNotification != null) {
            FCMService.handleMessagePayload(_foregroundNotification!, _handleNavigation);
          }
          setState(() {
            _foregroundNotification = null;
          });
        },
        onPanUpdate: (details) {
          if (details.delta.dy < -5) {
            setState(() {
              _foregroundNotification = null;
            });
          }
        },
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: -100.0, end: 0.0),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutBack,
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, value),
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkCard.withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.local_offer,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                fontFamily: isArabic ? 'Cairo' : 'Inter',
                                color: textColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              body,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                fontFamily: 'Inter',
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (imageUrl != null && imageUrl.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            imageUrl,
                            width: 45,
                            height: 45,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
