import 'package:flutter/material.dart';

import '../core/platform/device_services.dart';
import '../features/counter/counter_controller.dart';
import '../features/counter/counter_screen.dart';
import 'theme/tasbih_theme.dart';

class TasbihApp extends StatelessWidget {
  const TasbihApp({super.key, required this.controller, required this.device});
  final CounterController controller;
  final DeviceServices device;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Tasbih Counter',
    debugShowCheckedModeBanner: false,
    theme: TasbihTheme.data,
    home: CounterScreen(controller: controller, device: device),
  );
}
