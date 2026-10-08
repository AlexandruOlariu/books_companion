import 'package:flutter_test/flutter_test.dart';
import 'package:reading_library/features/library/domain/models.dart';
import 'package:reading_library/features/recommendations/domain/recommendations.dart';

void main() {
  var n = 0;
  BookEntry book(
    String title,
    String author,
    BookStatus status, {
    String? series,
    int? number,
    String? id,
    int? rating,
  }) {
    final i = id ?? 'b${n++}';
    return BookEntry(
      id: i,
      bookId: i,
      editionId: i,
      title: title,
      author: author,
      status: status,
      seriesName: series,
      seriesNumber: number,
      rating: rating,
    );
  }

  Completion done(BookEntry b) => Completion(
    id: 'c${n++}',
    userBookId: b.id,
    finish: const PartialDate.unknown(),
    source: 'entered_past',
  );

  LibrarySnapshot library(
    List<BookEntry> books, {
    List<Completion> completions = const [],
    List<BookPin> pins = const [],
  }) => LibrarySnapshot(books: books, completions: completions, pins: pins);

  const finished = BookStatus.finished,
      wishlist = BookStatus.wantToRead,
      reading = BookStatus.reading;

  group('library suggestions', () {
    test('an empty or unrelated library suggests nothing', () {
      expect(libraryRecommendations(library([])), isEmpty);
      expect(
        libraryRecommendations(
          library([
            book('Dune', 'Frank Herbert', finished),
            book('Emma', 'Jane Austen', wishlist),
          ]),
        ),
        isEmpty,
        reason: 'one finished book is no reason to pick an unrelated wishlist',
      );
    });

    test('offers the book after the last finished one in a series', () {
      final recs = libraryRecommendations(
        library([
          book('Dune', 'Frank Herbert', finished, series: 'Dune', number: 1),
          book('Messiah', 'Frank Herbert', finished, series: 'Dune', number: 2),
        ]),
      );
      expect(recs, hasLength(1));
      expect(recs.single.kind, RecommendationKind.nextInSeries);
      expect(recs.single.seriesNumber, 3);
      expect(recs.single.heading, 'Dune, book 3');
      expect(recs.single.author, 'Frank Herbert');
      expect(recs.single.bookId, isNull);
      expect(recs.single.reason, contains('not on your shelf'));
    });

    test('a series gap uses the highest finished number', () {
      final recs = libraryRecommendations(
        library([
          book('One', 'A B', finished, series: 'S', number: 1),
          book('Four', 'A B', finished, series: 'S', number: 4),
        ]),
      );
      expect(recs.single.seriesNumber, 5);
    });

    test('a Wishlist book that is next is offered as itself', () {
      final recs = libraryRecommendations(
        library([
          book('Dune', 'Frank Herbert', finished, series: 'Dune', number: 1),
          book(
            'Messiah',
            'Frank Herbert',
            wishlist,
            series: 'dune',
            number: 2,
            id: 'w',
          ),
        ]),
      );
      expect(recs, hasLength(1));
      expect(recs.single.kind, RecommendationKind.nextOnWishlist);
      expect(recs.single.bookId, 'w');
      expect(recs.single.title, 'Messiah');
    });

    test('nothing when the next book is already being read', () {
      expect(
        libraryRecommendations(
          library([
            book('Dune', 'Frank Herbert', finished, series: 'Dune', number: 1),
            book('Messiah', 'F H', reading, series: 'Dune', number: 2),
          ]),
        ),
        isEmpty,
      );
    });

    test('unnumbered or unfinished series books give no next number', () {
      expect(
        libraryRecommendations(
          library([
            book('A', 'X Y', finished, series: 'S'),
            book('B', 'P Q', wishlist, series: 'T', number: 1),
          ]),
        ),
        isEmpty,
      );
    });

    test('Wishlist books by an author the reader has finished', () {
      final a1 = book('Housemaid', 'Freida McFadden', finished);
      final a2 = book('Boyfriend', 'McFadden, Freida', finished);
      final recs = libraryRecommendations(
        library([
          a1,
          a2,
          book('Teacher', 'Freida McFadden', wishlist, id: 'w1'),
          book('Emma', 'Jane Austen', wishlist),
        ]),
      );
      expect(recs, hasLength(1));
      expect(recs.single.kind, RecommendationKind.wishlistByAuthor);
      expect(recs.single.bookId, 'w1');
      expect(recs.single.reason, contains('finished 2 books by'));
    });

    test('authors read more, or loved, come first', () {
      final f1 = book('A1', 'Ann Lee', finished);
      final f2 = book('B1', 'Bob Ray', finished);
      final f3 = book('B2', 'Bob Ray', finished);
      final f4 = book('C1', 'Cy Poe', finished);
      final favourite = BookPin(
        id: 'p',
        userBookId: f4.id,
        text: 'x',
        type: 'Favorite',
      );
      final recs = libraryRecommendations(
        library(
          [
            f1,
            f2,
            f3,
            f4,
            book('Ann next', 'Ann Lee', wishlist),
            book('Bob next', 'Bob Ray', wishlist),
            book('Cy next', 'Cy Poe', wishlist),
          ],
          completions: [done(f1), done(f2), done(f3), done(f4)],
          pins: [favourite],
        ),
      );
      expect(
        [for (final r in recs) r.title],
        [
          'Bob next', // 2 finished
          'Cy next', // 1 finished + a favourite
          'Ann next', // 1 finished
        ],
      );
      expect(recs[1].reason, contains('favourite'));
      expect(recs[0].reason, isNot(contains('favourite')));
    });

    test('a read-again book counts as loved', () {
      final f = book('A1', 'Ann Lee', finished);
      final g = book('B1', 'Bob Ray', finished);
      final recs = libraryRecommendations(
        library(
          [
            f,
            g,
            book('Ann next', 'Ann Lee', wishlist),
            book('Bob next', 'Bob Ray', wishlist),
          ],
          completions: [done(f), done(f), done(g)],
        ),
      );
      expect(recs.first.title, 'Ann next');
    });

    test('a low rating cancels a series follow-up; a high one is quoted', () {
      LibrarySnapshot s(int? rating) => library([
        book('One', 'A B', finished, series: 'S', number: 1, rating: 5),
        book('Two', 'A B', finished, series: 'S', number: 2, rating: rating),
      ]);
      expect(libraryRecommendations(s(2)), isEmpty);
      expect(libraryRecommendations(s(1)), isEmpty);
      expect(libraryRecommendations(s(3)), hasLength(1));
      expect(libraryRecommendations(s(null)), hasLength(1));
      expect(
        libraryRecommendations(s(5)).single.reason,
        contains('You rated book 2 5 of 5.'),
      );
    });

    test('books rated 1 or 2 stars say nothing in an author\'s favour', () {
      LibrarySnapshot s(List<int?> ratings, {String author = 'Ann Lee'}) =>
          library([
            for (final (i, r) in ratings.indexed)
              book('Read $i', author, finished, rating: r),
            book('Next', author, wishlist),
          ]);
      expect(libraryRecommendations(s([1])), isEmpty);
      expect(libraryRecommendations(s([2, 1])), isEmpty);
      final mixed = libraryRecommendations(s([1, null])).single;
      expect(mixed.reason, contains('finished 2 books by'));
      expect(mixed.reason, isNot(contains('rated highly')));
    });

    test('a rating of 4 or 5 counts as loved and ranks higher', () {
      final recs = libraryRecommendations(
        library([
          book('A1', 'Ann Lee', finished, rating: 3),
          book('B1', 'Bob Ray', finished, rating: 5),
          book('Ann next', 'Ann Lee', wishlist),
          book('Bob next', 'Bob Ray', wishlist),
        ]),
      );
      expect([for (final r in recs) r.title], ['Bob next', 'Ann next']);
      expect(recs.first.reason, contains('rated highly'));
      expect(recs.last.reason, isNot(contains('rated highly')));
    });

    test('dismissed suggestions stay hidden', () {
      final books = [
        book('One', 'A B', finished, series: 'S', number: 1),
        book('W', 'A B', wishlist, id: 'w'),
      ];
      final all = libraryRecommendations(library(books));
      expect(all, hasLength(2));
      final rest = libraryRecommendations(
        library(books),
        dismissed: {all.first.key},
      );
      expect(rest.map((r) => r.key), isNot(contains(all.first.key)));
      expect(rest, hasLength(1));
      expect(
        libraryRecommendations(
          library(books),
          dismissed: {for (final r in all) r.key},
        ),
        isEmpty,
      );
    });

    test('each group is capped', () {
      final books = <BookEntry>[
        for (var i = 0; i < 9; i++)
          book('F$i', 'A$i B', finished, series: 'Series $i', number: 1),
      ];
      expect(libraryRecommendations(library(books)), hasLength(maxPerGroup));
    });
  });

  group('friend suggestions', () {
    FriendShelf shelf(String name, List<(String, String)> books) => FriendShelf(
      name: name,
      books: [for (final (t, a) in books) SharedTitle(t, a)],
    );

    test('skips books the reader already has in any status', () {
      final recs = friendRecommendations(
        library([
          book('The Hobbit', 'J.R.R. Tolkien', wishlist),
          book('Dune', 'Frank Herbert', reading),
          book('Emma', 'Jane Austen', finished),
        ]),
        [
          shelf('Ana', [
            ('Hobbit', 'Tolkien, J.R.R.'),
            ('Dune', 'Frank Herbert'),
            ('Emma', 'Jane Austen'),
            ('Ulysses', 'James Joyce'),
          ]),
        ],
      );
      expect([for (final r in recs) r.title], ['Ulysses']);
      expect(recs.single.kind, RecommendationKind.friendsRead);
      expect(recs.single.reason, 'Finished by Ana.');
    });

    test('more friends first, then authors the reader already reads', () {
      final f = book('Own', 'Zed Quill', finished);
      final recs = friendRecommendations(library([f]), [
        shelf('Ana', [
          ('Solo', 'Ola Nord'),
          ('Pair', 'Pia Sol'),
          ('Zed2', 'Zed Quill'),
        ]),
        shelf('Bob', [('Pair', 'Pia Sol')]),
      ]);
      expect([for (final r in recs) r.title], ['Pair', 'Zed2', 'Solo']);
      expect(recs.first.friends, ['Ana', 'Bob']);
      expect(recs.first.reason, 'Finished by Ana and Bob.');
      expect(recs[1].reason, contains('You finished 1 book by Zed Quill'));
    });

    test('the same friend twice counts once; many friends are summarised', () {
      final recs = friendRecommendations(library([]), [
        shelf('Ana', [('T', 'A B'), ('T', 'A B')]),
        shelf('Bob', [('T', 'A B')]),
        shelf('Cris', [('T', 'A B')]),
        shelf('Dan', [('T', 'A B')]),
      ]);
      expect(recs.single.friends, hasLength(4));
      expect(
        recs.single.reason,
        startsWith('Finished by Ana, Bob and 2 more.'),
      );
    });

    test('ignores blank entries and honours dismissals', () {
      final shelves = [
        shelf('Ana', [('', 'A B'), ('T', ''), ('Real', 'A B')]),
      ];
      final recs = friendRecommendations(library([]), shelves);
      expect(recs.map((r) => r.title), ['Real']);
      expect(
        friendRecommendations(
          library([]),
          shelves,
          dismissed: {recs.single.key},
        ),
        isEmpty,
      );
    });

    test('friends\' books by a disliked author are not tied to affinity', () {
      final recs = friendRecommendations(
        library([book('Bad', 'Zed Quill', finished, rating: 1)]),
        [
          FriendShelf(
            name: 'Ana',
            books: const [SharedTitle('Zed2', 'Zed Quill')],
          ),
        ],
      );
      expect(recs.single.reason, 'Finished by Ana.');
    });

    test('identity ignores case, diacritics, articles and name order', () {
      expect(
        bookIdentity('Moromeții', 'Marin Preda'),
        bookIdentity('the moromeții', 'PREDA, Marin'),
      );
    });
  });
}
