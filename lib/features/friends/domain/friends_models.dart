import '../../library/domain/models.dart';

/// Another reader, as the server shows them: never an email or a phone number.
class Person {
  final String id, username, displayName;
  const Person({
    required this.id,
    required this.username,
    required this.displayName,
  });
}

class Account {
  final String id, email, username, firstName, lastName;
  final bool hasPhone, discoverableByPhone;
  const Account({
    required this.id,
    required this.email,
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.hasPhone,
    required this.discoverableByPhone,
  });
  String get displayName => '$firstName $lastName';
}

class FriendRequests {
  final List<Person> incoming, outgoing;
  const FriendRequests({this.incoming = const [], this.outgoing = const []});
}

/// A book as it is published for friends: what was read and when, nothing
/// private. There is deliberately no field for notes, pins, sessions, or covers.
class SharedBook {
  final String id, title, author;
  final BookStatus status;
  final List<PartialDate> finishes;
  const SharedBook({
    required this.id,
    required this.title,
    required this.author,
    required this.status,
    this.finishes = const [],
  });
}

class SharedShelf {
  final List<SharedBook> books;
  final DateTime updatedAt;
  const SharedShelf({required this.books, required this.updatedAt});
}

/// A failure the reader can act on. The message is always safe to show.
class FriendsException implements Exception {
  final String message;

  /// The session is gone (expired or revoked); the reader must sign in again.
  final bool signedOut;
  const FriendsException(this.message, {this.signedOut = false});
  @override
  String toString() => message;
}

/// The server's limits (see docs/backend.md).
const maxSharedBooks = 5000;
const maxContactNumbersPerCheck = 3000;

abstract class FriendsApi {
  /// Null when nobody is signed in on this device.
  Future<Account?> me();
  Future<Account> register({
    required String email,
    required String password,
    required String username,
    required String firstName,
    required String lastName,
  });
  Future<Account> signIn({required String email, required String password});
  Future<void> signOut();
  Future<void> deleteAccount({required String password});

  Future<Account> setPhone(String phone, {String? region});
  Future<Account> removePhone();
  Future<Account> setDiscoverable(bool value);

  Future<List<Person>> friends();
  Future<FriendRequests> requests();
  Future<Person> sendRequest(String userId);
  Future<Person> acceptRequest(String userId);
  Future<void> declineOrCancelRequest(String userId);
  Future<void> removeFriend(String userId);
  Future<Person?> lookup(String username);
  Future<List<Person>> matchContacts(List<String> numbers, {String? region});

  Future<List<Person>> blocked();
  Future<void> block(String userId);
  Future<void> unblock(String userId);

  Future<SharedShelf> publishShelf(List<SharedBook> books);
  Future<SharedShelf?> myShelf();
  Future<void> unpublishShelf();

  /// A friend's published shelf; null if they have not published one.
  Future<SharedShelf?> friendShelf(String userId);
}

/// What would be published for [library]: the books and their finish dates,
/// and nothing else. Finish dates keep their precision, so a remembered year
/// stays a year. A finished book that somehow has no recorded finish is sent
/// with an unknown date rather than an invented one.
List<SharedBook> sharedBooksFrom(LibrarySnapshot library) {
  final finishesByBook = <String, List<PartialDate>>{};
  for (final completion in library.completions) {
    finishesByBook
        .putIfAbsent(completion.userBookId, () => [])
        .add(completion.finish);
  }
  String clip(String s) => s.length <= 300 ? s : s.substring(0, 300);
  return [
    for (final book in library.books)
      SharedBook(
        id: book.id,
        title: clip(book.title),
        author: clip(book.author),
        status: book.status,
        finishes: switch (book.status) {
          BookStatus.wantToRead => const [],
          BookStatus.finished =>
            (finishesByBook[book.id] ?? const []).isEmpty
                ? const [PartialDate.unknown()]
                : finishesByBook[book.id]!.take(50).toList(),
          BookStatus.reading =>
            (finishesByBook[book.id] ?? const []).take(50).toList(),
        },
      ),
  ];
}
