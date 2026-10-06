import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_library/app/app.dart';
import 'package:reading_library/app/providers.dart';
import 'package:reading_library/core/storage/database.dart';
import 'package:reading_library/core/storage/preferences_store.dart';
import 'package:reading_library/features/library/data/local_library_repository.dart';
import 'package:reading_library/features/library/domain/models.dart';
import 'package:reading_library/features/library/presentation/library_screen.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<LocalLibraryRepository> newRepo(
    WidgetTester tester, {
    List<(String, String, String?, int?)> books = const [],
    double height = 2400,
  }) async {
    tester.view.physicalSize = Size(1080, height);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final repo = LocalLibraryRepository(AppDatabase(NativeDatabase.memory()));
    addTearDown(repo.db.close);
    for (final (title, author, series, number) in books) {
      await repo.saveBook(
        title: title,
        author: author,
        pageCount: 200,
        status: BookStatus.wantToRead,
        seriesName: series,
        seriesNumber: number,
      );
    }
    return repo;
  }

  Future<void> pumpApp(
    WidgetTester tester,
    LocalLibraryRepository repo, {
    PreferencesStore? prefs,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          if (prefs != null) preferencesProvider.overrideWithValue(prefs),
        ],
        child: const ReadingLibraryApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  String fieldText(WidgetTester tester, String label) => tester
      .widget<TextField>(find.widgetWithText(TextField, label))
      .controller!
      .text;

  Future<void> openAddForm(WidgetTester tester) async {
    await tester.tap(find.text('Add book').first);
    await tester.pumpAndSettle();
  }

  group('add form', () {
    testWidgets('has one Finished choice, not a confusing second one', (
      tester,
    ) async {
      await pumpApp(tester, await newRepo(tester));
      await openAddForm(tester);
      final addTo = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(addTo);
      await tester.tap(addTo);
      await tester.pumpAndSettle();
      expect(find.text('Finished'), findsOneWidget);
      expect(find.text('Reading now'), findsOneWidget);
      expect(find.text('Read in the past'), findsNothing);
    });

    testWidgets('keeps the series and moves the number on after Add another', (
      tester,
    ) async {
      final repo = await newRepo(tester);
      await pumpApp(tester, repo);
      await openAddForm(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Dune');
      await tester.enterText(
        find.widgetWithText(TextField, 'Author'),
        'Frank Herbert',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Series (optional)'),
        'Dune',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Book number in the series (optional)'),
        '1',
      );
      await tester.ensureVisible(find.text('Add another book after saving'));
      await tester.tap(find.text('Add another book after saving'));
      await tester.ensureVisible(find.text('Save book'));
      await tester.tap(find.text('Save book'));
      await tester.pumpAndSettle();

      final saved = (await repo.load()).books.single;
      expect(saved.seriesName, 'Dune');
      expect(saved.seriesNumber, 1);
      // Ready for book two of the same series; the rest starts blank.
      expect(fieldText(tester, 'Series (optional)'), 'Dune');
      expect(fieldText(tester, 'Book number in the series (optional)'), '2');
      expect(fieldText(tester, 'Title'), isEmpty);
      expect(fieldText(tester, 'Author'), isEmpty);
    });

    testWidgets('offers existing series and suggests the next number', (
      tester,
    ) async {
      final repo = await newRepo(
        tester,
        books: [
          ('Dune', 'Frank Herbert', 'Dune', 1),
          ('Dune Messiah', 'Frank Herbert', 'Dune', 2),
        ],
      );
      await pumpApp(tester, repo);
      await openAddForm(tester);
      final chip = find.widgetWithText(ActionChip, 'Dune');
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(fieldText(tester, 'Series (optional)'), 'Dune');
      expect(fieldText(tester, 'Book number in the series (optional)'), '3');
    });

    testWidgets('a number without a series is explained, input kept', (
      tester,
    ) async {
      await pumpApp(tester, await newRepo(tester));
      await openAddForm(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Solo');
      await tester.enterText(find.widgetWithText(TextField, 'Author'), 'Me');
      await tester.enterText(
        find.widgetWithText(TextField, 'Book number in the series (optional)'),
        '2',
      );
      await tester.ensureVisible(find.text('Save book'));
      await tester.tap(find.text('Save book'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter the series name for this number.'),
        findsOneWidget,
      );
      expect(fieldText(tester, 'Title'), 'Solo');
    });
  });

  group('sorting', () {
    List<String> listOrder(WidgetTester tester) => tester
        .widgetList<BookListTile>(find.byType(BookListTile))
        .map((t) => t.book.title)
        .toList();

    final books = [
      ('Zorba', 'Nikos Kazantzakis', null, null),
      ('Dune Messiah', 'Frank Herbert', 'Dune', 2),
      ('Emma', 'Jane Austen', null, null),
      ('Dune', 'Frank Herbert', 'Dune', 1),
    ];

    testWidgets('defaults to title, keeps series together, and can switch', (
      tester,
    ) async {
      final prefs = MemoryPreferencesStore();
      await pumpApp(
        tester,
        await newRepo(tester, books: books, height: 4800),
        prefs: prefs,
      );
      await tester.tap(find.widgetWithText(TextButton, 'List'));
      await tester.pumpAndSettle();
      expect(find.text('Sort: Title'), findsOneWidget);
      expect(listOrder(tester), ['Dune', 'Dune Messiah', 'Emma', 'Zorba']);

      await tester.tap(find.text('Sort: Title'));
      await tester.pumpAndSettle();
      expect(find.text('Title (A–Z)'), findsOneWidget);
      expect(find.text('Recently added'), findsOneWidget);
      await tester.tap(find.text('Author (A–Z)'));
      await tester.pumpAndSettle();
      expect(find.text('Sort: Author'), findsOneWidget);
      // Austen, then Herbert's series in order, then Kazantzakis.
      expect(listOrder(tester), ['Emma', 'Dune', 'Dune Messiah', 'Zorba']);
      expect(await prefs.read('librarySort'), 'author');
    });

    testWidgets('remembers the choice the next time the app opens', (
      tester,
    ) async {
      final prefs = MemoryPreferencesStore();
      await prefs.write('librarySort', 'author');
      await pumpApp(tester, await newRepo(tester, books: books), prefs: prefs);
      expect(find.text('Sort: Author'), findsOneWidget);
    });

    testWidgets('a search still ranks, with the sort breaking ties', (
      tester,
    ) async {
      await pumpApp(tester, await newRepo(tester, books: books, height: 4800));
      await tester.tap(find.widgetWithText(TextButton, 'List'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'dune');
      await tester.pumpAndSettle();
      expect(listOrder(tester), ['Dune', 'Dune Messiah']);
    });
  });
}
