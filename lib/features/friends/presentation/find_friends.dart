import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../domain/friends_models.dart';
import 'friends_providers.dart';
import 'person_row.dart';

/// Two ways to find someone: their exact username, or the phone numbers in the
/// reader's contacts. Neither adds a friend by itself: the other person has to
/// accept a request.
class FindFriends extends ConsumerStatefulWidget {
  const FindFriends({super.key});
  @override
  ConsumerState<FindFriends> createState() => _FindFriendsState();
}

class _FindFriendsState extends ConsumerState<FindFriends> {
  final username = TextEditingController();
  bool busy = false, searched = false;
  Person? found;
  List<Person>? fromContacts;
  String? contactsMessage;

  @override
  void dispose() {
    username.dispose();
    super.dispose();
  }

  Future<void> lookup() async {
    final text = username.text.trim();
    if (text.length < 3) {
      notifyUser(context, 'Enter the whole username (at least 3 characters).');
      return;
    }
    setState(() => busy = true);
    final result = await runFriends(
      context,
      ref,
      () async => (await ref.read(friendsApiProvider).lookup(text),),
    );
    if (!mounted) return;
    setState(() {
      busy = false;
      if (result != null) {
        searched = true;
        found = result.$1;
      }
    });
  }

  Future<void> request(Person person) async {
    final sent = await runFriends(
      context,
      ref,
      () => ref.read(friendsApiProvider).sendRequest(person.id),
    );
    if (sent == null || !mounted) return;
    ref
      ..invalidate(friendRequestsProvider)
      ..invalidate(friendsProvider);
    notifyUser(context, 'Request sent to ${person.displayName}.');
    setState(() {
      if (found?.id == person.id) found = null;
      fromContacts = fromContacts?.where((p) => p.id != person.id).toList();
    });
  }

  Future<void> findFromContacts() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Find friends from your contacts?'),
        content: const Text(
          'The app will ask to read your contacts, then send only the phone numbers (not names, emails, or photos) to the server. The server checks them against people who chose to be found by phone, answers, and does not keep them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    setState(() {
      busy = true;
      contactsMessage = null;
    });
    final outcome = await runFriends(context, ref, () async {
      final contacts = await ref.read(contactsSourceProvider).readNumbers();
      if (!contacts.granted) {
        return (granted: false, people: <Person>[], truncated: false);
      }
      final numbers = contacts.numbers.take(maxContactNumbersPerCheck).toList();
      final matches = numbers.isEmpty
          ? <Person>[]
          : await ref
                .read(friendsApiProvider)
                .matchContacts(numbers, region: ref.read(regionProvider));
      // People who are already friends or have a pending request are not new.
      final requests = await ref.read(friendRequestsProvider.future);
      final known = <String>{
        for (final p in await ref.read(friendsProvider.future)) p.id,
        for (final p in requests.incoming) p.id,
        for (final p in requests.outgoing) p.id,
      };
      return (
        granted: true,
        people: matches.where((p) => !known.contains(p.id)).toList(),
        truncated: contacts.numbers.length > maxContactNumbersPerCheck,
      );
    });
    if (!mounted) return;
    setState(() {
      busy = false;
      if (outcome == null) return; // The error was already shown.
      if (!outcome.granted) {
        fromContacts = null;
        contactsMessage = 'Contacts access was not given. You can still add friends by username.';
        return;
      }
      fromContacts = outcome.people;
      contactsMessage = outcome.truncated
          ? 'Only the first $maxContactNumbersPerCheck numbers were checked.'
          : null;
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: username,
              autocorrect: false,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => busy ? null : lookup(),
              decoration: const InputDecoration(
                labelText: 'Friend\'s username',
                helperText: 'The exact username, without the @',
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: busy ? null : lookup,
            child: const Text('Find'),
          ),
        ],
      ),
      if (searched && found == null)
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text(
            'No one has that username.',
            style: TextStyle(color: RoomColors.muted),
          ),
        ),
      if (found != null)
        PersonRow(
          person: found!,
          actions: [
            FilledButton(
              onPressed: () => request(found!),
              child: const Text('Send friend request'),
            ),
          ],
        ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: busy ? null : findFromContacts,
        icon: const Icon(Icons.contacts_outlined),
        label: const Text('Find friends from contacts'),
      ),
      if (contactsMessage != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(contactsMessage!),
        ),
      if (fromContacts != null) ...[
        const SizedBox(height: 12),
        if (fromContacts!.isEmpty)
          const Text(
            'No one in your contacts has chosen to be found by phone yet.',
            style: TextStyle(color: RoomColors.muted, height: 1.4),
          ),
        for (final person in fromContacts!)
          PersonRow(
            person: person,
            actions: [
              FilledButton(
                onPressed: () => request(person),
                child: const Text('Send friend request'),
              ),
            ],
          ),
      ],
    ],
  );
}
