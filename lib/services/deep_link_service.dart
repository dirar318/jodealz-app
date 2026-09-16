import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

class DeepLinkService {
  static final AppLinks _appLinks = AppLinks();

  // Initialize listening to App Links / Universal Links
  static void initialize({
    required Function(String url) onLinkReceived,
  }) {
    // 1. Listen for link changes when the app is running (foreground or background)
    _appLinks.uriLinkStream.listen((Uri uri) {
      debugPrint('DeepLink: Link intercepted: $uri');
      // Normalize and forward to the webview
      onLinkReceived(uri.toString());
    }, onError: (err) {
      debugPrint('DeepLink: Error processing link: $err');
    });

    // 2. Check if the app was launched from a closed/terminated state via a link
    _appLinks.getInitialAppLink().then((Uri? uri) {
      if (uri != null) {
        debugPrint('DeepLink: Initial launch link detected: $uri');
        onLinkReceived(uri.toString());
      }
    }).catchError((err) {
      debugPrint('DeepLink: Error retrieving initial link: $err');
    });
  }
}
