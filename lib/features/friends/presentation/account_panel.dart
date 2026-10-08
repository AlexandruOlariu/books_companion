import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../sync/presentation/sync_controller.dart';
import '../domain/friends_models.dart';
import 'friends_providers.dart';

/// Sign in or create an account. The app shows it before anything else while
/// nobody is signed in, because the library is saved to the account. Nothing
/// is sent until the reader presses the button.
class AccountPanel extends ConsumerStatefulWidget {
  const AccountPanel({super.key});
  @override
  ConsumerState<AccountPanel> createState() => _AccountPanelState();
}

class _AccountPanelState extends ConsumerState<AccountPanel> {
  bool creating = false, busy = false;
  String? error;
  final email = TextEditingController();
  final password = TextEditingController();
  final first = TextEditingController();
  final last = TextEditingController();
  final username = TextEditingController();

  @override
  void dispose() {
    for (final c in [email, password, first, last, username]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    final needed = [
      email,
      password,
      if (creating) ...[first, last, username],
    ];
    if (needed.any((c) => c.text.trim().isEmpty)) {
      setState(() => error = 'Fill in every field.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final api = ref.read(friendsApiProvider);
    try {
      final Account account;
      if (creating) {
        account = await api.register(
          email: email.text,
          password: password.text,
          username: username.text,
          firstName: first.text,
          lastName: last.text,
        );
      } else {
        account = await api.signIn(email: email.text, password: password.text);
      }
      if (!mounted) return;
      resetFriendsData(ref);
      // Remember whose library this is and save it; the phone never waits.
      unawaited(ref.read(syncControllerProvider.notifier).signedIn(account.id));
    } on FriendsException catch (e) {
      if (mounted) setState(() => error = e.message);
    } on Object {
      if (mounted) setState(() => error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(
    TextEditingController controller,
    String label, {
    bool secret = false,
    TextInputType? type,
    TextInputAction action = TextInputAction.next,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      obscureText: secret,
      keyboardType: type,
      textInputAction: action,
      autocorrect: false,
      enableSuggestions: !secret,
      decoration: InputDecoration(labelText: label),
    ),
  );

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const Eyebrow('Your account'),
      const SizedBox(height: 16),
      Text(
        'Your reading room, kept safe.',
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 16),
      const Text(
        'Your library is saved to your account, so a lost or new phone never loses it. The app works without a connection and saves when it can. An account also lets you find friends.',
        style: TextStyle(height: 1.5),
      ),
      const SizedBox(height: 20),
      const _PrivacyNote(),
      const SizedBox(height: 24),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('Sign in')),
          ButtonSegment(value: true, label: Text('Create account')),
        ],
        selected: {creating},
        onSelectionChanged: busy
            ? null
            : (s) => setState(() {
                creating = s.first;
                error = null;
              }),
      ),
      const SizedBox(height: 20),
      if (creating) ...[
        field(first, 'First name'),
        field(last, 'Last name'),
        field(username, 'Username'),
      ],
      field(email, 'Email', type: TextInputType.emailAddress),
      field(password, 'Password', secret: true, action: TextInputAction.done),
      if (creating)
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'Username: 3 to 30 letters, digits, "_" or ".". Friends find you by it. Password: at least 10 characters. There is no password reset yet, so keep it somewhere safe.',
            style: TextStyle(color: RoomColors.muted, height: 1.4),
          ),
        ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            error!,
            style: const TextStyle(color: RoomColors.terra),
            semanticsLabel: 'Error: $error',
          ),
        ),
      FilledButton(
        onPressed: busy ? null : submit,
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(creating ? 'Create account' : 'Sign in'),
      ),
    ],
  );
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: RoomColors.surface,
      border: Border.all(color: RoomColors.line),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Text(
      'What is saved: your name, username, and email, and your whole library: books, finish dates, ratings, reading sessions, and your private notes and pins. It is kept on the developer\'s server and is not end-to-end encrypted. Covers found online are fetched again from Open Library; photos you chose yourself stay on this phone. Friends only ever see what you choose to publish: titles, authors, status, and finish dates.',
      style: TextStyle(height: 1.5),
    ),
  );
}
