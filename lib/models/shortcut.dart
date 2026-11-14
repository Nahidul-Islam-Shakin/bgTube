/// A user-defined link shown in the main screen bar (Facebook, Instagram, ...).
class Shortcut {
  const Shortcut({required this.name, required this.url});

  final String name;
  final String url;

  Map<String, dynamic> toJson() => {'name': name, 'url': url};

  factory Shortcut.fromJson(Map<String, dynamic> json) => Shortcut(
        name: json['name'] as String,
        url: json['url'] as String,
      );

  /// Returns a clean https URL, or null when the input is not a usable web address.
  static String? normalizeUrl(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) text = 'https://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty || !uri.host.contains('.')) return null;
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    return uri.replace(scheme: 'https').toString();
  }

  /// "https://www.example.com/x" -> "example.com"
  static String displayHost(String url) {
    final host = Uri.tryParse(url)?.host ?? url;
    return host.replaceFirst(RegExp(r'^(www|m)\.'), '');
  }
}

/// Suggestions shown in Settings. The user can add any other site by hand.
const List<Shortcut> kShortcutPresets = [
  Shortcut(name: 'Facebook', url: 'https://m.facebook.com/'),
  Shortcut(name: 'Instagram', url: 'https://www.instagram.com/'),
  Shortcut(name: 'X', url: 'https://x.com/'),
  Shortcut(name: 'Reddit', url: 'https://www.reddit.com/'),
  Shortcut(name: 'TikTok', url: 'https://www.tiktok.com/'),
  Shortcut(name: 'LinkedIn', url: 'https://www.linkedin.com/'),
];