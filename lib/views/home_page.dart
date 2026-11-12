import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import '../js/scripts.dart';
import '../viewmodels/player_view_model.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static InAppWebViewSettings _buildSettings(String? userAgent) =>
      InAppWebViewSettings(
        userAgent: userAgent ?? '', // Chrome-like UA so Google sign-in works
        javaScriptEnabled: true,
        domStorageEnabled: true,
        databaseEnabled: false, // legacy WebSQL, not needed
        mediaPlaybackRequiresUserGesture: false,
        allowBackgroundAudioPlaying: true, // keeps the WebView "visible" when the screen is off
        useShouldOverrideUrlLoading: true,
        javaScriptCanOpenWindowsAutomatically: false,
        thirdPartyCookiesEnabled: true, // needed for staying signed in
        supportZoom: false,
        builtInZoomControls: false,
        displayZoomControls: false,
        // Low-end device: skip features this app never uses.
        safeBrowsingEnabled: false, // we only allow a fixed host list anyway
        geolocationEnabled: false,
        allowFileAccess: false,
        allowContentAccess: false,
      );

  /// The background-play script only runs on YouTube pages, so Google's
  /// sign-in pages are left untouched.
  /// If audio stops with the screen off and `window.__bgtube` is undefined in
  /// the page console, these rules didn't match: remove `allowedOriginRules`.
  static final UnmodifiableListView<UserScript> _userScripts =
      UnmodifiableListView<UserScript>([
    UserScript(
      source: Js.documentStart,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      forMainFrameOnly: true,
      allowedOriginRules: {'https://*.youtube.com', 'https://youtube.com'},
    ),
  ]);

  /// Only these hosts may load in the main frame (YouTube + Google sign-in).
  /// Everything else (ad click-outs, "open in app" deep links, ...) is cancelled.
  static bool _isAllowedHost(String host) {
    const suffixes = [
      'youtube.com',
      'youtu.be',
      'google.com',
      'gstatic.com',
      'googlevideo.com',
      'ytimg.com',
      'googleusercontent.com',
    ];
    return suffixes.any((s) => host == s || host.endsWith('.$s'));
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.read<PlayerViewModel>();
    final ready = context.select<PlayerViewModel, bool>((m) => m.isReady);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) vm.handleBack();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              const _TopBar(),
              ValueListenableBuilder<double>(
                valueListenable: vm.progress,
                builder: (_, value, __) => value < 1
                    ? LinearProgressIndicator(value: value, minHeight: 2)
                    : const SizedBox(height: 2),
              ),
              Expanded(
                child: !ready
                    ? const Center(child: CircularProgressIndicator())
                    : InAppWebView(
                        initialUrlRequest:
                            URLRequest(url: WebUri(PlayerViewModel.homeUrl)),
                        initialSettings: _buildSettings(vm.userAgent),
                        initialUserScripts: _userScripts,
                        onWebViewCreated: vm.onWebViewCreated,
                        onProgressChanged: (_, p) => vm.onProgressChanged(p),
                        onLoadStop: (_, __) => vm.onPageLoaded(),
                        shouldOverrideUrlLoading: (controller, action) async {
                          final uri = action.request.url;
                          if (uri == null) return NavigationActionPolicy.CANCEL;
                          if (uri.scheme == 'about') {
                            return NavigationActionPolicy.ALLOW;
                          }
                          final isWeb =
                              uri.scheme == 'http' || uri.scheme == 'https';
                          if (isWeb && _isAllowedHost(uri.host)) {
                            return NavigationActionPolicy.ALLOW;
                          }
                          // If a sign-in step silently goes nowhere, check
                          // this log line and add the host to the list above.
                          if (kDebugMode) debugPrint('Blocked navigation: $uri');
                          return NavigationActionPolicy.CANCEL;
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PlayerViewModel>();
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Home',
              icon: const Icon(Icons.home_outlined),
              onPressed: vm.goHome,
            ),
            IconButton(
              tooltip: 'Reload',
              icon: const Icon(Icons.refresh),
              onPressed: vm.reload,
            ),
            Expanded(
              child: Text(
                vm.hasMedia ? vm.title : 'BgTube',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (vm.hasMedia)
              IconButton(
                tooltip: vm.isPlaying ? 'Pause' : 'Play',
                icon: Icon(vm.isPlaying ? Icons.pause : Icons.play_arrow),
                onPressed: vm.togglePlayPause,
              ),
            if (!vm.batteryUnrestricted)
              IconButton(
                tooltip: 'Allow unrestricted battery use',
                icon: const Icon(Icons.battery_alert),
                onPressed: vm.requestBatteryExemption,
              ),
          ],
        ),
      ),
    );
  }
}
