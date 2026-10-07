import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../friends/presentation/friends_providers.dart';
import '../data/sync_engine.dart';
import '../domain/sync_models.dart';

/// What the reader is told about saving to the account.
enum SyncPhase {
  /// Not saving (the demo, or nobody is signed in).
  off,
  syncing,
  saved,

  /// Changes are safe on the phone and wait for a connection.
  waiting,

  /// The phone and the account each have a library; the reader must choose.
  conflict,
  problem,
}

class SyncState {
  final SyncPhase phase;
  final DateTime? lastSaved;
  final String? message;
  final SyncConflict? conflict;
  const SyncState(this.phase, {this.lastSaved, this.message, this.conflict});
}

final syncEngineProvider = Provider<SyncEngine>(
  (ref) => SyncEngine(
    repository: ref.watch(syncRepositoryProvider),
    api: ref.watch(librarySyncApiProvider),
    preferences: ref.watch(preferencesProvider),
    lookup: ref.watch(bookLookupProvider),
  ),
);

final syncControllerProvider = NotifierProvider<SyncController, SyncState>(
  SyncController.new,
);

/// Saves the library to the account soon after it changes, when the app comes
/// back to the foreground, and after signing in. The phone never waits for it.
class SyncController extends Notifier<SyncState> {
  Timer? _timer;
  bool _running = false, _again = false;
  static const _quiet = Duration(seconds: 3);
  static const _retry = Duration(minutes: 1);

  bool get _enabled =>
      ref.read(accountRequiredProvider) && !ref.read(demoProvider);

  @override
  SyncState build() {
    final hook = ref.read(libraryChangeHookProvider);
    hook.listener = _changed;
    ref.onDispose(() {
      _timer?.cancel();
      hook.listener = null;
    });
    return const SyncState(SyncPhase.off);
  }

  void _changed() {
    if (!_enabled) return;
    unawaited(ref.read(syncEngineProvider).markDirty());
    _later(_quiet);
  }

  void _later(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(sync()));
  }

  /// A new session: remember whose library this is, then save.
  Future<void> signedIn(String accountId) async {
    if (!_enabled) return;
    await ref.read(syncEngineProvider).adopt(accountId);
    await sync();
  }

  /// The account is gone: the library on the phone is new to the next one.
  Future<void> accountDeleted() async {
    _timer?.cancel();
    await ref.read(syncEngineProvider).forget();
    state = const SyncState(SyncPhase.off);
  }

  /// Makes the account and the phone agree, when they can without a choice.
  Future<void> sync() async {
    if (!_enabled) return;
    if (state.phase == SyncPhase.conflict) return; // Waiting for the reader.
    if (_running) {
      _again = true;
      return;
    }
    if (!await ref.read(friendsApiProvider).signedIn()) {
      state = const SyncState(SyncPhase.off);
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        state = SyncState(SyncPhase.syncing, lastSaved: state.lastSaved);
        await _apply(await ref.read(syncEngineProvider).sync());
      } while (_again && state.phase != SyncPhase.conflict);
    } finally {
      _running = false;
    }
  }

  /// The reader's choice after a conflict.
  Future<void> resolve({required bool keepPhone}) async {
    if (_running) return;
    _running = true;
    try {
      state = SyncState(SyncPhase.syncing, lastSaved: state.lastSaved);
      await _apply(
        await ref.read(syncEngineProvider).resolve(keepPhone: keepPhone),
      );
    } finally {
      _running = false;
    }
  }

  Future<void> _apply(SyncResult result) async {
    switch (result.outcome) {
      case SyncOutcome.upToDate:
      case SyncOutcome.uploaded:
      case SyncOutcome.downloaded:
        if (result.outcome == SyncOutcome.downloaded) {
          ref.invalidate(libraryProvider);
        }
        state = SyncState(SyncPhase.saved, lastSaved: DateTime.now());
        // Covers found online are fetched again, and may have been missed.
        final covers = await ref.read(syncEngineProvider).fetchMissingCovers();
        if (covers > 0) ref.invalidate(libraryProvider);
      case SyncOutcome.conflict:
        state = SyncState(
          SyncPhase.conflict,
          lastSaved: state.lastSaved,
          conflict: result.conflict,
        );
      case SyncOutcome.offline:
        state = SyncState(
          SyncPhase.waiting,
          lastSaved: state.lastSaved,
          message: result.message,
        );
        _later(_retry);
      case SyncOutcome.signedOut:
        state = const SyncState(SyncPhase.off);
        resetAccountData(ref.invalidate);
      case SyncOutcome.failed:
        state = SyncState(
          SyncPhase.problem,
          lastSaved: state.lastSaved,
          message: result.message,
        );
    }
  }
}
