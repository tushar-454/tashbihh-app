import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'package:window_manager/window_manager.dart';

import 'device_services.dart';

DeviceServices createDeviceServices() => NativeDeviceServices();

class NativeDeviceServices extends DeviceServices with WindowListener {
  @override
  Stream<void> get clockChanges =>
      defaultTargetPlatform == TargetPlatform.android
      ? const EventChannel('tasbih/local_clock')
            .receiveBroadcastStream()
            .map((_) {})
      : const Stream.empty();
  bool _fullscreen = false;
  bool _hasVibrator = false;
  Timer? _completion;
  bool get _desktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS);
  @override
  bool get fullscreen => _fullscreen;
  @override
  Future<void> initialize() async {
    if (_desktop) {
      await windowManager.ensureInitialized();
      windowManager.addListener(this);
      _fullscreen = await windowManager.isFullScreen();
    } else {
      try {
        _hasVibrator = await Vibration.hasVibrator();
      } catch (_) {
        /* unsupported hardware */
      }
    }
  }

  @override
  Future<void> toggleFullscreen() async {
    try {
      if (_desktop) {
        await windowManager.setFullScreen(!_fullscreen);
        _fullscreen = await windowManager.isFullScreen();
      } else {
        await SystemChrome.setEnabledSystemUIMode(
          _fullscreen ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
        );
        _fullscreen = !_fullscreen;
      }
      notifyListeners();
    } catch (_) {
      /* OS may reject a fullscreen request. */
    }
  }

  @override
  void onWindowEnterFullScreen() {
    _fullscreen = true;
    notifyListeners();
  }

  @override
  void onWindowLeaveFullScreen() {
    _fullscreen = false;
    notifyListeners();
  }

  @override
  Future<void> feedback(int milliseconds, {required bool completed}) async {
    if (_desktop || !_hasVibrator || milliseconds <= 0) return;
    try {
      await Vibration.vibrate(duration: milliseconds);
      if (completed) {
        _completion?.cancel();
        _completion = Timer(const Duration(milliseconds: 120), () async {
          try {
            await Vibration.vibrate(pattern: [0, 100, 80, 100, 80, 300]);
          } catch (_) {
            /* hardware fallback */
          }
        });
      }
    } catch (_) {
      /* No vibration must not affect the count. */
    }
  }

  @override
  void cancelFeedback() {
    _completion?.cancel();
    if (!_desktop && _hasVibrator) unawaited(Vibration.cancel());
  }

  @override
  void dispose() {
    cancelFeedback();
    if (_desktop) windowManager.removeListener(this);
    super.dispose();
  }
}
