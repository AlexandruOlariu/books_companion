import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_library/core/storage/database.dart';
import 'package:reading_library/features/library/data/local_library_repository.dart';
import 'package:reading_library/features/library/domain/models.dart';
import 'package:reading_library/features/library/domain/search.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late LocalLibraryRepository repo;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = LocalLibraryRepository(db);
  });
  tearDown(() async => db.close());

  Future<String> add({String? series, int? number, String title = 'Dune'}) =>
      repo.saveBook(
        title: title,
        author: 'Frank Herbert',
        pageCount: 400,
        status: BookStatus.wantToRead,
        seriesName: series,
        seriesNumber: number,
      );

  test('a series is saved, loaded, edited, and cleared', () async {
    final id = await add(series: '  Dune ', number: 1);
    var book = (await repo.load()).books.single;
    expect(book.seriesName, 'Dune'); // trimmed
    expect(book.seriesNumber, 1);
    expect(book.seriesLabel, 'Dune, book 1');
    await repo.saveBook(
      id: id,
      title: 'Dune',
      author: 'Frank Herbert',
      pageCount: 400,
      status: BookStatus.wantToRead,
      seriesName: 'Dune Chronicles',
      seriesNumber: 1,
    );
    book = (await repo.load()).books.single;
    expect(book.seriesName, 'Dune Chronicles');
    await repo.saveBook(
      id: id,
      title: 'Dune',
      author: 'Frank Herbert',
      pageCount: 400,
      status: BookStatus.wantToRead,
    );
    book = (await repo.load()).books.single;
    expect(book.seriesName, isNull);
    expect(book.seriesNumber, isNull);
    expect(book.seriesLabel, isNull);
  });

  test(
    'a name without a number is fine; a number needs a name and be 1+',
    () async {
      await add(series: 'Dune');
      expect((await repo.load()).books.single.seriesLabel, 'Dune');
      await expectLater(add(number: 2), throwsA(isA<FormatException>()));
      await expectLater(
        add(series: 'Dune', number: 0),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        add(series: 'Dune', number: -3),
        throwsA(isA<FormatException>()),
      );
      expect((await repo.load()).books, hasLength(1)); // nothing half-saved
    },
  );

  test('search finds a book by its series name', () async {
    await add(series: 'Chronicles of Arrakis', number: 1);
    final book = (await repo.load()).books.single;
    expect(matchesQuery(book, 'arrakis'), isTrue);
    expect(matchesQuery(book, 'arrakis herbert'), isTrue);
    expect(matchesQuery(book, 'narnia'), isFalse);
  });

  group('backup', () {
    test('series survives export and restore', () async {
      await add(series: 'Dune', number: 2, title: 'Dune Messiah');
      final data = await repo.exportData();
      final fresh = LocalLibraryRepository(
        AppDatabase(NativeDatabase.memory()),
      );
      await fresh.restoreData(data);
      final book = (await fresh.load()).books.single;
      expect(book.seriesName, 'Dune');
      expect(book.seriesNumber, 2);
    });

    test('a backup made before series existed still restores', () async {
      await add(title: 'Old book');
      final data = await repo.exportData();
      for (final b in data['books'] as List) {
        (b as Map)
          ..remove('seriesName')
          ..remove('seriesNumber');
      }
      await add(series: 'Replaced', title: 'Will be replaced');
      await repo.restoreData(data);
      final books = (await repo.load()).books;
      expect(books.single.title, 'Old book');
      expect(books.single.seriesName, isNull);
    });

    test(
      'an invalid series is rejected and the library is untouched',
      () async {
        await add(series: 'Keep', number: 1, title: 'Keep me');
        final data = await repo.exportData();
        (data['books'] as List).first['seriesNumber'] = 0;
        await expectLater(
          repo.restoreData(data),
          throwsA(isA<FormatException>()),
        );
        (data['books'] as List).first
          ..['seriesNumber'] = 2
          ..['seriesName'] = '   ';
        await expectLater(
          repo.restoreData(data),
          throwsA(isA<FormatException>()),
        );
        final book = (await repo.load()).books.single;
        expect(book.title, 'Keep me');
        expect(book.seriesNumber, 1);
      },
    );
  });
}
