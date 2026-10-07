import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_library/core/storage/database.dart';
import 'package:reading_library/features/library/data/local_library_repository.dart';
import 'package:reading_library/features/library/domain/models.dart';
import 'package:reading_library/features/sync/data/syncing_repository.dart';

void main() {
  late LocalLibraryRepository inner;
  late SyncingRepository repo;
  late int changes;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    inner = LocalLibraryRepository(AppDatabase(NativeDatabase.memory()));
    addTearDown(inner.db.close);
    final hook = LibraryChangeHook();
    changes = 0;
    hook.listener = () => changes++;
    repo = SyncingRepository(inner, hook);
  });

  test('every kind of write is reported once', () async {
    final id = await repo.saveBook(
      title: 'Dune',
      author: 'Frank Herbert',
      pageCount: 400,
      status: BookStatus.reading,
    );
    expect(changes, 1);
    await repo.updatePage(id, 10);
    expect(changes, 2);
    await repo.logSession(id, DateTime(2026, 1, 2), start: 10, end: 20);
    expect(changes, 3);
    await repo.addPin(id, 'A thought', 'Thought');
    expect(changes, 4);
    final pin = (await repo.load()).pins.single;
    await repo.deletePin(pin.id);
    expect(changes, 5);
    await repo.setStatus(
      id,
      BookStatus.finished,
      finish: PartialDate(DatePrecision.year, '2026'),
    );
    expect(changes, 6);
    await repo.restoreData(await repo.exportData());
    expect(changes, 7);
    await repo.deleteBook(id);
    expect(changes, 8);
  });

  test('reads, exports and cover attachments are not changes', () async {
    await repo.saveBook(
      title: 'Dune',
      author: 'Frank Herbert',
      status: BookStatus.reading,
    );
    changes = 0;
    await repo.load();
    await repo.exportData();
    await repo.coverPaths();
    await repo.coversToFetch();
    await repo.attachCover('missing', '/covers/x.cover');
    expect(changes, 0);
  });

  test('a write that fails is not reported', () async {
    await expectLater(
      repo.saveBook(title: ' ', author: 'x', status: BookStatus.reading),
      throwsFormatException,
    );
    expect(changes, 0);
  });
}
