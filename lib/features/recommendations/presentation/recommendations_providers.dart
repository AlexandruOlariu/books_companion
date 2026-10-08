import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../friends/presentation/friends_providers.dart';
import '../../library/domain/models.dart';
import '../domain/recommendations.dart';

/// The preferences key holding the suggestions the reader said no to.
const dismissedRecommendationsPreference = 'dismissedRecommendations';
const _maxDismissed = 500;

/// Suggestions the reader dismissed, remembered on this phone only (a device
/// preference, like the sort order: not library data, so never saved to the
/// account or a backup).
final dismissedRecommendationsProvider =
    NotifierProvider<DismissedRecommendations, Set<String>>(
      DismissedRecommendations.new,
    );

class DismissedRecommendations extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    final raw = await ref
        .read(preferencesProvider)
        .read(dismissedRecommendationsPreference);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        // A dismissal made while this was loading is kept.
        state = {...decoded.whereType<String>(), ...state};
      }
    } on FormatException {
      /* A damaged value is ignored; nothing is dismissed. */
    }
  }

  Future<void> dismiss(String key) => _set({...state, key});
  Future<void> restore(String key) => _set({...state}..remove(key));

  Future<void> _set(Set<String> keys) {
    // Oldest first, so the cap forgets the oldest.
    final kept = keys.length <= _maxDismissed
        ? keys
        : keys.skip(keys.length - _maxDismissed).toSet();
    state = kept;
    return ref
        .read(preferencesProvider)
        .write(dismissedRecommendationsPreference, jsonEncode(kept.toList()));
  }
}

/// How many friends' shelves are read for suggestions.
const maxFriendShelves = 30;

/// The books friends finished, from their published shelves. Quiet by design:
/// nobody signed in (or the demo), no network, or a failed call all give an
/// empty list, because suggestions from the reader's own library still work.
/// Reads only what Friends already shows; nothing about the reader is sent.
final friendShelvesForSuggestionsProvider = FutureProvider<List<FriendShelf>>((
  ref,
) async {
  if (ref.watch(demoProvider)) return const [];
  if (!await ref.watch(signedInProvider.future)) return const [];
  try {
    // `read` after the first await: the sign-in above is what invalidates
    // this provider, and each of these is its own cached provider.
    final friends = (await ref.read(friendsProvider.future))
        .take(maxFriendShelves)
        .toList();
    final shelves = await Future.wait([
      for (final friend in friends)
        ref
            .read(friendShelfProvider(friend.id).future)
            .then<FriendShelf?>(
              (shelf) => shelf == null
                  ? null
                  : FriendShelf(
                      name: friend.displayName,
                      books: [
                        for (final book in shelf.books)
                          if (book.status == BookStatus.finished)
                            SharedTitle(book.title, book.author),
                      ],
                    ),
            )
            .catchError((Object _) => null),
    ]);
    return [for (final shelf in shelves) ?shelf];
  } on Object {
    return const [];
  }
});
