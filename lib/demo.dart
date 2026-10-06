import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/storage/database.dart';
import 'features/library/data/local_library_repository.dart';
import 'features/library/domain/models.dart';

/// Preview only: all sample records live in a separate in-memory database.
Future<LocalLibraryRepository> createDemoRepository() async {
  final repo = LocalLibraryRepository(AppDatabase(NativeDatabase.memory()));
  final current = await repo.saveBook(
    title: 'The Creative Act',
    author: 'Rick Rubin',
    pageCount: 432,
    status: BookStatus.reading,
  );
  await repo.updatePage(current, 126);
  await repo.addPin(
    current,
    'Pay closer attention to what is already around me.',
    'Thought',
    page: 82,
  );
  await repo.saveBook(
    title: 'The Secret History',
    author: 'Donna Tartt',
    pageCount: 559,
    status: BookStatus.reading,
  );
  await repo.saveBook(
    title: 'A Room of One’s Own',
    author: 'Virginia Woolf',
    pageCount: 112,
    status: BookStatus.finished,
    finish: PartialDate(DatePrecision.year, '2025'),
    historical: true,
  );
  await repo.saveBook(
    title: 'The Art of Stillness',
    author: 'Pico Iyer',
    pageCount: 96,
    status: BookStatus.finished,
    finish: PartialDate(DatePrecision.month, '2026-09'),
    historical: true,
  );
  await repo.saveBook(
    title: 'Small Things Like These',
    author: 'Claire Keegan',
    pageCount: 128,
    status: BookStatus.finished,
    finish: const PartialDate.unknown(),
    historical: true,
  );
  await repo.saveBook(
    title: 'The Book of Disquiet',
    author: 'Fernando Pessoa',
    pageCount: 544,
    status: BookStatus.wantToRead,
  );
  await repo.saveBook(
    title: 'Ways of Seeing',
    author: 'John Berger',
    pageCount: 176,
    status: BookStatus.wantToRead,
  );
  await repo.saveBook(
    title: 'A Field Guide to Getting Lost',
    author: 'Rebecca Solnit',
    pageCount: 224,
    status: BookStatus.wantToRead,
  );
  final now = DateTime.now();
  await repo.logSession(
    current,
    DateTime(now.year, now.month, 1),
    start: 0,
    end: 24,
    seconds: 1800,
  );
  return repo;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = await createDemoRepository();
  runApp(
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        demoProvider.overrideWithValue(true),
      ],
      child: const ReadingLibraryApp(),
    ),
  );
}
