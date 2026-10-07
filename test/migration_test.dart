import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_library/core/storage/database.dart';

import 'generated_migrations/schema.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;
  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test(
    'upgrading the frozen version-1 schema reaches the current schema',
    () async {
      // Fails if a table or column changes without a migration step.
      final connection = await verifier.startAt(1);
      final db = AppDatabase(connection);
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, db.schemaVersion);
    },
  );

  test('the current schema matches the frozen version-3 dump', () async {
    // Fails if a table or column changes without a new schema version and a
    // dump in drift_schemas/.
    final connection = await verifier.startAt(3);
    final db = AppDatabase(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, db.schemaVersion);
    expect(db.schemaVersion, 3);
  });

  test(
    'upgrading the frozen version-2 schema reaches the current schema',
    () async {
      final connection = await verifier.startAt(2);
      final db = AppDatabase(connection);
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, db.schemaVersion);
    },
  );

  test('a version-2 library keeps its series and covers, with no cover source', () async {
    final schema = await verifier.schemaAt(2);
    final seeded = AppDatabase(schema.newConnection());
    await seeded.customStatement('PRAGMA foreign_keys = OFF');
    final stamp = DateTime(2024, 5, 1).millisecondsSinceEpoch ~/ 1000;
    await seeded.customStatement(
      "INSERT INTO books (id, title, series_name, series_number, created_at, updated_at) VALUES ('b1', 'Dune', 'Dune', 1, $stamp, $stamp)",
    );
    await seeded.customStatement(
      "INSERT INTO editions (id, book_id, page_count, cover_local_path, metadata_source) VALUES ('e1', 'b1', 412, '/covers/dune.cover', 'open_library')",
    );
    await seeded.close();

    final upgraded = AppDatabase(schema.newConnection());
    addTearDown(upgraded.close);
    await verifier.migrateAndValidate(upgraded, upgraded.schemaVersion);
    final book = await upgraded.select(upgraded.books).getSingle();
    expect((book.seriesName, book.seriesNumber), ('Dune', 1));
    final edition = await upgraded.select(upgraded.editions).getSingle();
    expect(edition.coverLocalPath, '/covers/dune.cover');
    expect(edition.pageCount, 412);
    // Nothing is invented: an old cover has no known source.
    expect(edition.coverSource, isNull);
  });

  test('a version-1 library survives upgrade to the current schema', () async {
    final schema = await verifier.schemaAt(1);
    final raw = schema.newConnection();
    final seeded = AppDatabase(raw);
    // Seed through the real v1 layout using plain SQL, as an old install would.
    await seeded.customStatement('PRAGMA foreign_keys = OFF');
    final stamp = DateTime(2024, 5, 1).millisecondsSinceEpoch ~/ 1000;
    await seeded.customStatement(
      "INSERT INTO books (id, title, created_at, updated_at) VALUES ('b1', 'Dune', $stamp, $stamp)",
    );
    await seeded.customStatement(
      "INSERT INTO authors (id, name) VALUES ('a1', 'Frank Herbert')",
    );
    await seeded.customStatement(
      "INSERT INTO book_authors (book_id, author_id, position) VALUES ('b1', 'a1', 0)",
    );
    await seeded.customStatement(
      "INSERT INTO editions (id, book_id, page_count, metadata_source) VALUES ('e1', 'b1', 412, 'manual')",
    );
    await seeded.customStatement(
      "INSERT INTO user_books (id, book_id, edition_id, status, current_page, added_at, updated_at) VALUES ('u1', 'b1', 'e1', 'finished', 0, $stamp, $stamp)",
    );
    await seeded.customStatement(
      "INSERT INTO reading_records (id, user_book_id, finished_value, finished_precision, source, created_at) VALUES ('r1', 'u1', '2019', 'year', 'entered_past', $stamp)",
    );
    await seeded.close();

    final upgraded = AppDatabase(schema.newConnection());
    addTearDown(upgraded.close);
    await verifier.migrateAndValidate(upgraded, upgraded.schemaVersion);
    final record = await upgraded.select(upgraded.readingRecords).getSingle();
    expect(record.finishedValue, '2019');
    expect(record.finishedPrecision, 'year');
    final book = await upgraded.select(upgraded.books).getSingle();
    expect(book.title, 'Dune');
    // The new columns exist and old rows simply have no series.
    expect(book.seriesName, isNull);
    expect(book.seriesNumber, isNull);
    expect(await upgraded.select(upgraded.readingSessions).get(), isEmpty);
  });
}
