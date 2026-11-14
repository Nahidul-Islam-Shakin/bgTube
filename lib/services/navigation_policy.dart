/// Decides which main-frame navigations the WebView may follow.
///
/// While on YouTube / Google pages only trusted hosts are allowed (this stops
/// ad click-outs and "open in app" redirects). Once the user is on a shortcut
/// site (Facebook, ...), normal https browsing is allowed.
class NavigationPolicy {
  const NavigationPolicy._();

  static const List<String> _trustedSuffixes = [
    'youtube.com',
    'youtu.be',
    'google.com',
    'gstatic.com',
    'googlevideo.com',
    'ytimg.com',
    'googleusercontent.com',
  ];

  static bool _matches(String host, List<String> suffixes) =>
      suffixes.any((s) => host == s || host.endsWith('.$s'));

  static bool isYoutubeHost(String host) =>
      host == 'youtu.be' || host == 'youtube.com' || host.endsWith('.youtube.com');

  static bool isTrustedHost(String host) => _matches(host, _trustedSuffixes);

  /// [currentHost] is the host of the page the navigation starts from.
  static bool allow({
    required String scheme,
    required String host,
    required String currentHost,
  }) {
    if (scheme == 'about') return true;
    if (scheme != 'https' && scheme != 'http') return false; // intent:, fb:, vnd.youtube: ...
    if (isTrustedHost(host)) return true;
    return !isTrustedHost(currentHost);
  }
}