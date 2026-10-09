import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../domain/push_models.dart';

/// Push through Firebase Cloud Messaging. Only Android is set up: iOS needs an
/// Apple push key and `GoogleService-Info.plist`, and initialising Firebase
/// without them would crash the app, so iOS reports itself unavailable.
///
/// Firebase reads `android/app/google-services.json` at build time. Without
/// that file (see docs/release.md) initialisation fails and the service is
/// simply unavailable; the rest of the app does not notice.
class FirebasePushService implements PushService {
  FirebasePushService._(this._messaging);

  final FirebaseMessaging _messaging;

  /// Never throws and never waits long: startup must not depend on Google.
  static Future<PushService> create() async {
    if (!Platform.isAndroid) return const NoPushService();
    try {
      await Firebase.initializeApp().timeout(const Duration(seconds: 5));
      return FirebasePushService._(FirebaseMessaging.instance);
    } on Object {
      return const NoPushService();
    }
  }

  @override
  bool get available => true;

  @override
  String get platform => 'android';

  @override
  Future<String?> enable() async {
    try {
      final settings = await _messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return null;
      }
      return await _messaging.getToken();
    } on Object {
      return null;
    }
  }

  @override
  Future<String?> currentToken() async {
    try {
      return await _messaging.getToken();
    } on Object {
      return null;
    }
  }

  @override
  Future<void> forget() async {
    try {
      await _messaging.deleteToken();
    } on Object {
      /* Best effort: the server also forgets a token that stops working. */
    }
  }

  @override
  Stream<String> get tokenRefreshed => _messaging.onTokenRefresh;

  @override
  Stream<void> get received => FirebaseMessaging.onMessage.map((_) {});

  @override
  Stream<void> get opened async* {
    final first = await _messaging.getInitialMessage();
    if (first != null) yield null;
    yield* FirebaseMessaging.onMessageOpenedApp.map((_) {});
  }
}
