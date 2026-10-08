import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_library/app/app.dart';
import 'package:reading_library/app/providers.dart';
import 'package:reading_library/demo.dart';

void main() {
  testWidgets('reader can update a page without creating activity', (
    tester,
  ) async {
    final repo = await createDemoRepository();
    addTearDown(repo.db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: const ReadingLibraryApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('My Library'), findsOneWidget);
    await tester.tap(find.text('Reading').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update page').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '55');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('Position saved. Reading activity is unchanged.'),
      findsOneWidget,
    );
    expect((await repo.load()).sessions, hasLength(1));
    expect(tester.takeException(), isNull);
  });
  testWidgets('screens reflow with large text on a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final repo = await createDemoRepository();
    addTearDown(repo.db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: const ReadingLibraryApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Reading').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Journal').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
