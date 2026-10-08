import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/database.dart';
import '../domain/models.dart';

class LocalLibraryRepository implements LibraryRepository {
  final AppDatabase db;
  LocalLibraryRepository(this.db);
  static const _uuid = Uuid();
  @override
  Future<LibrarySnapshot> load() async {
    final rows = await db.customSelect('''
      SELECT u.id, u.book_id, u.edition_id, u.status, u.current_page, u.rating,
        b.title,
        b.series_name, b.series_number,
        e.page_count, e.language, e.cover_local_path, e.cover_source,
        (SELECT group_concat(name, ', ') FROM
          (SELECT a.name FROM authors a JOIN book_authors ba ON ba.author_id=a.id
           WHERE ba.book_id=b.id ORDER BY ba.position)) AS author
      FROM user_books u JOIN books b ON u.book_id=b.id
      JOIN editions e ON e.id=u.edition_id ORDER BY u.added_at DESC, u.id
    ''').get();
    return LibrarySnapshot(
      books: rows
          .map(
            (r) => BookEntry(
              id: r.read('id'),
              bookId: r.read('book_id'),
              editionId: r.read('edition_id'),
              title: r.read('title'),
              author: r.readNullable<String>('author') ?? '',
              status: BookStatus.values.byName(r.read('status')),
              currentPage: r.read('current_page'),
              rating: r.readNullable('rating'),
              pageCount: r.readNullable('page_count'),
              seriesName: r.readNullable('series_name'),
              seriesNumber: r.readNullable('series_number'),
              language: r.readNullable('language'),
              coverPath: r.readNullable('cover_local_path'),
              coverSource: r.readNullable('cover_source'),
            ),
          )
          .toList(),
      completions: (await db.select(db.readingRecords).get())
          .map(
            (r) => Completion(
              id: r.id,
              userBookId: r.userBookId,
              finish: PartialDate(
                DatePrecision.values.byName(r.finishedPrecision),
                r.finishedValue,
              ),
              source: r.source,
            ),
          )
          .toList(),
      sessions: (await db.select(db.readingSessions).get())
          .map(
            (s) => ReadingActivity(
              id: s.id,
              userBookId: s.userBookId,
              startedAt: s.startedAt,
              startPage: s.startPage,
              endPage: s.endPage,
              durationSeconds: s.durationSeconds,
            ),
          )
          .toList(),
      pins: (await db.select(db.pins).get())
          .map(
            (p) => BookPin(
              id: p.id,
              userBookId: p.userBookId,
              text: p.textContent,
              type: p.type,
              page: p.page,
              percent: p.progressPercent,
            ),
          )
          .toList(),
    );
  }

  @override
  Future<Set<String>> coverPaths() async => (await db.select(db.editions).get())
      .map((e) => e.coverLocalPath)
      .whereType<String>()
      .toSet();
  @override
  Future<List<({String editionId, String source})>> coversToFetch() async {
    final rows =
        await (db.select(db.editions)..where(
              (e) => e.coverSource.isNotNull() & e.coverLocalPath.isNull(),
            ))
            .get();
    return [
      for (final e in rows)
        if (isOpenLibraryCoverUrl(e.coverSource!))
          (editionId: e.id, source: e.coverSource!),
    ];
  }

  @override
  Future<void> attachCover(String editionId, String path) async {
    await (db.update(db.editions)..where((e) => e.id.equals(editionId))).write(
      EditionsCompanion(coverLocalPath: Value(path)),
    );
  }

  Future<UserBook> _owned(String id) =>
      (db.select(db.userBooks)..where((u) => u.id.equals(id))).getSingle();
  Future<int?> _total(UserBook u) async => (await (db.select(
    db.editions,
  )..where((e) => e.id.equals(u.editionId))).getSingle()).pageCount;
  @override
  Future<String> saveBook({
    String? id,
    required String title,
    required String author,
    int? pageCount,
    String? language,
    String? coverPath,
    String? coverSource,
    required BookStatus status,
    PartialDate? finish,
    bool historical = false,
    String metadataSource = 'manual',
    String? seriesName,
    int? seriesNumber,
  }) async {
    if (title.trim().isEmpty || author.trim().isEmpty) {
      throw const FormatException('Enter a title and author.');
    }
    final series = seriesName?.trim().isEmpty ?? true
        ? null
        : seriesName!.trim();
    if (seriesNumber != null && series == null) {
      throw const FormatException('Enter the series name for this number.');
    }
    if (seriesNumber != null && seriesNumber <= 0) {
      throw const FormatException('The series number must be 1 or more.');
    }
    if (pageCount != null && pageCount <= 0) {
      throw const FormatException('Page count must be greater than zero.');
    }
    if (coverSource != null && !isOpenLibraryCoverUrl(coverSource)) {
      throw const FormatException('Unknown cover source.');
    }
    if (status == BookStatus.finished && id == null && finish == null) {
      throw const FormatException('Confirm when you finished this book.');
    }
    return db.transaction(() async {
      final now = DateTime.now();
      final old = id == null ? null : await _owned(id);
      if (status == BookStatus.finished &&
          old?.status != BookStatus.finished.name &&
          finish == null) {
        throw const FormatException('Confirm when you finished this book.');
      }
      final originalBook = old == null
          ? null
          : await (db.select(
              db.books,
            )..where((b) => b.id.equals(old.bookId))).getSingle();
      final bookId = old?.bookId ?? _uuid.v4(),
          editionId = old?.editionId ?? _uuid.v4(),
          userId = old?.id ?? _uuid.v4();
      if (old != null) {
        validatePage(old.currentPage, pageCount);
        final sessions = await (db.select(
          db.readingSessions,
        )..where((s) => s.userBookId.equals(userId))).get();
        for (final s in sessions) {
          validateSession(s.startPage, s.endPage, s.durationSeconds, pageCount);
        }
        final pins = await (db.select(
          db.pins,
        )..where((p) => p.userBookId.equals(userId))).get();
        for (final p in pins) {
          if (p.page != null) validatePage(p.page!, pageCount);
        }
      }
      await db
          .into(db.books)
          .insertOnConflictUpdate(
            BooksCompanion.insert(
              id: bookId,
              title: title.trim(),
              seriesName: Value(series),
              seriesNumber: Value(seriesNumber),
              createdAt: originalBook?.createdAt ?? now,
              updatedAt: now,
            ),
          );
      await (db.delete(
        db.bookAuthors,
      )..where((ba) => ba.bookId.equals(bookId))).go();
      final authorId = _uuid.v4();
      await db
          .into(db.authors)
          .insert(AuthorsCompanion.insert(id: authorId, name: author.trim()));
      await db
          .into(db.bookAuthors)
          .insert(
            BookAuthorsCompanion.insert(
              bookId: bookId,
              authorId: authorId,
              position: 0,
            ),
          );
      await db
          .into(db.editions)
          .insertOnConflictUpdate(
            EditionsCompanion.insert(
              id: editionId,
              bookId: bookId,
              pageCount: Value(pageCount),
              language: Value(language),
              coverLocalPath: Value(coverPath),
              coverSource: Value(coverSource),
              // Editing keeps the original provenance.
              metadataSource: old == null
                  ? Value(metadataSource)
                  : const Value.absent(),
            ),
          );
      await db
          .into(db.userBooks)
          .insertOnConflictUpdate(
            UserBooksCompanion.insert(
              id: userId,
              bookId: bookId,
              editionId: editionId,
              status: status.name,
              currentPage: Value(old?.currentPage ?? 0),
              addedAt: old?.addedAt ?? now,
              updatedAt: now,
            ),
          );
      if (status == BookStatus.finished && finish != null) {
        await _finish(userId, finish, historical);
      }
      await _pruneAuthors();
      return userId;
    });
  }

  Future<void> _pruneAuthors() => db.customStatement(
    'DELETE FROM authors WHERE id NOT IN (SELECT author_id FROM book_authors)',
  );
  Future<void> _finish(String id, PartialDate finish, bool historical) async {
    await db
        .into(db.readingRecords)
        .insert(
          ReadingRecordsCompanion.insert(
            id: _uuid.v4(),
            userBookId: id,
            finishedValue: Value(finish.value),
            finishedPrecision: finish.precision.name,
            source: historical ? 'entered_past' : 'tracked_in_app',
            createdAt: DateTime.now(),
          ),
        );
  }

  @override
  Future<void> updatePage(String id, int page) => db.transaction(() async {
    final u = await _owned(id);
    validatePage(page, await _total(u));
    await (db.update(db.userBooks)..where((u) => u.id.equals(id))).write(
      UserBooksCompanion(
        currentPage: Value(page),
        updatedAt: Value(DateTime.now()),
      ),
    );
  });
  @override
  Future<void> setStatus(String id, BookStatus status, {PartialDate? finish}) =>
      db.transaction(() async {
        final old = await _owned(id);
        if (status == BookStatus.finished) {
          if (finish == null) {
            throw const FormatException('Confirm the finish date.');
          }
          if (old.status == BookStatus.finished.name) {
            throw const FormatException('This book is already finished.');
          }
          await _finish(id, finish, false);
        }
        await (db.update(db.userBooks)..where((u) => u.id.equals(id))).write(
          UserBooksCompanion(
            status: Value(status.name),
            updatedAt: Value(DateTime.now()),
          ),
        );
      });
  @override
  Future<void> setRating(String id, int? rating) => db.transaction(() async {
    validateRating(rating);
    await _owned(id);
    final finished = await (db.select(
      db.readingRecords,
    )..where((r) => r.userBookId.equals(id))).get();
    if (rating != null && finished.isEmpty) {
      throw const FormatException('Rate a book after you have finished it.');
    }
    await (db.update(db.userBooks)..where((u) => u.id.equals(id))).write(
      UserBooksCompanion(
        rating: Value(rating),
        updatedAt: Value(DateTime.now()),
      ),
    );
  });
  @override
  Future<void> logSession(
    String id,
    DateTime date, {
    int? start,
    int? end,
    int? seconds,
  }) => db.transaction(() async {
    final u = await _owned(id);
    validateSession(start, end, seconds, await _total(u));
    if (date.isAfter(DateTime.now())) {
      throw const FormatException('A session cannot be in the future.');
    }
    await db
        .into(db.readingSessions)
        .insert(
          ReadingSessionsCompanion.insert(
            id: _uuid.v4(),
            userBookId: id,
            startedAt: date,
            startPage: Value(start),
            endPage: Value(end),
            durationSeconds: Value(seconds),
            createdAt: DateTime.now(),
          ),
        );
    // Session date and current position are independent. Backdated sessions do not rewind progress.
    if (end != null && end > u.currentPage) await updatePage(id, end);
  });
  @override
  Future<void> addPin(
    String id,
    String text,
    String type, {
    int? page,
    double? percent,
  }) async {
    final u = await _owned(id);
    if (text.trim().isEmpty) {
      throw const FormatException('Write something to remember.');
    }
    if (!['Thought', 'Favorite', 'Quote', 'Question', 'Idea'].contains(type)) {
      throw const FormatException('Unknown pin type.');
    }
    if (page != null) validatePage(page, await _total(u));
    if (percent != null &&
        (!percent.isFinite || percent < 0 || percent > 100)) {
      throw const FormatException('Percentage must be between 0 and 100.');
    }
    final now = DateTime.now();
    await db
        .into(db.pins)
        .insert(
          PinsCompanion.insert(
            id: _uuid.v4(),
            userBookId: id,
            textContent: text.trim(),
            type: type,
            page: Value(page),
            progressPercent: Value(percent),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  @override
  Future<void> deletePin(String id) async {
    await (db.delete(db.pins)..where((p) => p.id.equals(id))).go();
  }

  @override
  Future<void> deleteBook(String id) => db.transaction(() async {
    final u = await _owned(id);
    await (db.delete(db.userBooks)..where((b) => b.id.equals(id))).go();
    await (db.delete(db.books)..where((b) => b.id.equals(u.bookId))).go();
    await _pruneAuthors();
  });
  @override
  Future<Map<String, dynamic>> exportData() => db.transaction(
    () async => {
      'version': 1,
      'books': (await db.select(db.books).get())
          .map((r) => r.toJson())
          .toList(),
      'authors': (await db.select(db.authors).get())
          .map((r) => r.toJson())
          .toList(),
      'bookAuthors': (await db.select(db.bookAuthors).get())
          .map((r) => r.toJson())
          .toList(),
      'editions': (await db.select(db.editions).get())
          .map((r) => r.toJson())
          .toList(),
      'userBooks': (await db.select(db.userBooks).get())
          .map((r) => r.toJson())
          .toList(),
      'records': (await db.select(db.readingRecords).get())
          .map((r) => r.toJson())
          .toList(),
      'sessions': (await db.select(db.readingSessions).get())
          .map((r) => r.toJson())
          .toList(),
      'pins': (await db.select(db.pins).get()).map((r) => r.toJson()).toList(),
    },
  );
  @override
  Future<void> restoreData(Map<String, dynamic> data) async {
    if (data['version'] != 1) {
      throw const FormatException('Unsupported backup version.');
    }
    List<T> decode<T>(String key, T Function(Map<String, dynamic>) convert) {
      final rows = data[key];
      if (rows is! List || rows.length > 100000) {
        throw FormatException('Invalid $key in backup.');
      }
      return rows
          .map((r) => convert(Map<String, dynamic>.from(r as Map)))
          .toList();
    }

    final books = decode('books', Book.fromJson),
        authors = decode('authors', Author.fromJson);
    final links = decode('bookAuthors', BookAuthor.fromJson),
        editions = decode('editions', Edition.fromJson);
    final owned = decode('userBooks', UserBook.fromJson),
        records = decode('records', ReadingRecord.fromJson);
    final sessions = decode('sessions', ReadingSession.fromJson),
        pins = decode('pins', Pin.fromJson);
    if (books.any((b) => b.title.trim().isEmpty) ||
        authors.any((a) => a.name.trim().isEmpty)) {
      throw const FormatException('Empty title or author.');
    }
    // Series fields are optional (older backups have none), but when present
    // they must make sense.
    for (final b in books) {
      final name = b.seriesName;
      if ((name != null && name.trim().isEmpty) ||
          (b.seriesNumber != null && (b.seriesNumber! <= 0 || name == null))) {
        throw const FormatException('Invalid series.');
      }
    }
    for (final e in editions) {
      if (e.pageCount != null && e.pageCount! <= 0) {
        throw const FormatException('Invalid page count.');
      }
      if (e.coverSource != null && !isOpenLibraryCoverUrl(e.coverSource!)) {
        throw const FormatException('Unknown cover source.');
      }
    }
    final totals = <String, int?>{};
    for (final u in owned) {
      BookStatus.values.byName(u.status);
      final edition = editions
          .where((e) => e.id == u.editionId && e.bookId == u.bookId)
          .firstOrNull;
      if (edition == null || !links.any((l) => l.bookId == u.bookId)) {
        throw const FormatException('Missing edition or author.');
      }
      totals[u.id] = edition.pageCount;
      validatePage(u.currentPage, edition.pageCount);
      // Absent in backups made before ratings existed (read as unrated).
      validateRating(u.rating);
      if (u.rating != null && !records.any((r) => r.userBookId == u.id)) {
        throw const FormatException('A rating needs a finished book.');
      }
      if (u.status == BookStatus.finished.name &&
          !records.any((r) => r.userBookId == u.id)) {
        throw const FormatException('Finished book has no history.');
      }
    }
    for (final r in records) {
      PartialDate(
        DatePrecision.values.byName(r.finishedPrecision),
        r.finishedValue,
      );
      if (!['tracked_in_app', 'entered_past'].contains(r.source)) {
        throw const FormatException('Invalid history source.');
      }
    }
    for (final s in sessions) {
      validateSession(
        s.startPage,
        s.endPage,
        s.durationSeconds,
        totals[s.userBookId],
      );
    }
    for (final p in pins) {
      if (p.textContent.trim().isEmpty ||
          ![
            'Thought',
            'Favorite',
            'Quote',
            'Question',
            'Idea',
          ].contains(p.type)) {
        throw const FormatException('Invalid pin.');
      }
      if (p.page != null) validatePage(p.page!, totals[p.userBookId]);
      if (p.progressPercent != null &&
          (!p.progressPercent!.isFinite ||
              p.progressPercent! < 0 ||
              p.progressPercent! > 100)) {
        throw const FormatException('Invalid pin percentage.');
      }
    }
    await db.transaction(() async {
      for (final table in <TableInfo>[
        db.pins,
        db.readingSessions,
        db.readingRecords,
        db.userBooks,
        db.editions,
        db.bookAuthors,
        db.authors,
        db.books,
      ]) {
        await db.delete(table).go();
      }
      // Foreign keys and primary keys validate every relation and duplicate atomically.
      for (final b in books) {
        await db.into(db.books).insert(b);
      }
      for (final a in authors) {
        await db.into(db.authors).insert(a);
      }
      for (final l in links) {
        await db.into(db.bookAuthors).insert(l);
      }
      for (final e in editions) {
        await db.into(db.editions).insert(e);
      }
      for (final u in owned) {
        await db.into(db.userBooks).insert(u);
      }
      for (final r in records) {
        await db.into(db.readingRecords).insert(r);
      }
      for (final s in sessions) {
        await db.into(db.readingSessions).insert(s);
      }
      for (final p in pins) {
        await db.into(db.pins).insert(p);
      }
    });
  }
}
