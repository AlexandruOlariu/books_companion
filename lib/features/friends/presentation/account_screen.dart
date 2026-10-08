import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../domain/account_rules.dart';
import '../domain/friends_models.dart';
import 'friends_providers.dart';

/// `/account`: change the name and username, or the password. Signing out and
/// deleting the account stay on the Friends page.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Your account')),
      body: account.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load your account.'),
                TextButton(
                  onPressed: () => ref.invalidate(accountProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (a) => a == null
            ? const Center(child: Text('Sign in to edit your account.'))
            : ListView(
                padding: screenPadding(context),
                children: [
                  _DetailsForm(account: a),
                  const SizedBox(height: 40),
                  const _PasswordForm(),
                ],
              ),
      ),
    );
  }
}

class _DetailsForm extends ConsumerStatefulWidget {
  final Account account;
  const _DetailsForm({required this.account});
  @override
  ConsumerState<_DetailsForm> createState() => _DetailsFormState();
}

class _DetailsFormState extends ConsumerState<_DetailsForm> {
  late final first = TextEditingController(text: widget.account.firstName);
  late final last = TextEditingController(text: widget.account.lastName);
  late final username = TextEditingController(text: widget.account.username);
  bool busy = false;
  String? error;

  @override
  void dispose() {
    for (final c in [first, last, username]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get changed =>
      first.text.trim() != widget.account.firstName ||
      last.text.trim() != widget.account.lastName ||
      username.text.trim().toLowerCase() != widget.account.username;

  Future<void> save() async {
    final problem =
        checkName(first.text, 'First name') ??
        checkName(last.text, 'Last name') ??
        checkUsername(username.text);
    if (problem != null) {
      setState(() => error = problem);
      return;
    }
    final account = widget.account;
    final newUsername = username.text.trim().toLowerCase();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      // Only what changed is sent.
      await ref
          .read(friendsApiProvider)
          .updateProfile(
            firstName: first.text.trim() == account.firstName
                ? null
                : first.text,
            lastName: last.text.trim() == account.lastName ? null : last.text,
            username: newUsername == account.username ? null : newUsername,
          );
      ref.invalidate(accountProvider);
      if (mounted) notifyUser(context, 'Details saved.');
    } on FriendsException catch (e) {
      if (e.signedOut) resetFriendsData(ref);
      if (mounted) setState(() => error = e.message);
    } on Object {
      if (mounted) setState(() => error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Eyebrow('Your details'),
      const SizedBox(height: 12),
      Text('Who you are', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 16),
      _field(first, 'First name'),
      _field(last, 'Last name'),
      _field(username, 'Username', action: TextInputAction.done),
      const Text(
        'Friends find you by your username, so people who have the old one will need the new one. Your name is what friends see next to your books.',
        style: TextStyle(color: RoomColors.muted, height: 1.4),
      ),
      const SizedBox(height: 12),
      Text(
        'Email: ${widget.account.email}. It cannot be changed here yet.',
        style: const TextStyle(color: RoomColors.muted, height: 1.4),
      ),
      if (error != null) _Error(error!),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: busy || !changed ? null : save,
        child: busy ? const _Spinner() : const Text('Save details'),
      ),
    ],
  );

  Widget _field(
    TextEditingController c,
    String label, {
    TextInputAction action = TextInputAction.next,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: c,
      textInputAction: action,
      autocorrect: false,
      onChanged: (_) => setState(() => error = null),
      decoration: InputDecoration(labelText: label),
    ),
  );
}

class _PasswordForm extends ConsumerStatefulWidget {
  const _PasswordForm();
  @override
  ConsumerState<_PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends ConsumerState<_PasswordForm> {
  final current = TextEditingController();
  final next = TextEditingController();
  final again = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    for (final c in [current, next, again]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    final problem = current.text.isEmpty
        ? 'Enter your current password.'
        : checkNewPassword(next.text, confirmation: again.text);
    if (problem != null) {
      setState(() => error = problem);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(friendsApiProvider)
          .changePassword(
            currentPassword: current.text,
            newPassword: next.text,
          );
      for (final c in [current, next, again]) {
        c.clear();
      }
      if (mounted) {
        notifyUser(context, 'Password changed. Other devices were signed out.');
      }
    } on FriendsException catch (e) {
      if (e.signedOut) resetFriendsData(ref);
      if (mounted) setState(() => error = e.message);
    } on Object {
      if (mounted) setState(() => error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Eyebrow('Your password'),
      const SizedBox(height: 12),
      Text(
        'Change password',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 16),
      _secret(current, 'Current password'),
      _secret(next, 'New password'),
      _secret(again, 'New password again', action: TextInputAction.done),
      const Text(
        'At least 10 characters. Every other phone signed in to this account is signed out. There is no password reset yet, so keep the new one somewhere safe.',
        style: TextStyle(color: RoomColors.muted, height: 1.4),
      ),
      if (error != null) _Error(error!),
      const SizedBox(height: 16),
      OutlinedButton(
        onPressed: busy ? null : save,
        child: busy ? const _Spinner() : const Text('Change password'),
      ),
    ],
  );

  Widget _secret(
    TextEditingController c,
    String label, {
    TextInputAction action = TextInputAction.next,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: c,
      obscureText: true,
      textInputAction: action,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: (_) => setState(() => error = null),
      decoration: InputDecoration(labelText: label),
    ),
  );
}

class _Error extends StatelessWidget {
  final String message;
  const _Error(this.message);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Text(
      message,
      style: const TextStyle(color: RoomColors.terra),
      semanticsLabel: 'Error: $message',
    ),
  );
}

class _Spinner extends StatelessWidget {
  const _Spinner();
  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 20,
    height: 20,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}
