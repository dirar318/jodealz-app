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
import 'package:jodeals/screens/native_deals_feed.dart';
import 'package:jodeals/services/fcm_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:jodeals/services/auth_token_store.dart';
import 'package:jodeals/services/trusted_hosts.dart';
import 'package:jodeals/screens/auth/auth_screen_args.dart';
import 'package:jodeals/widgets/skeleton_loader.dart';
import 'package:jodeals/services/cache_service.dart';
import 'package:jodeals/services/local_db_service.dart';
import 'package:jodeals/services/anonymous_tracking_service.dart';
import 'package:jodeals/theme/app_colors.dart';
import 'package:jodeals/theme/app_radius.dart';

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

class WebViewContainerState extends State<WebViewContainer> with WidgetsBindingObserver {
  late final WebViewController _controller;
  final ValueNotifier<double> _progressNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<bool> _loadingNotifier = ValueNotifier<bool>(true);
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
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

  static bool _isOfflineResult(List<ConnectivityResult> results) =>
      results.isEmpty || results.every((r) => r == ConnectivityResult.none);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _recoverIfWebViewWasKilled();
    }
  }

  /// The OS may kill the WebView's renderer (Android) or content process (iOS)
  /// while the app is in the background, leaving a blank page. Reload in that case.
  Future<void> _recoverIfWebViewWasKilled() async {
    if (_isOffline) return;
    try {
      final Object len = await _controller.runJavaScriptReturningResult(
        'document.body ? document.body.innerHTML.length : 0',
      );
      if (int.tryParse(len.toString()) == 0) {
        _controller.reload();
      }
    } catch (_) {
      _controller.reload();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    WidgetsBinding.instance.addObserver(this);
    FCMService.baseUrl = _baseUrl;
    FCMService.tokenNotifier.addListener(_onFcmTokenChanged);
    _loadLanguagePreference();
    _checkConnectivity();
    _initWebViewController();
    // Defer Google Sign-In initialization — it hits a platform channel and is
    // only needed when the user taps "Sign in with Google". Delaying it keeps
    // initState lightweight and avoids competing with the WebView's first load.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 3), _ensureGoogleSignInInitialized);
    });

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> result) {
      if (_isOfflineResult(result)) {
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
    if (_isOfflineResult(result) && mounted) {
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
      ..setBackgroundColor(const Color(0xFFF8FAFC));

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
          // Fires for client-side (pushState) navigation too, which
          // onPageStarted/onPageFinished miss; keeps system back accurate.
          onUrlChange: (UrlChange change) {
            _updateBackState();
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

            // Never inject scripts, session tokens or cookies into pages that
            // are not served from a JoDeals host.
            if (!_isTrustedUrl(url)) {
              widget.onPageLoaded?.call();
              return;
            }

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
              final savedToken = await AuthTokenStore.read();
              if (savedToken != null && savedToken.isNotEmpty) {
                final String jsToken = jsonEncode(savedToken);
                await _controller.runJavaScript(
                  "if (localStorage.getItem('jodeals_auth_token') !== $jsToken) { "
                  "  localStorage.setItem('jodeals_auth_token', $jsToken); "
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
                  "document.cookie = ${jsonEncode('remember_token=${Uri.encodeComponent(savedToken)}; path=/; max-age=2592000$secureFlag$domainParam; SameSite=Lax')};"
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
            final bool isOwnUrl = url.startsWith('jodeals:') || _isTrustedUrl(url);

            if (!isOwnUrl) {
              if (!url.startsWith('http://') && !url.startsWith('https://')) {
                await _launchExternalUrl(url);
                return NavigationDecision.prevent;
              }
              // Third-party pages open outside the app so they never share the
              // app's WebView session. Sub-frames (embeds) are left alone.
              if (request.isMainFrame) {
                await _launchExternalUrl(url);
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            }

            if (url.contains('/auth-apple.php') || url.contains('jodeals://auth-apple') || url.contains('jodeals:auth-apple')) {
              handleAppleSignIn();
              return NavigationDecision.prevent;
            }

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

            // The plain deals listing opens the native, offline-capable feed.
            // Filtered/paginated listings (extra query params) stay on the web.
            if (_isPlainDealsListing(url)) {
              _showNativeDealsFeed();
              return NavigationDecision.prevent;
            }

            if (url.startsWith('jodeals:')) {
              // Unknown app-scheme route: stay on the current page.
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
      androidController.setMixedContentMode(MixedContentMode.neverAllow);

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

    _setUserAgentAndLoad();
  }

  /// Keeps the real WebView user agent (Google blocks spoofed embedded
  /// browsers) and appends an app marker the website can detect.
  Future<void> _setUserAgentAndLoad() async {
    try {
      final String? defaultUa = await _controller.getUserAgent();
      final info = await PackageInfo.fromPlatform();
      await _controller.setUserAgent('${defaultUa ?? ''} JoDealsApp/${info.version}'.trim());
    } catch (e) {
      debugPrint('WebViewContainer: Could not set user agent: $e');
    }
    _controller.loadRequest(Uri.parse(widget.initialUrl));
  }

  bool _isTrustedUrl(String url) {
    if (TrustedHosts.isTrustedUrl(url)) return true;
    // Also allow the configured base host (e.g. a staging server).
    final uri = Uri.tryParse(url);
    final base = Uri.parse(_baseUrl);
    return uri != null && uri.scheme == base.scheme && uri.host == base.host;
  }

  Future<void> _launchExternalUrl(String url) async {
    Uri? uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      // Android intent:// links: try the intent, then its browser fallback.
      if (uri.scheme == 'intent') {
        final fallback = RegExp(r'S\.browser_fallback_url=([^;]+)').firstMatch(url)?.group(1);
        final scheme = RegExp(r'scheme=([^;]+)').firstMatch(url)?.group(1);
        if (scheme != null) {
          final direct = Uri.tryParse(url.replaceFirst('intent:', '$scheme:').split('#Intent').first);
          if (direct != null && await launchUrl(direct, mode: LaunchMode.externalApplication)) return;
        }
        if (fallback != null) {
          uri = Uri.parse(Uri.decodeComponent(fallback));
        } else {
          return;
        }
      }
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) debugPrint('Could not launch external URL: $url');
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
        'onAccountDeleted': () {
          LocalDbService.instance.clearUserProfile();
          handleNativeLogout(message: _txt('تم حذف حسابك نهائياً.', 'Your account has been deleted.'));
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

  bool _isPlainDealsListing(String url) {
    if (url.startsWith('jodeals://deals') || url == 'jodeals:deals') return true;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.path != '/deals.php') return false;
    const allowedParams = {'lang', 'app'};
    return uri.queryParameters.keys.every(allowedParams.contains);
  }

  Future<void> _showNativeDealsFeed() async {
    final token = await AuthTokenStore.read();
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      settings: const RouteSettings(name: '/deals'),
      builder: (routeContext) => NativeDealsFeedScreen(
        baseUrl: _baseUrl,
        authToken: token,
        isArabic: _isArabic,
        onDealTap: (dealUrl) {
          Navigator.of(routeContext).pop();
          loadUrl(dealUrl);
        },
      ),
    ));
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
      // Edge-to-edge: only icon brightness is set; bar colours are
      // deprecated on Android 15+ and the Scaffold paints behind the bars.
      value: const SystemUiOverlayStyle(
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.dark,
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
          // Keep web content clear of the status bar, display cutouts and
          // the gesture/navigation bar on every device.
          body: SafeArea(
            top: true,
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
                            if (!_isOfflineResult(result)) {
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
      await AuthTokenStore.write(token);

      await _syncRememberTokenCookie(token);

      await _runOnTrustedPage("localStorage.setItem('jodeals_auth_token', ${jsonEncode(token)});");

      debugPrint('WebViewContainer: Successfully synced session to WebView.');
    } catch (e) {
      debugPrint('WebViewContainer: Error syncing session to WebView: $e');
    }
  }

  /// Runs [js] only when the WebView currently shows a JoDeals page.
  Future<void> _runOnTrustedPage(String js) async {
    final String? current = await _controller.currentUrl();
    if (current == null || !_isTrustedUrl(current)) return;
    await _controller.runJavaScript(js);
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
        appleSignInHandler: handleAppleSignIn,
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

    final savedToken = await AuthTokenStore.read();
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
    final savedToken = await AuthTokenStore.read();
    if (savedToken != null && savedToken.isNotEmpty) {
      debugPrint('WebViewContainer: Registration successful, navigating to: $redirectUrl');
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) {
        _controller.loadRequest(Uri.parse(redirectUrl));
      }
    }
  }

  Future<void> handleNativeLogout({String? message}) async {
    final prefs = await SharedPreferences.getInstance();
    final String? oldToken = await AuthTokenStore.read();

    await AuthTokenStore.clear();
    await prefs.remove('last_registered_auth_token');
    await prefs.remove('last_registered_fcm_token');

    final WebViewCookieManager cookieManager = WebViewCookieManager();
    await cookieManager.clearCookies();

    try {
      await _runOnTrustedPage("localStorage.removeItem('jodeals_auth_token');");
    } catch (_) {}

    if (oldToken != null && oldToken.isNotEmpty) {
      await _handleLogoutSync(oldToken);
    }

    _controller.loadRequest(Uri.parse(_baseUrl));
    _showSnackBar(message ?? _txt('تم تسجيل الخروج بنجاح.', 'Logged out successfully.'));
  }

  /// Non-reversible fingerprint of the auth token, used only to detect whether
  /// the device was already registered for this session (FNV-1a, 32-bit).
  static String _registrationKey(String? token) {
    if (token == null || token.isEmpty) return 'GUEST';
    int hash = 0x811c9dc5;
    for (final int unit in token.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return 'u:${hash.toRadixString(16)}';
  }

  Future<void> _syncAuthAndRegisterDevice() async {
    try {
      // Always read the secure store first — localStorage is empty on every
      // fresh WebView load (Android destroys WebView state when the process dies).
      final savedToken = await AuthTokenStore.read();

      if (savedToken != null && savedToken.isNotEmpty) {
        await _runOnTrustedPage(
          "if (!localStorage.getItem('jodeals_auth_token')) { "
          "  localStorage.setItem('jodeals_auth_token', ${jsonEncode(savedToken)}); "
          "}"
        );
        await registerDeviceWithBackend(savedToken);
        return;
      }

      // No stored token — double-check localStorage (e.g. web-only session)
      final String? current = await _controller.currentUrl();
      if (current == null || !_isTrustedUrl(current)) return;
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
        await AuthTokenStore.write(localToken);
        await registerDeviceWithBackend(localToken);
      } else {
        // No token anywhere — the user is not logged in (or logged out on the web).
        final prefs = await SharedPreferences.getInstance();
        final lastKey = prefs.getString('last_registered_auth_token');
        if (lastKey != null && lastKey != 'GUEST') {
          await prefs.remove('last_registered_auth_token');
          await prefs.remove('last_registered_fcm_token');
        }
        await registerDeviceWithBackend(null);
      }
    } catch (e) {
      debugPrint('WebViewContainer: Error in auth sync: $e');
    }
  }

  Future<void> _backgroundCacheData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = await AuthTokenStore.read();

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
    
    final String tokenKey = _registrationKey(token);
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
          debugPrint('WebViewContainer: Device registered successfully.');
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

    // The gallery uses the system photo picker, which needs no permission
    // (Android Photo Picker / iOS PHPicker). Only the camera does.
    if (source == 'camera' && !await _requestCameraPermission()) return [];

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
      await _ensureGoogleSignInInitialized();
      final googleUser = await _googleSignIn.authenticate();
      // The backend must verify this ID token (signature, aud, iss, exp) and
      // derive the user's identity from it — never trust the plain fields.
      final String? idToken = googleUser.authentication.idToken;
      if (idToken == null) {
        _showSnackBar(_txt('فشل تسجيل الدخول عبر Google.', 'Google Sign-In failed.'), isError: true);
        return false;
      }

      return await _completeSocialLogin(
        provider: 'google',
        providerName: 'Google',
        payload: {
          'id_token': idToken,
          'provider_id': googleUser.id,
          'email': googleUser.email,
          'name': googleUser.displayName ?? '',
          'profile_image': googleUser.photoUrl ?? '',
        },
      );
    } catch (e) {
      debugPrint('Google Sign-In exception: $e');
      final bool canceled = e is GoogleSignInException && e.code == GoogleSignInExceptionCode.canceled;
      if (!canceled && !e.toString().contains('canceled')) {
        _showSnackBar(_txt('فشل تسجيل الدخول عبر Google.', 'Google Sign-In failed.'), isError: true);
      }
      _loadingNotifier.value = false;
    }
    return false;
  }

  /// Sign in with Apple (App Store Guideline 4.8). The backend must verify the
  /// identity token against Apple's public keys (aud = com.jodealz.app).
  Future<bool> handleAppleSignIn() async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      );
      final String? identityToken = credential.identityToken;
      if (identityToken == null) {
        _showSnackBar(_txt('فشل تسجيل الدخول عبر Apple.', 'Sign in with Apple failed.'), isError: true);
        return false;
      }
      final String name = [credential.givenName, credential.familyName]
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .join(' ');

      return await _completeSocialLogin(
        provider: 'apple',
        providerName: 'Apple',
        payload: {
          'id_token': identityToken,
          'authorization_code': credential.authorizationCode,
          'provider_id': credential.userIdentifier ?? '',
          'email': credential.email ?? '',
          'name': name,
        },
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code != AuthorizationErrorCode.canceled) {
        _showSnackBar(_txt('فشل تسجيل الدخول عبر Apple.', 'Sign in with Apple failed.'), isError: true);
      }
    } catch (e) {
      debugPrint('Apple Sign-In exception: $e');
      _showSnackBar(_txt('فشل تسجيل الدخول عبر Apple.', 'Sign in with Apple failed.'), isError: true);
    }
    _loadingNotifier.value = false;
    return false;
  }

  Future<bool> _completeSocialLogin({
    required String provider,
    required String providerName,
    required Map<String, dynamic> payload,
  }) async {
    _loadingNotifier.value = true;

    final String? guestId = await getGuestId();
    final response = await http.post(
      Uri.parse('$_baseUrl/api/v1/auth/social.php'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: json.encode({
        'provider': provider,
        ...payload,
        'platform': 'mobile',
        'guest_id': guestId,
      }),
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);
      if (data['status'] == 'success' && data['token'] != null) {
        final String token = data['token'];

        await syncSessionToWebView(token);
        await registerDeviceWithBackend(token);

        final Uri baseUri = Uri.parse(widget.initialUrl);
        final String redirectUrl = baseUri.replace(
          path: '/profile.php',
          query: 'login_social_success=1',
        ).toString();

        _controller.loadRequest(Uri.parse(redirectUrl));
        _showSnackBar(_txt('تم تسجيل الدخول بنجاح عبر $providerName!', 'Logged in successfully with $providerName!'));
        return true;
      }
      _showSnackBar(
        data['message'] ?? _txt('فشل المصادقة.', 'Authentication failed.'),
        isError: true,
      );
    } else {
      _showSnackBar(
        _txt(
          'خطأ في المصادقة من الخادم (${response.statusCode}).',
          'Server authentication error (${response.statusCode}).',
        ),
        isError: true,
      );
    }
    _loadingNotifier.value = false;
    return false;
  }

  Future<void>? _googleInitFuture;

  Future<void> _ensureGoogleSignInInitialized() {
    return _googleInitFuture ??= _initGoogleSignIn();
  }

  Future<void> _initGoogleSignIn() async {
    try {
      // iOS reads its client ID from GIDClientID in Info.plist, which must be
      // an iOS OAuth client whose reversed ID is registered in
      // CFBundleURLSchemes. The server client is the Web client.
      await _googleSignIn.initialize(
        serverClientId: '724842455682-9277p7oml8409inicouerru4ivl4ns0f.apps.googleusercontent.com',
      );
    } catch (e) {
      debugPrint('WebViewContainer: GoogleSignIn.initialize failed: $e');
      _googleInitFuture = null;
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
