import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'device_services.dart';

DeviceServices createDeviceServices() => WebDeviceServices();

class WebDeviceServices extends DeviceServices {
  Timer? _completion;
  late final JSFunction _listener;
  @override
  bool get fullscreen => web.document.fullscreenElement != null;
  @override
  Future<void> initialize() async {
    _listener = ((web.Event event) {
      notifyListeners();
    }).toJS;
    web.document.addEventListener('fullscreenchange', _listener);
  }

  @override
  Future<void> toggleFullscreen() async {
    try {
      if (fullscreen) {
        await web.document.exitFullscreen().toDart;
      } else {
        await web.document.documentElement!.requestFullscreen().toDart;
      }
    } catch (_) {
      /* Unsupported or gesture-restricted browser. */
    }
  }

  @override
  Future<void> feedback(int milliseconds, {required bool completed}) async {
    if (milliseconds <= 0) return;
    try {
      web.window.navigator.vibrate(milliseconds.toJS);
      if (completed) {
        _completion?.cancel();
        _completion = Timer(const Duration(milliseconds: 120), () {
          try {
            web.window.navigator.vibrate(
              [100, 80, 100, 80, 300].map((v) => v.toJS).toList().toJS,
            );
          } catch (_) {
            /* unsupported */
          }
        });
      }
    } catch (_) {
      /* navigator.vibrate is optional. */
    }
  }

  @override
  void cancelFeedback() {
    _completion?.cancel();
    try {
      web.window.navigator.vibrate(0.toJS);
    } catch (_) {
      /* unsupported */
    }
  }

  @override
  void dispose() {
    cancelFeedback();
    web.document.removeEventListener('fullscreenchange', _listener);
    super.dispose();
  }
}
