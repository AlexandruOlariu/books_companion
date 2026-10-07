import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_library/core/storage/database.dart';
import 'package:reading_library/core/storage/preferences_store.dart';
import 'package:reading_library/features/library/data/local_library_repository.dart';
import 'package:reading_library/features/library/domain/models.dart';
import 'package:reading_library/features/sync/data/sync_engine.dart';
import 'package:reading_library/features/sync/domain/sync_models.dart';

import 'support/fake_library_server.dart';

const _cover = 'https://covers.openlibrary.org/b/id/42-L.jpg?default=false';

LocalLibraryRepository _repo() {
  final repo = LocalLibraryRepository(AppDatabase(NativeDatabase.memory()));
  addTearDown(repo.db.close);
  return repo;
}

Future<String> _book(
  LocalLibraryRepository repo,
  String title, {
  String? coverPath,
  String? coverSource,
}) => repo.saveBook(
  title: title,
  author: 'An Author',
  pageCount: 300,
  coverPath: coverPath,
  coverSource: coverSource,
  status: BookStatus.reading,
);

void main() {
  late LocalLibraryRepository repo;
  late FakeLibraryServer server;
  late FakeCoverLookup lookup;
  late MemoryPreferencesStore prefs;
  late SyncEngine engine;

  // Another phone has its own preferences, so it has its own baseline.
  SyncEngine makeEngine(LocalLibraryRepository r) => SyncEngine(
    repository: r,
    api: server,
    preferences: MemoryPreferencesStore(),
    lookup: lookup,
  );

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    repo = _repo();
    server = FakeLibraryServer();
    lookup = FakeCoverLookup();
    prefs = MemoryPreferencesStore();
    engine = SyncEngine(
      repository: repo,
      api: server,
      preferences: prefs,
      lookup: lookup,
    );
  });

  Future<int> phoneBooks() async => (await repo.load()).books.length;

  test(
    'the first sync of a library the account does not have saves it',
    () async {
      final id = await _book(repo, 'Dune');
      await repo.addPin(id, 'A private thought', 'Thought');
      await repo.logSession(id, DateTime(2026, 5, 1), start: 0, end: 20);
      final result = await engine.sync();
      expect(result.outcome, SyncOutcome.uploaded);
      expect(server.bases, [0]);
      final saved = server.stored!;
      // Everything the app keeps, including the private note and the session.
      expect(
        (saved['pins'] as List).single['textContent'],
        'A private thought',
      );
      expect(saved['sessions'], hasLength(1));
      expect(saved['userBooks'], hasLength(1));
      expect(await engine.isDirty, isFalse);
    },
  );

  test(
    'a cover file never leaves the phone, only where it came from',
    () async {
      await _book(
        repo,
        'Dune',
        coverPath: '/phone/only/path.cover',
        coverSource: _cover,
      );
      await _book(repo, 'Gallery', coverPath: '/phone/gallery.cover');
      await engine.sync();
      final editions = (server.stored!['editions'] as List).cast<Map>();
      expect(editions.every((e) => e['coverLocalPath'] == null), isTrue);
      expect(editions.map((e) => e['coverSource']), contains(_cover));
      expect(
        server.stored.toString().contains('/phone/'),
        isFalse,
        reason: 'no device path in what is saved',
      );
    },
  );

  test('a new phone with an empty library downloads the account\'s', () async {
    final other = _repo();
    final id = await _book(other, 'Dune');
    await other.addPin(id, 'Mine', 'Quote');
    await makeEngine(other).sync();

    final result = await engine.sync();
    expect(result.outcome, SyncOutcome.downloaded);
    final snapshot = await repo.load();
    expect(snapshot.books.single.title, 'Dune');
    expect(snapshot.pins.single.text, 'Mine');
    expect(await engine.isDirty, isFalse);
    // Now in step: nothing more to do.
    expect((await engine.sync()).outcome, SyncOutcome.upToDate);
    expect(server.saves, hasLength(1));
  });

  test('a download keeps the cover files this phone already has', () async {
    final id = await _book(repo, 'Dune', coverPath: '/phone/dune.cover');
    await engine.sync();
    // The same library comes back from another phone with one more book.
    final saved = {...server.stored!};
    saved['books'] = [...saved['books'] as List];
    server.saveElsewhere(saved);
    await engine.markDirty();
    await repo.deleteBook(id);
    await repo.restoreData({
      for (final e in saved.entries) e.key: e.value,
      'editions': [
        for (final e in saved['editions'] as List)
          {...e as Map<String, dynamic>, 'coverLocalPath': '/phone/dune.cover'},
      ],
    });
    // Clean again, and the account moved on: a download keeps the cover path.
    await engine.resolve(keepPhone: false);
    expect((await repo.load()).books.single.coverPath, '/phone/dune.cover');
    expect(id, isNotEmpty);
  });

  group('both sides have a library', () {
    late LocalLibraryRepository other;
    setUp(() async {
      other = _repo();
      await _book(other, 'From the account');
      await _book(other, 'Another');
      await makeEngine(other).sync();
      await _book(repo, 'On this phone');
    });

    test('is a conflict, with both counts, and changes nothing', () async {
      final result = await engine.sync();
      expect(result.outcome, SyncOutcome.conflict);
      expect(result.conflict!.phoneBooks, 1);
      expect(result.conflict!.accountBooks, 2);
      expect(await phoneBooks(), 1);
      expect(server.revision, 1);
    });

    test('keeping the phone replaces the account\'s library', () async {
      await engine.sync();
      final result = await engine.resolve(keepPhone: true);
      expect(result.outcome, SyncOutcome.uploaded);
      expect(server.revision, 2);
      expect(server.stored!['userBooks'], hasLength(1));
      expect(await phoneBooks(), 1);
      expect((await engine.sync()).outcome, SyncOutcome.upToDate);
    });

    test('taking the account\'s replaces this phone\'s library', () async {
      await engine.sync();
      final result = await engine.resolve(keepPhone: false);
      expect(result.outcome, SyncOutcome.downloaded);
      expect(
        (await repo.load()).books.map((b) => b.title),
        unorderedEquals(['From the account', 'Another']),
      );
      expect(server.revision, 1);
    });
  });

  group('after the first sync', () {
    setUp(() async {
      await _book(repo, 'Dune');
      await engine.sync();
    });

    test('nothing changed, nothing sent', () async {
      expect((await engine.sync()).outcome, SyncOutcome.upToDate);
      expect(server.saves, hasLength(1));
    });

    test('a change on the phone is sent on top of the last revision', () async {
      await _book(repo, 'Emma');
      await engine.markDirty();
      expect((await engine.sync()).outcome, SyncOutcome.uploaded);
      expect(server.bases, [0, 1]);
      expect(server.stored!['userBooks'], hasLength(2));
      expect(await engine.isDirty, isFalse);
    });

    test('a newer library on the account is downloaded when the phone has no unsaved change', () async {
      final other = _repo();
      await _book(other, 'Dune');
      await _book(other, 'From elsewhere');
      server.saveElsewhere(await other.exportData());
      expect((await engine.sync()).outcome, SyncOutcome.downloaded);
      expect(await phoneBooks(), 2);
    });

    test('a newer library on the account and an unsaved change is a conflict, nothing lost', () async {
      final other = _repo();
      await _book(other, 'From elsewhere');
      server.saveElsewhere(await other.exportData());
      await _book(repo, 'Unsaved here');
      await engine.markDirty();
      final result = await engine.sync();
      expect(result.outcome, SyncOutcome.conflict);
      expect(await phoneBooks(), 2);
      expect(server.saves, hasLength(1));
      expect(await engine.isDirty, isTrue);
    });

    test(
      'someone saving between the check and the save becomes a conflict',
      () async {
        await _book(repo, 'Emma');
        await engine.markDirty();
        final other = _repo();
        await _book(other, 'Elsewhere');
        server.duringSave = () =>
            server.saveElsewhere({...server.stored!, 'userBooks': []});
        final result = await engine.sync();
        expect(result.outcome, SyncOutcome.conflict);
        expect(await engine.isDirty, isTrue);
      },
    );

    test(
      'an account that lost its library is filled again from the phone',
      () async {
        server.stored = null;
        server.revision = 0;
        expect((await engine.sync()).outcome, SyncOutcome.uploaded);
        expect(server.stored!['userBooks'], hasLength(1));
      },
    );

    test('a change made while saving stays marked for the next sync', () async {
      await _book(repo, 'Emma');
      await engine.markDirty();
      server.duringSave = () => engine.markDirty();
      await engine.sync();
      expect(await engine.isDirty, isTrue);
      expect((await engine.sync()).outcome, SyncOutcome.uploaded);
      expect(await engine.isDirty, isFalse);
    });
  });

  group('when the server cannot be used', () {
    test('offline keeps the change waiting on the phone', () async {
      await _book(repo, 'Dune');
      await engine.markDirty();
      server.offline = true;
      expect((await engine.sync()).outcome, SyncOutcome.offline);
      expect(await engine.isDirty, isTrue);
      expect(await phoneBooks(), 1);
      server.offline = false;
      expect((await engine.sync()).outcome, SyncOutcome.uploaded);
      expect(await engine.isDirty, isFalse);
    });

    test('a lost session is reported, and nothing is sent', () async {
      await _book(repo, 'Dune');
      server.signedOut = true;
      expect((await engine.sync()).outcome, SyncOutcome.signedOut);
      expect(server.saves, isEmpty);
    });

    test('no account at all is signed out', () async {
      server.userId = null;
      expect((await engine.sync()).outcome, SyncOutcome.signedOut);
    });

    test(
      'an account library the app cannot read fails without touching the phone',
      () async {
        await _book(repo, 'Mine');
        server.saveElsewhere({
          'version': 1,
          'books': [],
          'authors': [],
          'bookAuthors': [],
          'editions': [
            {
              'id': 'e',
              'bookId': 'b',
              'coverSource': 'https://evil.test/x.jpg',
            },
          ],
          'userBooks': [],
          'records': [],
          'sessions': [],
          'pins': [],
        });
        // Phone has data and the account has some: a conflict, then taking the
        // account's fails validation and the phone keeps its library.
        expect((await engine.sync()).outcome, SyncOutcome.conflict);
        final result = await engine.resolve(keepPhone: false);
        expect(result.outcome, SyncOutcome.failed);
        expect((await repo.load()).books.single.title, 'Mine');
      },
    );
  });

  test('signing in as a different account starts from scratch', () async {
    await _book(repo, 'Dune');
    await engine.sync();
    await engine.adopt('someone-else');
    server.userId = 'someone-else';
    // The new account has nothing saved: the phone's library is sent as first.
    server.stored = null;
    server.revision = 0;
    expect((await engine.sync()).outcome, SyncOutcome.uploaded);
    // Signing in again as the same account keeps the baseline.
    await engine.adopt('someone-else');
    expect((await engine.sync()).outcome, SyncOutcome.upToDate);
  });

  group('covers that come from Open Library', () {
    test('are fetched again after a download', () async {
      final other = _repo();
      await _book(other, 'Dune', coverSource: _cover);
      await _book(other, 'Gallery cover only');
      await makeEngine(other).sync();
      await engine.sync();
      expect((await repo.load()).books.map((b) => b.coverPath), [null, null]);

      expect(await engine.fetchMissingCovers(), 1);
      expect(lookup.fetched, [_cover]);
      final covers = (await repo.load()).books.map((b) => b.coverPath);
      expect(covers, contains('/covers/fetched.cover'));
      // Attaching a cover is not a library change.
      expect(await engine.isDirty, isFalse);
      expect(await engine.fetchMissingCovers(), 0);
    });

    test('a failed fetch is tried again next time', () async {
      await _book(repo, 'Dune', coverSource: _cover);
      lookup.path = null;
      expect(await engine.fetchMissingCovers(), 0);
      lookup.path = '/covers/later.cover';
      expect(await engine.fetchMissingCovers(), 1);
    });
  });
}
