import 'dart:async';

import 'package:reading_library/features/friends/domain/friends_models.dart';
import 'package:reading_library/features/push/domain/push_models.dart';

/// A phone with (or without) push, controlled by the test.
class FakePushService implements PushService {
  bool isAvailable = true;

  /// Whether the reader allows notifications when asked.
  bool allow = true;
  String token = 'token-1';
  bool _issued = false;
  int asked = 0;
  bool forgotten = false;
  final refreshes = StreamController<String>.broadcast();
  final arrivals = StreamController<void>.broadcast();
  final taps = StreamController<void>.broadcast();

  @override
  bool get available => isAvailable;
  @override
  String get platform => 'android';
  @override
  Future<String?> enable() async {
    asked++;
    if (!allow) return null;
    _issued = true;
    return token;
  }

  @override
  Future<String?> currentToken() async => _issued ? token : null;
  @override
  Future<void> forget() async {
    forgotten = true;
    _issued = false;
  }

  @override
  Stream<String> get tokenRefreshed => refreshes.stream;
  @override
  Stream<void> get received => arrivals.stream;
  @override
  Stream<void> get opened => taps.stream;
}

class FakePushApi implements PushApi {
  /// The tokens the server currently holds for this account.
  final tokens = <String>{};
  final registerCalls = <String>[];
  bool offline = false;

  @override
  Future<void> registerDevice(String token, {required String platform}) async {
    if (offline) throw const FriendsException('Could not reach the server.');
    registerCalls.add(token);
    tokens.add(token);
  }

  @override
  Future<void> removeDevice(String token) async {
    if (offline) throw const FriendsException('Could not reach the server.');
    tokens.remove(token);
  }
}
