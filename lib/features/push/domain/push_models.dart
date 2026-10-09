/// The part of the server that remembers which phones get push notifications.
abstract class PushApi {
  /// Remembers [token] for the signed-in account (moving it from any other
  /// account that used this phone). Throws `FriendsException`.
  Future<void> registerDevice(String token, {required String platform});

  /// Forgets [token]. Never an error for an unknown token.
  Future<void> removeDevice(String token);
}

/// The phone's side of push: permission, the device token, and what arrives.
/// Firebase is behind this interface so tests (and builds without Firebase)
/// run the rest of the app unchanged.
abstract class PushService {
  /// False when this build cannot receive push: no Firebase configuration, no
  /// Google Play services, or a platform that is not set up yet (iOS).
  bool get available;

  /// The platform name the server stores ('android' or 'ios').
  String get platform;

  /// Asks the reader's permission (Android 13+ shows a system dialog) and
  /// returns this phone's token, or null if refused or unavailable.
  Future<String?> enable();

  /// The token, without asking for anything; null if there is none.
  Future<String?> currentToken();

  /// Throws the token away, so this install can no longer be reached.
  Future<void> forget();

  /// A new token, issued when Firebase rotates it.
  Stream<String> get tokenRefreshed;

  /// A notification arrived while the app was open.
  Stream<void> get received;

  /// The reader tapped a notification (including the one that opened the app).
  Stream<void> get opened;
}

/// Used by tests and by builds that have no push: nothing is available.
class NoPushService implements PushService {
  const NoPushService();
  @override
  bool get available => false;
  @override
  String get platform => 'android';
  @override
  Future<String?> enable() async => null;
  @override
  Future<String?> currentToken() async => null;
  @override
  Future<void> forget() async {}
  @override
  Stream<String> get tokenRefreshed => const Stream.empty();
  @override
  Stream<void> get received => const Stream.empty();
  @override
  Stream<void> get opened => const Stream.empty();
}
