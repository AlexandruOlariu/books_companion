import 'package:reading_library/features/book_search/domain/book_lookup.dart';
import 'package:reading_library/features/friends/domain/friends_models.dart';
import 'package:reading_library/features/sync/domain/sync_models.dart';

/// An in-memory server that saves one library per account, with the same
/// revision rule as the real one. Records what the app sent.
class FakeLibraryServer implements LibrarySyncApi {
  String? userId = 'ana';
  Map<String, dynamic>? stored;
  int revision = 0;
  bool offline = false, signedOut = false;

  /// Runs once, inside the next save, before the revision check; simulates
  /// another phone saving at the same moment.
  void Function()? duringSave;
  final saves = <Map<String, dynamic>>[];
  final bases = <int>[];

  /// What another phone saved.
  void saveElsewhere(Map<String, dynamic> data) {
    stored = data;
    revision++;
  }

  void _check() {
    if (offline) throw const FriendsException('Could not reach the server.');
    if (signedOut) {
      throw const FriendsException('Please sign in again.', signedOut: true);
    }
  }

  @override
  Future<String?> accountId() async {
    _check();
    return userId;
  }

  @override
  Future<LibraryRevision?> libraryRevision() async {
    _check();
    return stored == null ? null : LibraryRevision(revision, DateTime(2026));
  }

  @override
  Future<RemoteLibrary?> fetchLibrary() async {
    _check();
    return stored == null
        ? null
        : RemoteLibrary(revision, DateTime(2026), {...stored!});
  }

  @override
  Future<LibraryRevision> saveLibrary(
    Map<String, dynamic> data, {
    required int baseRevision,
  }) async {
    _check();
    duringSave?.call();
    duringSave = null;
    if (baseRevision != revision) throw const LibraryConflictException();
    bases.add(baseRevision);
    saves.add(data);
    stored = data;
    return LibraryRevision(++revision, DateTime(2026));
  }
}

class FakeCoverLookup implements BookLookup {
  final fetched = <String>[];
  String? path = '/covers/fetched.cover';
  @override
  Future<List<BookSuggestion>> search(String query) async => [];
  @override
  Future<String?> fetchCover(BookSuggestion suggestion) async => null;
  @override
  Future<String?> fetchCoverFromUrl(String url) async {
    fetched.add(url);
    return path;
  }
}
