import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_library/app/providers.dart';
import 'package:reading_library/core/storage/database.dart';
import 'package:reading_library/features/book_details/presentation/book_details_screen.dart';
import 'package:reading_library/features/library/data/local_library_repository.dart';
import 'package:reading_library/features/library/domain/models.dart';
import 'package:reading_library/features/library/presentation/book_form.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LocalLibraryRepository repo;
  setUp(
    () => repo = LocalLibraryRepository(AppDatabase(NativeDatabase.memory())),
  );
  tearDown(() => repo.db.close());

  Future<void> pump(WidgetTester tester, Widget home) async {
    // A phone: 360 x 800 logical.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<String> save(BookStatus status) => repo.saveBook(
    title: 'Dune',
    author: 'Frank Herbert',
    status: status,
    finish: status == BookStatus.finished ? const PartialDate.unknown() : null,
    historical: true,
  );

  Finder star(int n) => find.byKey(ValueKey('rating-star-$n'));
  Future<int?> rating() async => (await repo.load()).books.single.rating;

  group('book details', () {
    testWidgets('a finished book can be rated and the rating cleared', (
      tester,
    ) async {
      final id = await save(BookStatus.finished);
      await pump(tester, BookDetailsScreen(id: id));
      expect(find.text('Your rating: not rated. Only you see it.'), findsOne);

      await tester.tap(star(4));
      await tester.pumpAndSettle();
      expect(await rating(), 4);
      expect(find.text('Your rating: 4 of 5. Only you see it.'), findsOne);

      await tester.tap(star(2));
      await tester.pumpAndSettle();
      expect(await rating(), 2);

      // The chosen star again means "not rated".
      await tester.tap(star(2));
      await tester.pumpAndSettle();
      expect(await rating(), isNull);
      expect(find.text('Your rating: not rated. Only you see it.'), findsOne);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a book not yet finished offers no rating', (tester) async {
      final id = await save(BookStatus.wantToRead);
      await pump(tester, BookDetailsScreen(id: id));
      expect(star(3), findsNothing);
      expect(find.textContaining('Your rating'), findsNothing);
    });

    testWidgets('a book being read again keeps and shows its rating', (
      tester,
    ) async {
      final id = await save(BookStatus.finished);
      await repo.setRating(id, 5);
      await repo.setStatus(id, BookStatus.reading);
      await pump(tester, BookDetailsScreen(id: id));
      expect(find.text('Your rating: 5 of 5. Only you see it.'), findsOne);
    });

    testWidgets('stars are 48 px targets that fit a 360 px phone', (
      tester,
    ) async {
      final id = await save(BookStatus.finished);
      await pump(tester, BookDetailsScreen(id: id));
      for (var n = 1; n <= 5; n++) {
        final size = tester.getSize(star(n));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      expect(tester.getTopRight(star(5)).dx, lessThanOrEqualTo(360));
    });

    testWidgets('each star announces itself to a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final id = await save(BookStatus.finished);
      await repo.setRating(id, 3);
      await pump(tester, BookDetailsScreen(id: id));
      expect(
        tester.getSemantics(star(3)),
        matchesSemantics(
          label: '3 of 5 stars',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      expect(tester.getSemantics(star(4)).label, '4 of 5 stars');
      handle.dispose();
    });
  });

  group('add form', () {
    Future<void> fill(WidgetTester tester, {required bool finished}) async {
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Dune');
      await tester.enterText(
        find.widgetWithText(TextField, 'Author'),
        'Frank Herbert',
      );
      final addTo = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(addTo);
      await tester.tap(addTo);
      await tester.pumpAndSettle();
      await tester.tap(find.text(finished ? 'Finished' : 'Wishlist').last);
      await tester.pumpAndSettle();
    }

    Future<void> chooseUnknownDate(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Date precision'));
      await tester.tap(find.text('Date precision'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('I don’t remember').last);
      await tester.pumpAndSettle();
    }

    testWidgets('rating a book as it is added as Finished', (tester) async {
      await pump(tester, const BookForm());
      expect(star(3), findsNothing, reason: 'not for a Wishlist book');
      await fill(tester, finished: true);
      await chooseUnknownDate(tester);
      await tester.ensureVisible(star(5));
      await tester.tap(star(5));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save book'));
      await tester.tap(find.text('Save book'));
      await tester.pumpAndSettle();
      expect(await rating(), 5);
      expect((await repo.load()).completions, hasLength(1));
    });

    testWidgets('leaving it empty saves an unrated book', (tester) async {
      await pump(tester, const BookForm());
      await fill(tester, finished: true);
      await chooseUnknownDate(tester);
      await tester.ensureVisible(find.text('Save book'));
      await tester.tap(find.text('Save book'));
      await tester.pumpAndSettle();
      expect(await rating(), isNull);
    });

    testWidgets('changing to Wishlist drops a chosen rating', (tester) async {
      await pump(tester, const BookForm());
      await fill(tester, finished: true);
      await tester.ensureVisible(star(4));
      await tester.tap(star(4));
      await tester.pumpAndSettle();
      final addTo = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(addTo);
      await tester.tap(addTo);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wishlist').last);
      await tester.pumpAndSettle();
      expect(star(4), findsNothing);
      await tester.ensureVisible(find.text('Save book'));
      await tester.tap(find.text('Save book'));
      await tester.pumpAndSettle();
      final book = (await repo.load()).books.single;
      expect(book.status, BookStatus.wantToRead);
      expect(book.rating, isNull);
    });
  });
}
