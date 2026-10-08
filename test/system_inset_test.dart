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

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LocalLibraryRepository repo;
  setUp(
    () => repo = LocalLibraryRepository(AppDatabase(NativeDatabase.memory())),
  );
  tearDown(() => repo.db.close());

  testWidgets(
    'book details: Remove from library clears the system navigation bar',
    (tester) async {
      // A phone: 360 x 800 logical, with a 48 logical px navigation bar drawn
      // over the app (edge-to-edge, as on newer Android).
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      tester.view.padding = const FakeViewPadding(bottom: 144);
      tester.view.viewPadding = const FakeViewPadding(bottom: 144);
      addTearDown(tester.view.reset);

      final id = await repo.saveBook(
        title: 'The Couple Next Door',
        author: 'Shari Lapeña',
        status: BookStatus.finished,
        finish: const PartialDate.unknown(),
        historical: true,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [repositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(home: BookDetailsScreen(id: id)),
        ),
      );
      await tester.pumpAndSettle();

      final remove = find.text('Remove from library');
      await tester.scrollUntilVisible(
        remove,
        200,
        scrollable: find.byType(Scrollable),
      );
      await tester.drag(find.byType(Scrollable), const Offset(0, -2000));
      await tester.pumpAndSettle();

      // Fully scrolled: the button sits above the navigation bar.
      expect(tester.getBottomLeft(remove).dy, lessThanOrEqualTo(800 - 48));
    },
  );
}
