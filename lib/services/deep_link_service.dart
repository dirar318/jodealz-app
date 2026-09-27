import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

class DeepLinkService {
  static final AppLinks _appLinks = AppLinks();
  static StreamSubscription<Uri>? _subscription;

  /// Listens for App Links / Universal Links. Since app_links 6 the stream
  /// also delivers the link that launched the app, so no separate
  /// initial-link lookup is needed. Callers must treat the URL as untrusted.
  static void initialize({
    required Function(String url) onLinkReceived,
  }) {
    _subscription?.cancel();
    _subscription = _appLinks.uriLinkStream.listen((Uri uri) {
      onLinkReceived(uri.toString());
    }, onError: (err) {
      debugPrint('DeepLink: Error processing link: $err');
    });
  }
}
