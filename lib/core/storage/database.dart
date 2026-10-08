import 'package:drift/drift.dart';

import 'migrations/schema_versions.dart';

part 'database.g.dart';

class Books extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  // Added in schema version 2. Both are optional; a number needs a name.
  TextColumn get seriesName => text().nullable()();
  IntColumn get seriesNumber => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

class Authors extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class BookAuthors extends Table {
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();
  TextColumn get authorId => text().references(Authors, #id)();
  IntColumn get position => integer()();
  @override
  Set<Column> get primaryKey => {bookId, authorId};
}

class Editions extends Table {
  TextColumn get id => text()();
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();
  IntColumn get pageCount => integer().nullable()();
  TextColumn get language => text().nullable()();
  TextColumn get coverLocalPath => text().nullable()();
  // Added in schema version 3: where a cover found online came from (a URL on
  // Open Library's cover host), so a library restored on another phone can
  // fetch it again. Null for a cover chosen from the gallery.
  TextColumn get coverSource => text().nullable()();
  TextColumn get metadataSource =>
      text().withDefault(const Constant('manual'))();
  @override
  Set<Column> get primaryKey => {id};
}

class UserBooks extends Table {
  TextColumn get id => text()();
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();
  TextColumn get editionId => text().references(Editions, #id)();
  TextColumn get status => text()();
  // Added in schema version 4: the reader's own rating, 1 to 5, or null. Set
  // only by the reader, never inferred, and never shared with friends.
  IntColumn get rating => integer().nullable()();
  IntColumn get currentPage => integer().withDefault(const Constant(0))();
  DateTimeColumn get addedAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

class ReadingRecords extends Table {
  TextColumn get id => text()();
  TextColumn get userBookId =>
      text().references(UserBooks, #id, onDelete: KeyAction.cascade)();
  TextColumn get finishedValue => text().nullable()();
  TextColumn get finishedPrecision => text()();
  TextColumn get source => text()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

class ReadingSessions extends Table {
  TextColumn get id => text()();
  TextColumn get userBookId =>
      text().references(UserBooks, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get startedAt => dateTime()();
  IntColumn get startPage => integer().nullable()();
  IntColumn get endPage => integer().nullable()();
  IntColumn get durationSeconds => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

class Pins extends Table {
  TextColumn get id => text()();
  TextColumn get userBookId =>
      text().references(UserBooks, #id, onDelete: KeyAction.cascade)();
  TextColumn get textContent => text()();
  TextColumn get type => text()();
  IntColumn get page => integer().nullable()();
  RealColumn get progressPercent => real().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Books,
    Authors,
    BookAuthors,
    Editions,
    UserBooks,
    ReadingRecords,
    ReadingSessions,
    Pins,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);
  @override
  int get schemaVersion => 4;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    // Each new schema version needs a frozen dump (`dart run drift_dev schema
    // dump`), a generated step, and a data-preserving case in
    // test/migration_test.dart. A missing step throws and never drops data.
    onUpgrade: stepByStep(
      // 1 -> 2: optional series name and number on books. Existing rows keep
      // their data and simply have no series.
      from1To2: (m, schema) async {
        await m.addColumn(schema.books, schema.books.seriesName);
        await m.addColumn(schema.books, schema.books.seriesNumber);
      },
      // 2 -> 3: where an online cover came from. Existing rows have none.
      from2To3: (m, schema) async {
        await m.addColumn(schema.editions, schema.editions.coverSource);
      },
      // 3 -> 4: the reader's rating of a book. Existing rows are unrated.
      from3To4: (m, schema) async {
        await m.addColumn(schema.userBooks, schema.userBooks.rating);
      },
    ),
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
