import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_library/app/providers.dart';
import 'package:reading_library/core/storage/preferences_store.dart';
import 'package:reading_library/features/friends/presentation/friends_providers.dart';
import 'package:reading_library/features/push/presentation/push_controller.dart';

import 'support/fake_friends_api.dart';
import 'support/fake_push.dart';

void main() {
  late FakePushService service;
  late FakePushApi api;
  late MemoryPreferencesStore prefs;
  late ProviderContainer container;

  PushController controller() =>
      container.read(pushControllerProvider.notifier);
  PushState state() => container.read(pushControllerProvider);

  setUp(() {
    service = FakePushService();
    api = FakePushApi();
    prefs = MemoryPreferencesStore();
    container = ProviderContainer(
      overrides: [
        pushServiceProvider.overrideWithValue(service),
        pushApiProvider.overrideWithValue(api),
        preferencesProvider.overrideWithValue(prefs),
        friendsApiProvider.overrideWithValue(FakeFriendsApi()),
      ],
    );
    addTearDown(container.dispose);
  });

  test('nothing is on until the reader decides', () async {
    await controller().refresh();
    expect(state().choice, PushChoice.unset);
    expect(state().enabled, isFalse);
    expect(service.asked, 0);
    expect(api.tokens, isEmpty);
  });

  test('turning on asks permission once and registers the token', () async {
    expect(await controller().enable(), PushResult.enabled);
    expect(service.asked, 1);
    expect(api.tokens, {'token-1'});
    expect(state().enabled, isTrue);
    expect(await prefs.read('push'), 'on');
  });

  test(
    'a refusal leaves nothing registered and is remembered as off',
    () async {
      service.allow = false;
      expect(await controller().enable(), PushResult.denied);
      expect(api.tokens, isEmpty);
      expect(state().choice, PushChoice.off);
      expect(await prefs.read('push'), 'off');
    },
  );

  test('an unreachable server leaves notifications off', () async {
    api.offline = true;
    expect(await controller().enable(), PushResult.offline);
    expect(state().enabled, isFalse);
    expect(await prefs.read('push'), isNull);
  });

  test('a build without push reports it and asks for nothing', () async {
    service.isAvailable = false;
    expect(await controller().enable(), PushResult.unavailable);
    expect(service.asked, 0);
    expect(state().enabled, isFalse);
  });

  test(
    'turning off removes the phone from the server and from Firebase',
    () async {
      await controller().enable();
      await controller().disable();
      expect(api.tokens, isEmpty);
      expect(service.forgotten, isTrue);
      expect(state().choice, PushChoice.off);
      expect(await prefs.read('push'), 'off');
    },
  );

  test('turning off works even when the server cannot be reached', () async {
    await controller().enable();
    api.offline = true;
    await controller().disable();
    expect(service.forgotten, isTrue);
    expect(state().enabled, isFalse);
  });

  test(
    'on start the server is told this phone again; off sends nothing',
    () async {
      await controller().enable();
      api.tokens.clear(); // e.g. the server lost it, or another account took it
      await controller().refresh();
      expect(api.tokens, {'token-1'});

      await controller().disable();
      api.registerCalls.clear();
      await controller().refresh();
      expect(api.registerCalls, isEmpty);
    },
  );

  test(
    'a rotated token replaces the old one while notifications are on',
    () async {
      await controller().enable();
      service.refreshes.add('token-2');
      await Future<void>.delayed(Duration.zero);
      expect(api.tokens, contains('token-2'));
    },
  );

  test('a rotated token is ignored while notifications are off', () async {
    await controller().refresh();
    service.refreshes.add('token-2');
    await Future<void>.delayed(Duration.zero);
    expect(api.tokens, isEmpty);
  });

  test(
    'signing out forgets the phone and lets the next account be asked',
    () async {
      await controller().enable();
      await controller().signingOut();
      expect(api.tokens, isEmpty);
      expect(service.forgotten, isTrue);
      expect(state().choice, PushChoice.unset);
      expect(await prefs.read('push'), '');
      await controller().refresh();
      expect(state().choice, PushChoice.unset);
    },
  );

  test('a notification while the app is open refreshes the requests', () async {
    final friends = FakeFriendsApi();
    var loads = 0;
    final c = ProviderContainer(
      overrides: [
        pushServiceProvider.overrideWithValue(service),
        pushApiProvider.overrideWithValue(api),
        preferencesProvider.overrideWithValue(prefs),
        friendsApiProvider.overrideWithValue(friends),
        friendRequestsProvider.overrideWith((ref) {
          loads++;
          return friends.requests();
        }),
      ],
    );
    addTearDown(c.dispose);
    c.read(pushControllerProvider);
    await c.read(friendRequestsProvider.future);
    expect(loads, 1);
    service.arrivals.add(null);
    await Future<void>.delayed(Duration.zero);
    await c.read(friendRequestsProvider.future);
    expect(loads, 2);
  });
}
