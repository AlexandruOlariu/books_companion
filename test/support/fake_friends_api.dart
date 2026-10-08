import 'package:reading_library/features/friends/data/contacts_source.dart';
import 'package:reading_library/features/friends/domain/friends_models.dart';

/// An in-memory friends server for widget tests. Records what the app sent.
class FakeFriendsApi implements FriendsApi {
  Account? account;
  String password = 'a long password';
  List<Person> friendList = [];
  FriendRequests requestList = const FriendRequests();
  List<Person> blockedList = [];
  final shelves = <String, SharedShelf>{};
  SharedShelf? mine;
  Person? lookupResult;
  List<Person> contactMatches = [];

  // What the app sent.
  final registered = <Map<String, String>>[];
  List<SharedBook>? published;
  List<String>? matchedNumbers;
  String? matchedRegion;
  final accepted = <String>[], sent = <String>[], removed = <String>[];
  final blockedIds = <String>[];
  String? deletedWith;
  bool unpublished = false;

  static const ana = Account(
    id: 'me',
    email: 'ana@example.com',
    username: 'ana',
    firstName: 'Ana',
    lastName: 'Pop',
    hasPhone: false,
    discoverableByPhone: false,
  );

  /// What the app sent for a profile change or a password change.
  final profileChanges = <Map<String, String?>>[];
  final passwordChanges = <({String current, String next})>[];
  final takenUsernames = <String>{'taken'};

  @override
  Future<Account> updateProfile({
    String? firstName,
    String? lastName,
    String? username,
  }) async {
    if (username != null && takenUsernames.contains(username)) {
      throw const FriendsException('That username is already taken.');
    }
    profileChanges.add({
      'first': firstName,
      'last': lastName,
      'username': username,
    });
    final a = account!;
    return account = Account(
      id: a.id,
      email: a.email,
      username: username ?? a.username,
      firstName: firstName ?? a.firstName,
      lastName: lastName ?? a.lastName,
      hasPhone: a.hasPhone,
      discoverableByPhone: a.discoverableByPhone,
    );
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (currentPassword != password) {
      throw const FriendsException('Wrong password.');
    }
    passwordChanges.add((current: currentPassword, next: newPassword));
    password = newPassword;
  }

  @override
  Future<bool> signedIn() async => account != null;

  @override
  Future<Account?> me() async => account;

  @override
  Future<Account> register({
    required String email,
    required String password,
    required String username,
    required String firstName,
    required String lastName,
  }) async {
    registered.add({
      'email': email,
      'username': username,
      'first': firstName,
      'last': lastName,
    });
    return account = Account(
      id: 'me',
      email: email,
      username: username,
      firstName: firstName,
      lastName: lastName,
      hasPhone: false,
      discoverableByPhone: false,
    );
  }

  @override
  Future<Account> signIn({
    required String email,
    required String password,
  }) async {
    if (password != this.password) {
      throw const FriendsException('Wrong email or password.');
    }
    return account = ana;
  }

  @override
  Future<void> signOut() async => account = null;

  @override
  Future<void> deleteAccount({required String password}) async {
    if (password != this.password) {
      throw const FriendsException('Wrong password.');
    }
    deletedWith = password;
    account = null;
  }

  Account _with({bool? hasPhone, bool? discoverable}) {
    final a = account!;
    return account = Account(
      id: a.id,
      email: a.email,
      username: a.username,
      firstName: a.firstName,
      lastName: a.lastName,
      hasPhone: hasPhone ?? a.hasPhone,
      discoverableByPhone: discoverable ?? a.discoverableByPhone,
    );
  }

  @override
  Future<Account> setPhone(String phone, {String? region}) async =>
      _with(hasPhone: true);
  @override
  Future<Account> removePhone() async =>
      _with(hasPhone: false, discoverable: false);
  @override
  Future<Account> setDiscoverable(bool value) async =>
      _with(discoverable: value);

  @override
  Future<List<Person>> friends() async => friendList;
  @override
  Future<FriendRequests> requests() async => requestList;
  @override
  Future<Person> sendRequest(String userId) async {
    sent.add(userId);
    return contactMatches
        .followedBy([?lookupResult])
        .firstWhere((p) => p.id == userId);
  }

  @override
  Future<Person> acceptRequest(String userId) async {
    accepted.add(userId);
    final person = requestList.incoming.firstWhere((p) => p.id == userId);
    friendList = [...friendList, person];
    requestList = FriendRequests(
      incoming: requestList.incoming.where((p) => p.id != userId).toList(),
      outgoing: requestList.outgoing,
    );
    return person;
  }

  @override
  Future<void> declineOrCancelRequest(String userId) async {
    requestList = FriendRequests(
      incoming: requestList.incoming.where((p) => p.id != userId).toList(),
      outgoing: requestList.outgoing.where((p) => p.id != userId).toList(),
    );
  }

  @override
  Future<void> removeFriend(String userId) async {
    removed.add(userId);
    friendList = friendList.where((p) => p.id != userId).toList();
  }

  @override
  Future<Person?> lookup(String username) async =>
      lookupResult?.username == username.trim() ? lookupResult : null;

  @override
  Future<List<Person>> matchContacts(
    List<String> numbers, {
    String? region,
  }) async {
    matchedNumbers = numbers;
    matchedRegion = region;
    return contactMatches;
  }

  @override
  Future<List<Person>> blocked() async => blockedList;
  @override
  Future<void> block(String userId) async {
    blockedIds.add(userId);
    friendList = friendList.where((p) => p.id != userId).toList();
  }

  @override
  Future<void> unblock(String userId) async =>
      blockedList = blockedList.where((p) => p.id != userId).toList();

  @override
  Future<SharedShelf> publishShelf(List<SharedBook> books) async {
    published = books;
    return mine = SharedShelf(
      books: books,
      updatedAt: DateTime(2026, 10, 7, 12),
    );
  }

  @override
  Future<SharedShelf?> myShelf() async => mine;
  @override
  Future<void> unpublishShelf() async {
    unpublished = true;
    mine = null;
  }

  @override
  Future<SharedShelf?> friendShelf(String userId) async => shelves[userId];
}

class FakeContactsSource implements ContactsSource {
  ContactNumbers result;
  int asked = 0;
  FakeContactsSource([this.result = const ContactNumbers(granted: true)]);
  @override
  Future<ContactNumbers> readNumbers() async {
    asked++;
    return result;
  }
}
