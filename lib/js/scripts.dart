/// JavaScript that runs inside the YouTube page.
class Js {
  const Js._();

  /// Injected at DOCUMENT START, before YouTube's own scripts run.
  ///
  /// Performance notes: no permanent polling timers. Reporting is event driven,
  /// and the keep-alive timer only exists while the app is in the background.
  static const String documentStart = r'''
(function () {
  if (window.__bgtube) return;

  var background = false;
  var keepAliveTimer = null;
  var reportTimer = null;
  var last = '';

  // 1) Make the page believe it is always visible, so YouTube's own
  //    "page hidden -> pause" logic never fires.
  var define = function (obj, name, value) {
    try {
      Object.defineProperty(obj, name, {
        configurable: true,
        get: function () { return value; }
      });
    } catch (e) {}
  };
  define(document, 'hidden', false);
  define(document, 'visibilityState', 'visible');
  define(document, 'webkitHidden', false);
  define(document, 'webkitVisibilityState', 'visible');

  var swallow = function (e) { e.stopImmediatePropagation(); };
  ['visibilitychange', 'webkitvisibilitychange'].forEach(function (type) {
    window.addEventListener(type, swallow, true);
    document.addEventListener(type, swallow, true);
  });

  // 2) Background only: a harmless Alt key press once a minute so YouTube's
  //    "Video paused. Continue watching?" idle prompt does not trigger.
  function sendAlt() {
    ['keydown', 'keyup'].forEach(function (type) {
      document.dispatchEvent(new KeyboardEvent(type, {
        bubbles: true, cancelable: true,
        key: 'Alt', code: 'AltLeft', keyCode: 18, which: 18
      }));
    });
  }

  // 3) Background only: ask the player for the lowest quality (less decoding
  //    work and data). Best effort, fails silently if the player API changes.
  function applyLowQuality() {
    try {
      var p = document.getElementById('movie_player') ||
              document.querySelector('.html5-video-player');
      if (p && typeof p.setPlaybackQualityRange === 'function') {
        p.setPlaybackQualityRange('tiny', 'tiny');
      }
    } catch (e) {}
  }

  // 4) Report playback state + title to Flutter (only when it changes).
  function report() {
    try {
      var bridge = window.flutter_inappwebview;
      if (!bridge || !bridge.callHandler) return;
      var v = document.querySelector('video');
      var meta = (navigator.mediaSession && navigator.mediaSession.metadata) || null;
      var title = (meta && meta.title) || document.title.replace(/\s*-\s*YouTube$/, '');
      var artist = (meta && meta.artist) || '';
      var payload = {
        playing: !!v && !v.paused && !v.ended,
        title: title || '',
        artist: artist || ''
      };
      var s = JSON.stringify(payload);
      if (s === last) return;
      last = s;
      bridge.callHandler('bgtubeState', payload);
    } catch (e) {}
  }

  function onMediaEvent(e) {
    if (background && (e.type === 'playing' || e.type === 'loadedmetadata')) {
      applyLowQuality();
    }
    report();
    // Metadata often updates a moment after the media event.
    clearTimeout(reportTimer);
    reportTimer = setTimeout(report, 1500);
  }
  ['play', 'playing', 'pause', 'ended', 'emptied', 'loadedmetadata'].forEach(function (type) {
    // Media events don't bubble, so listen in the capture phase.
    document.addEventListener(type, onMediaEvent, true);
  });

  window.__bgtube = {
    setBackground: function (value) {
      background = !!value;
      if (background) {
        if (!keepAliveTimer) keepAliveTimer = setInterval(sendAlt, 60000);
        applyLowQuality();
      } else if (keepAliveTimer) {
        clearInterval(keepAliveTimer);
        keepAliveTimer = null;
      }
    }
  };
})();
''';

  static const String play = r'''
(function () {
  var v = document.querySelector('video');
  if (v) { v.play(); }
})();
''';

  static const String pause = r'''
(function () {
  var v = document.querySelector('video');
  if (v) { v.pause(); }
})();
''';

  /// Best effort: click the player's "next" button if present, otherwise jump
  /// to the end so YouTube's own autoplay/playlist logic moves on.
  static const String next = r'''
(function () {
  var btn = document.querySelector('.ytp-next-button');
  if (btn && btn.offsetParent !== null) { btn.click(); return; }
  var v = document.querySelector('video');
  if (v && isFinite(v.duration)) { v.currentTime = v.duration; }
})();
''';

  /// Best effort: previous button if present, otherwise restart the track.
  static const String previous = r'''
(function () {
  var btn = document.querySelector('.ytp-prev-button');
  if (btn && btn.offsetParent !== null) { btn.click(); return; }
  var v = document.querySelector('video');
  if (v) { v.currentTime = 0; }
})();
''';

  /// Tells the page whether the app is in the background.
  static String setBackground(bool value) =>
      'if (window.__bgtube) { window.__bgtube.setBackground($value); }';
}
