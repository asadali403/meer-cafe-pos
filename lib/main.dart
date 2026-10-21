import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/app.dart';
import 'app/app_controller.dart';
import 'database/app_database.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  for (final a in args) {
    if (a.startsWith('--data-dir=')) AppDatabase.dataDirOverride = a.substring('--data-dir='.length);
  }
  final controller = AppController()..init();
  runApp(ChangeNotifierProvider.value(value: controller, child: const MeerCafeApp()));
}
