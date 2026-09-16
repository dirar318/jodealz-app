import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jodeals/main.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

// Minimal Fake WebView Platform implementation to stub out native channel dependencies in widget tests
class FakeWebViewPlatform extends WebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    return FakePlatformWebViewController(params);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return FakePlatformWebViewWidget(params);
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return FakePlatformNavigationDelegate(params);
  }
}

class FakePlatformWebViewController extends PlatformWebViewController {
  FakePlatformWebViewController(super.params) : super.implementation();

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> setUserAgent(String? userAgent) async {}

  @override
  Future<void> setPlatformNavigationDelegate(PlatformNavigationDelegate handler) async {}

  @override
  Future<void> setOnScrollPositionChange(void Function(ScrollPositionChange)? onScrollPositionChange) async {}

  @override
  Future<void> loadRequest(LoadRequestParams params) async {}

  @override
  Future<bool> canGoBack() async => false;

  @override
  Future<void> reload() async {}

  @override
  Future<void> goBack() async {}
}

class FakePlatformWebViewWidget extends PlatformWebViewWidget {
  FakePlatformWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class FakePlatformNavigationDelegate extends PlatformNavigationDelegate {
  FakePlatformNavigationDelegate(super.params) : super.implementation();

  @override
  Future<void> setOnProgress(void Function(int progress) onProgress) async {}

  @override
  Future<void> setOnPageStarted(void Function(String url) onPageStarted) async {}

  @override
  Future<void> setOnPageFinished(void Function(String url) onPageFinished) async {}

  @override
  Future<void> setOnWebResourceError(
    void Function(WebResourceError error) onWebResourceError,
  ) async {}

  @override
  Future<void> setOnNavigationRequest(
    FutureOr<NavigationDecision> Function(NavigationRequest request) onNavigationRequest,
  ) async {}
}

void main() {
  setUp(() {
    // Inject the fake platform implementation before each test runs
    WebViewPlatform.instance = FakeWebViewPlatform();
  });

  testWidgets('Verify that the splash screen logo/brand title is displayed', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const JoDealsApp(
      initialLang: 'ar',
      isFirstLaunch: false,
    ));

    // Verify that the splash screen logo/brand title is displayed
    expect(find.text('JoDeals'), findsOneWidget);

    // Run out all pending timers (splash animations/timeouts) so tests clean up successfully
    await tester.pump(const Duration(seconds: 10));
  });
}
