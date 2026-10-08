import 'package:intl/intl.dart';

enum BookStatus { reading, wantToRead, finished }

extension BookStatusLabel on BookStatus {
  String get label => switch (this) {
    BookStatus.reading => 'Reading',
    // Stored as `want_to_read`; shown as Wishlist.
    BookStatus.wantToRead => 'Wishlist',
    BookStatus.finished => 'Finished',
  };
}

enum DatePrecision { day, month, year, unknown }

/// A memory of a date, never a synthetic calendar date.
class PartialDate {
  final DatePrecision precision;
  final String? value;
  const PartialDate.unknown() : precision = DatePrecision.unknown, value = null;
  factory PartialDate(DatePrecision precision, String? value) {
    if (precision == DatePrecision.unknown) {
      if (value != null) {
        throw const FormatException('Unknown dates must be empty.');
      }
      return const PartialDate.unknown();
    }
    final pattern = switch (precision) {
      DatePrecision.day => r'^\d{4}-\d{2}-\d{2}$',
      DatePrecision.month => r'^\d{4}-\d{2}$',
      _ => r'^\d{4}$',
    };
    if (value == null || !RegExp(pattern).hasMatch(value)) {
      throw const FormatException('Choose a date with the selected precision.');
    }
    final parts = value.split('-').map(int.parse).toList();
    if (parts[0] < 1 ||
        parts[0] > 9999 ||
        (parts.length > 1 && (parts[1] < 1 || parts[1] > 12)) ||
        (parts.length > 2 &&
            (parts[2] < 1 ||
                parts[2] > DateTime(parts[0], parts[1] + 1, 0).day))) {
      throw const FormatException('This date is not valid.');
    }
    return PartialDate._(precision, value);
  }
  const PartialDate._(this.precision, this.value);
  int? get year => value == null ? null : int.parse(value!.substring(0, 4));
  int? get month => value != null && value!.length >= 7
      ? int.parse(value!.substring(5, 7))
      : null;
  String get label => switch (precision) {
    DatePrecision.unknown => 'Date unknown',
    DatePrecision.year => value!,
    DatePrecision.month => DateFormat.yMMMM().format(DateTime(year!, month!)),
    DatePrecision.day => DateFormat.yMMMd().format(DateTime.parse(value!)),
  };
}

/// A cover address the app may fetch again: Open Library's cover host only, so
/// a restored library or a synced one can never make the app download from
/// anywhere else.
bool isOpenLibraryCoverUrl(String url) => RegExp(
  r'^https://covers\.openlibrary\.org/b/id/\d{1,12}-L\.jpg(\?default=false)?$',
).hasMatch(url);

class BookEntry {
  final String id, bookId, editionId, title, author;
  final String? language, coverPath, coverSource, seriesName;
  final int? pageCount, seriesNumber;

  /// The reader's own rating, 1 to [maxRating], or null (not rated). Only the
  /// reader sets it; it is never inferred, shared with friends, or used for
  /// keepsakes.
  final int? rating;
  final int currentPage;
  final BookStatus status;
  const BookEntry({
    required this.id,
    required this.bookId,
    required this.editionId,
    required this.title,
    required this.author,
    required this.status,
    this.language,
    this.coverPath,
    this.coverSource,
    this.pageCount,
    this.seriesName,
    this.seriesNumber,
    this.rating,
    this.currentPage = 0,
  });

  /// "Dune, book 2" when the book belongs to a series; null otherwise.
  String? get seriesLabel => seriesName == null
      ? null
      : seriesNumber == null
      ? seriesName
      : '$seriesName, book $seriesNumber';
  double? get progress =>
      pageCount == null ? null : (currentPage / pageCount!).clamp(0, 1);
  String get progressLabel => pageCount == null
      ? 'Page $currentPage'
      : '$currentPage of $pageCount pages';
}

/// The highest rating; ratings are whole stars from 1 to this.
const maxRating = 5;

void validateRating(int? rating) {
  if (rating != null && (rating < 1 || rating > maxRating)) {
    throw const FormatException('A rating is 1 to 5 stars.');
  }
}

class Completion {
  final String id, userBookId, source;
  final PartialDate finish;
  const Completion({
    required this.id,
    required this.userBookId,
    required this.finish,
    required this.source,
  });
}

class ReadingActivity {
  final String id, userBookId;
  final DateTime startedAt;
  final int? startPage, endPage, durationSeconds;
  const ReadingActivity({
    required this.id,
    required this.userBookId,
    required this.startedAt,
    this.startPage,
    this.endPage,
    this.durationSeconds,
  });
  int get pages =>
      startPage == null || endPage == null ? 0 : endPage! - startPage!;
}

class BookPin {
  final String id, userBookId, text, type;
  final int? page;
  final double? percent;
  const BookPin({
    required this.id,
    required this.userBookId,
    required this.text,
    required this.type,
    this.page,
    this.percent,
  });
}

class LibrarySnapshot {
  final List<BookEntry> books;
  final List<Completion> completions;
  final List<ReadingActivity> sessions;
  final List<BookPin> pins;
  const LibrarySnapshot({
    this.books = const [],
    this.completions = const [],
    this.sessions = const [],
    this.pins = const [],
  });
  List<Completion> finishesIn(int? year) =>
      completions.where((c) => year == null || c.finish.year == year).toList();
  List<ReadingActivity> activityIn(int? year) =>
      sessions.where((s) => year == null || s.startedAt.year == year).toList();
  int pagesLogged(int? year) => activityIn(year).fold(0, (n, s) => n + s.pages);
  int secondsLogged(int? year) =>
      activityIn(year).fold(0, (n, s) => n + (s.durationSeconds ?? 0));
  List<int> get years => ({
    DateTime.now().year,
    ...completions.map((c) => c.finish.year).whereType<int>(),
    ...sessions.map((s) => s.startedAt.year),
  }.toList()..sort((a, b) => b.compareTo(a)));
}

void validatePage(int page, int? total) {
  if (page < 0 || (total != null && page > total)) {
    throw FormatException(
      total == null
          ? 'Page must be zero or more.'
          : 'Enter a page between 0 and $total.',
    );
  }
}

void validateSession(int? start, int? end, int? seconds, int? total) {
  if ((start == null) != (end == null)) {
    throw const FormatException('Enter both starting and ending pages.');
  }
  if (start != null && end != null) {
    validatePage(start, total);
    validatePage(end, total);
    if (end < start) {
      throw const FormatException(
        'Ending page must be at least the starting page.',
      );
    }
  }
  if (seconds != null && seconds <= 0) {
    throw const FormatException('Duration must be greater than zero.');
  }
  if ((start == null || start == end) && seconds == null) {
    throw const FormatException('Enter pages read or a duration.');
  }
}

abstract class LibraryRepository {
  Future<LibrarySnapshot> load();
  Future<String> saveBook({
    String? id,
    required String title,
    required String author,
    int? pageCount,
    String? language,
    String? coverPath,
    String? coverSource,
    required BookStatus status,
    PartialDate? finish,
    bool historical = false,
    String metadataSource = 'manual',
    String? seriesName,
    int? seriesNumber,
  });
  Future<Set<String>> coverPaths();

  /// Editions whose cover came from Open Library but is not on this device
  /// (a library restored or synced from another phone).
  Future<List<({String editionId, String source})>> coversToFetch();

  /// Stores a cover file fetched later for [editionId]. Not a change to the
  /// library itself, so it is never synced.
  Future<void> attachCover(String editionId, String path);
  Future<void> updatePage(String id, int page);
  Future<void> setStatus(String id, BookStatus status, {PartialDate? finish});

  /// Sets (1 to 5) or clears (null) the reader's rating of a book they have
  /// finished at least once. A rating survives reading the book again.
  Future<void> setRating(String id, int? rating);
  Future<void> logSession(
    String id,
    DateTime date, {
    int? start,
    int? end,
    int? seconds,
  });
  Future<void> addPin(
    String id,
    String text,
    String type, {
    int? page,
    double? percent,
  });
  Future<void> deletePin(String id);
  Future<void> deleteBook(String id);
  Future<Map<String, dynamic>> exportData();
  Future<void> restoreData(Map<String, dynamic> data);
}
