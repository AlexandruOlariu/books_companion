import 'package:drift/drift.dart';

import 'migrations/schema_versions.dart';

part 'database.g.dart';

class Books extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
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
  int get schemaVersion => 1;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    // Each new schema version needs a frozen dump (`dart run drift_dev schema
    // dump`), a generated step, and a data-preserving case in
    // test/migration_test.dart. A missing step throws and never drops data.
    onUpgrade: stepByStep(),
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
