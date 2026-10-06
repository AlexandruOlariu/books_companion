import 'package:flutter_test/flutter_test.dart';
import 'package:reading_library/features/friends/domain/friends_models.dart';
import 'package:reading_library/features/library/domain/models.dart';

BookEntry book(String id, BookStatus status, {String title = 'T'}) => BookEntry(
  id: id,
  bookId: 'b$id',
  editionId: 'e$id',
  title: title,
  author: 'A',
  status: status,
);

Completion done(String bookId, PartialDate date) => Completion(
  id: 'c$bookId${date.value}',
  userBookId: bookId,
  finish: date,
  source: 'entered_past',
);

void main() {
  test('only titles, authors, status, and finish dates are published', () {
    final shared = sharedBooksFrom(
      LibrarySnapshot(
        books: [
          BookEntry(
            id: '1',
            bookId: 'b',
            editionId: 'e',
            title: 'Dune',
            author: 'Frank Herbert',
            status: BookStatus.finished,
            coverPath: '/private/cover.jpg',
            seriesName: 'Dune',
            seriesNumber: 1,
            pageCount: 600,
            currentPage: 600,
          ),
        ],
        completions: [done('1', PartialDate(DatePrecision.year, '2021'))],
        pins: const [
          BookPin(
            id: 'p',
            userBookId: '1',
            text: 'a private thought',
            type: 'quote',
          ),
        ],
        sessions: [
          ReadingActivity(
            id: 's',
            userBookId: '1',
            startedAt: DateTime(2021, 3, 4),
            durationSeconds: 600,
          ),
        ],
      ),
    );
    expect(shared, hasLength(1));
    expect(shared.single.title, 'Dune');
    expect(shared.single.author, 'Frank Herbert');
    expect(shared.single.status, BookStatus.finished);
    // SharedBook has no field for notes, pins, sessions, covers, or progress:
    // what is sent is limited by the type, not by remembering to leave it out.
    expect(
      shared.single.finishes.single.precision,
      DatePrecision.year,
      reason: 'a remembered year stays a year',
    );
    expect(shared.single.finishes.single.value, '2021');
  });

  test('every precision is carried over unchanged', () {
    final dates = [
      PartialDate(DatePrecision.day, '2020-02-29'),
      PartialDate(DatePrecision.month, '2019-07'),
      PartialDate(DatePrecision.year, '2018'),
      const PartialDate.unknown(),
    ];
    final shared = sharedBooksFrom(
      LibrarySnapshot(
        books: [book('1', BookStatus.finished)],
        completions: [for (final d in dates) done('1', d)],
      ),
    );
    expect(
      shared.single.finishes.map((d) => (d.precision, d.value)),
      dates.map((d) => (d.precision, d.value)),
    );
  });

  test(
    'a finished book with no recorded finish is sent as unknown, not dated',
    () {
      final shared = sharedBooksFrom(
        LibrarySnapshot(books: [book('1', BookStatus.finished)]),
      );
      expect(shared.single.finishes.single.precision, DatePrecision.unknown);
      expect(shared.single.finishes.single.value, isNull);
    },
  );

  test('wishlist books carry no finishes; a re-read keeps earlier ones', () {
    final shared = sharedBooksFrom(
      LibrarySnapshot(
        books: [
          book('w', BookStatus.wantToRead),
          book('r', BookStatus.reading),
        ],
        completions: [
          done('w', PartialDate(DatePrecision.year, '2000')),
          done('r', PartialDate(DatePrecision.year, '2001')),
        ],
      ),
    );
    expect(shared.firstWhere((b) => b.id == 'w').finishes, isEmpty);
    expect(shared.firstWhere((b) => b.id == 'r').finishes, hasLength(1));
  });

  test('over-long titles are clipped to the server limit', () {
    final shared = sharedBooksFrom(
      LibrarySnapshot(
        books: [book('1', BookStatus.wantToRead, title: 'x' * 500)],
      ),
    );
    expect(shared.single.title.length, 300);
  });

  test('an empty library publishes nothing', () {
    expect(sharedBooksFrom(const LibrarySnapshot()), isEmpty);
  });
}
