import '../../library/domain/models.dart';
import '../../library/domain/sorting.dart';

/// Where a suggestion comes from. Each one says so in words, so the reader can
/// always see why a book is offered.
enum RecommendationKind {
  /// The next numbered book of a series the reader has been finishing, which
  /// is not on any of their shelves yet.
  nextInSeries,

  /// A Wishlist book that continues a series the reader has been finishing.
  nextOnWishlist,

  /// A Wishlist book by an author the reader has finished before.
  wishlistByAuthor,

  /// A book friends finished that is not in the reader's library.
  friendsRead,
}

/// One suggestion. It never changes the library: adding a book is always the
/// reader's own step, through the normal form.
class Recommendation {
  /// Stable between runs, so "Not interested" can be remembered.
  final String key;
  final RecommendationKind kind;

  /// Empty for [RecommendationKind.nextInSeries]: the title of an unseen
  /// volume is not known, so it is shown as "Series, book N".
  final String title, author;
  final String? seriesName;
  final int? seriesNumber;

  /// The Wishlist book this refers to, when it is already in the library.
  final String? bookId;
  final String reason;

  /// The friends who finished it (display names), for [friendsRead].
  final List<String> friends;
  const Recommendation({
    required this.key,
    required this.kind,
    required this.title,
    required this.author,
    required this.reason,
    this.seriesName,
    this.seriesNumber,
    this.bookId,
    this.friends = const [],
  });

  String get heading => title.isNotEmpty
      ? title
      : seriesNumber == null
      ? seriesName ?? ''
      : '$seriesName, book $seriesNumber';
}

/// A friend's published shelf, reduced to what suggestions need.
class FriendShelf {
  final String name;
  final List<SharedTitle> books;
  const FriendShelf({required this.name, required this.books});
}

/// A book a friend finished. Titles and authors only: friends never share
/// covers, notes, or anything else.
class SharedTitle {
  final String title, author;
  const SharedTitle(this.title, this.author);
}

/// The suggestions shown at most per group.
const maxPerGroup = 5;

String _surname(String author) => authorKey(author).split(' ').first;

/// A book as the shelf would recognise it: the same title and author surname,
/// ignoring case, diacritics, a leading "The", and "Given Surname" against
/// "Surname, Given".
String bookIdentity(String title, String author) =>
    '${titleKey(title)}|${_surname(author)}';

String _seriesKey(String name) => titleKey(name);

/// How much the reader has read of each author: finished books, and how many
/// of those they read again or pinned as a favourite. Keyed by author surname.
class _Affinity {
  int finished = 0, loved = 0;
}

Map<String, _Affinity> _authorAffinity(LibrarySnapshot library) {
  final completions = <String, int>{};
  for (final c in library.completions) {
    completions[c.userBookId] = (completions[c.userBookId] ?? 0) + 1;
  }
  final favourites = {
    for (final p in library.pins)
      if (p.type.toLowerCase() == 'favorite') p.userBookId,
  };
  final result = <String, _Affinity>{};
  for (final book in library.books) {
    if (book.status != BookStatus.finished) continue;
    final a = result.putIfAbsent(_surname(book.author), _Affinity.new);
    a.finished++;
    if ((completions[book.id] ?? 0) > 1 || favourites.contains(book.id)) {
      a.loved++;
    }
  }
  result.remove('');
  return result;
}

String _books(int n) => n == 1 ? '1 book' : '$n books';

/// Suggestions drawn only from the reader's own library: no network, nothing
/// invented. [dismissed] holds the keys the reader said no to.
///
/// - **Next in a series:** for each series with numbered finished books, the
///   book after the highest finished number. If it is on the Wishlist it is
///   offered to start; if it is not in the library at all it is offered to
///   add; if it is being read, nothing is offered. The series' real length is
///   unknown, so the last book of a finished series is offered too; the
///   reader dismisses it.
/// - **Wishlist by a known author:** Wishlist books whose author the reader has
///   finished, ordered by how much they have read of that author (finished
///   books, plus any they read again or pinned as a favourite).
List<Recommendation> libraryRecommendations(
  LibrarySnapshot library, {
  Set<String> dismissed = const {},
}) {
  final result = <Recommendation>[];
  final inSeries = <String, List<BookEntry>>{};
  for (final book in library.books) {
    final name = book.seriesName;
    if (name == null) continue;
    inSeries.putIfAbsent(_seriesKey(name), () => []).add(book);
  }

  // Series first, the most finished books at the top.
  final series = <({int finished, Recommendation rec})>[];
  final handledWishlist = <String>{};
  for (final entry in inSeries.entries) {
    final books = entry.value;
    final finished = books.where(
      (b) => b.status == BookStatus.finished && b.seriesNumber != null,
    );
    if (finished.isEmpty) continue;
    final last = finished.map((b) => b.seriesNumber!).reduce(_max);
    final next = last + 1;
    final existing = books.where((b) => b.seriesNumber == next).toList();
    final seriesName = finished.first.seriesName!;
    final reason = last == 1
        ? 'You finished book 1 of $seriesName.'
        : 'You finished ${_books(finished.length)} of $seriesName, up to book $last.';
    if (existing.isEmpty) {
      final key = 'series:${entry.key}:$next';
      if (dismissed.contains(key)) continue;
      series.add((
        finished: finished.length,
        rec: Recommendation(
          key: key,
          kind: RecommendationKind.nextInSeries,
          title: '',
          author: finished.first.author,
          seriesName: seriesName,
          seriesNumber: next,
          reason: '$reason Book $next is not on your shelf.',
        ),
      ));
    } else if (existing.first.status == BookStatus.wantToRead) {
      final book = existing.first;
      handledWishlist.add(book.id);
      final key = 'wish:${book.id}';
      if (dismissed.contains(key)) continue;
      series.add((
        finished: finished.length,
        rec: Recommendation(
          key: key,
          kind: RecommendationKind.nextOnWishlist,
          title: book.title,
          author: book.author,
          seriesName: book.seriesName,
          seriesNumber: book.seriesNumber,
          bookId: book.id,
          reason: '$reason It is on your Wishlist.',
        ),
      ));
    }
  }
  series.sort((a, b) {
    final c = b.finished.compareTo(a.finished);
    return c != 0 ? c : a.rec.heading.compareTo(b.rec.heading);
  });
  result.addAll(series.take(maxPerGroup).map((s) => s.rec));

  // Wishlist books by authors the reader already reads.
  final affinity = _authorAffinity(library);
  final wishlist = <({int weight, Recommendation rec})>[];
  for (final book in library.books) {
    if (book.status != BookStatus.wantToRead ||
        handledWishlist.contains(book.id)) {
      continue;
    }
    final a = affinity[_surname(book.author)];
    final key = 'wish:${book.id}';
    if (a == null || dismissed.contains(key)) continue;
    wishlist.add((
      weight: a.finished + a.loved,
      rec: Recommendation(
        key: key,
        kind: RecommendationKind.wishlistByAuthor,
        title: book.title,
        author: book.author,
        seriesName: book.seriesName,
        seriesNumber: book.seriesNumber,
        bookId: book.id,
        reason:
            'On your Wishlist. You finished ${_books(a.finished)} by ${book.author}.'
            '${a.loved > 0 ? ' You read one again or pinned a favourite.' : ''}',
      ),
    ));
  }
  wishlist.sort((a, b) {
    final c = b.weight.compareTo(a.weight);
    return c != 0 ? c : titleKey(a.rec.title).compareTo(titleKey(b.rec.title));
  });
  result.addAll(wishlist.take(maxPerGroup).map((s) => s.rec));
  return result;
}

int _max(int a, int b) => a > b ? a : b;

/// Books friends finished that the reader does not have in any status, most
/// friends first, then authors the reader already reads. Friends' shelves are
/// only read here; nothing from them is added to the library, its dates, its
/// activity, or its keepsakes.
List<Recommendation> friendRecommendations(
  LibrarySnapshot library,
  List<FriendShelf> shelves, {
  Set<String> dismissed = const {},
}) {
  final owned = {
    for (final b in library.books) bookIdentity(b.title, b.author),
  };
  final affinity = _authorAffinity(library);
  final found = <String, ({SharedTitle book, List<String> friends})>{};
  for (final shelf in shelves) {
    for (final book in shelf.books) {
      if (book.title.trim().isEmpty || book.author.trim().isEmpty) continue;
      final id = bookIdentity(book.title, book.author);
      if (owned.contains(id)) continue;
      final entry = found.putIfAbsent(id, () => (book: book, friends: []));
      if (!entry.friends.contains(shelf.name)) entry.friends.add(shelf.name);
    }
  }
  final ranked = <({int friends, int weight, Recommendation rec})>[];
  for (final MapEntry(key: id, value: entry) in found.entries) {
    final key = 'friend:$id';
    if (dismissed.contains(key)) continue;
    final a = affinity[_surname(entry.book.author)];
    final names = entry.friends;
    final who = names.length <= 2
        ? names.join(' and ')
        : '${names.take(2).join(', ')} and ${names.length - 2} more';
    ranked.add((
      friends: names.length,
      weight: a == null ? 0 : a.finished + a.loved,
      rec: Recommendation(
        key: key,
        kind: RecommendationKind.friendsRead,
        title: entry.book.title,
        author: entry.book.author,
        friends: names,
        reason:
            'Finished by $who.'
            '${a == null ? '' : ' You finished ${_books(a.finished)} by ${entry.book.author}.'}',
      ),
    ));
  }
  ranked.sort((a, b) {
    var c = b.friends.compareTo(a.friends);
    if (c == 0) c = b.weight.compareTo(a.weight);
    return c != 0 ? c : titleKey(a.rec.title).compareTo(titleKey(b.rec.title));
  });
  return [for (final r in ranked.take(maxPerGroup)) r.rec];
}
