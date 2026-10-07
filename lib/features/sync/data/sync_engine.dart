import '../../../core/storage/preferences_store.dart';
import '../../book_search/domain/book_lookup.dart';
import '../../friends/domain/friends_models.dart';
import '../../library/domain/models.dart';
import '../domain/sync_models.dart';

/// Keeps the account's saved library and the phone's library the same, with
/// the phone as the source of truth.
///
/// The phone never waits for the server: every change is written locally first
/// and marked "not saved yet". A later sync sends the whole library (the app's
/// backup data, covers left out) based on the revision the phone last saw. If
/// the server has a newer revision the phone does not overwrite it: it either
/// downloads it (nothing unsaved here) or asks the reader which side to keep.
/// Nothing is merged, so no date or activity is ever invented.
class SyncEngine {
  final LibraryRepository repository;
  final LibrarySyncApi api;
  final PreferencesStore preferences;
  final BookLookup lookup;
  SyncEngine({
    required this.repository,
    required this.api,
    required this.preferences,
    required this.lookup,
  });

  static const userKey = 'sync.userId';
  static const revisionKey = 'sync.revision';
  static const dirtyKey = 'sync.dirty';
  static const _coversPerRun = 40;

  int _localVersion = 0;

  Future<bool> get isDirty async => await preferences.read(dirtyKey) == '1';

  /// The library changed on this phone and is not saved to the account yet.
  Future<void> markDirty() async {
    _localVersion++;
    await preferences.write(dirtyKey, '1');
  }

  /// Call after signing in. A different account than last time means the
  /// phone has never been synced with this one.
  Future<void> adopt(String userId) async {
    if (await preferences.read(userKey) != userId) {
      await preferences.write(userKey, userId);
      await preferences.write(revisionKey, '');
    }
  }

  /// Call after the account is deleted: the phone's library is then new to
  /// whatever account is made or used next.
  Future<void> forget() async {
    await preferences.write(userKey, '');
    await preferences.write(revisionKey, '');
    await preferences.write(dirtyKey, '1');
  }

  Future<int?> _baseline() async =>
      int.tryParse(await preferences.read(revisionKey) ?? '');

  Future<void> _saved(int revision) async {
    await preferences.write(revisionKey, '$revision');
  }

  /// Makes the account and the phone agree, when they can without a choice.
  Future<SyncResult> sync() async {
    try {
      var userId = await preferences.read(userKey);
      if (userId == null || userId.isEmpty) {
        userId = await api.accountId();
        if (userId == null) return const SyncResult(SyncOutcome.signedOut);
        await adopt(userId);
      }
      final server = await api.libraryRevision();
      final baseline = await _baseline();
      final dirty = await isDirty;
      final phone = (await repository.load()).books.length;

      if (baseline == null) {
        // First time this phone meets this account.
        if (server == null) return await _push(0);
        if (phone == 0) return await _pull();
        return SyncResult(
          SyncOutcome.conflict,
          conflict: await _describe(phone, server),
        );
      }
      if (server == null) {
        // The account lost it; the phone has it.
        return await _push(0);
      }
      if (server.revision == baseline) {
        return dirty
            ? await _push(baseline)
            : await _finish(SyncOutcome.upToDate);
      }
      if (server.revision > baseline && !dirty) {
        return await _pull();
      }
      if (server.revision > baseline) {
        return SyncResult(
          SyncOutcome.conflict,
          conflict: await _describe(phone, server),
        );
      }
      // The server is behind what this phone saw (it was restored from an old
      // copy): the phone is the source.
      return await _push(server.revision);
    } on LibraryConflictException {
      // Someone saved between the check and the save: look again.
      return await _conflictNow();
    } on FriendsException catch (e) {
      return SyncResult(
        e.signedOut ? SyncOutcome.signedOut : SyncOutcome.offline,
        message: e.message,
      );
    } on FormatException catch (e) {
      return SyncResult(SyncOutcome.failed, message: e.message);
    }
  }

  /// The reader's answer to a [SyncOutcome.conflict]: keep what is on this
  /// phone (replacing the account's library) or take the account's.
  Future<SyncResult> resolve({required bool keepPhone}) async {
    try {
      if (!keepPhone) return await _pull();
      final server = await api.libraryRevision();
      return await _push(server?.revision ?? 0);
    } on LibraryConflictException {
      return await _conflictNow();
    } on FriendsException catch (e) {
      return SyncResult(
        e.signedOut ? SyncOutcome.signedOut : SyncOutcome.offline,
        message: e.message,
      );
    } on FormatException catch (e) {
      return SyncResult(SyncOutcome.failed, message: e.message);
    }
  }

  Future<SyncResult> _conflictNow() async {
    final server = await api.libraryRevision();
    final phone = (await repository.load()).books.length;
    return SyncResult(
      SyncOutcome.conflict,
      conflict: server == null ? null : await _describe(phone, server),
    );
  }

  Future<SyncConflict> _describe(int phone, LibraryRevision server) async {
    final remote = await api.fetchLibrary();
    final books = remote?.data['userBooks'];
    return SyncConflict(
      phoneBooks: phone,
      accountBooks: books is List ? books.length : 0,
      accountUpdatedAt: server.updatedAt,
    );
  }

  Future<SyncResult> _push(int base) async {
    final version = _localVersion;
    final data = await repository.exportData();
    // Cover files stay on the phone; only where an online cover came from is
    // saved, so another phone can fetch it again.
    for (final edition in data['editions'] as List) {
      (edition as Map<String, dynamic>)['coverLocalPath'] = null;
    }
    final saved = await api.saveLibrary(data, baseRevision: base);
    await _saved(saved.revision);
    // Changes made while this was sending stay marked for the next sync.
    if (version == _localVersion) await preferences.write(dirtyKey, '');
    return await _finish(SyncOutcome.uploaded);
  }

  Future<SyncResult> _pull() async {
    final remote = await api.fetchLibrary();
    if (remote == null) return await _push(0);
    // Keep the covers already on this phone for the books it already has.
    final covers = {
      for (final e in (await repository.exportData())['editions'] as List)
        if ((e as Map)['coverLocalPath'] != null)
          e['id'] as String: e['coverLocalPath'] as String,
    };
    try {
      final data = Map<String, dynamic>.from(remote.data);
      data['editions'] = [
        for (final e in data['editions'] as List)
          {
            ...Map<String, dynamic>.from(e as Map),
            'coverLocalPath': covers[e['id']],
          },
      ];
      await repository.restoreData(data);
    } on FormatException {
      rethrow;
    } on Object {
      // Wrong shapes surface as type errors; either way the phone is untouched.
      throw const FormatException('The saved library could not be read.');
    }
    await _saved(remote.revision);
    await preferences.write(dirtyKey, '');
    return await _finish(SyncOutcome.downloaded);
  }

  Future<SyncResult> _finish(SyncOutcome outcome) async => SyncResult(outcome);

  /// Fetches again the online covers this phone does not have (after a
  /// download or a failed attempt). Best effort: a missing cover stays
  /// generated. Returns how many arrived.
  Future<int> fetchMissingCovers() async {
    var fetched = 0;
    final missing = await repository.coversToFetch();
    for (final cover in missing.take(_coversPerRun)) {
      try {
        final path = await lookup.fetchCoverFromUrl(cover.source);
        if (path == null) continue;
        await repository.attachCover(cover.editionId, path);
        fetched++;
      } on Object {
        /* Try again at the next sync. */
      }
    }
    return fetched;
  }
}
