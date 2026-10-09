import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../push/presentation/push_controller.dart';
import '../../push/presentation/push_prompts.dart';
import '../../sync/presentation/sync_controller.dart';
import '../domain/friends_models.dart';
import 'account_panel.dart';
import 'find_friends.dart';
import 'friends_providers.dart';
import 'person_row.dart';

class FriendsScreen extends ConsumerWidget {
  const FriendsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Friends')),
    body: ref
        .watch(accountProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    e is FriendsException
                        ? e.message
                        : 'Could not reach the Reading Library server.',
                    textAlign: TextAlign.center,
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(accountProvider),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
          data: (account) => account == null
              ? const AccountPanel()
              : _SignedIn(account: account),
        ),
  );
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 32, bottom: 12),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );
}

class _Muted extends StatelessWidget {
  final String text;
  const _Muted(this.text);
  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(color: RoomColors.muted, height: 1.4));
}

class _SignedIn extends ConsumerWidget {
  final Account account;
  const _SignedIn({required this.account});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: screenPadding(context),
    children: [
      const Eyebrow('Signed in'),
      const SizedBox(height: 12),
      Text(
        account.displayName,
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 4),
      Text(
        '@${account.username} · ${account.email}',
        style: const TextStyle(color: RoomColors.muted),
      ),
      const _SectionTitle('Your shelf for friends'),
      const _ShelfSharing(),
      const _Requests(),
      const _SectionTitle('Notifications'),
      const _Notifications(),
      const _SectionTitle('Friends'),
      const _FriendsList(),
      const _SectionTitle('Add a friend'),
      const FindFriends(),
      const _SectionTitle('Be found by phone'),
      _PhoneSettings(account: account),
      const _Blocked(),
      const _SectionTitle('Your account'),
      _AccountActions(account: account),
    ],
  );
}

// --- notifications ---------------------------------------------------------

class _Notifications extends ConsumerWidget {
  const _Notifications();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final push = ref.watch(pushControllerProvider);
    if (!push.available) {
      return const _Muted('This build of the app cannot send notifications.');
    }
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Friend requests'),
      subtitle: const Text(
        'A notification when someone asks to be your friend or accepts. It never shows a name or a book. Google delivers it.',
      ),
      value: push.enabled,
      onChanged: (on) async {
        final controller = ref.read(pushControllerProvider.notifier);
        if (!on) return controller.disable();
        final problem = pushProblem(await controller.enable());
        if (problem != null && context.mounted) notifyUser(context, problem);
      },
    );
  }
}

// --- the published shelf -------------------------------------------------

class _ShelfSharing extends ConsumerStatefulWidget {
  const _ShelfSharing();
  @override
  ConsumerState<_ShelfSharing> createState() => _ShelfSharingState();
}

class _ShelfSharingState extends ConsumerState<_ShelfSharing> {
  bool busy = false;

  Future<void> publish() async {
    final library = await ref.read(libraryProvider.future);
    final books = sharedBooksFrom(library);
    if (!mounted) return;
    if (books.isEmpty) {
      notifyUser(context, 'Add some books before sharing your shelf.');
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Share ${books.length} books with your friends?'),
        content: const Text(
          'They will see each title, author, status, and finish date, exactly as you recorded it (a year stays a year). Your ratings, notes, pins, reading sessions, and covers are never shared. Only accepted friends can see it, and you can stop sharing at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Share'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    setState(() => busy = true);
    final shelf = await runFriends(
      context,
      ref,
      () => ref.read(friendsApiProvider).publishShelf(books),
    );
    if (!mounted) return;
    setState(() => busy = false);
    if (shelf != null) {
      ref.invalidate(mySharedShelfProvider);
      notifyUser(context, 'Your shelf is shared with your friends.');
    }
  }

  Future<void> stop() async {
    setState(() => busy = true);
    final done = await runFriends(context, ref, () async {
      await ref.read(friendsApiProvider).unpublishShelf();
      return true;
    });
    if (!mounted) return;
    setState(() => busy = false);
    if (done == true) {
      ref.invalidate(mySharedShelfProvider);
      notifyUser(context, 'Your shelf is no longer shared.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final shelf = ref.watch(mySharedShelfProvider);
    final shared = shelf.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Muted(
          shelf.isLoading
              ? 'Checking…'
              : shelf.hasError
              ? 'Could not check what you share.'
              : shared == null
              ? 'Not shared. Friends cannot see any of your books. Friends see the shelf as it was when you last published it.'
              : '${shared.books.length} books shared, last published ${DateFormat.yMMMd().add_jm().format(shared.updatedAt.toLocal())}. Publish again to update it.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: busy ? null : publish,
              child: Text(
                shared == null ? 'Share my shelf' : 'Update shared shelf',
              ),
            ),
            if (shared != null)
              OutlinedButton(
                onPressed: busy ? null : stop,
                child: const Text('Stop sharing'),
              ),
          ],
        ),
      ],
    );
  }
}

// --- requests and friends ------------------------------------------------

class _Requests extends ConsumerWidget {
  const _Requests();

  Future<void> answer(
    BuildContext context,
    WidgetRef ref,
    Future<Object?> Function() action,
  ) async {
    final ok = await runFriends(context, ref, () async {
      await action();
      return true;
    });
    if (ok == true) {
      ref
        ..invalidate(friendRequestsProvider)
        ..invalidate(friendsProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(friendsApiProvider);
    final requests = ref.watch(friendRequestsProvider).value;
    if (requests == null ||
        (requests.incoming.isEmpty && requests.outgoing.isEmpty)) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Friend requests'),
        for (final p in requests.incoming)
          PersonRow(
            person: p,
            actions: [
              FilledButton(
                onPressed: () =>
                    answer(context, ref, () => api.acceptRequest(p.id)),
                child: const Text('Accept'),
              ),
              TextButton(
                onPressed: () => answer(
                  context,
                  ref,
                  () => api.declineOrCancelRequest(p.id),
                ),
                child: const Text('Decline'),
              ),
            ],
          ),
        for (final p in requests.outgoing)
          PersonRow(
            person: p,
            actions: [
              const Text(
                'Waiting for an answer',
                style: TextStyle(color: RoomColors.muted),
              ),
              TextButton(
                onPressed: () => answer(
                  context,
                  ref,
                  () => api.declineOrCancelRequest(p.id),
                ),
                child: const Text('Cancel request'),
              ),
            ],
          ),
      ],
    );
  }
}

class _FriendsList extends ConsumerWidget {
  const _FriendsList();
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(friendsProvider)
      .when(
        loading: () => const _Muted('Loading…'),
        error: (_, _) => const _Muted('Could not load your friends.'),
        data: (friends) => friends.isEmpty
            ? const _Muted(
                'No friends yet. Add someone by username or from your contacts. They have to accept before you see each other\'s shelves.',
              )
            : Column(
                children: [
                  for (final p in friends)
                    PersonRow(
                      person: p,
                      onTap: () => context.push(
                        '/friends/${p.id}?name=${Uri.encodeQueryComponent(p.displayName)}',
                      ),
                    ),
                ],
              ),
      );
}

// --- phone ---------------------------------------------------------------

class _PhoneSettings extends ConsumerStatefulWidget {
  final Account account;
  const _PhoneSettings({required this.account});
  @override
  ConsumerState<_PhoneSettings> createState() => _PhoneSettingsState();
}

class _PhoneSettingsState extends ConsumerState<_PhoneSettings> {
  final phone = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    phone.dispose();
    super.dispose();
  }

  Future<void> run(Future<Account> Function(FriendsApi api) action) async {
    setState(() => busy = true);
    final updated = await runFriends(
      context,
      ref,
      () => action(ref.read(friendsApiProvider)),
    );
    if (!mounted) return;
    setState(() => busy = false);
    if (updated != null) {
      phone.clear();
      ref.invalidate(accountProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Muted(
          'Optional. If you add your number and switch this on, people who have your number in their contacts can find you and ask to be friends. The server stores a scrambled code of the number, never the number itself. It does not check that the number is yours.',
        ),
        const SizedBox(height: 12),
        if (!account.hasPhone)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Your phone number',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: busy
                    ? null
                    : () => run(
                        (api) => api.setPhone(
                          phone.text,
                          region: ref.read(regionProvider),
                        ),
                      ),
                child: const Text('Save'),
              ),
            ],
          )
        else ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Let people find me by phone'),
            value: account.discoverableByPhone,
            onChanged: busy
                ? null
                : (v) => run((api) => api.setDiscoverable(v)),
          ),
          TextButton(
            onPressed: busy ? null : () => run((api) => api.removePhone()),
            child: const Text('Remove my number'),
          ),
        ],
      ],
    );
  }
}

// --- blocked and account -------------------------------------------------

class _Blocked extends ConsumerWidget {
  const _Blocked();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(blockedProvider).value;
    if (blocked == null || blocked.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Blocked'),
        for (final p in blocked)
          PersonRow(
            person: p,
            actions: [
              TextButton(
                onPressed: () async {
                  final ok = await runFriends(context, ref, () async {
                    await ref.read(friendsApiProvider).unblock(p.id);
                    return true;
                  });
                  if (ok == true) ref.invalidate(blockedProvider);
                },
                child: const Text('Unblock'),
              ),
            ],
          ),
      ],
    );
  }
}

class _AccountActions extends ConsumerWidget {
  final Account account;
  const _AccountActions({required this.account});

  Future<void> signOut(BuildContext context, WidgetRef ref) async {
    await ref.read(pushControllerProvider.notifier).signingOut();
    await ref.read(friendsApiProvider).signOut();
    resetFriendsData(ref);
  }

  Future<void> delete(BuildContext context, WidgetRef ref) async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (password == null || !context.mounted) return;
    final done = await runFriends(context, ref, () async {
      await ref.read(friendsApiProvider).deleteAccount(password: password);
      return true;
    });
    if (done == true) {
      // The server already forgot this phone; this clears Firebase's side.
      await ref.read(pushControllerProvider.notifier).signingOut();
      await ref.read(syncControllerProvider.notifier).accountDeleted();
      resetFriendsData(ref);
      if (context.mounted) notifyUser(context, 'Your account was deleted.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      OutlinedButton(
        onPressed: () => signOut(context, ref),
        child: const Text('Sign out'),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: () => delete(context, ref),
        style: TextButton.styleFrom(foregroundColor: RoomColors.terra),
        child: const Text('Delete my account'),
      ),
    ],
  );
}

/// Asks for the password again before erasing the account. Owns its controller
/// so it is disposed only after the dialog has finished closing.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();
  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final password = TextEditingController();

  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Delete your account?'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'This erases your account, your saved library, your friend list, and your shared shelf from the server. The library on this phone is not affected, and is saved again if you make a new account. This cannot be undone.',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Your password'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, password.text),
        child: const Text('Delete account'),
      ),
    ],
  );
}
