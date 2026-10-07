import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import '../../../app/providers.dart';
import '../../../core/widgets/common.dart';
import '../domain/friends_models.dart';

/// The signed-in account, or null when nobody is signed in on this device.
final accountProvider = FutureProvider<Account?>(
  (ref) => ref.watch(friendsApiProvider).me(),
);
final friendsProvider = FutureProvider<List<Person>>(
  (ref) => ref.watch(friendsApiProvider).friends(),
);
final friendRequestsProvider = FutureProvider<FriendRequests>(
  (ref) => ref.watch(friendsApiProvider).requests(),
);
final blockedProvider = FutureProvider<List<Person>>(
  (ref) => ref.watch(friendsApiProvider).blocked(),
);

/// What this reader has published for friends (null: nothing published).
final mySharedShelfProvider = FutureProvider<SharedShelf?>(
  (ref) => ref.watch(friendsApiProvider).myShelf(),
);
final friendShelfProvider = FutureProvider.family<SharedShelf?, String>(
  (ref, userId) => ref.watch(friendsApiProvider).friendShelf(userId),
);

/// Forget everything loaded for the previous account, and look again at
/// whether anyone is signed in (the app asks for an account when no one is).
void resetFriendsData(WidgetRef ref) => resetAccountData(ref.invalidate);

void resetAccountData(void Function(ProviderOrFamily) invalidate) {
  for (final provider in <ProviderOrFamily>[
    accountProvider,
    friendsProvider,
    friendRequestsProvider,
    blockedProvider,
    mySharedShelfProvider,
    friendShelfProvider,
    signedInProvider,
  ]) {
    invalidate(provider);
  }
}

/// Runs a friends action and shows the problem, if any, instead of throwing.
/// Returns null on failure. A lost session sends the reader back to sign-in.
Future<T?> runFriends<T>(
  BuildContext context,
  WidgetRef ref,
  Future<T> Function() action,
) async {
  try {
    return await action();
  } on FriendsException catch (e) {
    if (e.signedOut) resetFriendsData(ref);
    if (context.mounted) notifyUser(context, e.message);
  } on Object {
    if (context.mounted) {
      notifyUser(context, 'Something went wrong. Please try again.');
    }
  }
  return null;
}
