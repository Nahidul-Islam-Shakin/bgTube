import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Ad blocking, built for a low-end phone:
///  1. A SHORT native blocklist (every request is matched against it, so it
///     must stay small).
///  2. An in-page script for YouTube with no permanent timers: it hooks JSON
///     parsing, hides ad slots with one style tag, and only runs a timer
///     while an ad is actually showing.
/// This is best effort. YouTube changes things, and ads that are stitched into
/// the video stream itself cannot be removed.
class AdBlock {
  const AdBlock._();

  static const List<String> _urlPatterns = [
    r'.*://([^/]*\.)?doubleclick\.net/.*',
    r'.*://([^/]*\.)?googlesyndication\.com/.*',
    r'.*://([^/]*\.)?googleadservices\.com/.*',
    r'.*://adservice\.google\.[a-z.]+/.*',
    r'.*://([^/]*\.)?youtube\.com/pagead/.*',
    r'.*://([^/]*\.)?youtube\.com/api/stats/ads.*',
    r'.*://([^/]*\.)?youtube\.com/ptracking.*',
    r'.*://([^/]*\.)?youtube\.com/get_midroll_info.*',
  ];

  static final List<ContentBlocker> contentBlockers = List<ContentBlocker>.unmodifiable(
    _urlPatterns.map(
      (pattern) => ContentBlocker(
        trigger: ContentBlockerTrigger(urlFilter: pattern),
        action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
      ),
    ),
  );

  /// Injected at document start on YouTube pages only (when ad blocking is on).
  static const String script = r'''
(function () {
  if (window.__bgtubeAds) return;
  window.__bgtubeAds = true;

  // 1) Remove ad data from YouTube's player responses.
  var AD_KEYS = ['adPlacements', 'playerAds', 'adSlots', 'adBreakHeartbeatParams'];

  function prune(o) {
    if (!o || typeof o !== 'object') return;
    for (var i = 0; i < AD_KEYS.length; i++) {
      if (AD_KEYS[i] in o) { try { delete o[AD_KEYS[i]]; } catch (e) {} }
    }
  }
  function pruneResponse(r) {
    if (!r || typeof r !== 'object') return;
    if (Array.isArray(r)) {
      var n = Math.min(r.length, 5);
      for (var i = 0; i < n; i++) {
        var item = r[i];
        if (item && typeof item === 'object') { prune(item); prune(item.playerResponse); }
      }
      return;
    }
    prune(r);
    prune(r.playerResponse);
  }

  try {
    var nativeParse = JSON.parse;
    JSON.parse = function () {
      var r = nativeParse.apply(this, arguments);
      try { pruneResponse(r); } catch (e) {}
      return r;
    };
  } catch (e) {}

  try {
    var nativeJson = Response.prototype.json;
    Response.prototype.json = function () {
      var p = nativeJson.apply(this, arguments);
      if ((this.url || '').indexOf('/youtubei/v1/') === -1) return p;
      return p.then(function (r) { try { pruneResponse(r); } catch (e) {} return r; });
    };
  } catch (e) {}

  try {
    var initial;
    Object.defineProperty(window, 'ytInitialPlayerResponse', {
      configurable: true,
      get: function () { return initial; },
      set: function (v) { try { pruneResponse(v); } catch (e) {} initial = v; }
    });
  } catch (e) {}

  // 2) Hide ad slots (one style tag, a handful of selectors).
  var CSS = 'ytm-promoted-sparkles-web-renderer,ytm-promoted-video-renderer,' +
            'ytm-companion-ad-renderer,ytm-companion-slot,ad-slot-renderer,' +
            'ytm-ad-slot-renderer,.ytp-ad-overlay-container,.ytp-ad-image-overlay' +
            '{display:none!important}';
  function addStyle() {
    var root = document.head || document.documentElement;
    if (!root) return false;
    var s = document.createElement('style');
    s.textContent = CSS;
    root.appendChild(s);
    return true;
  }
  if (!addStyle()) document.addEventListener('DOMContentLoaded', addStyle, { once: true });

  // 3) If an ad still plays: click Skip, or mute + fast-forward it.
  //    The timer exists ONLY while an ad is showing.
  var adTimer = null, recheck = null, touched = false, savedMuted = false, savedRate = 1;

  function adShowing() {
    var p = document.querySelector('.html5-video-player');
    return !!p && p.classList.contains('ad-showing');
  }

  function handleAd() {
    var v = document.querySelector('video');
    if (!adShowing()) {
      if (touched && v) { v.muted = savedMuted; v.playbackRate = savedRate; }
      touched = false;
      if (adTimer) { clearInterval(adTimer); adTimer = null; }
      return;
    }
    var btn = document.querySelector('.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern');
    if (btn) { btn.click(); }
    if (v) {
      if (!touched) { savedMuted = v.muted; savedRate = v.playbackRate; touched = true; }
      v.muted = true;
      v.playbackRate = 16;
      // Only jump to the end of SHORT media (a real ad). A long duration means
      // the ad is stitched into the content, and jumping would skip the video.
      if (isFinite(v.duration) && v.duration > 0 && v.duration <= 120 &&
          v.currentTime < v.duration - 0.2) {
        v.currentTime = v.duration - 0.1;
      }
    }
  }

  function checkForAd() {
    if (adTimer) return;
    if (adShowing()) { handleAd(); adTimer = setInterval(handleAd, 400); }
  }

  function onMedia() {
    checkForAd();
    clearTimeout(recheck);
    recheck = setTimeout(checkForAd, 700); // the ad class can appear a moment later
  }
  ['loadstart', 'loadedmetadata', 'durationchange', 'playing', 'emptied'].forEach(function (t) {
    document.addEventListener(t, onMedia, true);
  });
})();
''';
}