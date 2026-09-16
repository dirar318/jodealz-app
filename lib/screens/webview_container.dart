import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:jodeals/screens/error_screen.dart';
import 'package:webview_refresher/webview_refresher.dart';
import 'package:jodeals/services/fcm_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:jodeals/screens/auth/auth_screen_args.dart';
import 'package:jodeals/widgets/skeleton_loader.dart';
import 'package:jodeals/services/cache_service.dart';
import 'package:jodeals/services/anonymous_tracking_service.dart';
import 'package:jodeals/theme/app_colors.dart';
import 'package:jodeals/theme/app_radius.dart';
import 'package:jodeals/theme/app_spacing.dart';
import 'package:jodeals/theme/app_typography.dart';

class WebViewContainer extends StatefulWidget {
  final String initialUrl;
  final VoidCallback? onPageLoaded;

  const WebViewContainer({
    super.key,
    this.initialUrl = 'https://jodealz.online?app=1',
    this.onPageLoaded,
  });

  @override
  State<WebViewContainer> createState() => WebViewContainerState();
}

class WebViewContainerState extends State<WebViewContainer> {
  late final WebViewController _controller;
  final ValueNotifier<double> _progressNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<bool> _loadingNotifier = ValueNotifier<bool>(true);
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  Timer? _loadingTimeoutTimer;
  Timer? _slowConnectionTimer;
  int _retryCount = 0;
  static const int _maxRetries = 3;
  bool _isOffline = false;
  bool _isSlowConnection = false;
  String _currentLoadingUrl = '';
  bool _canGoBack = false;
  bool _isRetrying = false;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  DateTime? _pageLoadStartTime;
  bool _isArabic = true; // Cached locale — updated from SharedPreferences
  DateTime? _lastCacheSync; // Guards _backgroundCacheData to max once per 2 min
  int _deviceRegRetryCount = 0; // Tracks device registration retry attempts
  static const int _maxDeviceRegRetries = 2;
  bool _isRegisteringDevice = false; // Prevents concurrent device registration calls

  String get _baseUrl {
    final Uri baseUri = Uri.parse(widget.initialUrl);
    return '${baseUri.scheme}://${baseUri.host}${baseUri.hasPort ? ":${baseUri.port}" : ""}';
  }

  @override
  void dispose() {
    FCMService.tokenNotifier.removeListener(_onFcmTokenChanged);
    _loadingTimeoutTimer?.cancel();
    _slowConnectionTimer?.cancel();
    _connectivitySubscription?.cancel();
    _progressNotifier.dispose();
    _loadingNotifier.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    FCMService.baseUrl = _baseUrl;
    FCMService.tokenNotifier.addListener(_onFcmTokenChanged);
    _loadLanguagePreference();
    _checkConnectivity();
    _initWebViewController();
    // Defer Google Sign-In initialization — it hits a platform channel and is
    // only needed when the user taps "Sign in with Google". Delaying it keeps
    // initState lightweight and avoids competing with the WebView's first load.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 3), _initGoogleSignIn);
    });

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((ConnectivityResult result) {
      if (result == ConnectivityResult.none) {
        if (!_isOffline) {
          setState(() {
            _isOffline = true;
          });
        }
      } else {
        if (_isOffline) {
          setState(() {
            _isOffline = false;
            _retryCount = 0;
            _isRetrying = false;
          });
          _controller.reload();
        }
      }
    });
  }

  Future<void> _checkConnectivity() async {
    var result = await Connectivity().checkConnectivity();
    if (result == ConnectivityResult.none) {
      setState(() {
        _isOffline = true;
      });
    }
  }

  Future<void> _loadLanguagePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lang = prefs.getString('jodeals_app_lang') ?? 'ar';
      _isArabic = lang == 'ar';
    } catch (_) {}
  }

  /// Returns [ar] when the app is in Arabic mode, otherwise [en].
  String _txt(String ar, String en) => _isArabic ? ar : en;

  void _onFcmTokenChanged() {
    final token = FCMService.tokenNotifier.value;
    if (token != null && token.isNotEmpty) {
      debugPrint('WebViewContainer: FCM token is now available, syncing auth and registering device...');
      _syncAuthAndRegisterDevice();
    }
  }

  void _handleConnectionError(String reason) {
    _loadingTimeoutTimer?.cancel();
    if (_retryCount < _maxRetries) {
      _retryCount++;
      debugPrint('WebViewContainer: Connection error ($reason). Retrying $_retryCount/$_maxRetries in ${_retryCount * 2}s...');
      setState(() {
        _isRetrying = true;
      });
      Future.delayed(Duration(seconds: _retryCount * 2), () {
        if (mounted && _isRetrying) {
          _controller.reload();
        }
      });
    } else {
      debugPrint('WebViewContainer: Max retries reached. Showing error screen.');
      setState(() {
        _isOffline = true;
        _isRetrying = false;
      });
      widget.onPageLoaded?.call();
    }
  }

  void _initWebViewController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF8FAFC))
      ..setUserAgent(
        Platform.isAndroid
            ? "Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36 JoDealsApp/1.0"
            : "Mozilla/5.0 (iPhone; CPU iPhone OS 16_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.5 Mobile/15E148 Safari/604.1 JoDealsApp/1.0",
      );

    if (_controller.platform is AndroidWebViewController) {
      final androidController = _controller.platform as AndroidWebViewController;
      androidController.setMediaPlaybackRequiresUserGesture(false);
    }

    _controller.setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            _progressNotifier.value = progress / 100.0;
            _loadingNotifier.value = progress < 100;
          },
          onPageStarted: (String url) {
            _pageLoadStartTime = DateTime.now();
            _loadingNotifier.value = true;
            _updateBackState();
            if (mounted) {
              setState(() {
                _currentLoadingUrl = url;
                _isSlowConnection = false;
              });
            }

            _loadingTimeoutTimer?.cancel();
            _loadingTimeoutTimer = Timer(const Duration(seconds: 15), () {
              if (mounted && _loadingNotifier.value) {
                _handleConnectionError('Timeout (15 seconds exceeded)');
              }
            });

            _slowConnectionTimer?.cancel();
            _slowConnectionTimer = Timer(const Duration(seconds: 6), () {
              if (mounted && _loadingNotifier.value && !_isOffline) {
                setState(() {
                  _isSlowConnection = true;
                });
              }
            });
          },
          onPageFinished: (String url) async {
            if (_pageLoadStartTime != null) {
              final double duration = DateTime.now().difference(_pageLoadStartTime!).inMilliseconds / 1000.0;
              AnonymousTrackingService().trackLoadTime(duration);
              _pageLoadStartTime = null;
            }
            _trackUrlActivity(url);

            _loadingTimeoutTimer?.cancel();
            _slowConnectionTimer?.cancel();
            _loadingNotifier.value = false;
            _progressNotifier.value = 0.0;
            _retryCount = 0;
            if (mounted) {
              setState(() {
                _isRetrying = false;
                _isSlowConnection = false;
              });
            }
            _updateBackState();

            try {
              await _controller.runJavaScript('''
                (function() {
                  var meta = document.querySelector('meta[name="viewport"]');
                  if (meta) {
                    meta.setAttribute('content', 'width=device-width, initial-scale=1.0, viewport-fit=cover');
                  } else {
                    var newMeta = document.createElement('meta');
                    newMeta.name = 'viewport';
                    newMeta.content = 'width=device-width, initial-scale=1.0, viewport-fit=cover';
                    document.getElementsByTagName('head')[0].appendChild(newMeta);
                  }

                  // Force Light Mode across website inside WebView
                  document.documentElement.classList.remove('dark');
                  document.documentElement.setAttribute('data-theme', 'light');
                  document.body && document.body.classList.remove('dark');
                  if (typeof localStorage !== 'undefined') {
                    localStorage.removeItem('theme');
                    localStorage.setItem('theme', 'light');
                  }
                })();
              ''');
            } catch (e) {
              debugPrint('WebViewContainer: Error setting viewport / light theme via JS: $e');
            }

            try {
              final prefs = await SharedPreferences.getInstance();
              final savedToken = prefs.getString('jodeals_auth_token');
              if (savedToken != null && savedToken.isNotEmpty) {
                await _controller.runJavaScript(
                  "if (localStorage.getItem('jodeals_auth_token') !== '$savedToken') { "
                  "  localStorage.setItem('jodeals_auth_token', '$savedToken'); "
                  "}"
                );
                
                final String secureFlag = _baseUrl.startsWith('https') ? '; Secure' : '';
                String domainParam = '';
                final Uri targetUri = Uri.parse(_baseUrl);
                final String host = targetUri.host;
                if (!host.contains('localhost') && !host.contains('127.0.0.1')) {
                  String domain = host;
                  if (domain.startsWith('www.')) {
                    domain = domain.substring(4);
                  }
                  domainParam = '; domain=.$domain';
                }
                await _controller.runJavaScript(
                  "document.cookie = 'remember_token=$savedToken; path=/; max-age=2592000$secureFlag$domainParam';"
                );

                await _syncRememberTokenCookie(savedToken);
              }
            } catch (e) {
              debugPrint('WebViewContainer: Error in post-load session sync: $e');
            }

            try {
              final Object langObj = await _controller.runJavaScriptReturningResult("localStorage.getItem('jodeals_lang') || ''");
              final String langStr = langObj.toString().replaceAll('"', '').trim();
              if (langStr == 'en' || langStr == 'ar') {
                final prefs = await SharedPreferences.getInstance();
                final currentSavedLang = prefs.getString('jodeals_app_lang');
                if (currentSavedLang != langStr) {
                  await prefs.setString('jodeals_app_lang', langStr);
                  _isArabic = langStr == 'ar'; // keep in-memory locale in sync
                  debugPrint('WebViewContainer: Saved language preference from localStorage: $langStr');
                }
              }
            } catch (e) {
              debugPrint('WebViewContainer: Error reading/saving language preference: $e');
            }

            _syncAuthAndRegisterDevice();

            // BUG-016: Guard cache sync to at most once per 2 minutes
            final now = DateTime.now();
            if (_lastCacheSync == null || now.difference(_lastCacheSync!).inMinutes >= 2) {
              _lastCacheSync = now;
              Future.delayed(const Duration(seconds: 1), () {
                if (mounted) {
                  _backgroundCacheData();
                }
              });
            }

            widget.onPageLoaded?.call();
          },
          onWebResourceError: (WebResourceError error) {
            _slowConnectionTimer?.cancel();
            if (error.errorType == WebResourceErrorType.hostLookup ||
                error.errorType == WebResourceErrorType.connect ||
                error.errorType == WebResourceErrorType.timeout) {
              _handleConnectionError(error.description);
            }
          },
          onNavigationRequest: (NavigationRequest request) async {
            final String url = request.url;

            if (url.contains('/auth-google.php') || url.contains('jodeals://auth-google') || url.contains('jodeals:auth-google')) {
              handleGoogleSignIn();
              return NavigationDecision.prevent;
            }

            final bool isLoginRequest = !url.contains('/admin/') && (
                                         url.contains('/login.php') || 
                                         url.contains('/login?') || 
                                         url.endsWith('/login') || 
                                         url.endsWith('/login/') || 
                                         url.contains('jodeals://login') ||
                                         url.contains('jodeals:login')
                                        );

            if (isLoginRequest) {
              _showNativeLogin(interceptedUrl: url);
              return NavigationDecision.prevent;
            }

            final bool isRegisterRequest = !url.contains('/admin/') && 
                                           !url.contains('merchant-register') && (
                                             url.contains('/register.php') || 
                                             url.contains('/register?') || 
                                             url.endsWith('/register') || 
                                             url.endsWith('/register/') || 
                                             url.contains('jodeals://register') ||
                                             url.contains('jodeals:register')
                                           );

            if (isRegisterRequest) {
              _showNativeRegister(interceptedUrl: url);
              return NavigationDecision.prevent;
            }

            final bool isLogoutRequest = url.contains('/logout.php') || 
                                         url.contains('/logout?') || 
                                         url.endsWith('/logout') || 
                                         url.endsWith('/logout/') || 
                                         url.contains('jodeals://logout') ||
                                         url.contains('jodeals:logout');

            if (isLogoutRequest) {
              handleNativeLogout();
              return NavigationDecision.prevent;
            }

            // Intercept Profile page and load native Profile screen instead
            final bool isProfileRequest = url.contains('/profile.php') || 
                                          url.contains('jodeals://profile') ||
                                          url.contains('jodeals:profile');

            if (isProfileRequest) {
              _showNativeProfile();
              return NavigationDecision.prevent;
            }

            // Intercept Settings page and load native Settings screen instead
            final bool isSettingsRequest = url.contains('/settings.php') || 
                                           url.contains('jodeals://settings') ||
                                           url.contains('jodeals:settings');

            if (isSettingsRequest) {
              _showNativeSettings();
              return NavigationDecision.prevent;
            }

            if (!url.startsWith('http://') && !url.startsWith('https://')) {
              await _launchExternalUrl(url);
              return NavigationDecision.prevent;
            }

            if (url.contains('wa.me') ||
                url.contains('api.whatsapp.com') ||
                url.contains('play.google.com') ||
                url.contains('apps.apple.com') ||
                url.contains('maps.google.com') ||
                url.contains('maps.apple.com')) {
              await _launchExternalUrl(url);
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      );

    if (_controller.platform is WebKitWebViewController) {
      (_controller.platform as WebKitWebViewController)
          .setAllowsBackForwardNavigationGestures(true);
    }

    if (_controller.platform is AndroidWebViewController) {
      final androidController = _controller.platform as AndroidWebViewController;
      androidController.setMixedContentMode(MixedContentMode.alwaysAllow);

      androidController.setGeolocationPermissionsPromptCallbacks(
        onShowPrompt: (request) async {
          final bool isGranted = await _requestLocationPermission();
          return GeolocationPermissionsResponse(
            allow: isGranted,
            retain: true,
          );
        },
      );

      androidController.setOnShowFileSelector((FileSelectorParams params) async {
        return await _handleFileSelection(params);
      });
    }

    _controller.loadRequest(Uri.parse(widget.initialUrl));
  }

  Future<void> _launchExternalUrl(String url) async {
    final Uri uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        debugPrint('Could not launch external URL: $url');
      }
    } catch (e) {
      debugPrint('Error launching URL: $e');
    }
  }

  void _updateBackState() async {
    bool canBack = await _controller.canGoBack();
    if (mounted) {
      setState(() {
        _canGoBack = canBack;
      });
    }
  }

  void loadUrl(String url) {
    if (mounted) {
      setState(() {
        _isOffline = false;
      });
      _controller.loadRequest(Uri.parse(url));
    }
  }

  Future<void> syncAuthSession(String token) async {
    await syncSessionToWebView(token);
    await registerDeviceWithBackend(token);
  }

  void _showNativeProfile() {
    Navigator.pushNamed(
      context,
      '/profile',
      arguments: {
        'baseUrl': _baseUrl,
        'onLogout': () {
          handleNativeLogout();
        },
      },
    ).then((_) {
      _loadSavedLanguageOrReload();
    });
  }

  void _showNativeSettings() {
    Navigator.pushNamed(
      context,
      '/settings',
      arguments: {
        'baseUrl': _baseUrl,
      },
    ).then((_) {
      _loadSavedLanguageOrReload();
    });
  }

  Future<void> _loadSavedLanguageOrReload() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLang = prefs.getString('jodeals_app_lang') ?? 'ar';
      final target = '$_baseUrl?lang=$savedLang&app=1';
      _controller.loadRequest(Uri.parse(target));
    } catch (e) {
      debugPrint('WebViewContainer: Error in post-setting reload: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color brandRed = AppColors.primary;
    const Color brandAmber = AppColors.secondary;

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color scaffoldBgColor = AppColors.bg(isDark);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.lightBg,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: PopScope(
        canPop: !_canGoBack,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          if (_canGoBack) {
            await _controller.goBack();
            _updateBackState();
          }
        },
        child: Scaffold(
          backgroundColor: scaffoldBgColor,
          body: SafeArea(
            top: false,
            bottom: true,
            child: Stack(
              children: [
                WebViewWidget(
                  controller: _controller,
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: _loadingNotifier,
                  builder: (context, isLoading, child) {
                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: isLoading && !_isOffline
                          ? Container(
                              color: scaffoldBgColor,
                              child: _getSkeletonWidget(),
                            )
                          : const SizedBox.shrink(),
                    );
                  },
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 3.5,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _loadingNotifier,
                    builder: (context, isLoading, child) {
                      if (!isLoading) return const SizedBox.shrink();
                      return ValueListenableBuilder<double>(
                        valueListenable: _progressNotifier,
                        builder: (context, progress, child) {
                          if (progress <= 0.0) return const SizedBox.shrink();
                          return LinearGradientProgressIndicator(
                            value: progress,
                            color1: brandRed,
                            color2: brandAmber,
                          );
                        },
                      );
                    },
                  ),
                ),
                if (_isSlowConnection && !_isOffline)
                  Positioned(
                    bottom: 24,
                    left: 20,
                    right: 20,
                    child: _buildNetworkBanner(
                      icon: Icons.speed_outlined,
                      message: _txt('الاتصال بطيء', 'Slow connection detected'),
                      color: brandAmber,
                      showRetry: true,
                    ),
                  ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _isOffline
                      ? ErrorScreen(
                          key: const ValueKey('error_screen'),
                          baseUrl: _baseUrl,
                          isArabic: _isArabic,
                          onRetry: () async {
                            final scaffoldMessenger = ScaffoldMessenger.of(context);
                            var result = await Connectivity().checkConnectivity();
                            if (result != ConnectivityResult.none) {
                              setState(() {
                                _isOffline = false;
                              });
                              _controller.reload();
                            } else {
                              scaffoldMessenger.showSnackBar(
                                SnackBar(
                                  content: Text(_txt(
                                    'لا يزال غير متصل. يرجى التحقق من الاتصال.',
                                    'Still offline. Please check your connection.',
                                  )),
                                  backgroundColor: brandRed,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _getSkeletonWidget() {
    if (_currentLoadingUrl.isEmpty) {
      return const HomeSkeleton();
    }
    try {
      final uri = Uri.parse(_currentLoadingUrl);
      final path = uri.path.toLowerCase();
      if (path.contains('categories.php') ||
          path.contains('deals.php') ||
          path.contains('hot-deals.php') ||
          path.contains('search.php')) {
        return const DealsSkeleton();
      } else if (path.contains('profile.php')) {
        return const ProfileSkeleton();
      }
    } catch (_) {}
    return const HomeSkeleton();
  }

  Widget _buildNetworkBanner({
    required IconData icon,
    required String message,
    required Color color,
    bool showRetry = false,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkCard.withValues(alpha: 0.95)
            : Colors.white.withValues(alpha: 0.95),
        borderRadius: AppRadius.radiusMd,
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                fontFamily: _isArabic ? 'Cairo' : 'Inter',
              ),
            ),
          ),
          if (showRetry) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                _controller.reload();
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                backgroundColor: color.withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.radiusSm,
                ),
              ),
              child: Text(
                _txt('إعادة المحاولة', 'Retry'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _syncRememberTokenCookie(String token) async {
    try {
      final Uri targetUri = Uri.parse(_baseUrl);
      final WebViewCookieManager cookieManager = WebViewCookieManager();
      
      final String host = targetUri.host;
      final List<String> domainsToSet = [host];
      
      if (!host.contains('localhost') && !host.contains('127.0.0.1')) {
        if (!host.startsWith('.')) {
          domainsToSet.add('.$host');
        }
        if (host.startsWith('www.')) {
          final rootDomain = host.substring(4);
          domainsToSet.add(rootDomain);
          domainsToSet.add('.$rootDomain');
        } else {
          final wwwDomain = 'www.$host';
          domainsToSet.add(wwwDomain);
          domainsToSet.add('.$wwwDomain');
        }
      }
      
      for (final domain in domainsToSet) {
        await cookieManager.setCookie(
          WebViewCookie(
            name: 'remember_token',
            value: token,
            domain: domain,
            path: '/',
          ),
        );
      }
      debugPrint('WebViewContainer: Synced remember_token cookie to domains: $domainsToSet');
    } catch (e) {
      debugPrint('WebViewContainer: Failed to sync remember_token cookie: $e');
    }
  }

  Future<void> syncSessionToWebView(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('jodeals_auth_token', token);

      await _syncRememberTokenCookie(token);

      await _controller.runJavaScript(
        "localStorage.setItem('jodeals_auth_token', '$token');"
      );

      debugPrint('WebViewContainer: Successfully synced session to WebView.');
    } catch (e) {
      debugPrint('WebViewContainer: Error syncing session to WebView: $e');
    }
  }

  Future<String?> getGuestId() async {
    try {
      final Object cookieObj = await _controller.runJavaScriptReturningResult("document.cookie");
      final String cookieString = cookieObj.toString();
      final RegExp regExp = RegExp(r'guest_id=([^;]+)');
      final match = regExp.firstMatch(cookieString);
      if (match != null) {
        String guestId = match.group(1)!;
        if (guestId.startsWith('"') && guestId.endsWith('"')) {
          guestId = guestId.substring(1, guestId.length - 1);
        }
        return guestId;
      }
    } catch (e) {
      debugPrint('WebViewContainer: Failed to get guest_id from cookie: $e');
    }
    return null;
  }

  void _showNativeLogin({String? interceptedUrl}) async {
    final String? guestId = await getGuestId();
    if (!mounted) return;

    String redirectUrl = '$_baseUrl/profile.php';
    if (interceptedUrl != null) {
      try {
        final uri = Uri.parse(interceptedUrl);
        final redirectParam = uri.queryParameters['redirect'];
        if (redirectParam != null && redirectParam.isNotEmpty) {
          if (redirectParam.startsWith('/')) {
            redirectUrl = '$_baseUrl$redirectParam';
          } else if (!redirectParam.startsWith('http')) {
            redirectUrl = '$_baseUrl/$redirectParam';
          } else {
            try {
              final redirectUri = Uri.parse(redirectParam);
              final String pathAndQuery = '${redirectUri.path}${redirectUri.hasQuery ? "?${redirectUri.query}" : ""}';
              redirectUrl = '$_baseUrl$pathAndQuery';
            } catch (_) {
              redirectUrl = redirectParam;
            }
          }
        }
      } catch (e) {
        debugPrint('WebViewContainer: Error parsing login redirect url: $e');
      }
    }

    final result = await Navigator.pushNamed(
      context,
      '/login',
      arguments: AuthScreenArgs(
        baseUrl: _baseUrl,
        onSuccess: (token) async {
          await syncSessionToWebView(token);
          await registerDeviceWithBackend(token);
        },
        onCancel: () {
          if (mounted) {
            _controller.loadRequest(Uri.parse(_baseUrl));
          }
        },
        googleSignInHandler: handleGoogleSignIn,
        guestId: guestId,
      ),
    );

    if (!mounted) return;

    if (result is String && result.isNotEmpty) {
      debugPrint('WebViewContainer: Received custom route target result: $result');
      if (result.startsWith('/')) {
        _controller.loadRequest(Uri.parse('$_baseUrl$result'));
      } else {
        _controller.loadRequest(Uri.parse(result));
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('jodeals_auth_token');
    if (savedToken != null && savedToken.isNotEmpty) {
      debugPrint('WebViewContainer: Login successful, navigating to: $redirectUrl');
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) {
        _controller.loadRequest(Uri.parse(redirectUrl));
        registerDeviceWithBackend(savedToken);
      }
    }
  }

  void _showNativeRegister({String? interceptedUrl}) async {
    final String? guestId = await getGuestId();
    if (!mounted) return;

    String redirectUrl = '$_baseUrl/profile.php';
    if (interceptedUrl != null) {
      try {
        final uri = Uri.parse(interceptedUrl);
        final redirectParam = uri.queryParameters['redirect'];
        if (redirectParam != null && redirectParam.isNotEmpty) {
          if (redirectParam.startsWith('/')) {
            redirectUrl = '$_baseUrl$redirectParam';
          } else if (!redirectParam.startsWith('http')) {
            redirectUrl = '$_baseUrl/$redirectParam';
          } else {
            try {
              final redirectUri = Uri.parse(redirectParam);
              final String pathAndQuery = '${redirectUri.path}${redirectUri.hasQuery ? "?${redirectUri.query}" : ""}';
              redirectUrl = '$_baseUrl$pathAndQuery';
            } catch (_) {
              redirectUrl = redirectParam;
            }
          }
        }
      } catch (e) {
        debugPrint('WebViewContainer: Error parsing register redirect url: $e');
      }
    }

    await Navigator.pushNamed(
      context,
      '/register',
      arguments: AuthScreenArgs(
        baseUrl: _baseUrl,
        onSuccess: (token) async {
          await syncSessionToWebView(token);
          await registerDeviceWithBackend(token);
        },
        onCancel: () {
          if (mounted) {
            _controller.loadRequest(Uri.parse(_baseUrl));
          }
        },
        guestId: guestId,
      ),
    );

    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('jodeals_auth_token');
    if (savedToken != null && savedToken.isNotEmpty) {
      debugPrint('WebViewContainer: Registration successful, navigating to: $redirectUrl');
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) {
        _controller.loadRequest(Uri.parse(redirectUrl));
      }
    }
  }

  Future<void> handleNativeLogout() async {
    final prefs = await SharedPreferences.getInstance();
    final String? oldToken = prefs.getString('jodeals_auth_token');
    
    await prefs.remove('jodeals_auth_token');
    await prefs.remove('last_registered_auth_token');
    await prefs.remove('last_registered_fcm_token');
    
    final WebViewCookieManager cookieManager = WebViewCookieManager();
    await cookieManager.clearCookies();
    
    await _controller.runJavaScript("localStorage.removeItem('jodeals_auth_token');");
    
    if (oldToken != null && oldToken.isNotEmpty) {
      await _handleLogoutSync(oldToken);
    }
    
    _controller.loadRequest(Uri.parse(_baseUrl));
    _showSnackBar(_txt('تم تسجيل الخروج بنجاح.', 'Logged out successfully.'));
  }

  Future<void> _syncAuthAndRegisterDevice() async {
    try {
      // ALWAYS read SharedPreferences first — localStorage is empty on every fresh WebView load
      // (Android destroys WebView state when app is closed or process is killed).
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString('jodeals_auth_token');

      if (savedToken != null && savedToken.isNotEmpty) {
        // Re-inject the persisted token into localStorage (WebView was freshly created)
        await _controller.runJavaScript(
          "if (!localStorage.getItem('jodeals_auth_token')) { "
          "  localStorage.setItem('jodeals_auth_token', '${savedToken.replaceAll("'", "\\'")}'); "
          "}"
        );
        debugPrint('WebViewContainer: Token found in SharedPreferences, injected into localStorage.');
        await registerDeviceWithBackend(savedToken);
        return;
      }

      // No token in SharedPreferences — double-check localStorage (e.g. web-only session)
      final result = await _controller.runJavaScriptReturningResult(
        "localStorage.getItem('jodeals_auth_token')"
      );
      
      String? localToken;
      if (result is String) {
        String cleaned = result.trim();
        if (cleaned != 'null' && cleaned.isNotEmpty) {
          localToken = cleaned.startsWith('"') && cleaned.endsWith('"')
              ? cleaned.substring(1, cleaned.length - 1)
              : cleaned;
        }
      }

      if (localToken != null && localToken.isNotEmpty) {
        // Token found in localStorage but not in SharedPreferences — sync it
        debugPrint('WebViewContainer: Token found in localStorage, saving to SharedPreferences.');
        await prefs.setString('jodeals_auth_token', localToken);
        await registerDeviceWithBackend(localToken);
      } else {
        // No token anywhere — user is genuinely not logged in
        final lastToken = prefs.getString('last_registered_auth_token');
        if (lastToken != null && lastToken.isNotEmpty && lastToken != 'GUEST') {
          debugPrint('WebViewContainer: No token found anywhere after re-check — user logged out externally.');
          await _handleLogoutSync(lastToken);
        } else {
          debugPrint('WebViewContainer: No auth token found. Registering as guest device...');
          await registerDeviceWithBackend(null);
        }
      }
    } catch (e) {
      debugPrint('WebViewContainer: Error in auth sync: $e');
    }
  }

  Future<void> _backgroundCacheData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jodeals_auth_token');
      
      final cacheService = CacheService.instance;
      if (await cacheService.isDealsCacheExpired() || await cacheService.isCategoriesCacheExpired()) {
        await cacheService.syncDealsAndCategories(_baseUrl, token: token);
      }
      
      if (token != null && token.isNotEmpty) {
        final lastProfileSyncStr = prefs.getString('last_profile_sync_time');
        final lastProfileSync = lastProfileSyncStr != null ? DateTime.tryParse(lastProfileSyncStr) : null;
        if (lastProfileSync == null || DateTime.now().difference(lastProfileSync).inMinutes >= 15) {
          final result = await cacheService.syncUserProfile(_baseUrl, token);
          if (result == ProfileSyncResult.unauthorized) {
            debugPrint('WebViewContainer: Profile sync returned 401 — token revoked. Logging out...');
            await handleNativeLogout();
            return;
          }
          await prefs.setString('last_profile_sync_time', DateTime.now().toIso8601String());
        }
      }
    } catch (e) {
      debugPrint('WebViewContainer: Background cache failed: $e');
    }
  }

  void _trackUrlActivity(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path.toLowerCase();
      
      String screenName = 'home';
      if (path.contains('categories.php') || path.contains('/categories')) {
        screenName = 'categories';
      } else if (path.contains('deal.php') || path.contains('/deals/')) {
        screenName = 'deals';
      } else if (path.contains('favorites.php') || path.contains('/favorites')) {
        screenName = 'favorites';
      } else if (path.contains('profile.php') || path.contains('/profile')) {
        screenName = 'profile';
      } else if (path.contains('settings.php') || path.contains('/settings')) {
        screenName = 'settings';
      } else if (path.contains('hot-deals.php') || path.contains('/hot-deals')) {
        screenName = 'hot_deals';
      } else if (path.contains('search.php') || path.contains('/search')) {
        screenName = 'search';
      }
      
      // Update last screen on backend
      AnonymousTrackingService().updateLastScreen(screenName);
      
      // Check if category view
      if (screenName == 'categories') {
        final categoryVal = uri.queryParameters['category'] ?? uri.queryParameters['cat'] ?? '';
        if (categoryVal.isNotEmpty) {
          AnonymousTrackingService().trackBehavior(
            interestType: 'view_category',
            itemId: categoryVal,
          );
        } else {
          final segments = uri.pathSegments;
          if (segments.length > 1 && segments[0].toLowerCase() == 'categories') {
            AnonymousTrackingService().trackBehavior(
              interestType: 'view_category',
              itemId: segments[1],
            );
          }
        }
      }
      
      // Check if deal view
      if (screenName == 'deals') {
        final dealId = uri.queryParameters['id'] ?? uri.queryParameters['slug'] ?? '';
        if (dealId.isNotEmpty) {
          AnonymousTrackingService().trackBehavior(
            interestType: 'view_deal',
            itemId: dealId,
          );
        } else {
          final segments = uri.pathSegments;
          if (segments.length > 1 && segments[0].toLowerCase() == 'deals') {
            AnonymousTrackingService().trackBehavior(
              interestType: 'view_deal',
              itemId: segments[1],
            );
          }
        }
      }
    } catch (e) {
      debugPrint('WebViewContainer: Error tracking URL activity: $e');
    }
  }

  Future<void> registerDeviceWithBackend(String? token) async {
    if (_isRegisteringDevice) {
      debugPrint('WebViewContainer: Device registration already in progress, skipping.');
      return;
    }
    
    final prefs = await SharedPreferences.getInstance();
    final lastRegisteredToken = prefs.getString('last_registered_auth_token');
    final lastFcmToken = prefs.getString('last_registered_fcm_token');
    
    final String? currentFcmToken = FCMService.token;
    if (currentFcmToken == null) {
      debugPrint('WebViewContainer: FCM token is null, skipping registration.');
      return;
    }
    
    final String tokenKey = token ?? 'GUEST';
    if (lastRegisteredToken == tokenKey && lastFcmToken == currentFcmToken) {
      return;
    }
    
    _isRegisteringDevice = true;
    try {
      int? userId;
      if (token != null && token.isNotEmpty) {
        final profileResponse = await http.get(
          Uri.parse('$_baseUrl/api/v1/profile.php'),
          headers: {
            'Authorization': 'Bearer $token',
            'X-Auth-Token': token,
            'Accept': 'application/json',
          },
        );
        
        if (profileResponse.statusCode == 200) {
          final profileData = json.decode(profileResponse.body);
          if (profileData['status'] == 'success' && profileData['profile'] != null) {
            userId = profileData['profile']['id'];
          }
        } else if (profileResponse.statusCode == 401) {
          debugPrint('WebViewContainer: Profile fetch returned 401 — token revoked. Logging out...');
          await handleNativeLogout();
          return;
        } else {
          debugPrint('WebViewContainer: Profile fetch failed (${profileResponse.statusCode}). Skipping device registration.');
          return;
        }
      }
      
      final deviceInfo = DeviceInfoPlugin();
      String deviceId = '';
      String osVersion = '';
      String deviceType = '';
      
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id;
        osVersion = androidInfo.version.release;
        deviceType = 'Android';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? 'UnknowniOSDevice';
        osVersion = iosInfo.systemVersion;
        deviceType = 'iOS';
      }
      
      final packageInfo = await PackageInfo.fromPlatform();
      final appVersion = packageInfo.version;
      
      final Map<String, dynamic> requestBody = {
        'fcm_token': currentFcmToken,
        'device_type': deviceType,
        'device_id': deviceId,
        'app_version': appVersion,
        'os_version': osVersion,
        'platform': 'mobile',
      };
      if (userId != null) {
        requestBody['user_id'] = userId;
      }
      
      final registerResponse = await http.post(
        Uri.parse('$_baseUrl/api/register-device.php'),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          // ignore: use_null_aware_elements  — ?key applies to keys, not nullable values
          if (token != null) 'X-Auth-Token': token,
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode(requestBody),
      );
      
      if (registerResponse.statusCode == 200) {
        final regData = json.decode(registerResponse.body);
        if (regData['status'] == 'success') {
          debugPrint('WebViewContainer: Device registered successfully (token: $tokenKey).');
          await prefs.setString('last_registered_auth_token', tokenKey);
          await prefs.setString('last_registered_fcm_token', currentFcmToken);
        }
      } else if (registerResponse.statusCode == 401) {
        debugPrint('WebViewContainer: Device registration returned 401 — token revoked. Logging out...');
        await handleNativeLogout();
      } else {
        debugPrint('WebViewContainer: Device registration failed: ${registerResponse.statusCode}');
        // BUG-015: Schedule retry on non-200 failure
        _scheduleDeviceRegRetry(token);
      }
    } catch (e) {
      debugPrint('WebViewContainer: Exception in device registration: $e');
      // BUG-015: Schedule retry on network exception
      _scheduleDeviceRegRetry(token);
    } finally {
      _isRegisteringDevice = false;
    }
  }

  /// BUG-015: Schedules a device registration retry after 30 seconds.
  void _scheduleDeviceRegRetry(String? token) {
    if (_deviceRegRetryCount >= _maxDeviceRegRetries) {
      debugPrint('WebViewContainer: Max device registration retries reached. Push notifications may not work.');
      return;
    }
    _deviceRegRetryCount++;
    debugPrint('WebViewContainer: Scheduling device registration retry #$_deviceRegRetryCount in 30s...');
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted) {
        // Reset the cached registration check to force a re-attempt
        SharedPreferences.getInstance().then((prefs) {
          prefs.remove('last_registered_auth_token');
          prefs.remove('last_registered_fcm_token');
        });
        registerDeviceWithBackend(token);
      }
    });
  }

  Future<void> _handleLogoutSync(String oldToken) async {
    final prefs = await SharedPreferences.getInstance();
    
    final deviceInfo = DeviceInfoPlugin();
    String deviceId = '';
    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? 'UnknowniOSDevice';
      }
    } catch (e) {
      debugPrint('WebViewContainer: Failed to get device ID for logout: $e');
    }

    try {
      await prefs.remove('last_registered_auth_token');
      await prefs.remove('last_registered_fcm_token');

      await _googleSignIn.signOut();

      await http.post(
        Uri.parse('$_baseUrl/api/v1/auth/logout.php'),
        headers: {
          'Authorization': 'Bearer $oldToken',
          'X-Auth-Token': oldToken,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'device_id': deviceId,
        }),
      );
      debugPrint('WebViewContainer: Backend logout sync done.');
    } catch (e) {
      debugPrint('WebViewContainer: Error in logout sync request: $e');
    }
  }

  Future<bool> _requestLocationPermission() async {
    PermissionStatus status = await Permission.locationWhenInUse.status;
    if (status.isDenied) {
      status = await Permission.locationWhenInUse.request();
    }

    if (status.isGranted) {
      return true;
    } else if (status.isPermanentlyDenied) {
      _showSettingsDialog(
        title: _txt('إذن الموقع مطلوب', 'Location Permission Required'),
        message: _txt(
          'يرجى تفعيل الوصول للموقع في الإعدادات للعثور على العروض والمتاجر القريبة منك.',
          'Please enable Location access in Settings to find deals and shops near you.',
        ),
      );
      return false;
    } else {
      _showSnackBar(_txt('تم رفض إذن الموقع.', 'Location permission denied.'), isError: true);
      return false;
    }
  }

  Future<bool> _requestGalleryPermission() async {
    PermissionStatus status;
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        status = await Permission.photos.status;
        if (status.isDenied) {
          status = await Permission.photos.request();
        }
      } else {
        status = await Permission.storage.status;
        if (status.isDenied) {
          status = await Permission.storage.request();
        }
      }
    } else {
      status = await Permission.photos.status;
      if (status.isDenied) {
        status = await Permission.photos.request();
      }
    }

    if (status.isGranted || status.isLimited) {
      return true;
    } else if (status.isPermanentlyDenied) {
      _showSettingsDialog(
        title: _txt('إذن الصور مطلوب', 'Photos Permission Required'),
        message: _txt(
          'يرجى تفعيل الوصول للصور في الإعدادات لرفع الصور.',
          'Please enable Photos access in Settings to upload images.',
        ),
      );
      return false;
    } else {
      _showSnackBar(_txt('تم رفض إذن الصور.', 'Photos permission denied.'), isError: true);
      return false;
    }
  }

  Future<bool> _requestCameraPermission() async {
    PermissionStatus status = await Permission.camera.status;
    if (status.isDenied) {
      status = await Permission.camera.request();
    }

    if (status.isGranted) {
      return true;
    } else if (status.isPermanentlyDenied) {
      _showSettingsDialog(
        title: _txt('إذن الكاميرا مطلوب', 'Camera Permission Required'),
        message: _txt(
          'يرجى تفعيل الوصول للكاميرا في الإعدادات لالتقاط الصور.',
          'Please enable Camera access in Settings to take photos.',
        ),
      );
      return false;
    } else {
      _showSnackBar(_txt('تم رفض إذن الكاميرا.', 'Camera permission denied.'), isError: true);
      return false;
    }
  }

  void _showSettingsDialog({required String title, required String message}) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              child: Text(_txt('إلغاء', 'Cancel'), style: const TextStyle(color: Colors.grey)),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF4D4D),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(_txt('الإعدادات', 'Go to Settings')),
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
            ),
          ],
        );
      },
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFFFF4D4D) : const Color(0xFF10B981),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<List<String>> _handleFileSelection(FileSelectorParams params) async {
    if (!mounted) return [];
    
    final String? source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        final Color cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
        final Color textColor = isDark ? Colors.white : const Color(0xFF1E293B);
        
        return Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[700] : Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  _txt('اختر مصدر الصورة', 'Select Image Source'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    InkWell(
                      onTap: () => Navigator.pop(context, 'camera'),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 110,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: const Color(0xFFFF4D4D).withValues(alpha: 0.2),
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.camera_alt, color: Color(0xFFFF4D4D), size: 28),
                            const SizedBox(height: 8),
                            Text(
                              _txt('الكاميرا', 'Camera'),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => Navigator.pop(context, 'gallery'),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 110,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: const Color(0xFFFF9F0A).withValues(alpha: 0.2),
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.photo_library, color: Color(0xFFFF9F0A), size: 28),
                            const SizedBox(height: 8),
                            Text(
                              _txt('المعرض', 'Gallery'),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );

    if (source == null) return [];

    bool isGranted = false;
    if (source == 'camera') {
      isGranted = await _requestCameraPermission();
    } else {
      isGranted = await _requestGalleryPermission();
    }

    if (!isGranted) return [];

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      
      if (file != null) {
        return [Uri.file(file.path).toString()];
      }
    } catch (e) {
      debugPrint('WebViewContainer: Error picking file: $e');
      _showSnackBar(_txt('فشل تحديد الملف.', 'Failed to select file.'), isError: true);
    }
    return [];
  }

  Future<bool> handleGoogleSignIn() async {
    try {
      final googleUser = await _googleSignIn.authenticate();
      if (googleUser == null) {
        return false;
      }
      
      _loadingNotifier.value = true;
      
      final String? guestId = await getGuestId();
      final response = await http.post(
        Uri.parse('$_baseUrl/api/v1/auth/social.php'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode({
          'provider': 'google',
          'provider_id': googleUser.id,
          'email': googleUser.email,
          'name': googleUser.displayName ?? '',
          'profile_image': googleUser.photoUrl ?? '',
          'platform': 'mobile',
          'guest_id': guestId,
        }),
      );
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['status'] == 'success' && data['token'] != null) {
          final String token = data['token'];
          
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('jodeals_auth_token', token);
          
          await _controller.runJavaScript(
            "localStorage.setItem('jodeals_auth_token', '$token');"
          );
          
          await _syncRememberTokenCookie(token);
          await registerDeviceWithBackend(token);
          
          final Uri baseUri = Uri.parse(widget.initialUrl);
          final String redirectUrl = baseUri.replace(
            path: '/profile.php',
            query: 'login_social_success=1',
          ).toString();

          _controller.loadRequest(Uri.parse(redirectUrl));
          _showSnackBar(_txt('تم تسجيل الدخول بنجاح عبر Google!', 'Logged in successfully with Google!'));
          return true;
        } else {
          _showSnackBar(
            data['message'] ?? _txt('فشل المصادقة.', 'Authentication failed.'),
            isError: true,
          );
          _loadingNotifier.value = false;
        }
      } else {
        _showSnackBar(
          _txt(
            'خطأ في المصادقة من الخادم (${response.statusCode}).',
            'Server authentication error (${response.statusCode}).',
          ),
          isError: true,
        );
        _loadingNotifier.value = false;
      }
    } catch (e) {
      debugPrint('Google Sign-In exception: $e');
      // If error is canceled by user, don't show scary error message
      final errStr = e.toString();
      if (!errStr.contains('canceled')) {
        _showSnackBar(
          _txt('فشل تسجيل الدخول عبر Google.', 'Google Sign-In failed.'),
          isError: true,
        );
      }
      _loadingNotifier.value = false;
    }
    return false;
  }

  Future<void> _initGoogleSignIn() async {
    try {
      await _googleSignIn.initialize(
        clientId: Platform.isIOS
            ? '724842455682-9277p7oml8409inicouerru4ivl4ns0f.apps.googleusercontent.com'
            : null,
        serverClientId: '724842455682-9277p7oml8409inicouerru4ivl4ns0f.apps.googleusercontent.com',
      );
    } catch (e) {
      debugPrint('WebViewContainer: GoogleSignIn.initialize failed: $e');
    }
  }
}

class LinearGradientProgressIndicator extends StatelessWidget {
  final double value;
  final Color color1;
  final Color color2;

  const LinearGradientProgressIndicator({
    super.key,
    required this.value,
    required this.color1,
    required this.color2,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: value),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          builder: (context, animatedValue, child) {
            final double width = constraints.maxWidth * animatedValue;
            return Container(
              width: constraints.maxWidth,
              color: Colors.transparent,
              alignment: Alignment.centerLeft,
              child: Container(
                width: width,
                height: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color1, color2],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(2),
                    bottomRight: Radius.circular(2),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
