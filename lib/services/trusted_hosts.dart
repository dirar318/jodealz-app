/// Hosts that belong to JoDeals. Session tokens, cookies and in-app
/// navigation are only ever applied to these hosts; everything else is
/// opened outside the app.
class TrustedHosts {
  TrustedHosts._();

  static const String baseUrl = 'https://jodealz.online';
  static const String _rootDomain = 'jodealz.online';

  static bool isTrustedHost(String host) {
    final h = host.toLowerCase();
    return h == _rootDomain || h.endsWith('.$_rootDomain');
  }

  /// True only for https URLs on a JoDeals host.
  static bool isTrustedUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return uri.scheme == 'https' && isTrustedHost(uri.host);
  }

  /// Normalises a link from an untrusted source (push payload, deep link)
  /// to a trusted absolute URL, or falls back to the home page.
  static String sanitize(String? target) {
    if (target == null || target.isEmpty) return baseUrl;
    if (target.startsWith('/')) return '$baseUrl$target';
    if (!target.contains('://')) return '$baseUrl/$target';
    return isTrustedUrl(target) ? target : baseUrl;
  }
}
