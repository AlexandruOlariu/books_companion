import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../friends/domain/friends_models.dart';
import '../../friends/presentation/friends_providers.dart';
import '../domain/push_models.dart';

final pushServiceProvider = Provider<PushService>(
  (ref) => const NoPushService(),
);
final pushApiProvider = Provider<PushApi>(
  (ref) => ref.watch(serverApiProvider),
);

/// What the reader chose about notifications on this phone.
enum PushChoice {
  /// Not decided yet (a new sign-in): the app offers once.
  unset,
  on,
  off,
}

enum PushResult { enabled, denied, unavailable, offline }

class PushState {
  final bool available;
  final PushChoice choice;
  const PushState({required this.available, required this.choice});
  bool get enabled => available && choice == PushChoice.on;
}

/// Turns friend notifications on and off for this phone and keeps the server
/// pointed at the phone's current token. Everything here is best effort: a
/// failure never blocks the reader, and a notification only ever says that
/// something happened (the server sends no names), so the app looks it up.
class PushController extends Notifier<PushState> {
  static const preferenceKey = 'push';

  PushService get _service => ref.read(pushServiceProvider);
  PushApi get _api => ref.read(pushApiProvider);

  @override
  PushState build() {
    final service = ref.read(pushServiceProvider);
    final subscriptions = [
      service.tokenRefreshed.listen((token) => unawaited(_register(token))),
      service.received.listen((_) => _refreshFriends()),
    ];
    ref.onDispose(() {
      for (final s in subscriptions) {
        unawaited(s.cancel());
      }
    });
    return PushState(available: service.available, choice: PushChoice.unset);
  }

  Future<PushChoice> _stored() async {
    final value = await ref.read(preferencesProvider).read(preferenceKey);
    return switch (value) {
      'on' => PushChoice.on,
      'off' => PushChoice.off,
      _ => PushChoice.unset,
    };
  }

  Future<void> _store(PushChoice choice) async {
    await ref.read(preferencesProvider).write(preferenceKey, switch (choice) {
      PushChoice.on => 'on',
      PushChoice.off => 'off',
      PushChoice.unset => '',
    });
    state = PushState(available: state.available, choice: choice);
  }

  void _refreshFriends() {
    ref.invalidate(friendRequestsProvider);
    ref.invalidate(friendsProvider);
  }

  Future<bool> _register(String token) async {
    if (state.choice != PushChoice.on) return false;
    try {
      await _api.registerDevice(token, platform: _service.platform);
      return true;
    } on Object {
      return false;
    }
  }

  /// Reads the stored choice and, if notifications are on, tells the server
  /// this phone's token again (tokens change, and a phone can change owner).
  Future<void> refresh() async {
    final choice = await _stored();
    state = PushState(available: _service.available, choice: choice);
    if (!state.enabled) return;
    final token = await _service.currentToken();
    if (token != null) await _register(token);
  }

  Future<PushResult> enable() async {
    if (!_service.available) return PushResult.unavailable;
    final token = await _service.enable();
    if (token == null) {
      await _store(PushChoice.off);
      return PushResult.denied;
    }
    try {
      await _api.registerDevice(token, platform: _service.platform);
    } on FriendsException {
      return PushResult.offline;
    }
    await _store(PushChoice.on);
    return PushResult.enabled;
  }

  /// The reader turns notifications off: the server and Firebase forget the
  /// phone. [choice] is `unset` when signing out, so the next account is asked.
  Future<void> disable({PushChoice choice = PushChoice.off}) async {
    final token = await _service.currentToken();
    if (token != null) {
      try {
        await _api.removeDevice(token);
      } on Object {
        /* The server also drops a token that stops working. */
      }
    }
    if (_service.available) await _service.forget();
    await _store(choice);
  }

  /// Before signing out or deleting the account, while the session still works.
  Future<void> signingOut() async {
    if (state.enabled || await _stored() == PushChoice.on) {
      await disable(choice: PushChoice.unset);
    } else {
      await _store(PushChoice.unset);
    }
  }
}

final pushControllerProvider = NotifierProvider<PushController, PushState>(
  PushController.new,
);
