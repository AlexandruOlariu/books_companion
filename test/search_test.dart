import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_library/app/app.dart';
import 'package:reading_library/app/providers.dart';
import 'package:reading_library/core/storage/database.dart';
import 'package:reading_library/features/library/data/local_library_repository.dart';
import 'package:reading_library/features/library/domain/models.dart';
import 'package:reading_library/features/library/domain/search.dart';

BookEntry book(String title, String author, [String id = '']) => BookEntry(
  id: id.isEmpty ? title : id,
  bookId: 'b',
  editionId: 'e',
  title: title,
  author: author,
  status: BookStatus.wantToRead,
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('matching', () {
    test('ignores diacritics in both directions', () {
      final b = book('Enigma Otiliei', 'George Călinescu');
      expect(matchesQuery(b, 'calinescu'), isTrue);
      expect(matchesQuery(b, 'CĂLINESCU'), isTrue);
      expect(
        matchesQuery(book('Moromeții', 'Marin Preda'), 'moromeții'),
        isTrue,
      );
      expect(
        matchesQuery(book('Moromeții', 'Marin Preda'), 'morometii'),
        isTrue,
      );
      expect(matchesQuery(book('Țara', 'x'), 'tara'), isTrue);
      expect(matchesQuery(book('Șoapte', 'x'), 'soapte'), isTrue);
    });

    test('words match in any order, with stray spaces and punctuation', () {
      final b = book('It Ends with Us', 'Colleen Hoover');
      expect(matchesQuery(b, 'hoover colleen'), isTrue);
      expect(matchesQuery(b, '  it   ends  '), isTrue);
      expect(matchesQuery(b, 'it-ends, with'), isTrue);
      expect(matchesQuery(b, 'hoover tolkien'), isFalse);
    });

    test('partial words and an empty query', () {
      final b = book('The Housemaid', 'Freida McFadden');
      expect(matchesQuery(b, 'freid'), isTrue);
      expect(matchesQuery(b, 'mcf hous'), isTrue);
      expect(matchesQuery(b, ''), isTrue);
      expect(matchesQuery(b, '   '), isTrue);
    });
  });

  group('ranking', () {
    test('exact and leading matches come first, ties keep library order', () {
      final books = [
        book('Beyond the Housemaid', 'Someone Else', 'a'),
        book('Housemaid', 'Other Author', 'b'),
        book('The Housemaid', 'Freida McFadden', 'c'),
        book('Freida', 'Another Writer', 'd'),
      ];
      // 'b' is an exact title; 'a' and 'c' tie, so the library order decides.
      expect(searchBooks(books, 'housemaid').map((b) => b.id), ['b', 'a', 'c']);
      expect(searchBooks(books, 'freida').map((b) => b.id), ['d', 'c']);
      expect(searchBooks(books, '').map((b) => b.id), ['a', 'b', 'c', 'd']);
    });
  });

  group('library screen', () {
    Future<LocalLibraryRepository> openApp(WidgetTester tester) async {
      // A phone-sized screen, not the default 800x600 desktop test surface.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final repo = LocalLibraryRepository(AppDatabase(NativeDatabase.memory()));
      addTearDown(repo.db.close);
      await repo.saveBook(
        title: 'The Housemaid',
        author: 'Freida McFadden',
        pageCount: 330,
        status: BookStatus.wantToRead,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [repositoryProvider.overrideWithValue(repo)],
          child: const ReadingLibraryApp(),
        ),
      );
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('a search hidden by the status filter says so and recovers', (
      tester,
    ) async {
      await openApp(tester);
      await tester.tap(find.text('Finished'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'freida');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('hidden by the Finished filter'),
        findsOneWidget,
      );
      // A search miss must not tell the reader to add their *first* book.
      expect(find.text('Add your first book'), findsNothing);
      // Reachable the way a reader reaches it: by dragging the page up.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show it'));
      await tester.pumpAndSettle();
      expect(find.text('1 BOOK ON THE SHELF'), findsOneWidget);
    });

    testWidgets('a real miss offers to add, and the field can be cleared', (
      tester,
    ) async {
      await openApp(tester);
      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();
      expect(find.textContaining('No book matches'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('1 BOOK ON THE SHELF'), findsOneWidget);
    });

    testWidgets('finds by author words in any order, ignoring diacritics', (
      tester,
    ) async {
      await openApp(tester);
      await tester.enterText(find.byType(TextField), 'mcfadden FREIDA');
      await tester.pumpAndSettle();
      expect(find.text('1 BOOK ON THE SHELF'), findsOneWidget);
    });
  });
}
