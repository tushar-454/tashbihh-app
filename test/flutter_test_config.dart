import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tashbihh/core/localization/app_localizations.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await AppLocalizations.load();
  await testMain();
}
