import 'package:flutter_test/flutter_test.dart';
import 'package:reading_library/features/library/domain/models.dart';
import 'package:reading_library/features/library/domain/sorting.dart';

BookEntry book(
  String title,
  String author, {
  String? series,
  int? number,
  String id = '',
}) => BookEntry(
  id: id.isEmpty ? title : id,
  bookId: 'b',
  editionId: 'e',
  title: title,
  author: author,
  status: BookStatus.wantToRead,
  seriesName: series,
  seriesNumber: number,
);

List<String> order(List<BookEntry> books, LibrarySort sort) =>
    sortBooks(books, sort).map((b) => b.title).toList();

void main() {
  group('keys', () {
    test('titles are filed without a leading article or diacritics', () {
      expect(titleKey('The Hobbit'), 'hobbit');
      expect(titleKey('A Room of One’s Own'), 'room of one s own');
      expect(titleKey('An Ember'), 'ember');
      expect(titleKey('Țara'), 'tara');
      expect(titleKey('The'), 'the'); // an article alone is the title
    });

    test('authors file by surname in every common format', () {
      expect(authorKey('Frank Herbert'), 'herbert frank');
      expect(authorKey('George Călinescu'), 'calinescu george');
      expect(authorKey('Călinescu, George'), 'calinescu george');
      expect(authorKey('J.R.R. Tolkien'), 'tolkien j r r');
      // Several authors joined by commas: the first one decides.
      expect(authorKey('Kevin J. Anderson, Brian Herbert'), 'anderson kevin j');
      expect(authorKey('Plato'), 'plato');
      expect(authorKey(''), '');
    });
  });

  group('title sort', () {
    test('is alphabetical, ignoring case, articles, and diacritics', () {
      final books = [
        book('The Stranger', 'Camus'),
        book('Ulysses', 'Joyce'),
        book('A Room of One’s Own', 'Woolf'),
        book('Țara', 'x'),
        book('brave new world', 'Huxley'),
      ];
      expect(order(books, LibrarySort.title), [
        'brave new world',
        'A Room of One’s Own',
        'The Stranger',
        'Țara',
        'Ulysses',
      ]);
    });

    test('keeps a series together, in order, at the place of its name', () {
      final books = [
        book('Zorba', 'Kazantzakis'),
        book('Children of Dune', 'Herbert', series: 'Dune', number: 3),
        book('Brave New World', 'Huxley'),
        book('Dune', 'Herbert', series: 'Dune', number: 1),
        book('Emma', 'Austen'),
        book('Dune Messiah', 'Herbert', series: 'Dune', number: 2),
      ];
      expect(order(books, LibrarySort.title), [
        'Brave New World',
        'Dune',
        'Dune Messiah',
        'Children of Dune',
        'Emma',
        'Zorba',
      ]);
    });

    test('unnumbered books follow the numbered ones of their series', () {
      final books = [
        book('Companion', 'x', series: 'Saga'),
        book('Second', 'x', series: 'Saga', number: 2),
        book('First', 'x', series: 'Saga', number: 1),
      ];
      expect(order(books, LibrarySort.title), ['First', 'Second', 'Companion']);
    });

    test(
      'a series named like a standalone book still keeps its own together',
      () {
        final books = [
          book('Dune', 'Someone Else'),
          book('Dune Messiah', 'Herbert', series: 'Dune', number: 2),
          book('Dune', 'Herbert', series: 'Dune', number: 1),
        ];
        expect(
          sortBooks(
            books,
            LibrarySort.title,
          ).map((b) => b.seriesNumber).toList(),
          [1, 2, null],
        );
      },
    );
  });

  group('author sort', () {
    test('files by surname, then by series and title', () {
      final books = [
        book('Emma', 'Jane Austen'),
        book('Ulysses', 'James Joyce'),
        book('The Hobbit', 'J.R.R. Tolkien', series: 'Middle-earth', number: 1),
        book('Dune Messiah', 'Frank Herbert', series: 'Dune', number: 2),
        book('Dune', 'Frank Herbert', series: 'Dune', number: 1),
        book(
          'The Return of the King',
          'J.R.R. Tolkien',
          series: 'Middle-earth',
          number: 3,
        ),
        book('Brave New World', 'Aldous Huxley'),
      ];
      expect(order(books, LibrarySort.author), [
        'Emma',
        'Dune',
        'Dune Messiah',
        'Brave New World',
        'Ulysses',
        'The Hobbit',
        'The Return of the King',
      ]);
    });
  });

  group('recent', () {
    test('keeps the order given', () {
      final books = [book('Zeta', 'a'), book('Alpha', 'b'), book('Mid', 'c')];
      expect(order(books, LibrarySort.recent), ['Zeta', 'Alpha', 'Mid']);
    });
  });

  test('equal books keep their given order (stable)', () {
    final books = [
      book('Same', 'Same', id: '1'),
      book('Same', 'Same', id: '2'),
      book('Same', 'Same', id: '3'),
    ];
    for (final sort in [LibrarySort.title, LibrarySort.author]) {
      expect(sortBooks(books, sort).map((b) => b.id).toList(), ['1', '2', '3']);
    }
  });

  test('an unknown saved name falls back to Title', () {
    expect(LibrarySort.fromName('author'), LibrarySort.author);
    expect(LibrarySort.fromName('nonsense'), LibrarySort.title);
    expect(LibrarySort.fromName(null), LibrarySort.title);
  });
}
