import 'package:flutter/material.dart';

class RootBackGuard extends StatelessWidget {
  final Widget child;

  const RootBackGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return PopScope(canPop: false, child: child);
  }
}
