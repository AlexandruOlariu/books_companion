import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_library/app/app.dart';
import 'package:reading_library/app/providers.dart';
import 'package:reading_library/core/storage/database.dart';
import 'package:reading_library/features/library/data/local_library_repository.dart';
import 'package:reading_library/features/settings/presentation/settings_screen.dart';

import 'support/fake_friends_api.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late FakeFriendsApi api;

  Future<void> openAccount(WidgetTester tester) async {
    // A phone: 360 logical px wide, tall enough to build the whole page.
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final repo = LocalLibraryRepository(AppDatabase(NativeDatabase.memory()));
    addTearDown(repo.db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          friendsApiProvider.overrideWithValue(api),
        ],
        child: const ReadingLibraryApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings and backups'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Edit my account'));
    await tester.tap(find.text('Edit my account'));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextField, label);
  final save = find.widgetWithText(FilledButton, 'Save details');
  final change = find.widgetWithText(OutlinedButton, 'Change password');

  Future<void> tapButton(WidgetTester tester, Finder button) async {
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  setUp(() {
    api = FakeFriendsApi()..account = FakeFriendsApi.ana;
  });

  testWidgets('the demo has no account page to open', (tester) async {
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          friendsApiProvider.overrideWithValue(api),
          demoProvider.overrideWithValue(true),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit my account'), findsNothing);
  });

  testWidgets('shows the current details, and Save waits for a change', (
    tester,
  ) async {
    await openAccount(tester);
    expect(
      tester.widget<TextField>(field('First name')).controller!.text,
      'Ana',
    );
    expect(tester.widget<TextField>(field('Username')).controller!.text, 'ana');
    expect(find.textContaining('ana@example.com'), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
  });

  testWidgets('saving sends only what changed, and the page shows it', (
    tester,
  ) async {
    await openAccount(tester);
    await tester.enterText(field('First name'), 'Anna');
    await tester.pump();
    await tapButton(tester, save);
    expect(api.profileChanges, [
      {'first': 'Anna', 'last': null, 'username': null},
    ]);
    expect(find.text('Details saved.'), findsOneWidget);
    expect(api.account!.firstName, 'Anna');
  });

  testWidgets('a username is sent lower-case, and a taken one is explained', (
    tester,
  ) async {
    await openAccount(tester);
    await tester.enterText(field('Username'), 'Taken');
    await tester.pump();
    await tapButton(tester, save);
    expect(find.text('That username is already taken.'), findsOneWidget);
    expect(api.profileChanges, isEmpty);
    expect(api.account!.username, 'ana', reason: 'nothing changed');

    await tester.enterText(field('Username'), 'Ana.P');
    await tester.pump();
    await tapButton(tester, save);
    expect(api.profileChanges.single['username'], 'ana.p');
  });

  testWidgets('bad input is refused before anything is sent', (tester) async {
    await openAccount(tester);
    await tester.enterText(field('First name'), '   ');
    await tester.pump();
    await tapButton(tester, save);
    expect(find.text('First name cannot be empty.'), findsOneWidget);
    await tester.enterText(field('First name'), 'Ana');
    await tester.enterText(field('Username'), 'a b');
    await tester.pump();
    await tapButton(tester, save);
    expect(find.textContaining('Username: 3 to 30'), findsOneWidget);
    expect(api.profileChanges, isEmpty);
  });

  testWidgets('changing the password needs the current one', (tester) async {
    await openAccount(tester);
    await tester.enterText(field('Current password'), 'not my password');
    await tester.enterText(field('New password'), 'a brand new secret');
    await tester.enterText(field('New password again'), 'a brand new secret');
    await tapButton(tester, change);
    expect(find.text('Wrong password.'), findsOneWidget);
    expect(api.passwordChanges, isEmpty);

    await tester.enterText(field('Current password'), 'a long password');
    await tapButton(tester, change);
    expect(api.passwordChanges, [
      (current: 'a long password', next: 'a brand new secret'),
    ]);
    expect(
      find.text('Password changed. Other devices were signed out.'),
      findsOneWidget,
    );
    // The fields are emptied so the secret does not stay on screen.
    expect(
      tester.widget<TextField>(field('New password')).controller!.text,
      isEmpty,
    );
  });

  testWidgets('a short or mismatched new password is refused first', (
    tester,
  ) async {
    await openAccount(tester);
    await tester.enterText(field('Current password'), 'a long password');
    await tester.enterText(field('New password'), 'short');
    await tester.enterText(field('New password again'), 'short');
    await tapButton(tester, change);
    expect(find.textContaining('at least 10 characters.'), findsWidgets);
    await tester.enterText(field('New password'), 'a brand new secret');
    await tester.enterText(field('New password again'), 'another secret!!');
    await tapButton(tester, change);
    expect(
      find.text('The two new passwords are not the same.'),
      findsOneWidget,
    );
    expect(api.passwordChanges, isEmpty);
  });
}
