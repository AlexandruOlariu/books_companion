import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_library/core/storage/database.dart';

import 'generated_migrations/schema.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;
  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('the current schema matches the frozen version-1 dump', () async {
    // Fails if a table or column changes without a new schema version and a
    // dump in drift_schemas/.
    final connection = await verifier.startAt(1);
    final db = AppDatabase(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, db.schemaVersion);
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
    expect((await upgraded.select(upgraded.books).getSingle()).title, 'Dune');
    expect(await upgraded.select(upgraded.readingSessions).get(), isEmpty);
  });
}
