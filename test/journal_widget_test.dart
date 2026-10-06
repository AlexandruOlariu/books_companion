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
import 'package:reading_library/features/library/presentation/library_screen.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<void> openJournal(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final repo = LocalLibraryRepository(AppDatabase(NativeDatabase.memory()));
    addTearDown(repo.db.close);
    Future<void> finished(String title, DatePrecision p, String? v) =>
        repo.saveBook(
          title: title,
          author: 'Someone',
          pageCount: 200,
          status: BookStatus.finished,
          finish: PartialDate(p, v),
          historical: true,
        );
    await finished('Remembered Day', DatePrecision.day, '2024-06-30');
    await finished('June Only', DatePrecision.month, '2024-06');
    await finished('Year Only', DatePrecision.year, '2024');
    await finished('Never Dated', DatePrecision.unknown, null);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: const ReadingLibraryApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Journal'));
    await tester.pumpAndSettle();
  }

  testWidgets('all time shows one row per year, and undated books apart', (
    tester,
  ) async {
    await openJournal(tester);
    expect(find.text('Months'), findsOneWidget);
    expect(find.bySemanticsLabel('2024, 3 books'), findsOneWidget);
    expect(find.bySemanticsLabel('Date unknown, 1 book'), findsOneWidget);
  });

  testWidgets('a year shows months, keeping year-only books out of them', (
    tester,
  ) async {
    await openJournal(tester);
    await tester.tap(find.bySemanticsLabel('2024, 3 books'));
    await tester.pumpAndSettle();
    final june = find.bySemanticsLabel(RegExp(r'^June 2024, 2 books'));
    await tester.dragUntilVisible(
      june,
      find.byType(ListView),
      const Offset(0, -150),
    );
    // Scroll it fully into view, clear of the bottom navigation.
    await tester.ensureVisible(june);
    await tester.pumpAndSettle();
    expect(june, findsOneWidget);
    // The year-only book has its own tile; it is in no month.
    expect(
      find.bySemanticsLabel(
        'Sometime in 2024, month unknown, 1 book: Year Only',
      ),
      findsOneWidget,
    );
    await tester.tap(june);
    await tester.pumpAndSettle();
    // Look only inside the sheet: covers elsewhere repeat their titles.
    Finder inSheet(String t) =>
        find.descendant(of: find.byType(BottomSheet), matching: find.text(t));
    expect(inSheet('Remembered Day'), findsWidgets);
    expect(inSheet('June Only'), findsWidgets);
    expect(inSheet('Year Only'), findsNothing);
    // Exactly the two books remembered as June, one row each.
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(BookListTile),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('days explains itself and does not count past finishes', (
    tester,
  ) async {
    await openJournal(tester);
    await tester.tap(find.text('Days'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No sessions logged yet'), findsOneWidget);
    expect(find.textContaining('do not count as reading days'), findsOneWidget);
    // The legend is further down a lazy list; scroll to it like a reader.
    await tester.dragUntilVisible(
      find.textContaining('A day you read'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    expect(find.textContaining('You finished a book that day'), findsOneWidget);
  });

  testWidgets('history still groups by what is remembered', (tester) async {
    await openJournal(tester);
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    // The group header, not the cover that repeats the title.
    await tester.dragUntilVisible(
      find.text('Date unknown'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    expect(find.text('Date unknown'), findsOneWidget);
  });
}
