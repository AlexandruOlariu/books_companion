import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_library/app/app.dart';
import 'package:reading_library/app/providers.dart';
import 'package:reading_library/core/storage/draft_store.dart';
import 'package:reading_library/demo.dart';
import 'package:reading_library/features/book_search/domain/book_lookup.dart';
import 'package:reading_library/features/library/data/local_library_repository.dart';

class _FakeLookup implements BookLookup {
  final bool offline;
  final String? cover;
  _FakeLookup({this.offline = false, this.cover});
  @override
  Future<List<BookSuggestion>> search(String query) async {
    if (offline) throw const LookupException('Could not reach Open Library.');
    return [
      BookSuggestion(
        title: 'Dune',
        author: 'Frank Herbert',
        pageCount: 412,
        language: 'English',
        firstPublishYear: 1965,
        coverUrl: cover == null ? null : 'https://example.test/c.jpg',
      ),
    ];
  }

  @override
  Future<String?> fetchCover(BookSuggestion suggestion) async => cover;
}

void main() {
  Future<void> open(
    WidgetTester tester, {
    required BookLookup lookup,
    DraftStore? drafts,
    LocalLibraryRepository? library,
  }) async {
    final repo = library ?? await createDemoRepository();
    if (library == null) addTearDown(repo.db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          bookLookupProvider.overrideWithValue(lookup),
          if (drafts != null) draftStoreProvider.overrideWithValue(drafts),
        ],
        child: const ReadingLibraryApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a search result fills the form and is saved locally', (
    tester,
  ) async {
    await open(tester, lookup: _FakeLookup());
    await tester.tap(find.text('Add book').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search online'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'dune');
    await tester.tap(find.text('Search').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dune'));
    await tester.pumpAndSettle();
    expect(find.text('Frank Herbert'), findsOneWidget);
    expect(find.text('412'), findsOneWidget);
    expect(find.textContaining('Filled from Open Library'), findsOneWidget);
    await tester.ensureVisible(find.text('Save book'));
    await tester.tap(find.text('Save book'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Dune saved'), findsOneWidget);
  });

  testWidgets('a downloaded cover is previewed in the form', (tester) async {
    final file = File('${Directory.systemTemp.path}/rl_cover_test.png')
      ..writeAsBytesSync(_png);
    addTearDown(file.deleteSync);
    await open(tester, lookup: _FakeLookup(cover: file.path));
    await tester.tap(find.text('Add book').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search online'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'dune');
    await tester.tap(find.text('Search').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('no cover'), findsNothing);
    await tester.tap(find.text('Dune'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Selected cover'), findsOneWidget);
    expect(find.textContaining('has no cover'), findsNothing);
  });

  testWidgets('a book with no cover says so, before and after choosing', (
    tester,
  ) async {
    await open(tester, lookup: _FakeLookup());
    await tester.tap(find.text('Add book').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search online'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'dune');
    await tester.tap(find.text('Search').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('no cover'), findsOneWidget);
    await tester.tap(find.text('Dune'));
    await tester.pumpAndSettle();
    expect(find.textContaining('has no cover for this book'), findsOneWidget);
    expect(find.bySemanticsLabel('Selected cover'), findsNothing);
  });

  testWidgets('offline search keeps the text and offers manual entry', (
    tester,
  ) async {
    await open(tester, lookup: _FakeLookup(offline: true));
    await tester.tap(find.text('Add book').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search online'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'dune');
    await tester.tap(find.text('Search').last);
    await tester.pumpAndSettle();
    expect(find.text('Could not reach Open Library.'), findsOneWidget);
    expect(find.text('dune'), findsOneWidget);
    await tester.tap(find.text('Add manually instead'));
    await tester.pumpAndSettle();
    expect(find.text('Save book'), findsOneWidget);
  });

  testWidgets('an unsaved book draft is restored after a restart', (
    tester,
  ) async {
    final drafts = MemoryDraftStore();
    await open(tester, lookup: _FakeLookup(), drafts: drafts);
    await tester.tap(find.text('Add book').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Title'),
      'Half-typed',
    );
    await tester.pumpAndSettle();
    // Simulate the process dying: a brand new app instance, same draft store.
    await tester.pumpWidget(const SizedBox());
    await open(tester, lookup: _FakeLookup(), drafts: drafts);
    await tester.tap(find.text('Add book').first);
    await tester.pumpAndSettle();
    expect(find.text('Restored your unsaved draft.'), findsOneWidget);
    expect(find.text('Half-typed'), findsOneWidget);
    await tester.tap(find.text('Start fresh'));
    await tester.pumpAndSettle();
    expect(find.text('Half-typed'), findsNothing);
    expect(await drafts.load('book:new'), isNull);
  });

  testWidgets('a pin draft is restored, and cleared once saved', (
    tester,
  ) async {
    final drafts = MemoryDraftStore();
    Future<void> openPin() async {
      await tester.tap(find.text('Reading').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add pin').first);
      await tester.pumpAndSettle();
    }

    // Book ids are random per demo library, so a restart reuses the library.
    final library = await createDemoRepository();
    addTearDown(library.db.close);
    await open(tester, lookup: _FakeLookup(), drafts: drafts, library: library);
    await openPin();
    await tester.enterText(
      find.widgetWithText(TextField, 'Your note'),
      'keep me',
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await open(tester, lookup: _FakeLookup(), drafts: drafts, library: library);
    await openPin();
    expect(find.text('keep me'), findsOneWidget);
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Pin saved, just for you.'), findsOneWidget);
    await tester.pumpAndSettle();
    final pins = (await library.load()).pins;
    expect(pins.where((p) => p.text == 'keep me'), hasLength(1));
    // Saving removes the draft, so a reopened sheet starts empty.
    await openPin();
    expect(find.text('keep me'), findsNothing);
    expect(find.text('Restored your unsaved draft.'), findsNothing);
  });
}

/// A valid 1x1 PNG.
final _png = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0,
  0,
  0,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0,
  0,
  0,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0xF8,
  0xFF,
  0xFF,
  0x3F,
  0,
  5,
  0xFE,
  2,
  0xFE,
  0xA7,
  0x35,
  0x81,
  0x84,
  0,
  0,
  0,
  0,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);
