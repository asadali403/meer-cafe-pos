import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/home_shell.dart';
import '../screens/login/change_password_screen.dart';
import '../screens/login/database_error_screen.dart';
import '../screens/login/first_run_screen.dart';
import '../screens/login/login_screen.dart';
import 'app_controller.dart';
import 'theme.dart';

class MeerCafeApp extends StatelessWidget {
  const MeerCafeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final stage = context.select<AppController, AppStage>((c) => c.stage);
    final userId = context.select<AppController, int?>((c) => c.user?.id);
    return MaterialApp(
      title: 'Meer Cafe POS',
      debugShowCheckedModeBanner: false,
      theme: buildMeerTheme(),
      home: switch (stage) {
        AppStage.loading => const _Splash(),
        AppStage.databaseError => const DatabaseErrorScreen(),
        AppStage.firstRun => const FirstRunScreen(),
        AppStage.login => const LoginScreen(),
        AppStage.changePassword => const ChangePasswordScreen(forced: true),
        AppStage.home => HomeShell(key: ValueKey('home-$userId')),
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: MeerColors.black,
        body: Center(child: CircularProgressIndicator(color: MeerColors.gold)),
      );
}
