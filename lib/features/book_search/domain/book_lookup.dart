/// A candidate edition from an online catalogue. Nothing here is saved until
/// the reader confirms the form.
class BookSuggestion {
  final String title, author;
  final int? pageCount, firstPublishYear;
  final String? language, coverUrl, thumbnailUrl;

  /// True when nothing matched every word, so this is only a close match.
  final bool approximate;
  const BookSuggestion({
    required this.title,
    required this.author,
    this.pageCount,
    this.firstPublishYear,
    this.language,
    this.coverUrl,
    this.thumbnailUrl,
    this.approximate = false,
  });

  BookSuggestion copyWith({bool? approximate}) => BookSuggestion(
    title: title,
    author: author,
    pageCount: pageCount,
    firstPublishYear: firstPublishYear,
    language: language,
    coverUrl: coverUrl,
    thumbnailUrl: thumbnailUrl,
    approximate: approximate ?? this.approximate,
  );
}

class LookupException implements Exception {
  final String message;
  const LookupException(this.message);
  @override
  String toString() => message;
}

abstract class BookLookup {
  /// Searches by title, author, or ISBN. Throws [LookupException] with a
  /// message that is safe to show when the catalogue cannot be reached.
  Future<List<BookSuggestion>> search(String query);

  /// Copies a suggestion's cover into app storage. Returns null when there is
  /// no usable cover; the caller keeps the book and falls back to a generated
  /// cover.
  Future<String?> fetchCover(BookSuggestion suggestion);
}

/// An ISBN-10 or ISBN-13, ignoring hyphens and spaces; null for other input.
String? isbnFrom(String query) {
  final compact = query.replaceAll(RegExp(r'[\s-]'), '');
  if (RegExp(r'^\d{13}$').hasMatch(compact) ||
      RegExp(r'^\d{9}[\dXx]$').hasMatch(compact)) {
    return compact.toUpperCase();
  }
  return null;
}
