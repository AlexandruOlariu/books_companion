import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The sign-in tokens for the optional friends server.
class Session {
  final String accessToken, refreshToken;
  const Session({required this.accessToken, required this.refreshToken});
}

/// Where the session lives. Tokens are credentials, so the real store uses the
/// platform's secure storage (Keychain on iOS, an encrypted store on Android)
/// and not the plain preferences file. Never part of a backup.
abstract class SessionStore {
  Future<Session?> read();
  Future<void> write(Session session);
  Future<void> clear();
}

class MemorySessionStore implements SessionStore {
  Session? _session;
  @override
  Future<Session?> read() async => _session;
  @override
  Future<void> write(Session session) async => _session = session;
  @override
  Future<void> clear() async => _session = null;
}

class SecureSessionStore implements SessionStore {
  final FlutterSecureStorage _storage;
  SecureSessionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();
  static const _access = 'friends.accessToken';
  static const _refresh = 'friends.refreshToken';

  @override
  Future<Session?> read() async {
    try {
      final access = await _storage.read(key: _access);
      final refresh = await _storage.read(key: _refresh);
      return access == null || refresh == null
          ? null
          : Session(accessToken: access, refreshToken: refresh);
    } on Object {
      return null; // Unreadable storage means signed out, never a crash.
    }
  }

  @override
  Future<void> write(Session session) async {
    await _storage.write(key: _access, value: session.accessToken);
    await _storage.write(key: _refresh, value: session.refreshToken);
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _access);
      await _storage.delete(key: _refresh);
    } on Object {
      /* Nothing to clear if the storage cannot be reached. */
    }
  }
}
