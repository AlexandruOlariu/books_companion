import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/book_cover.dart';
import '../../../core/widgets/common.dart';
import '../../library/domain/models.dart';
import '../domain/recommendations.dart';

/// What the reader chose in the details sheet. The card carries it out, so the
/// sheet itself never touches the library.
enum RecommendationChoice { primary, dismiss }

/// More about one suggestion, from what this phone knows and nothing else: the
/// reason, the book's details when it is already in the library, the reader's
/// own books of the same series, and who finished it. No lookup is made.
Future<RecommendationChoice?> showRecommendationSheet(
  BuildContext context,
  Recommendation item,
  LibrarySnapshot data,
) {
  ScaffoldMessenger.of(context).removeCurrentSnackBar();
  return showModalBottomSheet<RecommendationChoice>(
    context: context,
    isScrollControlled: true,
    // Above the tab bar, so the buttons are never covered by it.
    useRootNavigator: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => RecommendationSheet(item: item, data: data),
  );
}

class RecommendationSheet extends StatelessWidget {
  final Recommendation item;
  final LibrarySnapshot data;
  const RecommendationSheet({
    super.key,
    required this.item,
    required this.data,
  });

  BookEntry? get _owned {
    final id = item.bookId;
    if (id == null) return null;
    for (final b in data.books) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// A generated cover unless the book is in the library (friends never share
  /// covers and an unseen volume has none).
  BookEntry get _cover =>
      _owned ??
      BookEntry(
        id: item.key,
        bookId: item.key,
        editionId: item.key,
        title: item.heading,
        author: item.author,
        status: BookStatus.wantToRead,
      );

  @override
  Widget build(BuildContext context) {
    final owned = _owned;
    final theme = Theme.of(context);
    final series = item.seriesName == null
        ? const <BookEntry>[]
        : seriesShelf(data, item.seriesName!);
    final facts = [
      if (owned?.pageCount != null) '${owned!.pageCount} pages',
      if (owned?.language != null) owned!.language!,
      if (owned != null) 'On your ${owned.status.label}',
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: BookCover(book: _cover, width: 90, height: 135),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          item.heading,
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      if (item.title.isNotEmpty && item.seriesName != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.seriesNumber == null
                              ? item.seriesName!
                              : '${item.seriesName}, book ${item.seriesNumber}',
                          style: const TextStyle(color: RoomColors.muted),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        item.author,
                        style: const TextStyle(color: RoomColors.muted),
                      ),
                      if (facts.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          facts.join(' · '),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Eyebrow('Why it is suggested'),
            const SizedBox(height: 8),
            Text(item.reason, style: const TextStyle(height: 1.5)),
            if (item.friends.length > 2) ...[
              const SizedBox(height: 8),
              Text(
                'Finished by ${item.friends.join(', ')}.',
                style: const TextStyle(height: 1.5),
              ),
            ],
            if (item.seriesName != null) ...[
              const SizedBox(height: 20),
              Eyebrow('Your shelf in ${item.seriesName}'),
              const SizedBox(height: 8),
              _SeriesList(item: item, books: series),
            ],
            const SizedBox(height: 16),
            Text(
              owned == null
                  ? 'This is all the app knows about it. Nothing is looked up '
                        'online, and nothing is added unless you choose.'
                  : 'Nothing is looked up online. Open the book to see its '
                        'full page.',
              style: const TextStyle(
                color: RoomColors.muted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, RecommendationChoice.primary),
                  child: Text(owned != null ? 'Open book' : 'Add to Wishlist'),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.pop(context, RecommendationChoice.dismiss),
                  child: const Text('Not interested'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The reader's books of the series in number order, with the suggested
/// volume marked where it would sit when it is not on the shelf.
class _SeriesList extends StatelessWidget {
  final Recommendation item;
  final List<BookEntry> books;
  const _SeriesList({required this.item, required this.books});

  @override
  Widget build(BuildContext context) {
    final rows = <({int? number, String title, String note, bool suggested})>[
      for (final b in books)
        (
          number: b.seriesNumber,
          title: b.title,
          note: [
            b.status.label,
            if (b.rating != null) '${b.rating} of $maxRating stars',
          ].join(' · '),
          suggested: b.id == item.bookId,
        ),
    ];
    if (item.bookId == null && item.seriesNumber != null) {
      rows.add((
        number: item.seriesNumber,
        title: 'Suggested',
        note: 'Not on your shelf',
        suggested: true,
      ));
    }
    rows.sort((a, b) {
      if (a.number == null || b.number == null) {
        return a.number == null ? (b.number == null ? 0 : 1) : -1;
      }
      return a.number!.compareTo(b.number!);
    });
    return Column(
      children: [
        for (final r in rows)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: r.suggested ? RoomColors.surface : null,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: r.suggested ? RoomColors.muted : RoomColors.line,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    r.number == null ? '' : '${r.number}',
                    style: const TextStyle(
                      color: RoomColors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    r.title,
                    style: TextStyle(
                      fontWeight: r.suggested ? FontWeight.w600 : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    r.note,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      color: RoomColors.muted,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
