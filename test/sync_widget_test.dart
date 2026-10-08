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
import 'package:reading_library/features/sync/data/syncing_repository.dart';

import 'support/fake_friends_api.dart';
import 'support/fake_library_server.dart';

void main() {
  late LocalLibraryRepository repo;
  late LibraryChangeHook hook;
  late FakeFriendsApi api;
  late FakeLibraryServer server;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    repo = LocalLibraryRepository(AppDatabase(NativeDatabase.memory()));
    addTearDown(repo.db.close);
    hook = LibraryChangeHook();
    api = FakeFriendsApi();
    server = FakeLibraryServer()..userId = 'me';
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(SyncingRepository(repo, hook)),
          syncRepositoryProvider.overrideWithValue(repo),
          libraryChangeHookProvider.overrideWithValue(hook),
          accountRequiredProvider.overrideWithValue(true),
          friendsApiProvider.overrideWithValue(api),
          librarySyncApiProvider.overrideWithValue(server),
          bookLookupProvider.overrideWithValue(FakeCoverLookup()),
        ],
        child: const ReadingLibraryApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('an account is needed to open the app', () {
    testWidgets(
      'nobody signed in: the account page comes first, not the library',
      (tester) async {
        await repo.saveBook(
          title: 'Dune',
          author: 'Frank Herbert',
          status: BookStatus.wantToRead,
        );
        await pump(tester);
        expect(find.text('Your reading room, kept safe.'), findsOneWidget);
        expect(find.text('Library'), findsNothing);
        expect(find.text('Dune'), findsNothing);
        // Nothing is saved until someone signs in.
        expect(server.saves, isEmpty);
      },
    );

    testWidgets(
      'signing in opens the library and saves what was on the phone',
      (tester) async {
        await repo.saveBook(
          title: 'Dune',
          author: 'Frank Herbert',
          status: BookStatus.wantToRead,
        );
        await pump(tester);
        // The page is a lazy list: scroll until a widget has been built.
        Future<void> reveal(Finder finder) async {
          for (var i = 0; i < 40 && finder.evaluate().isEmpty; i++) {
            await tester.drag(
              find.byType(ListView).first,
              const Offset(0, -200),
            );
            await tester.pump();
          }
          await tester.ensureVisible(finder.first);
          await tester.pumpAndSettle();
        }

        Future<void> type(String label, String text) async {
          final field = find.widgetWithText(TextField, label);
          await reveal(field);
          await tester.enterText(field, text);
        }

        await type('Email', 'ana@example.com');
        await type('Password', 'a long password');
        final button = find.widgetWithText(FilledButton, 'Sign in');
        await reveal(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.text('Library'), findsWidgets);
        expect(find.text('Ana’s Library'), findsOneWidget);
        expect(find.text('Your reading room, kept safe.'), findsNothing);
        expect(server.saves, hasLength(1));
        expect((server.stored!['books'] as List).single['title'], 'Dune');
      },
    );

    testWidgets('someone already signed in goes straight to the library', (
      tester,
    ) async {
      api.account = FakeFriendsApi.ana;
      await pump(tester);
      expect(find.text('Your reading room, kept safe.'), findsNothing);
      expect(find.text('Library'), findsWidgets);
      expect(find.text('Ana’s Library'), findsOneWidget);
    });
  });

  group('saving to the account', () {
    setUp(() => api.account = FakeFriendsApi.ana);

    testWidgets('a change is saved shortly after, not on every keystroke', (
      tester,
    ) async {
      await pump(tester);
      await tester.pump(const Duration(seconds: 1));
      final before = server.saves.length;
      final wrapped = SyncingRepository(repo, hook);
      await wrapped.saveBook(
        title: 'Emma',
        author: 'Jane Austen',
        status: BookStatus.wantToRead,
      );
      await tester.pump(const Duration(seconds: 1));
      await wrapped.saveBook(
        title: 'Persuasion',
        author: 'Jane Austen',
        status: BookStatus.wantToRead,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(server.saves.length, before, reason: 'still within the pause');
      await tester.pump(const Duration(seconds: 3));
      expect(server.saves.length, before + 1, reason: 'one save for both');
      final titles = [
        for (final b in server.stored!['books'] as List) (b as Map)['title'],
      ];
      expect(titles, unorderedEquals(['Emma', 'Persuasion']));
    });

    testWidgets('offline: the phone keeps working and saves when it can', (
      tester,
    ) async {
      await pump(tester);
      // The first save made the account's copy; nothing is on it yet.
      expect(server.stored!['books'], isEmpty);
      server.offline = true;
      await SyncingRepository(repo, hook).saveBook(
        title: 'Emma',
        author: 'Jane Austen',
        status: BookStatus.wantToRead,
      );
      await tester.pump(const Duration(seconds: 4));
      expect((await repo.load()).books, hasLength(1));
      expect(server.stored!['books'], isEmpty, reason: 'still waiting');
      server.offline = false;
      await tester.pump(const Duration(minutes: 1, seconds: 1));
      expect((server.stored!['books'] as List), hasLength(1));
    });

    testWidgets(
      'a library on both sides asks which to keep, and keeping the phone replaces the account',
      (tester) async {
        await repo.saveBook(
          title: 'On the phone',
          author: 'A',
          status: BookStatus.wantToRead,
        );
        final other = LocalLibraryRepository(
          AppDatabase(NativeDatabase.memory()),
        );
        addTearDown(other.db.close);
        await other.saveBook(
          title: 'On the account',
          author: 'B',
          status: BookStatus.wantToRead,
        );
        await other.saveBook(
          title: 'Also on the account',
          author: 'B',
          status: BookStatus.wantToRead,
        );
        server.saveElsewhere(await other.exportData());

        await pump(tester);
        expect(find.text('Which library do you want to keep?'), findsOneWidget);
        expect(find.textContaining('This phone has 1 book.'), findsOneWidget);
        expect(find.textContaining('Your account has 2 books'), findsOneWidget);
        // Nothing changed while the reader decides.
        expect(server.saves, isEmpty);

        await tester.tap(find.textContaining('Keep this phone'));
        await tester.pumpAndSettle();
        expect(find.text('Which library do you want to keep?'), findsNothing);
        expect(
          (server.stored!['books'] as List).single['title'],
          'On the phone',
        );
      },
    );

    testWidgets('choosing the account replaces the phone\'s library', (
      tester,
    ) async {
      await repo.saveBook(
        title: 'On the phone',
        author: 'A',
        status: BookStatus.wantToRead,
      );
      final other = LocalLibraryRepository(
        AppDatabase(NativeDatabase.memory()),
      );
      addTearDown(other.db.close);
      await other.saveBook(
        title: 'On the account',
        author: 'B',
        status: BookStatus.wantToRead,
      );
      server.saveElsewhere(await other.exportData());
      await pump(tester);
      await tester.tap(find.textContaining('Use my account'));
      await tester.pumpAndSettle();
      expect((await repo.load()).books.single.title, 'On the account');
      expect(find.text('On the account'), findsWidgets);
    });
  });

  group('the demo', () {
    testWidgets('opens without an account and saves nothing', (tester) async {
      tester.view.physicalSize = const Size(420 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(SyncingRepository(repo, hook)),
            libraryChangeHookProvider.overrideWithValue(hook),
            accountRequiredProvider.overrideWithValue(true),
            demoProvider.overrideWithValue(true),
            friendsApiProvider.overrideWithValue(api),
            librarySyncApiProvider.overrideWithValue(server),
          ],
          child: const ReadingLibraryApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your reading room, kept safe.'), findsNothing);
      expect(server.saves, isEmpty);
    });
  });
}
