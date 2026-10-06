import 'models.dart';
import 'search.dart';

/// How the shelf and the list are ordered.
enum LibrarySort {
  title('Title (A–Z)', 'Title'),
  author('Author (A–Z)', 'Author'),
  recent('Recently added', 'Recent');

  const LibrarySort(this.label, this.shortLabel);
  final String label, shortLabel;

  String get description => switch (this) {
    LibrarySort.title =>
      'Alphabetical. Books in a series stay together, in order.',
    LibrarySort.author => 'By author surname. Series stay together, in order.',
    LibrarySort.recent => 'Newest first, as you added them.',
  };

  static LibrarySort fromName(String? name) =>
      LibrarySort.values.asNameMap()[name] ?? LibrarySort.title;
}

const _articles = {'the ', 'a ', 'an '};

/// A title as a shelf would file it: lower case, no diacritics, and without a
/// leading English article ("The Hobbit" sits under H).
String titleKey(String title) {
  final folded = foldForSearch(title);
  for (final article in _articles) {
    if (folded.startsWith(article) && folded.length > article.length) {
      return folded.substring(article.length);
    }
  }
  return folded;
}

/// The first author's surname, then the rest, for filing by author. Handles
/// "Given Surname", "Surname, Given", and several authors joined by commas
/// ("Kevin J. Anderson, Brian Herbert" files under Anderson).
String authorKey(String author) {
  final first = author.split(',').first.trim();
  final commaForm =
      author.contains(',') &&
      !first.contains(' ') &&
      author.substring(author.indexOf(',') + 1).trim().isNotEmpty;
  final words = foldForSearch(commaForm ? first : first).split(' ');
  if (words.isEmpty || words.first.isEmpty) return '';
  if (commaForm || words.length == 1) {
    final given = commaForm
        ? foldForSearch(author.substring(author.indexOf(',') + 1))
        : '';
    return '${words.first} $given'.trim();
  }
  return '${words.last} ${words.sublist(0, words.length - 1).join(' ')}';
}

// Books without a number sort after numbered ones in the same series.
const _unnumbered = 1 << 30;

/// Orders [books]. A series is kept together at the position of its name, in
/// number order; other books are filed by title. [LibrarySort.recent] returns
/// the books in the order given (the repository supplies newest first).
List<BookEntry> sortBooks(Iterable<BookEntry> books, LibrarySort sort) {
  final list = books.toList();
  if (sort == LibrarySort.recent) return list;
  String group(BookEntry b) => titleKey(b.seriesName ?? b.title);
  int number(BookEntry b) => b.seriesNumber ?? _unnumbered;
  int compare(BookEntry a, BookEntry b) {
    var c = 0;
    if (sort == LibrarySort.author) {
      c = authorKey(a.author).compareTo(authorKey(b.author));
    }
    if (c == 0) c = group(a).compareTo(group(b));
    if (c == 0) c = number(a).compareTo(number(b));
    if (c == 0) c = titleKey(a.title).compareTo(titleKey(b.title));
    return c;
  }

  // Decorate with the original index so equal books keep their given order.
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((x, y) {
    final c = compare(x.$2, y.$2);
    return c != 0 ? c : x.$1.compareTo(y.$1);
  });
  return [for (final e in indexed) e.$2];
}
