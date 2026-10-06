import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/draft_store.dart';
import '../core/storage/preferences_store.dart';
import '../core/storage/session_store.dart';
import '../features/book_search/data/open_library_lookup.dart';
import '../features/book_search/domain/book_lookup.dart';
import '../features/friends/data/contacts_source.dart';
import '../features/friends/data/http_friends_api.dart';
import '../features/friends/domain/friends_models.dart';
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
final preferencesProvider = Provider<PreferencesStore>(
  (ref) => MemoryPreferencesStore(),
);
final sessionStoreProvider = Provider<SessionStore>(
  (ref) => MemorySessionStore(),
);
final friendsApiProvider = Provider<FriendsApi>(
  (ref) => HttpFriendsApi(session: ref.watch(sessionStoreProvider)),
);
final contactsSourceProvider = Provider<ContactsSource>(
  (ref) => DeviceContactsSource(),
);
final regionProvider = Provider<String?>(
  (ref) => PlatformDispatcher.instance.locale.countryCode,
);
