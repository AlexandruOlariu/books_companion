import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reading_library/app/app.dart';
import 'package:reading_library/app/providers.dart';
import 'package:reading_library/demo.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real-device library, progress, pin and partial-date history', (
    tester,
  ) async {
    final repo = await createDemoRepository();
    addTearDown(repo.db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          demoProvider.overrideWithValue(true),
        ],
        child: const ReadingLibraryApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('My library'), findsOneWidget);
    await tester.tap(find.text('Reading').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update page').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '42');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((await repo.load()).sessions, hasLength(1));
    await tester.tap(find.text('Add pin').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'A note saved on an Android device.',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((await repo.load()).pins, hasLength(2));
    await tester.tap(find.text('Journal').last);
    await tester.pumpAndSettle();
    expect(find.text('Reading journal'), findsOneWidget);
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('2025 · Month unknown'), findsOneWidget);
    await tester.tap(find.text('Library').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add book'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Title'),
      'Remembered book',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Author'),
      'A Reader',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final addTo = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(addTo);
    await tester.tap(addTo);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read in the past').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Date precision'));
    await tester.tap(find.text('Date precision'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Year only').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Year'), '2019');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save book'));
    await tester.tap(find.text('Save book'));
    await tester.pumpAndSettle();
    final data = await repo.load();
    expect(data.finishesIn(2019), hasLength(1));
    expect(data.sessions, hasLength(1));
    expect(data.completions.last.finish.value, '2019');
    expect(tester.takeException(), isNull);
  });
}
