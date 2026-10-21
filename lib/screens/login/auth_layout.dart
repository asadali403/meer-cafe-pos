import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/common.dart';

/// Split-screen layout: black brand panel on the left, form card on the right.
class AuthLayout extends StatelessWidget {
  final Widget child;
  const AuthLayout({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 900;
    final form = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: child),
      ),
    );
    return Scaffold(
      body: Row(children: [
        if (wide)
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [MeerColors.black, MeerColors.graphite],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  MeerLogo(size: 280),
                  SizedBox(height: 24),
                  Text('Meer Cafe POS',
                      style: TextStyle(color: MeerColors.gold, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 1)),
                  SizedBox(height: 8),
                  Text('Our Circle. Your Place.',
                      style: TextStyle(color: Colors.white70, fontSize: 16, fontStyle: FontStyle.italic)),
                ]),
              ),
            ),
          ),
        Expanded(
          child: Container(
            color: MeerColors.surface,
            child: Column(children: [
              if (!wide) const Padding(padding: EdgeInsets.only(top: 32), child: MeerLogo(size: 120)),
              Expanded(child: form),
            ]),
          ),
        ),
      ]),
    );
  }
}
