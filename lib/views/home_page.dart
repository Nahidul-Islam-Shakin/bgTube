import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import '../js/adblock.dart';
import '../js/scripts.dart';
import '../models/shortcut.dart';
import '../services/navigation_policy.dart';
import '../viewmodels/player_view_model.dart';
import '../viewmodels/settings_view_model.dart';
import 'settings_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static InAppWebViewSettings _buildSettings({
    required String? userAgent,
    required bool adBlock,
  }) =>
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
        // Safe Browsing stays ON now that shortcut sites can be opened.
        geolocationEnabled: false,
        allowFileAccess: false,
        allowContentAccess: false,
        contentBlockers: adBlock ? AdBlock.contentBlockers : const [],
      );

  /// These scripts only run on YouTube pages, so Google's sign-in pages and the
  /// shortcut sites are left untouched.
  /// If audio stops with the screen off and `window.__bgtube` is undefined in
  /// the page console, these rules didn't match: remove `allowedOriginRules`.
  static const Set<String> _youtubeOrigins = {
    'https://*.youtube.com',
    'https://youtube.com',
  };

  static final UserScript _backgroundScript = UserScript(
    source: Js.documentStart,
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    forMainFrameOnly: true,
    allowedOriginRules: _youtubeOrigins,
  );

  static final UserScript _adBlockScript = UserScript(
    source: AdBlock.script,
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    forMainFrameOnly: true,
    allowedOriginRules: _youtubeOrigins,
  );

  @override
  Widget build(BuildContext context) {
    final vm = context.read<PlayerViewModel>();
    final playerReady = context.select<PlayerViewModel, bool>((m) => m.isReady);
    final settingsReady =
        context.select<SettingsViewModel, bool>((s) => s.isLoaded);
    final adBlock =
        context.select<SettingsViewModel, bool>((s) => s.adBlockEnabled);
    final revision =
        context.select<SettingsViewModel, int>((s) => s.webViewRevision);
    final ready = playerReady && settingsReady;

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
              const _ShortcutBar(),
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
                        // A new key = a fresh WebView (used when ad blocking is toggled).
                        key: ValueKey<int>(revision),
                        initialUrlRequest:
                            URLRequest(url: WebUri(PlayerViewModel.homeUrl)),
                        initialSettings: _buildSettings(
                          userAgent: vm.userAgent,
                          adBlock: adBlock,
                        ),
                        initialUserScripts: UnmodifiableListView<UserScript>([
                          _backgroundScript,
                          if (adBlock) _adBlockScript,
                        ]),
                        onWebViewCreated: vm.onWebViewCreated,
                        onProgressChanged: (_, p) => vm.onProgressChanged(p),
                        onLoadStart: (_, url) => vm.onPageStarted(url?.host ?? ''),
                        onLoadStop: (_, __) => vm.onPageLoaded(),
                        shouldOverrideUrlLoading: (controller, action) async {
                          final uri = action.request.url;
                          if (uri == null) return NavigationActionPolicy.CANCEL;
                          final allowed = NavigationPolicy.allow(
                            scheme: uri.scheme,
                            host: uri.host,
                            currentHost: vm.currentHost,
                          );
                          if (!allowed && kDebugMode) {
                            debugPrint('Blocked navigation: $uri');
                          }
                          return allowed
                              ? NavigationActionPolicy.ALLOW
                              : NavigationActionPolicy.CANCEL;
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
              tooltip: 'YouTube home',
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
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Second row of the app bar: the user's shortcuts (hidden when there are none).
class _ShortcutBar extends StatelessWidget {
  const _ShortcutBar();

  @override
  Widget build(BuildContext context) {
    final shortcuts =
        context.select<SettingsViewModel, List<Shortcut>>((s) => s.shortcuts);
    if (shortcuts.isEmpty) return const SizedBox.shrink();

    final player = context.read<PlayerViewModel>();
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          itemCount: shortcuts.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final shortcut = shortcuts[i];
            return ActionChip(
              label: Text(shortcut.name),
              onPressed: () => player.openUrl(shortcut.url),
            );
          },
        ),
      ),
    );
  }
}