import 'package:flutter/material.dart';

import '../../friends/presentation/account_panel.dart';

/// Shown before anything else while nobody is signed in: the library is saved
/// to the account, so the app asks for one first.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: SafeArea(child: AccountPanel()));
}
