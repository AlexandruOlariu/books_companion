import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../library/domain/models.dart';
import '../domain/friends_models.dart';
import 'friends_providers.dart';

/// A friend's published shelf, read-only. It is a snapshot they chose to share
/// and is kept apart from the reader's own library: it never feeds their
/// journal, statistics, or keepsakes.
class FriendShelfScreen extends ConsumerWidget {
  final String id;
  final String name;
  const FriendShelfScreen({super.key, required this.id, required this.name});

  Future<void> remove(BuildContext context, WidgetRef ref, bool block) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(block ? 'Block $name?' : 'Remove $name?'),
        content: Text(
          block
              ? 'You will no longer be friends, and neither of you will be able to find the other or send requests.'
              : 'You will no longer see each other\'s shelves. You can send a new request later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(block ? 'Block' : 'Remove'),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    final api = ref.read(friendsApiProvider);
    final ok = await runFriends(context, ref, () async {
      block ? await api.block(id) : await api.removeFriend(id);
      return true;
    });
    if (ok != true) return;
    ref
      ..invalidate(friendsProvider)
      ..invalidate(blockedProvider)
      ..invalidate(friendShelfProvider(id));
    if (context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      title: Text(name),
      actions: [
        PopupMenuButton<bool>(
          tooltip: 'More',
          onSelected: (block) => remove(context, ref, block),
          itemBuilder: (_) => const [
            PopupMenuItem(value: false, child: Text('Remove friend')),
            PopupMenuItem(value: true, child: Text('Block')),
          ],
        ),
      ],
    ),
    body: ref
        .watch(friendShelfProvider(id))
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
                        : 'Could not load this shelf.',
                    textAlign: TextAlign.center,
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(friendShelfProvider(id)),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
          data: (shelf) => shelf == null
              ? EmptyRoom(
                  title: 'Nothing shared yet',
                  message:
                      '$name has not shared a shelf, or has stopped sharing it.',
                )
              : _ShelfList(name: name, shelf: shelf),
        ),
  );
}

/// The most recent finish year (for ordering); unknown dates sort last.
int _recency(SharedBook b) =>
    b.finishes.map((f) => f.year ?? 0).fold(0, (a, y) => y > a ? y : a);

class _ShelfList extends StatelessWidget {
  final String name;
  final SharedShelf shelf;
  const _ShelfList({required this.name, required this.shelf});

  @override
  Widget build(BuildContext context) {
    List<SharedBook> of(BookStatus s) =>
        shelf.books.where((b) => b.status == s).toList();
    final reading = of(BookStatus.reading);
    final finished = of(BookStatus.finished)
      ..sort((a, b) {
        final byYear = _recency(b).compareTo(_recency(a));
        return byYear != 0
            ? byYear
            : a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    final wishlist = of(BookStatus.wantToRead);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          '${shelf.books.length} books, shared ${DateFormat.yMMMd().format(shelf.updatedAt.toLocal())}. This is a snapshot: it does not change until $name publishes again, and it is not part of your own journal or keepsakes.',
          style: const TextStyle(color: RoomColors.muted, height: 1.4),
        ),
        _group(context, 'Reading now', reading),
        _group(context, 'Finished', finished),
        _group(context, 'Wishlist', wishlist),
      ],
    );
  }

  Widget _group(BuildContext context, String title, List<SharedBook> books) =>
      books.isEmpty
      ? const SizedBox.shrink()
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 28, bottom: 8),
              child: Text(
                '$title (${books.length})',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            for (final b in books) _BookTile(book: b),
          ],
        );
}

class _BookTile extends StatelessWidget {
  final SharedBook book;
  const _BookTile({required this.book});
  @override
  Widget build(BuildContext context) {
    final finishes = book.finishes.map((f) => f.label).join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            book.title,
            style: const TextStyle(fontWeight: FontWeight.w600, height: 1.3),
          ),
          if (book.author.isNotEmpty)
            Text(book.author, style: const TextStyle(color: RoomColors.muted)),
          if (finishes.isNotEmpty)
            Text(
              book.status == BookStatus.reading
                  ? 'Read before: $finishes'
                  : 'Finished: $finishes',
              style: const TextStyle(color: RoomColors.forest),
            ),
        ],
      ),
    );
  }
}
