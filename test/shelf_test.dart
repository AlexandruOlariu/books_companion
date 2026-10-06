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
import 'package:reading_library/features/library/presentation/keepsakes.dart';
import 'package:reading_library/features/library/presentation/shelf.dart';

BookEntry book(int i, {BookStatus status = BookStatus.finished, int? pages}) =>
    BookEntry(
      id: 'b$i',
      bookId: 'b$i',
      editionId: 'e$i',
      title: 'Book number $i',
      author: 'Author $i',
      status: status,
      pageCount: pages ?? 100 + i * 17,
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('keepsakes', () {
    test('are earned only by finished-book count', () {
      expect(Keepsake.earned(0), isEmpty);
      expect(Keepsake.earned(1), [Keepsake.bookend]);
      expect(Keepsake.earned(5), [
        Keepsake.bookend,
        Keepsake.plant,
        Keepsake.mug,
      ]);
      expect(Keepsake.earned(1000), Keepsake.values);
      expect(Keepsake.next(0), Keepsake.bookend);
      expect(Keepsake.next(5), Keepsake.candle);
      expect(Keepsake.next(25), isNull);
    });

    test('every keepsake is at least a tappable size', () {
      for (final k in Keepsake.values) {
        expect(k.size.width, greaterThanOrEqualTo(30));
        expect(k.size.height, greaterThanOrEqualTo(48));
      }
    });
  });

  group('packing', () {
    final books = [for (var i = 0; i < 60; i++) book(i)];

    test('every book appears once, in order, and no row overflows', () {
      for (final width in [280.0, 304.0, 400.0]) {
        final rows = packShelves(books, width, const []);
        final shelved = [
          for (final r in rows)
            for (final s in r.slots.whereType<BookSlot>()) s.book.id,
        ];
        expect(shelved, books.map((b) => b.id).toList());
        for (final r in rows) {
          expect(r.used, lessThanOrEqualTo(width));
          expect(r.slots, isNotEmpty);
        }
      }
    });

    test('books being read stand face-out and every slot is tappable', () {
      final rows = packShelves(
        [book(1, status: BookStatus.reading), book(2)],
        304,
        const [],
      );
      final slots = rows.expand((r) => r.slots.whereType<BookSlot>()).toList();
      expect(slots.first.faceOut, isTrue);
      for (final s in slots) {
        expect(s.width, greaterThanOrEqualTo(48));
        expect(s.height, greaterThanOrEqualTo(48));
      }
    });

    test('keepsakes are spread through the shelf, not piled at the end', () {
      final rows = packShelves(books, 304, Keepsake.values);
      final flat = rows.expand((r) => r.slots).toList();
      final at = [
        for (var i = 0; i < flat.length; i++)
          if (flat[i] is KeepsakeSlot) i,
      ];
      expect(at, hasLength(Keepsake.values.length));
      expect(at.first, lessThan(flat.length ~/ 4));
      expect(at.last, lessThan(flat.length - 2));
      // No two ornaments side by side.
      for (var i = 1; i < at.length; i++) {
        expect(at[i] - at[i - 1], greaterThan(1));
      }
    });

    test('a short shelf still holds its keepsakes, and none means none', () {
      final rows = packShelves([book(1)], 304, [Keepsake.bookend]);
      expect(
        rows.expand((r) => r.slots).whereType<KeepsakeSlot>(),
        hasLength(1),
      );
      expect(packShelves(const [], 304, const []), isEmpty);
    });
  });

  group('library screen', () {
    Future<void> open(WidgetTester tester, int finished) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final repo = LocalLibraryRepository(AppDatabase(NativeDatabase.memory()));
      addTearDown(repo.db.close);
      for (var i = 0; i < finished; i++) {
        await repo.saveBook(
          title: 'Finished $i',
          author: 'Someone',
          pageCount: 200,
          status: BookStatus.finished,
          finish: PartialDate(DatePrecision.year, '2020'),
          historical: true,
        );
      }
      await repo.saveBook(
        title: 'Waiting',
        author: 'Someone',
        status: BookStatus.wantToRead,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [repositoryProvider.overrideWithValue(repo)],
          child: const ReadingLibraryApp(),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> scrollDown(WidgetTester tester) async {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
    }

    testWidgets('the first finished book earns the first keepsake', (
      tester,
    ) async {
      await open(tester, 1);
      await scrollDown(tester);
      expect(
        find.bySemanticsLabel(RegExp('Shelf keepsake: Brass bookend')),
        findsOneWidget,
      );
      expect(find.textContaining('Keepsakes: 1 of 7'), findsOneWidget);
      expect(find.textContaining('never by streaks'), findsOneWidget);
    });

    testWidgets('no finished books means no keepsakes', (tester) async {
      await open(tester, 0);
      await scrollDown(tester);
      expect(find.bySemanticsLabel(RegExp('Shelf keepsake')), findsNothing);
      expect(find.textContaining('Finish 1 more book'), findsOneWidget);
    });

    testWidgets('a filter or search hides keepsakes, and tapping explains', (
      tester,
    ) async {
      await open(tester, 3);
      await scrollDown(tester);
      await tester.tap(find.bySemanticsLabel(RegExp('Shelf keepsake: Brass')));
      await tester.pump();
      expect(
        find.text('Brass bookend. Earned by finishing 1 book.'),
        findsOneWidget,
      );
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 800));
      await tester.pumpAndSettle();
      // The chip, not the selected-book panel, which can also say "Want to read".
      await tester.tap(find.widgetWithText(ChoiceChip, 'Want to read'));
      await tester.pumpAndSettle();
      await scrollDown(tester);
      expect(find.bySemanticsLabel(RegExp('Shelf keepsake')), findsNothing);
      expect(find.textContaining('Keepsakes:'), findsNothing);
    });
  });
}
