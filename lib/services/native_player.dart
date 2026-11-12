import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef MediaActionCallback = void Function(String action);

/// Thin wrapper around the Kotlin side (foreground service, MediaSession,
/// notification, wake locks).
class NativePlayer {
  NativePlayer() {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  static const MethodChannel _channel = MethodChannel('bgtube/player');

  /// Called when the user presses a notification / lock-screen / headset
  /// button. Actions: play, pause, next, previous, stop.
  MediaActionCallback? onMediaAction;

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method == 'onMediaAction') {
      onMediaAction?.call(call.arguments as String);
    }
    return null;
  }

  Future<void> updatePlayback({
    required String title,
    required String artist,
    required bool playing,
  }) =>
      _invoke<void>('update', {
        'title': title,
        'artist': artist,
        'playing': playing,
      });

  Future<void> stopService() => _invoke<void>('stop');

  Future<void> moveToBackground() => _invoke<void>('moveToBack');

  Future<bool> isBatteryUnrestricted() async =>
      (await _invoke<bool>('isBatteryExempt')) ?? true;

  Future<void> requestBatteryUnrestricted() =>
      _invoke<void>('requestBatteryExemption');

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      debugPrint('NativePlayer.$method failed: ${e.code} ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
