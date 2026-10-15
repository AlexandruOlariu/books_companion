import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../domain/friends_models.dart';
import 'friends_providers.dart';
import 'person_row.dart';

/// How many people are waiting for an answer to a friend request.
final pendingRequestCountProvider = Provider<int>(
  (ref) => ref.watch(friendRequestsProvider).value?.incoming.length ?? 0,
);

/// The bell in the top bar. It shows only for a signed-in reader (never in the
/// demo) and carries the number of friend requests waiting for an answer.
class NotificationsButton extends ConsumerWidget {
  const NotificationsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(demoProvider) || ref.watch(signedInProvider).value != true) {
      return const SizedBox.shrink();
    }
    final count = ref.watch(pendingRequestCountProvider);
    return IconButton(
      tooltip: count == 0
          ? 'Notifications'
          : 'Notifications, $count friend ${count == 1 ? 'request' : 'requests'}',
      onPressed: () => context.push('/notifications'),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: Icon(
          count > 0 ? Icons.notifications : Icons.notifications_outlined,
        ),
      ),
    );
  }
}

/// What needs the reader's answer. The server keeps no history of what
/// happened, so this lists what is true now: the friend requests waiting.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  Future<void> _answer(
    BuildContext context,
    WidgetRef ref,
    Person person, {
    required bool accept,
  }) async {
    final api = ref.read(friendsApiProvider);
    final ok = await runFriends(context, ref, () async {
      if (accept) {
        await api.acceptRequest(person.id);
      } else {
        await api.declineOrCancelRequest(person.id);
      }
      return true;
    });
    if (ok != true) return;
    ref
      ..invalidate(friendRequestsProvider)
      ..invalidate(friendsProvider);
    if (accept && context.mounted) {
      notifyUser(context, 'You and ${person.displayName} are now friends.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Notifications')),
    body: ref
        .watch(friendRequestsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Could not load your notifications.',
                    textAlign: TextAlign.center,
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(friendRequestsProvider),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
          data: (requests) => requests.incoming.isEmpty
              ? EmptyRoom(
                  title: 'Nothing new.',
                  message: 'When someone asks to be your friend, the request waits here for your answer.',
                  action: TextButton(
                    onPressed: () => context.push('/friends'),
                    child: const Text('Open Friends'),
                  ),
                )
              : ListView(
                  padding: screenPadding(context),
                  children: [
                    const Eyebrow('Friend requests'),
                    const SizedBox(height: 8),
                    const Text(
                      'Nobody becomes a friend until you accept. Friends can see the shelf you share, never your notes or ratings.',
                      style: TextStyle(color: RoomColors.muted, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    for (final p in requests.incoming)
                      PersonRow(
                        person: p,
                        actions: [
                          FilledButton(
                            onPressed: () =>
                                _answer(context, ref, p, accept: true),
                            child: const Text('Accept'),
                          ),
                          TextButton(
                            onPressed: () =>
                                _answer(context, ref, p, accept: false),
                            child: const Text('Decline'),
                          ),
                        ],
                      ),
                  ],
                ),
        ),
  );
}
