// Development only: fills THIS device's real library with sample books so the
// shelf can be judged at a realistic size, then starts the normal app.
//
//   flutter run -t lib/dev_seed.dart -d <device>
//
// It adds only books whose title is not already present, and downloads covers
// from Open Library when the device is online. Never shipped: the release
// entry point is lib/main.dart.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'core/storage/database.dart';
import 'features/book_search/data/open_library_lookup.dart';
import 'features/library/data/local_library_repository.dart';
import 'features/library/domain/models.dart';
import 'features/library/domain/search.dart';
import 'main.dart' as app;

typedef _Seed = (String, String, int, String);

// title, author, pages, state: R reading, W want, otherwise finish date.
const _books = <_Seed>[
  ('Dune', 'Frank Herbert', 608, '2019'),
  ('Nineteen Eighty-Four', 'George Orwell', 328, '2019-06'),
  ('Brave New World', 'Aldous Huxley', 288, '2020'),
  ('The Great Gatsby', 'F. Scott Fitzgerald', 180, '2020-03-14'),
  ('To Kill a Mockingbird', 'Harper Lee', 336, '2020'),
  ('Pride and Prejudice', 'Jane Austen', 432, '2021-01'),
  ('The Hobbit', 'J.R.R. Tolkien', 310, '2021'),
  ('Fahrenheit 451', 'Ray Bradbury', 256, '2021-08-02'),
  ('The Catcher in the Rye', 'J.D. Salinger', 234, '2021'),
  ('Crime and Punishment', 'Fyodor Dostoevsky', 671, '2022-02'),
  ('The Stranger', 'Albert Camus', 123, '2022'),
  ('The Old Man and the Sea', 'Ernest Hemingway', 127, '2022-05-20'),
  ('Frankenstein', 'Mary Shelley', 280, '2022'),
  ('Dracula', 'Bram Stoker', 418, '2022-10'),
  ('Jane Eyre', 'Charlotte Brontë', 532, '2023'),
  ('Wuthering Heights', 'Emily Brontë', 416, '2023-04'),
  ('The Picture of Dorian Gray', 'Oscar Wilde', 254, '2023'),
  ('Siddhartha', 'Hermann Hesse', 152, '2023-07-09'),
  ('The Alchemist', 'Paulo Coelho', 208, '2023'),
  ('Enigma Otiliei', 'George Călinescu', 462, '2023-11'),
  ('Moromeții', 'Marin Preda', 520, '2024'),
  ('Maitreyi', 'Mircea Eliade', 240, '2024-02'),
  ('Ion', 'Liviu Rebreanu', 380, '2024'),
  ('Sapiens', 'Yuval Noah Harari', 443, '2024-06-30'),
  ('Educated', 'Tara Westover', 352, '2024'),
  ('Atomic Habits', 'James Clear', 320, '2024-09'),
  ('Thinking, Fast and Slow', 'Daniel Kahneman', 499, '?'),
  ('The Housemaid', 'Freida McFadden', 330, '2025-01'),
  ('It Ends with Us', 'Colleen Hoover', 376, '2025'),
  ('Project Hail Mary', 'Andy Weir', 476, '2025-08-11'),
  ('The Name of the Rose', 'Umberto Eco', 536, 'R'),
  ('Piranesi', 'Susanna Clarke', 272, 'R'),
  ('Kafka on the Shore', 'Haruki Murakami', 467, 'R'),
  ('Ulysses', 'James Joyce', 730, 'W'),
  ('War and Peace', 'Leo Tolstoy', 1225, 'W'),
  ('The Brothers Karamazov', 'Fyodor Dostoevsky', 824, 'W'),
  ('Middlemarch', 'George Eliot', 880, 'W'),
  ('Beloved', 'Toni Morrison', 324, 'W'),
  ('Norwegian Wood', 'Haruki Murakami', 296, 'W'),
  ('Dune Messiah', 'Frank Herbert', 331, '2020'),
  ('Children of Dune', 'Frank Herbert', 444, '2021'),
  ('Harry Potter and the Philosopher’s Stone', 'J.K. Rowling', 309, '2021'),
  ('Harry Potter and the Chamber of Secrets', 'J.K. Rowling', 341, '2022'),
  ('Harry Potter and the Prisoner of Azkaban', 'J.K. Rowling', 435, 'W'),
  ('The Fellowship of the Ring', 'J.R.R. Tolkien', 423, 'W'),
  ('The Two Towers', 'J.R.R. Tolkien', 352, 'W'),
  ('The Secret History', 'Donna Tartt', 559, 'W'),
  ('Circe', 'Madeline Miller', 393, 'W'),
  ('Klara and the Sun', 'Kazuo Ishiguro', 303, 'W'),
  ('Ways of Seeing', 'John Berger', 176, 'W'),
  ('A Room of One’s Own', 'Virginia Woolf', 112, 'W'),
];

// title -> (series, number), applied to new and existing books alike.
const _series = <String, (String, int)>{
  'Dune': ('Dune', 1),
  'Dune Messiah': ('Dune', 2),
  'Children of Dune': ('Dune', 3),
  'Harry Potter and the Philosopher’s Stone': ('Harry Potter', 1),
  'Harry Potter and the Chamber of Secrets': ('Harry Potter', 2),
  'Harry Potter and the Prisoner of Azkaban': ('Harry Potter', 3),
  'The Hobbit': ('Middle-earth', 1),
  'The Fellowship of the Ring': ('Middle-earth', 2),
  'The Two Towers': ('Middle-earth', 3),
};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationDocumentsDirectory();
  final db = AppDatabase(
    NativeDatabase.createInBackground(
      File(p.join(dir.path, 'reading-library.sqlite')),
    ),
  );
  final repo = LocalLibraryRepository(db);
  final lookup = OpenLibraryLookup();
  final have = (await repo.load()).books
      .map((b) => foldForSearch(b.title))
      .toSet();
  var added = 0, covers = 0;
  for (final (title, author, pages, state) in _books) {
    if (have.contains(foldForSearch(title))) continue;
    String? cover;
    try {
      final found = await lookup.search('$title $author');
      final match = found
          .where(
            (s) =>
                s.coverUrl != null &&
                foldForSearch(s.title).contains(foldForSearch(title)),
          )
          .firstOrNull;
      if (match != null) cover = await lookup.fetchCover(match);
    } on Object {
      /* Offline: a generated cover is used. */
    }
    if (cover != null) covers++;
    final reading = state == 'R', want = state == 'W';
    final finish = state == '?'
        ? const PartialDate.unknown()
        : reading || want
        ? null
        : PartialDate(switch (state.length) {
            4 => DatePrecision.year,
            7 => DatePrecision.month,
            _ => DatePrecision.day,
          }, state);
    final id = await repo.saveBook(
      title: title,
      author: author,
      pageCount: pages,
      coverPath: cover,
      status: reading
          ? BookStatus.reading
          : want
          ? BookStatus.wantToRead
          : BookStatus.finished,
      finish: finish,
      historical: true,
      metadataSource: cover == null ? 'manual' : 'open_library',
    );
    if (reading) await repo.updatePage(id, pages ~/ 3);
    added++;
  }
  // Series are set in a second pass so books added on earlier runs get them too.
  for (final book in (await repo.load()).books) {
    final series = _series[book.title];
    if (series == null || book.seriesName == series.$1) continue;
    await repo.saveBook(
      id: book.id,
      title: book.title,
      author: book.author,
      pageCount: book.pageCount,
      language: book.language,
      coverPath: book.coverPath,
      status: book.status,
      seriesName: series.$1,
      seriesNumber: series.$2,
    );
  }
  debugPrint('SEED added=$added covers=$covers');
  await db.close();
  await app.main();
}
