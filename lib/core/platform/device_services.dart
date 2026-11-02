import 'package:flutter/foundation.dart';

abstract class DeviceServices extends ChangeNotifier {
  bool get fullscreen;
  Future<void> initialize();
  Future<void> toggleFullscreen();
  Future<void> feedback(int milliseconds, {required bool completed});
  void cancelFeedback();
}
