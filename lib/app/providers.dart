import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/draft_store.dart';
import '../features/book_search/data/open_library_lookup.dart';
import '../features/book_search/domain/book_lookup.dart';
import '../features/library/domain/models.dart';

final repositoryProvider = Provider<LibraryRepository>(
  (ref) => throw UnimplementedError('Provide a local repository.'),
);
final libraryProvider = FutureProvider<LibrarySnapshot>(
  (ref) => ref.watch(repositoryProvider).load(),
);
final demoProvider = Provider<bool>((ref) => false);
final draftStoreProvider = Provider<DraftStore>((ref) => MemoryDraftStore());
final bookLookupProvider = Provider<BookLookup>((ref) => OpenLibraryLookup());
