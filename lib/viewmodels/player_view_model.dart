import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../js/scripts.dart';
import '../services/native_player.dart';
import '../services/navigation_policy.dart';

class PlayerViewModel extends ChangeNotifier with WidgetsBindingObserver {
  PlayerViewModel(this._native) {
    WidgetsBinding.instance.addObserver(this);
    _native.onMediaAction = _handleMediaAction;
  }

  static const String homeUrl = 'https://m.youtube.com/';

  final NativePlayer _native;
  InAppWebViewController? _web;

  bool _isPlaying = false;
  String _title = '';
  String _artist = '';
  bool _batteryUnrestricted = true;
  bool _inBackground = false;
  bool _isReady = false;
  String? _userAgent;
  String _currentHost = 'm.youtube.com';

  /// Page load progress lives in its own notifier so that progress ticks
  /// only repaint the thin progress bar, not the whole UI.
  final ValueNotifier<double> progress = ValueNotifier<double>(0);

  bool get isPlaying => _isPlaying;
  String get title => _title;
  bool get hasMedia => _title.isNotEmpty;
  bool get batteryUnrestricted => _batteryUnrestricted;

  /// False until the WebView user agent has been prepared (see [init]).
  bool get isReady => _isReady;
  String? get userAgent => _userAgent;

  /// Host of the page currently shown (used by the navigation policy).
  String get currentHost => _currentHost;

  // ---- Startup ------------------------------------------------------------

  /// Google refuses sign-in from embedded WebViews by looking at the user agent
  /// (the "; wv" token and "Version/x.x"). We present the WebView as a normal
  /// mobile Chrome so signing in to your own account is possible.
  Future<void> init() async {
    try {
      final defaultUa = await InAppWebViewController.getDefaultUserAgent();
      _userAgent = _toChromeUserAgent(defaultUa);
    } catch (e) {
      debugPrint('Could not read default user agent: $e');
    }
    _isReady = true;
    notifyListeners();
  }

  static String _toChromeUserAgent(String ua) => ua
      .replaceAll('; wv', '')
      .replaceAll(RegExp(r'\s*Version/\d+(\.\d+)*'), '');

  // ---- WebView wiring -----------------------------------------------------

  void onWebViewCreated(InAppWebViewController controller) {
    _web = controller;
    controller.addJavaScriptHandler(
      handlerName: 'bgtubeState',
      callback: _onPageMediaState,
    );
    refreshBatteryStatus();
  }

  void onProgressChanged(int value) => progress.value = value / 100;

  /// A new document replaces our injected JS state, so re-apply it.
  void onPageLoaded() {
    if (_inBackground) _run(Js.setBackground(true));
  }

  /// A full page load started: the previous document (and its media) is gone.
  void onPageStarted(String host) {
    if (host.isEmpty) return;
    _currentHost = host;

    final hadMedia = _isPlaying || _title.isNotEmpty;
    if (hadMedia) {
      _isPlaying = false;
      _title = '';
      _artist = '';
      notifyListeners();
    }

    if (!NavigationPolicy.isYoutubeHost(host)) {
      // Left YouTube: nothing can be playing, remove the notification.
      _native.stopService();
    } else if (hadMedia) {
      _native.updatePlayback(title: 'YouTube', artist: '', playing: false);
    }
  }

  dynamic _onPageMediaState(List<dynamic> args) {
    if (args.isEmpty || args.first is! Map) return null;
    final data = Map<String, dynamic>.from(args.first as Map);
    final playing = data['playing'] == true;
    final title = ((data['title'] as String?) ?? '').trim();
    final artist = ((data['artist'] as String?) ?? '').trim();

    if (playing == _isPlaying && title == _title && artist == _artist) {
      return null;
    }
    _isPlaying = playing;
    _title = title;
    _artist = artist;
    notifyListeners();

    _native.updatePlayback(
      title: title.isEmpty ? 'YouTube' : title,
      artist: artist,
      playing: playing,
    );
    return null;
  }

  // ---- Controls (UI, notification, headset buttons all land here) ---------

  void togglePlayPause() => _run(_isPlaying ? Js.pause : Js.play);

  void _handleMediaAction(String action) {
    switch (action) {
      case 'play':
        _run(Js.play);
      case 'pause':
        _run(Js.pause);
      case 'next':
        _run(Js.next);
      case 'previous':
        _run(Js.previous);
      case 'stop':
        _run(Js.pause);
        _native.stopService();
    }
  }

  void _run(String js) => _web?.evaluateJavascript(source: js);

  // ---- Navigation ---------------------------------------------------------

  Future<void> goHome() => openUrl(homeUrl);

  /// Loads [url] in the same WebView (used by Home and by the shortcuts).
  Future<void> openUrl(String url) async =>
      _web?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));

  Future<void> reload() async => _web?.reload();

  /// Back inside the web history; if there is none, send the app to the
  /// background instead of closing it (closing would kill the audio).
  Future<void> handleBack() async {
    final web = _web;
    if (web != null && await web.canGoBack()) {
      await web.goBack();
    } else {
      await _native.moveToBackground();
    }
  }

  // ---- Battery optimisation ----------------------------------------------

  Future<void> refreshBatteryStatus() async {
    final value = await _native.isBatteryUnrestricted();
    if (value == _batteryUnrestricted) return;
    _batteryUnrestricted = value;
    notifyListeners();
  }

  Future<void> requestBatteryExemption() async {
    await _native.requestBatteryUnrestricted();
  }

  // ---- App lifecycle ------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final inBackground = state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden;
    if (inBackground != _inBackground) {
      _inBackground = inBackground;
      _run(Js.setBackground(inBackground));
    }
    if (state == AppLifecycleState.resumed) {
      refreshBatteryStatus();
    }
    // NOTE: never call pauseTimers()/pause() on the WebView here,
    // that would stop the audio.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _native.onMediaAction = null;
    progress.dispose();
    super.dispose();
  }
}