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
        2,
      );
      await diskDb.close();
    },
  );
}
