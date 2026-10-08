import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_library/app/app.dart';
import 'package:reading_library/app/providers.dart';
import 'package:reading_library/core/storage/database.dart';
import 'package:reading_library/core/storage/preferences_store.dart';
import 'package:reading_library/features/friends/domain/friends_models.dart';
import 'package:reading_library/features/library/data/local_library_repository.dart';
import 'package:reading_library/features/library/domain/models.dart';
import 'package:reading_library/features/recommendations/presentation/recommendations_providers.dart';
import 'package:reading_library/features/recommendations/presentation/recommendations_section.dart';

import 'support/fake_friends_api.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LocalLibraryRepository repo;
  late FakeFriendsApi api;
  late MemoryPreferencesStore prefs;

  Future<void> finish(String title, String author, {String? series, int? n}) =>
      repo.saveBook(
        title: title,
        author: author,
        status: BookStatus.finished,
        finish: const PartialDate.unknown(),
        historical: true,
        seriesName: series,
        seriesNumber: n,
      );

  setUp(() {
    repo = LocalLibraryRepository(AppDatabase(NativeDatabase.memory()));
    api = FakeFriendsApi();
    prefs = MemoryPreferencesStore();
  });
  tearDown(() => repo.db.close());

  Future<void> openReading(WidgetTester tester) async {
    // A phone: 360 x 800 logical.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          friendsApiProvider.overrideWithValue(api),
          preferencesProvider.overrideWithValue(prefs),
        ],
        child: const ReadingLibraryApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reading').last);
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 40 && finder.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pump();
    }
    expect(finder, findsWidgets, reason: 'could not scroll to it');
    await tester.ensureVisible(finder.first);
    await tester.pumpAndSettle();
  }

  testWidgets('an empty library shows no section', (tester) async {
    await openReading(tester);
    expect(find.text('What to read next'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('books but nothing to suggest says what makes an idea appear', (
    tester,
  ) async {
    // No series, no Wishlist, no friends: a short shelf is quiet, not broken.
    await finish('The Alchemist', 'Paulo Coelho');
    await openReading(tester);
    await reveal(tester, find.text('What to read next'));
    expect(find.textContaining('Nothing to suggest yet'), findsOneWidget);
    expect(find.textContaining('numbered series'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('suggests the next book in a series and opens a prefilled form', (
    tester,
  ) async {
    await finish('Dune', 'Frank Herbert', series: 'Dune', n: 1);
    await openReading(tester);
    await reveal(tester, find.text('What to read next'));
    expect(find.text('Continue a series'.toUpperCase()), findsOneWidget);
    // The generated cover repeats the title, so it is found twice.
    expect(find.text('Dune, book 2'), findsWidgets);
    expect(find.textContaining('Book 2 is not on your shelf'), findsOneWidget);

    await tester.tap(find.text('Add to Wishlist'));
    await tester.pumpAndSettle();
    String text(String label) => tester
        .widget<TextField>(find.widgetWithText(TextField, label))
        .controller!
        .text;
    expect(text('Author'), 'Frank Herbert');
    expect(text('Series (optional)'), 'Dune');
    expect(text('Book number in the series (optional)'), '2');
    expect(text('Title'), '');
    // Nothing was added by merely looking.
    expect((await repo.load()).books, hasLength(1));
  });

  testWidgets('Not interested hides it, can be undone, and is remembered', (
    tester,
  ) async {
    await finish('Dune', 'Frank Herbert', series: 'Dune', n: 1);
    await openReading(tester);
    await reveal(tester, find.text('Not interested'));
    await tester.tap(find.text('Not interested'));
    await tester.pumpAndSettle();
    expect(find.text('Dune, book 2'), findsNothing);
    expect(find.text('Undo'), findsOneWidget);
    expect(
      await prefs.read(dismissedRecommendationsPreference),
      contains('series:dune:2'),
    );

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    // The generated cover repeats the title, so it is found twice.
    expect(find.text('Dune, book 2'), findsWidgets);

    await reveal(tester, find.text('Not interested'));
    await tester.tap(find.text('Not interested'));
    await tester.pumpAndSettle();
    // A new launch with the same preferences still hides it.
    await openReading(tester);
    expect(find.text('Dune, book 2'), findsNothing);
  });

  group('friends', () {
    const bob = Person(
      id: 'u-bob',
      username: 'bob',
      displayName: 'Bob Ionescu',
    );
    SharedBook shared(String title, String author, BookStatus status) =>
        SharedBook(
          id: title,
          title: title,
          author: author,
          status: status,
          finishes: status == BookStatus.finished
              ? const [PartialDate.unknown()]
              : const [],
        );

    setUp(() {
      api.account = FakeFriendsApi.ana;
      api.friendList = [bob];
      api.shelves[bob.id] = SharedShelf(
        books: [
          shared('Ulysses', 'James Joyce', BookStatus.finished),
          shared('Emma', 'Jane Austen', BookStatus.finished),
          shared('Still reading', 'Some One', BookStatus.reading),
        ],
        updatedAt: DateTime(2026, 10, 7),
      );
    });

    testWidgets('lists books friends finished that the reader lacks', (
      tester,
    ) async {
      await finish('Emma', 'Jane Austen');
      await openReading(tester);
      await reveal(tester, find.text('Ulysses'));
      expect(find.text('Your friends finished'.toUpperCase()), findsOneWidget);
      expect(find.text('Finished by Bob Ionescu.'), findsOneWidget);
      expect(find.text('Emma'), findsNothing, reason: 'already in the library');
      expect(find.text('Still reading'), findsNothing);

      await tester.tap(find.text('Add to Wishlist'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Title'))
            .controller!
            .text,
        'Ulysses',
      );
      // Friends' shelves never touch the library.
      expect((await repo.load()).books, hasLength(1));
    });

    testWidgets('a friend made after the tab was first seen shows up later', (
      tester,
    ) async {
      // Seen before there was any friend: nothing is remembered from that.
      api.friendList = [];
      await finish('Emma', 'Jane Austen');
      await openReading(tester);
      await reveal(tester, find.textContaining('Nothing to suggest yet'));
      expect(find.text('Ulysses'), findsNothing);

      api.friendList = [bob];
      await tester.tap(find.text('Library').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reading').last);
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Ulysses'));
      expect(find.text('Finished by Bob Ionescu.'), findsOneWidget);
    });

    testWidgets('a friends outage leaves the rest of the screen working', (
      tester,
    ) async {
      api.friendList = [bob];
      api.shelves.clear();
      await finish('Dune', 'Frank Herbert', series: 'Dune', n: 1);
      await openReading(tester);
      await reveal(tester, find.text('Dune, book 2'));
      expect(find.text('Your friends finished'.toUpperCase()), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the demo never asks the server for friends', (tester) async {
      await finish('Dune', 'Frank Herbert', series: 'Dune', n: 1);
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            friendsApiProvider.overrideWithValue(api),
            demoProvider.overrideWithValue(true),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RecommendationsSection(data: await repo.load()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Dune, book 2'), findsWidgets);
      expect(find.text('Ulysses'), findsNothing);
    });
  });
}
