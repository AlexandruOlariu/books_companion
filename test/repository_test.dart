import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_library/core/storage/backup_service.dart';
import 'package:reading_library/core/storage/database.dart';
import 'package:reading_library/features/library/data/local_library_repository.dart';
import 'package:reading_library/features/library/domain/models.dart';

void main() {
  // Tests deliberately use distinct, isolated databases to verify restoration.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late LocalLibraryRepository repo;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = LocalLibraryRepository(db);
  });
  tearDown(() async => db.close());
  Future<String> add({
    BookStatus status = BookStatus.reading,
    PartialDate? finish,
    String? cover,
  }) => repo.saveBook(
    title: 'A book',
    author: 'An author',
    pageCount: 200,
    status: status,
    finish: finish,
    historical: true,
    coverPath: cover,
  );
  test(
    'page corrections, batch history, and sessions remain independent',
    () async {
      final id = await add();
      await repo.updatePage(id, 100);
      await repo.updatePage(id, 80);
      for (var i = 0; i < 5; i++) {
        await add(
          status: BookStatus.finished,
          finish: PartialDate(DatePrecision.year, '2019'),
        );
      }
      await add(
        status: BookStatus.finished,
        finish: const PartialDate.unknown(),
      );
      var data = await repo.load();
      expect(data.pagesLogged(null), 0);
      expect(data.sessions, isEmpty);
      expect(data.finishesIn(2019), hasLength(5));
      expect(data.books.firstWhere((b) => b.id == id).currentPage, 80);
      await repo.logSession(
        id,
        DateTime(2025, 3, 2),
        start: 80,
        end: 95,
        seconds: 900,
      );
      data = await repo.load();
      expect(data.pagesLogged(2025), 15);
      expect(data.secondsLogged(2025), 900);
      expect(data.books.firstWhere((b) => b.id == id).currentPage, 95);
      await repo.logSession(id, DateTime(2025, 3, 1), start: 10, end: 20);
      expect(
        (await repo.load()).books.firstWhere((b) => b.id == id).currentPage,
        95,
      );
      await expectLater(repo.updatePage(id, 201), throwsFormatException);
      await expectLater(
        repo.logSession(id, DateTime(2025), start: 90, end: 70),
        throwsFormatException,
      );
    },
  );
  test('complete export restores history, notes, and cover bytes on a clean database', () async {
    final temp = await Directory.systemTemp.createTemp('reading-test-');
    addTearDown(() => temp.delete(recursive: true));
    final cover = File('${temp.path}/original.png');
    final image = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWZkAAAAASUVORK5CYII=',
    );
    await cover.writeAsBytes(image);
    final id = await add(
      status: BookStatus.finished,
      finish: PartialDate(DatePrecision.month, '2020-03'),
      cover: cover.path,
    );
    await repo.addPin(
      id,
      'A private thought',
      'Thought',
      page: 32,
      percent: 16,
    );
    final bytes = await BackupService(repo).export();
    final restoredDb = AppDatabase(NativeDatabase.memory());
    addTearDown(restoredDb.close);
    final restored = LocalLibraryRepository(restoredDb);
    await BackupService(
      restored,
      coverDirectory: () async => temp,
    ).restore(bytes);
    final data = await restored.load();
    expect(data.books.single.title, 'A book');
    expect(data.completions.single.finish.value, '2020-03');
    expect(data.pins.single.text, 'A private thought');
    expect(data.sessions, isEmpty);
    expect(await File(data.books.single.coverPath!).readAsBytes(), image);
    expect(data.books.single.coverPath, isNot(cover.path));
  });
  test(
    'malformed restore and FK failure roll back all existing records',
    () async {
      final id = await add();
      await repo.addPin(id, 'Keep me', 'Favorite');
      final bad = await repo.exportData();
      (bad['userBooks'] as List).first['bookId'] = 'missing-book';
      await expectLater(repo.restoreData(bad), throwsA(anything));
      expect((await repo.load()).pins.single.text, 'Keep me');
      final duplicate = await repo.exportData();
      (duplicate['books'] as List).add((duplicate['books'] as List).first);
      await expectLater(repo.restoreData(duplicate), throwsA(anything));
      expect((await repo.load()).books.single.id, id);
      final invalidDate = await repo.exportData();
      (invalidDate['records'] as List).add({
        'id': 'bad',
        'userBookId': id,
        'finishedValue': '2019-01-01',
        'finishedPrecision': 'year',
        'source': 'entered_past',
        'createdAt': 1,
      });
      await expectLater(repo.restoreData(invalidDate), throwsA(anything));
      expect((await repo.load()).books.single.id, id);
    },
  );
  test(
    'backup rejects path references and leaves existing library untouched',
    () async {
      final id = await add();
      final data = await repo.exportData();
      data['editions'][0]['coverLocalPath'] = '../../escape';
      final bytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'format': 'reading-library',
            'version': 1,
            'data': data,
            'covers': {'../../escape': 'AA=='},
          }),
        ),
      );
      await expectLater(
        BackupService(repo).restore(bytes),
        throwsFormatException,
      );
      expect((await repo.load()).books.single.id, id);
    },
  );
  test('delete cascades through pins, activity and history', () async {
    final id = await add();
    await repo.addPin(id, 'Note', 'Idea');
    await repo.logSession(id, DateTime(2025), start: 0, end: 10);
    await repo.setStatus(
      id,
      BookStatus.finished,
      finish: const PartialDate.unknown(),
    );
    await repo.deleteBook(id);
    final data = await repo.load();
    expect(data.books, isEmpty);
    expect(data.sessions, isEmpty);
    expect(data.pins, isEmpty);
    expect(data.completions, isEmpty);
    expect((await repo.exportData())['authors'], isEmpty);
  });
  test(
    'editing an edition cannot invalidate saved positions or pins',
    () async {
      final id = await add();
      await repo.addPin(id, 'Near the end', 'Thought', page: 195);
      await expectLater(
        repo.saveBook(
          id: id,
          title: 'Edited',
          author: 'An author',
          pageCount: 100,
          status: BookStatus.reading,
        ),
        throwsFormatException,
      );
      expect((await repo.load()).books.single.title, 'A book');
    },
  );
  test(
    'database survives close and reopen at the current schema version',
    () async {
      final temp = await Directory.systemTemp.createTemp('reading-db-');
      addTearDown(() => temp.delete(recursive: true));
      final file = File('${temp.path}/library.sqlite');
      var diskDb = AppDatabase(NativeDatabase(file));
      await LocalLibraryRepository(diskDb).saveBook(
        title: 'Persistent',
        author: 'Reader',
        status: BookStatus.wantToRead,
      );
      await diskDb.close();
      diskDb = AppDatabase(NativeDatabase(file));
      expect(
        (await LocalLibraryRepository(diskDb).load()).books.single.title,
        'Persistent',
      );
      expect(
        (await diskDb.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        4,
      );
      await diskDb.close();
    },
  );

  group('cover source', () {
    const source = 'https://covers.openlibrary.org/b/id/42-L.jpg?default=false';

    test('is kept with the book and travels in the exported data', () async {
      final id = await repo.saveBook(
        title: 'Dune',
        author: 'Frank Herbert',
        coverPath: '/covers/dune.cover',
        coverSource: source,
        status: BookStatus.reading,
      );
      final book = (await repo.load()).books.single;
      expect(book.id, id);
      expect(
        (book.coverPath, book.coverSource),
        ('/covers/dune.cover', source),
      );
      final edition = ((await repo.exportData())['editions'] as List).single;
      expect(edition['coverSource'], source);
    });

    test('only Open Library cover addresses are accepted', () async {
      for (final bad in [
        'https://example.com/c.jpg',
        'http://covers.openlibrary.org/b/id/42-L.jpg',
        'https://covers.openlibrary.org.evil.test/b/id/42-L.jpg',
        'file:///etc/passwd',
        'https://covers.openlibrary.org/b/id/42-L.jpg?x=1',
      ]) {
        expect(isOpenLibraryCoverUrl(bad), isFalse, reason: bad);
        await expectLater(
          repo.saveBook(
            title: 'Dune',
            author: 'Frank Herbert',
            coverSource: bad,
            status: BookStatus.reading,
          ),
          throwsFormatException,
        );
      }
      expect(isOpenLibraryCoverUrl(source), isTrue);
      expect(await repo.load().then((l) => l.books), isEmpty);
    });

    test(
      'restoring data with a foreign cover address is refused whole',
      () async {
        await add();
        final data = await repo.exportData();
        (data['editions'] as List).first['coverSource'] = 'https://evil.test/x';
        await expectLater(repo.restoreData(data), throwsFormatException);
        expect((await repo.load()).books, hasLength(1));
      },
    );

    test('a cover still to fetch is one with a source and no file', () async {
      await repo.saveBook(
        title: 'On the phone',
        author: 'A',
        coverPath: '/covers/a.cover',
        coverSource: source,
        status: BookStatus.reading,
      );
      await repo.saveBook(
        title: 'Not downloaded',
        author: 'B',
        coverSource: source,
        status: BookStatus.reading,
      );
      await repo.saveBook(
        title: 'Gallery or none',
        author: 'C',
        status: BookStatus.reading,
      );
      final missing = await repo.coversToFetch();
      expect(missing, hasLength(1));
      await repo.attachCover(missing.single.editionId, '/covers/b.cover');
      expect(await repo.coversToFetch(), isEmpty);
      final titles = {
        for (final b in (await repo.load()).books) b.title: b.coverPath,
      };
      expect(titles['Not downloaded'], '/covers/b.cover');
      expect(titles['Gallery or none'], isNull);
    });

    test('a backup from before cover sources existed still restores', () async {
      await add();
      final data = await repo.exportData();
      for (final e in data['editions'] as List) {
        (e as Map).remove('coverSource');
      }
      await repo.restoreData(data);
      expect((await repo.load()).books.single.coverSource, isNull);
    });
  });
  group('rating', () {
    const known = PartialDate.unknown();
    Future<String> finished() =>
        add(status: BookStatus.finished, finish: known);
    Future<int?> ratingOf(String id) async =>
        (await repo.load()).books.singleWhere((b) => b.id == id).rating;

    test('a finished book can be rated, changed, and cleared', () async {
      final id = await finished();
      expect(await ratingOf(id), isNull, reason: 'never rated by default');
      await repo.setRating(id, 4);
      expect(await ratingOf(id), 4);
      await repo.setRating(id, 2);
      expect(await ratingOf(id), 2);
      await repo.setRating(id, null);
      expect(await ratingOf(id), isNull);
    });

    test('only 1 to 5 stars, and only after a finish', () async {
      final id = await finished();
      for (final bad in [0, 6, -1]) {
        await expectLater(repo.setRating(id, bad), throwsFormatException);
      }
      expect(await ratingOf(id), isNull);
      final unread = await add(status: BookStatus.wantToRead);
      await expectLater(repo.setRating(unread, 5), throwsFormatException);
      await expectLater(repo.setRating('nope', 3), throwsA(anything));
      // Clearing is always allowed.
      await repo.setRating(unread, null);
    });

    test('a rating survives reading the book again and editing it', () async {
      final id = await finished();
      await repo.setRating(id, 5);
      await repo.setStatus(id, BookStatus.reading);
      expect(await ratingOf(id), 5, reason: 'a reread keeps its rating');
      await repo.saveBook(
        id: id,
        title: 'A book, edited',
        author: 'An author',
        pageCount: 200,
        status: BookStatus.reading,
      );
      expect(await ratingOf(id), 5);
    });

    test('rating changes neither history nor activity', () async {
      final id = await finished();
      await repo.setRating(id, 3);
      final data = await repo.load();
      expect(data.completions, hasLength(1));
      expect(data.sessions, isEmpty);
    });

    test('ratings round-trip through export and restore', () async {
      final id = await finished();
      await repo.setRating(id, 4);
      final data = await repo.exportData();
      final other = LocalLibraryRepository(
        AppDatabase(NativeDatabase.memory()),
      );
      addTearDown(other.db.close);
      await other.restoreData(data);
      expect((await other.load()).books.single.rating, 4);
    });

    test('a backup from before ratings restores as unrated', () async {
      final id = await finished();
      await repo.setRating(id, 4);
      final data = await repo.exportData();
      for (final row in data['userBooks'] as List) {
        (row as Map).remove('rating');
      }
      await repo.restoreData(data);
      expect((await repo.load()).books.single.rating, isNull);
    });

    test('a restore rejects a bad rating and keeps the library', () async {
      final id = await finished();
      await repo.setRating(id, 3);
      final tooHigh = await repo.exportData();
      ((tooHigh['userBooks'] as List).single as Map)['rating'] = 9;
      await expectLater(repo.restoreData(tooHigh), throwsA(anything));
      final unfinished = await repo.exportData();
      (unfinished['records'] as List).clear();
      ((unfinished['userBooks'] as List).single as Map)['status'] = 'reading';
      await expectLater(repo.restoreData(unfinished), throwsA(anything));
      expect(await ratingOf(id), 3, reason: 'the library is unchanged');
    });
  });
}
