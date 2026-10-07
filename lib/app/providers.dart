import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/draft_store.dart';
import '../core/storage/preferences_store.dart';
import '../core/storage/session_store.dart';
import '../features/book_search/data/server_book_lookup.dart';
import '../features/book_search/domain/book_lookup.dart';
import '../features/friends/data/contacts_source.dart';
import '../features/friends/data/http_friends_api.dart';
import '../features/friends/domain/friends_models.dart';
import '../features/library/domain/models.dart';
import '../features/sync/data/syncing_repository.dart';
import '../features/sync/domain/sync_models.dart';

final repositoryProvider = Provider<LibraryRepository>(
  (ref) => throw UnimplementedError('Provide a local repository.'),
);
final libraryProvider = FutureProvider<LibrarySnapshot>(
  (ref) => ref.watch(repositoryProvider).load(),
);
final demoProvider = Provider<bool>((ref) => false);
final draftStoreProvider = Provider<DraftStore>((ref) => MemoryDraftStore());
final bookLookupProvider = Provider<BookLookup>((ref) => ServerBookLookup());
final preferencesProvider = Provider<PreferencesStore>(
  (ref) => MemoryPreferencesStore(),
);
final sessionStoreProvider = Provider<SessionStore>(
  (ref) => MemorySessionStore(),
);

/// One client for the whole server, so the friends calls and the library
/// saves share a sign-in and a single token refresh.
final serverApiProvider = Provider<HttpFriendsApi>(
  (ref) => HttpFriendsApi(session: ref.watch(sessionStoreProvider)),
);
final friendsApiProvider = Provider<FriendsApi>(
  (ref) => ref.watch(serverApiProvider),
);
final librarySyncApiProvider = Provider<LibrarySyncApi>(
  (ref) => ref.watch(serverApiProvider),
);

/// True in the real app: the library is saved to an account, so the app asks
/// for one before it opens. Off by default so tests and the demo run without.
final accountRequiredProvider = Provider<bool>((ref) => false);

/// Whether this device holds an account session (answered on the device).
final signedInProvider = FutureProvider<bool>(
  (ref) => ref.watch(friendsApiProvider).signedIn(),
);

/// The repository the sync engine reads and replaces. `main.dart` gives it the
/// plain local one, so a download is not seen as a change to save again.
final syncRepositoryProvider = Provider<LibraryRepository>(
  (ref) => ref.watch(repositoryProvider),
);
final libraryChangeHookProvider = Provider<LibraryChangeHook>(
  (ref) => LibraryChangeHook(),
);
final contactsSourceProvider = Provider<ContactsSource>(
  (ref) => DeviceContactsSource(),
);
final regionProvider = Provider<String?>(
  (ref) => PlatformDispatcher.instance.locale.countryCode,
);
