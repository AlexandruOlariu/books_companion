import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/book_cover.dart';
import '../../../core/widgets/common.dart';
import '../../library/domain/models.dart';
import '../domain/recommendations.dart';
import 'recommendations_providers.dart';

/// "What to read next": suggestions from the reader's own shelf and from what
/// friends finished. It shows nothing at all when there is nothing honest to
/// suggest, and never adds a book by itself.
class RecommendationsSection extends ConsumerWidget {
  final LibrarySnapshot data;
  const RecommendationsSection({super.key, required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissed = ref.watch(dismissedRecommendationsProvider);
    final own = libraryRecommendations(data, dismissed: dismissed);
    final shelves =
        ref.watch(friendShelvesForSuggestionsProvider).value ?? const [];
    final friends = friendRecommendations(data, shelves, dismissed: dismissed);
    if (own.isEmpty && friends.isEmpty) return const SizedBox.shrink();

    List<Recommendation> of(Set<RecommendationKind> kinds) => [
      for (final r in own)
        if (kinds.contains(r.kind)) r,
    ];
    final groups = [
      (
        'Continue a series',
        of({
          RecommendationKind.nextOnWishlist,
          RecommendationKind.nextInSeries,
        }),
      ),
      ('From your Wishlist', of({RecommendationKind.wishlistByAuthor})),
      ('Your friends finished', friends),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Ideas for later'),
          const SizedBox(height: 12),
          Text(
            'What to read next',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Taken from your own shelf and from books your friends finished. '
            'Nothing is added unless you choose.',
            style: TextStyle(color: RoomColors.muted, height: 1.5),
          ),
          for (final (label, items) in groups)
            if (items.isNotEmpty) ...[
              const SizedBox(height: 24),
              Semantics(header: true, child: Eyebrow(label)),
              const SizedBox(height: 12),
              for (final item in items) _RecommendationCard(item),
            ],
        ],
      ),
    );
  }
}

class _RecommendationCard extends ConsumerWidget {
  final Recommendation item;
  const _RecommendationCard(this.item);

  /// Only the Wishlist books are in the library; the rest get a generated
  /// cover, because covers are never shared and a missing volume has none.
  BookEntry get _cover => BookEntry(
    id: item.key,
    bookId: item.key,
    editionId: item.key,
    title: item.heading,
    author: item.author,
    status: BookStatus.wantToRead,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inLibrary = item.bookId != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          color: RoomColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: RoomColors.line),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: BookCover(book: _cover, width: 60, height: 90),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.heading,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (item.title.isNotEmpty && item.seriesName != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.seriesNumber == null
                          ? item.seriesName!
                          : '${item.seriesName}, book ${item.seriesNumber}',
                      style: const TextStyle(
                        color: RoomColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    item.author,
                    style: const TextStyle(color: RoomColors.muted),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.reason,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () => context.push(
                          inLibrary
                              ? '/book/${item.bookId}'
                              : Uri(
                                  path: '/add',
                                  queryParameters: {
                                    if (item.title.isNotEmpty)
                                      'title': item.title,
                                    'author': item.author,
                                    if (item.seriesName != null)
                                      'series': item.seriesName!,
                                    if (item.seriesNumber != null)
                                      'number': '${item.seriesNumber}',
                                  },
                                ).toString(),
                        ),
                        child: Text(
                          inLibrary ? 'Open book' : 'Add to Wishlist',
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          final dismissed = ref.read(
                            dismissedRecommendationsProvider.notifier,
                          );
                          dismissed.dismiss(item.key);
                          notifyUser(
                            context,
                            'Hidden. It will not be suggested again.',
                            action: SnackBarAction(
                              label: 'Undo',
                              onPressed: () => dismissed.restore(item.key),
                            ),
                          );
                        },
                        child: const Text('Not interested'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
