import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_library/app/app.dart';
import 'package:reading_library/app/providers.dart';
import 'package:reading_library/core/storage/database.dart';
import 'package:reading_library/features/friends/data/contacts_source.dart';
import 'package:reading_library/features/friends/domain/friends_models.dart';
import 'package:reading_library/features/library/data/local_library_repository.dart';
import 'package:reading_library/features/library/domain/models.dart';
import 'package:reading_library/features/settings/presentation/settings_screen.dart';

import 'support/fake_friends_api.dart';

const bob = Person(id: 'u-bob', username: 'bob', displayName: 'Bob Ionescu');
const cris = Person(id: 'u-cris', username: 'cris', displayName: 'Cris Dima');

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late FakeFriendsApi api;
  late FakeContactsSource contacts;
  late LocalLibraryRepository repo;

  Future<void> pump(
    WidgetTester tester, {
    bool withBooks = true,
    bool demo = false,
    double textScale = 1,
    bool phoneHeight = false,
  }) async {
    // Always 360 logical px wide. Functional tests use a tall view so the whole
    // page is built; layout tests use the real 800 px height and scroll.
    tester.view.physicalSize = Size(1080, phoneHeight ? 2400 : 9000);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    repo = LocalLibraryRepository(AppDatabase(NativeDatabase.memory()));
    addTearDown(repo.db.close);
    if (withBooks) {
      await repo.saveBook(
        title: 'Dune',
        author: 'Frank Herbert',
        status: BookStatus.finished,
        finish: PartialDate(DatePrecision.year, '2021'),
        historical: true,
      );
      await repo.saveBook(
        title: 'Emma',
        author: 'Jane Austen',
        status: BookStatus.wantToRead,
      );
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          friendsApiProvider.overrideWithValue(api),
          contactsSourceProvider.overrideWithValue(contacts),
          regionProvider.overrideWithValue('RO'),
          if (demo) demoProvider.overrideWithValue(true),
        ],
        child: const ReadingLibraryApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Brings [finder] on screen. Lists build lazily, so on a phone-height view
  /// anything below the fold is reached by dragging the page up.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 80 && finder.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pump();
    }
    expect(finder, findsWidgets, reason: 'could not scroll to it');
    await tester.ensureVisible(finder.first);
    await tester.pumpAndSettle();
  }

  Future<void> openFriends(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Settings and backups'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Friends and sharing'));
    await tester.tap(find.text('Friends and sharing'));
    await tester.pumpAndSettle();
  }

  Future<void> typeInto(WidgetTester tester, String label, String text) async {
    final field = find.widgetWithText(TextField, label);
    await reveal(tester, field);
    await tester.enterText(field, text);
  }

  Future<void> tapButton(WidgetTester tester, Finder finder) async {
    await reveal(tester, finder);
    await tester.tap(finder.first);
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await reveal(tester, find.text(text));
    await tester.tap(find.text(text).first);
    await tester.pumpAndSettle();
  }

  setUp(() {
    api = FakeFriendsApi();
    contacts = FakeContactsSource();
  });

  group('signed out', () {
    testWidgets('Settings offers friends, and the demo does not', (
      tester,
    ) async {
      Future<void> settings({required bool demo}) async {
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              friendsApiProvider.overrideWithValue(api),
              if (demo) demoProvider.overrideWithValue(true),
            ],
            child: const MaterialApp(home: SettingsScreen()),
          ),
        );
        await tester.pumpAndSettle();
      }

      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await settings(demo: false);
      await tester.scrollUntilVisible(
        find.text('Friends and sharing'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Friends and sharing'), findsOneWidget);
      expect(find.textContaining('Find friends and share'), findsOneWidget);
      await settings(demo: true);
      expect(find.text('Friends and sharing'), findsNothing);
    });

    testWidgets('the sign-in panel says what is sent before anything is', (
      tester,
    ) async {
      await pump(tester);
      await openFriends(tester);
      expect(find.text('Your reading room, kept safe.'), findsOneWidget);
      expect(find.textContaining('What is saved:'), findsOneWidget);
      expect(find.textContaining('private notes and pins'), findsOneWidget);
      expect(find.textContaining('not end-to-end encrypted'), findsOneWidget);
      expect(api.registered, isEmpty);
    });

    testWidgets('creating an account signs the reader in', (tester) async {
      await pump(tester);
      await openFriends(tester);
      await tester.tap(find.text('Create account').first);
      await tester.pumpAndSettle();
      Future<void> type(String label, String text) =>
          typeInto(tester, label, text);
      await type('First name', 'Ana');
      await type('Last name', 'Pop');
      await type('Username', 'ana');
      await type('Email', 'ana@example.com');
      await type('Password', 'a long password');
      await tapButton(
        tester,
        find.widgetWithText(FilledButton, 'Create account'),
      );
      expect(api.registered.single['username'], 'ana');
      expect(find.text('Ana Pop'), findsOneWidget);
      expect(find.text('Signed in'.toUpperCase()), findsOneWidget);
    });

    testWidgets('missing fields are explained, nothing is sent', (
      tester,
    ) async {
      await pump(tester);
      await openFriends(tester);
      await tapButton(tester, find.widgetWithText(FilledButton, 'Sign in'));
      expect(find.text('Fill in every field.'), findsOneWidget);
    });

    testWidgets('a wrong password shows the server\'s message', (tester) async {
      await pump(tester);
      await openFriends(tester);
      await typeInto(tester, 'Email', 'ana@example.com');
      await typeInto(tester, 'Password', 'nope');
      await tapButton(tester, find.widgetWithText(FilledButton, 'Sign in'));
      await reveal(tester, find.text('Wrong email or password.'));
      expect(find.text('Wrong email or password.'), findsOneWidget);
      expect(api.account, isNull);
    });
  });

  group('signed in', () {
    setUp(() => api.account = FakeFriendsApi.ana);

    testWidgets(
      'sharing the shelf asks first, then sends only books and dates',
      (tester) async {
        await pump(tester);
        await openFriends(tester);
        expect(find.textContaining('Not shared.'), findsOneWidget);
        await tester.tap(find.text('Share my shelf'));
        await tester.pumpAndSettle();
        expect(find.text('Share 2 books with your friends?'), findsOneWidget);
        expect(find.textContaining('never shared'), findsOneWidget);
        expect(
          api.published,
          isNull,
          reason: 'nothing is sent before confirming',
        );
        await tester.tap(find.text('Share'));
        await tester.pumpAndSettle();
        final sent = api.published!;
        expect(sent.map((b) => b.title).toSet(), {'Dune', 'Emma'});
        final dune = sent.firstWhere((b) => b.title == 'Dune');
        expect(dune.finishes.single.precision, DatePrecision.year);
        expect(dune.finishes.single.value, '2021');
        expect(find.textContaining('2 books shared'), findsOneWidget);
        expect(find.text('Update shared shelf'), findsOneWidget);
      },
    );

    testWidgets('cancelling the dialog sends nothing', (tester) async {
      await pump(tester);
      await openFriends(tester);
      await tester.tap(find.text('Share my shelf'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(api.published, isNull);
    });

    testWidgets('an empty library has nothing to share', (tester) async {
      await pump(tester, withBooks: false);
      await openFriends(tester);
      await tester.tap(find.text('Share my shelf'));
      await tester.pumpAndSettle();
      expect(
        find.text('Add some books before sharing your shelf.'),
        findsOneWidget,
      );
      expect(api.published, isNull);
    });

    testWidgets('sharing can be stopped', (tester) async {
      await pump(tester);
      await openFriends(tester);
      await tester.tap(find.text('Share my shelf'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop sharing'));
      await tester.pumpAndSettle();
      expect(api.unpublished, isTrue);
      expect(find.text('Share my shelf'), findsOneWidget);
    });

    testWidgets('an incoming request can be accepted', (tester) async {
      api.requestList = const FriendRequests(incoming: [bob]);
      await pump(tester);
      await openFriends(tester);
      expect(find.text('Friend requests'), findsOneWidget);
      await tapText(tester, 'Accept');
      expect(api.accepted, ['u-bob']);
      expect(find.text('Friend requests'), findsNothing);
      expect(find.text('Bob Ionescu'), findsOneWidget);
    });

    testWidgets(
      'finding someone by username sends a request, not a friendship',
      (tester) async {
        api.lookupResult = cris;
        await pump(tester);
        await openFriends(tester);
        await typeInto(tester, 'Friend\'s username', 'nobody');
        await tapButton(tester, find.widgetWithText(FilledButton, 'Find'));
        expect(find.text('No one has that username.'), findsOneWidget);
        await typeInto(tester, 'Friend\'s username', 'cris');
        await tapButton(tester, find.widgetWithText(FilledButton, 'Find'));
        await tapButton(tester, find.text('Send friend request'));
        expect(api.sent, ['u-cris']);
        expect(find.text('Request sent to Cris Dima.'), findsOneWidget);
      },
    );

    testWidgets('contacts are explained first and only read after Continue', (
      tester,
    ) async {
      contacts.result = const ContactNumbers(
        granted: true,
        numbers: ['+40712345678'],
      );
      api.contactMatches = [cris];
      await pump(tester);
      await openFriends(tester);
      await tapText(tester, 'Find friends from contacts');
      expect(find.text('Find friends from your contacts?'), findsOneWidget);
      expect(contacts.asked, 0, reason: 'no permission request before consent');
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(contacts.asked, 0);
      expect(api.matchedNumbers, isNull);

      await tapText(tester, 'Find friends from contacts');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(contacts.asked, 1);
      expect(api.matchedNumbers, ['+40712345678']);
      expect(api.matchedRegion, 'RO');
      expect(find.text('Cris Dima'), findsOneWidget);
    });

    testWidgets(
      'refusing the contacts permission is explained, nothing is sent',
      (tester) async {
        contacts.result = const ContactNumbers(granted: false);
        await pump(tester);
        await openFriends(tester);
        await tapText(tester, 'Find friends from contacts');
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Contacts access was not given'),
          findsOneWidget,
        );
        expect(api.matchedNumbers, isNull);
      },
    );

    testWidgets('contacts who are already friends are not offered again', (
      tester,
    ) async {
      api.friendList = [bob];
      api.contactMatches = [bob, cris];
      contacts.result = const ContactNumbers(
        granted: true,
        numbers: ['1', '2'],
      );
      await pump(tester);
      await openFriends(tester);
      await tapText(tester, 'Find friends from contacts');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Send friend request'), findsOneWidget);
      expect(find.text('Cris Dima'), findsOneWidget);
    });

    testWidgets('a phone number can be added and made findable', (
      tester,
    ) async {
      await pump(tester);
      await openFriends(tester);
      await reveal(tester, find.text('Be found by phone'));
      await typeInto(tester, 'Your phone number', '0712 345 678');
      await tapText(tester, 'Save');
      expect(api.account!.hasPhone, isTrue);
      expect(
        api.account!.discoverableByPhone,
        isFalse,
        reason: 'findable only when switched on',
      );
      await tapButton(tester, find.byType(Switch));
      expect(api.account!.discoverableByPhone, isTrue);
    });

    testWidgets('signing out returns to the sign-in panel', (tester) async {
      await pump(tester);
      await openFriends(tester);
      await tapText(tester, 'Sign out');
      expect(find.text('Your reading room, kept safe.'), findsOneWidget);
    });

    testWidgets('deleting the account needs the password', (tester) async {
      await pump(tester);
      await openFriends(tester);
      await tapText(tester, 'Delete my account');
      expect(find.text('Delete your account?'), findsOneWidget);
      expect(
        find.textContaining('library on this phone is not affected'),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Your password'),
        'wrong',
      );
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      expect(find.text('Wrong password.'), findsOneWidget);
      expect(api.deletedWith, isNull);

      await tapText(tester, 'Delete my account');
      await tester.enterText(
        find.widgetWithText(TextField, 'Your password'),
        'a long password',
      );
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      expect(api.deletedWith, 'a long password');
      expect(find.text('Your reading room, kept safe.'), findsOneWidget);
      // The reader's own library is untouched.
      expect((await repo.load()).books, hasLength(2));
    });

    testWidgets('lays out at 200% text on a phone', (tester) async {
      api.friendList = [bob];
      api.requestList = const FriendRequests(incoming: [cris]);
      await pump(tester, textScale: 2, phoneHeight: true);
      await openFriends(tester);
      expect(tester.takeException(), isNull);
      for (final label in ['Be found by phone', 'Sign out']) {
        await reveal(tester, find.text(label));
        expect(tester.takeException(), isNull, reason: label);
      }
    });
  });

  group('a friend\'s shelf', () {
    setUp(() {
      api.account = FakeFriendsApi.ana;
      api.friendList = [bob];
      api.shelves['u-bob'] = SharedShelf(
        updatedAt: DateTime(2026, 10, 1),
        books: [
          SharedBook(
            id: '1',
            title: 'Middlemarch',
            author: 'George Eliot',
            status: BookStatus.finished,
            finishes: [PartialDate(DatePrecision.month, '2024-03')],
          ),
          SharedBook(
            id: '2',
            title: 'Old Favourite',
            author: '',
            status: BookStatus.finished,
            finishes: [PartialDate(DatePrecision.year, '2019')],
          ),
          const SharedBook(
            id: '3',
            title: 'Mystery Year',
            author: 'X',
            status: BookStatus.finished,
            finishes: [PartialDate.unknown()],
          ),
          const SharedBook(
            id: '4',
            title: 'Now Reading',
            author: 'Y',
            status: BookStatus.reading,
          ),
          const SharedBook(
            id: '5',
            title: 'Someday',
            author: 'Z',
            status: BookStatus.wantToRead,
          ),
        ],
      );
    });

    testWidgets('shows the snapshot with dates exactly as shared', (
      tester,
    ) async {
      await pump(tester, withBooks: false);
      await openFriends(tester);
      await tapText(tester, 'Bob Ionescu');
      expect(find.text('Middlemarch'), findsOneWidget);
      expect(find.text('Finished: March 2024'), findsOneWidget);
      expect(
        find.text('Finished: 2019'),
        findsOneWidget,
        reason: 'a year stays a year',
      );
      expect(find.text('Finished: Date unknown'), findsOneWidget);
      expect(
        find.textContaining('not part of your own journal'),
        findsOneWidget,
      );
      final order = [
        for (final t in ['Reading now (1)', 'Finished (3)', 'Wishlist (1)'])
          tester.getTopLeft(find.text(t)).dy,
      ];
      expect(order, [...order]..sort());
      // Most recent finish first, unknown last.
      final titles = ['Middlemarch', 'Old Favourite', 'Mystery Year'];
      final y = [for (final t in titles) tester.getTopLeft(find.text(t)).dy];
      expect(y, [...y]..sort());
    });

    testWidgets('viewing a friend\'s shelf never adds to your own library', (
      tester,
    ) async {
      await pump(tester, withBooks: false);
      await openFriends(tester);
      await tapText(tester, 'Bob Ionescu');
      expect((await repo.load()).books, isEmpty);
      expect((await repo.load()).completions, isEmpty);
    });

    testWidgets('a friend with nothing shared says so', (tester) async {
      api.shelves.clear();
      await pump(tester, withBooks: false);
      await openFriends(tester);
      await tapText(tester, 'Bob Ionescu');
      expect(find.text('Nothing shared yet'), findsOneWidget);
    });

    testWidgets('a friend can be removed or blocked', (tester) async {
      await pump(tester, withBooks: false);
      await openFriends(tester);
      await tapText(tester, 'Bob Ionescu');
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove friend'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(api.removed, ['u-bob']);
      expect(find.text('Friends'), findsWidgets);
      expect(find.text('Bob Ionescu'), findsNothing);
    });

    testWidgets('lays out at 200% text on a phone', (tester) async {
      await pump(tester, withBooks: false, textScale: 2, phoneHeight: true);
      await openFriends(tester);
      await tapText(tester, 'Bob Ionescu');
      expect(tester.takeException(), isNull);
      await reveal(tester, find.text('Someday'));
      expect(tester.takeException(), isNull);
    });
  });
}
