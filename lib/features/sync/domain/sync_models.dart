/// A saved library's version on the server. It moves on by one with every save.
class LibraryRevision {
  final int revision;
  final DateTime updatedAt;
  const LibraryRevision(this.revision, this.updatedAt);
}

class RemoteLibrary extends LibraryRevision {
  /// The app's backup data (`LibraryRepository.exportData`), without covers.
  final Map<String, dynamic> data;
  const RemoteLibrary(super.revision, super.updatedAt, this.data);
}

/// The server has a newer revision than the one this save was based on.
class LibraryConflictException implements Exception {
  const LibraryConflictException();
}

/// The part of the server that saves the reader's library. Failures are
/// `FriendsException`s (unreachable, signed out) so one place handles them.
abstract class LibrarySyncApi {
  /// The signed-in account's id, or null when nobody is signed in.
  Future<String?> accountId();

  /// Null when nothing has been saved for this account yet.
  Future<LibraryRevision?> libraryRevision();
  Future<RemoteLibrary?> fetchLibrary();

  /// Replaces the saved library. [baseRevision] is the revision this phone last
  /// saw (0 for none); throws [LibraryConflictException] if the server moved on.
  Future<LibraryRevision> saveLibrary(
    Map<String, dynamic> data, {
    required int baseRevision,
  });
}

/// Both the phone and the account hold a library and neither came from the
/// other, so the reader chooses.
class SyncConflict {
  final int phoneBooks, accountBooks;
  final DateTime? accountUpdatedAt;
  const SyncConflict({
    required this.phoneBooks,
    required this.accountBooks,
    this.accountUpdatedAt,
  });
}

enum SyncOutcome {
  /// Nothing to do: both sides already agree.
  upToDate,
  uploaded,
  downloaded,
  conflict,

  /// The server could not be reached; the changes wait on the phone.
  offline,
  signedOut,

  /// The server's library could not be read or saved (see [SyncResult.message]).
  failed,
}

class SyncResult {
  final SyncOutcome outcome;
  final SyncConflict? conflict;
  final String? message;
  const SyncResult(this.outcome, {this.conflict, this.message});
}
