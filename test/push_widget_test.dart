import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_library/app/app.dart';
import 'package:reading_library/app/providers.dart';
import 'package:reading_library/core/storage/database.dart';
import 'package:reading_library/core/storage/preferences_store.dart';
import 'package:reading_library/features/friends/presentation/friends_screen.dart';
import 'package:reading_library/features/library/data/local_library_repository.dart';
import 'package:reading_library/features/push/presentation/push_controller.dart';
import 'package:reading_library/features/sync/data/syncing_repository.dart';

import 'support/fake_friends_api.dart';
import 'support/fake_library_server.dart';
import 'support/fake_push.dart';

void main() {
  late LocalLibraryRepository repo;
  late FakeFriendsApi friends;
  late FakePushService service;
  late FakePushApi pushApi;
  late MemoryPreferencesStore prefs;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    repo = LocalLibraryRepository(AppDatabase(NativeDatabase.memory()));
    addTearDown(repo.db.close);
    friends = FakeFriendsApi()..account = FakeFriendsApi.ana;
    service = FakePushService();
    pushApi = FakePushApi();
    prefs = MemoryPreferencesStore();
  });

  List<Override> overrides() => [
    friendsApiProvider.overrideWithValue(friends),
    pushServiceProvider.overrideWithValue(service),
    pushApiProvider.overrideWithValue(pushApi),
    preferencesProvider.overrideWithValue(prefs),
  ];

  void phone(WidgetTester tester, {double height = 800}) {
    tester.view.physicalSize = Size(360 * 3, height * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpApp(WidgetTester tester) async {
    phone(tester);
    final hook = LibraryChangeHook();
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          ...overrides(),
          repositoryProvider.overrideWithValue(SyncingRepository(repo, hook)),
          syncRepositoryProvider.overrideWithValue(repo),
          libraryChangeHookProvider.overrideWithValue(hook),
          accountRequiredProvider.overrideWithValue(true),
          librarySyncApiProvider.overrideWithValue(
            FakeLibraryServer()..userId = 'me',
          ),
          bookLookupProvider.overrideWithValue(FakeCoverLookup()),
        ],
        child: const ReadingLibraryApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpFriends(WidgetTester tester) async {
    phone(tester, height: 4000);
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: overrides(),
        child: const MaterialApp(home: FriendsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    // The switch reads the stored choice the way the app does after sign-in.
    await tester.runAsync(() async {
      final element = tester.element(find.byType(FriendsScreen));
      await ProviderScope.containerOf(element)
          .read(pushControllerProvider.notifier)
          .refresh();
    });
    await tester.pumpAndSettle();
  }

  Finder theSwitch() => find.widgetWithText(SwitchListTile, 'Friend requests');

  group('after signing in', () {
    testWidgets('the reader is offered notifications once and can accept', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(find.text('Know when a friend writes?'), findsOneWidget);
      expect(service.asked, 0, reason: 'nothing is requested before they say');
      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();
      expect(service.asked, 1);
      expect(pushApi.tokens, {'token-1'});
      expect(await prefs.read('push'), 'on');
    });

    testWidgets('"Not now" is remembered and the reader is not asked again', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(service.asked, 0);
      expect(pushApi.tokens, isEmpty);
      expect(await prefs.read('push'), 'off');

      await pumpApp(tester); // the next start
      expect(find.text('Know when a friend writes?'), findsNothing);
    });

    testWidgets('a phone that already said yes registers quietly', (
      tester,
    ) async {
      await prefs.write('push', 'on');
      await service.enable();
      await pumpApp(tester);
      expect(find.text('Know when a friend writes?'), findsNothing);
      expect(pushApi.tokens, {'token-1'});
    });

    testWidgets('a build without push offers nothing', (tester) async {
      service.isAvailable = false;
      await pumpApp(tester);
      expect(find.text('Know when a friend writes?'), findsNothing);
    });

    testWidgets('tapping a notification opens Friends', (tester) async {
      await prefs.write('push', 'off');
      await pumpApp(tester);
      expect(find.text('Friends'), findsNothing);
      service.taps.add(null);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Friends'), findsOneWidget);
    });
  });

  group('the Friends switch', () {
    testWidgets('turns notifications on and off', (tester) async {
      await pumpFriends(tester);
      expect(tester.widget<SwitchListTile>(theSwitch()).value, isFalse);

      await tester.tap(theSwitch());
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(theSwitch()).value, isTrue);
      expect(pushApi.tokens, {'token-1'});

      await tester.tap(theSwitch());
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(theSwitch()).value, isFalse);
      expect(pushApi.tokens, isEmpty);
      expect(service.forgotten, isTrue);
    });

    testWidgets('a blocked permission is explained and the switch stays off', (
      tester,
    ) async {
      service.allow = false;
      await pumpFriends(tester);
      await tester.tap(theSwitch());
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(theSwitch()).value, isFalse);
      expect(find.textContaining('Notifications are blocked'), findsOneWidget);
    });

    testWidgets('a build without push says so instead of showing a switch', (
      tester,
    ) async {
      service.isAvailable = false;
      await pumpFriends(tester);
      expect(theSwitch(), findsNothing);
      expect(
        find.text('This build of the app cannot send notifications.'),
        findsOneWidget,
      );
    });

    testWidgets('signing out turns the phone off for the next account', (
      tester,
    ) async {
      await pumpFriends(tester);
      await tester.tap(theSwitch());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Sign out'));
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(pushApi.tokens, isEmpty);
      expect(await prefs.read('push'), '');
    });
  });
}
