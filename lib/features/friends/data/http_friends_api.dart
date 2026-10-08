import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../core/storage/session_store.dart';
import '../../library/domain/models.dart';
import '../../sync/domain/sync_models.dart';
import '../domain/friends_models.dart';

/// Talks to the optional friends server (see docs/backend.md) with `dart:io`,
/// like the Open Library lookup. Nothing here runs unless the reader opens
/// Friends and acts; the library itself is never sent, only what the reader
/// publishes.
class HttpFriendsApi implements FriendsApi, LibrarySyncApi {
  final SessionStore _session;
  final Uri _origin;
  final HttpClient Function() _client;
  HttpFriendsApi({
    required this._session,
    Uri? origin,
    HttpClient Function()? client,
  }) : _origin = origin ?? Uri.parse(defaultOrigin),
       _client = client ?? HttpClient.new;

  static const defaultOrigin = 'https://ai.duk-tech.com/books-api';
  static const _agent = 'ReadingLibrary/0.1';
  static const _unavailable =
      'Could not reach the Reading Library server. Check your connection and try again.';
  static const _signedOut = 'Please sign in again.';
  static const _responseLimit = 8 * 1024 * 1024;
  // A saved library (notes and sessions, no covers) may be larger than that.
  static const _libraryLimit = 24 * 1024 * 1024;

  // --- transport -----------------------------------------------------------

  Future<(int, dynamic)> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    String? token,
    int limit = _responseLimit,
  }) async {
    final uri = _origin.replace(
      path: '${_origin.path}$path',
      queryParameters: query,
    );
    final client = _client()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.openUrl(method, uri);
      request.headers
        ..set(HttpHeaders.userAgentHeader, _agent)
        ..set(HttpHeaders.acceptHeader, 'application/json');
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(body)));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        bytes.add(chunk);
        if (bytes.length > limit) throw const HttpException('Too big');
      }
      final text = utf8.decode(bytes.takeBytes());
      return (response.statusCode, text.isEmpty ? null : jsonDecode(text));
    } on Object {
      // Network, timeout, TLS, and parse failures all mean "unreachable" to
      // the reader. Never a reason to sign them out.
      throw const FriendsException(_unavailable);
    } finally {
      client.close(force: true);
    }
  }

  Future<bool>? _refreshing;

  /// Swaps the refresh token for a new pair. False means the server refused it
  /// (the session is over); a network failure throws and keeps the session.
  Future<bool> _refresh() =>
      _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<bool> _doRefresh() async {
    final session = await _session.read();
    if (session == null) return false;
    final (status, json) = await _send(
      'POST',
      '/auth/refresh',
      body: {'refresh_token': session.refreshToken},
    );
    if (status != 200 || json is! Map) return false;
    await _session.write(_tokens(json));
    return true;
  }

  Session _tokens(Map json) => Session(
    accessToken: json['access_token'] as String,
    refreshToken: json['refresh_token'] as String,
  );

  /// A call that needs sign-in. Retries once after refreshing an expired token.
  Future<dynamic> _call(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    Set<int> allow = const {},
    int limit = _responseLimit,
  }) async {
    final session = await _session.read();
    if (session == null) {
      throw const FriendsException(_signedOut, signedOut: true);
    }
    var (status, json) = await _send(
      method,
      path,
      body: body,
      query: query,
      token: session.accessToken,
      limit: limit,
    );
    if (status == 401) {
      if (!await _refresh()) {
        await _session.clear();
        throw const FriendsException(_signedOut, signedOut: true);
      }
      final fresh = await _session.read();
      (status, json) = await _send(
        method,
        path,
        body: body,
        query: query,
        token: fresh?.accessToken,
        limit: limit,
      );
      if (status == 401) {
        await _session.clear();
        throw const FriendsException(_signedOut, signedOut: true);
      }
    }
    if (status >= 400 && !allow.contains(status)) throw _failure(status, json);
    return status >= 400 ? null : json;
  }

  FriendsException _failure(int status, dynamic json) {
    final detail = json is Map ? json['detail'] : null;
    if (detail is String && detail.isNotEmpty) return FriendsException(detail);
    if (status == 429) {
      return const FriendsException(
        'Too many attempts. Please wait a while and try again.',
      );
    }
    if (status == 422 && detail is List && detail.isNotEmpty) {
      final first = detail.first;
      if (first is Map) {
        final loc = first['loc'];
        final field = loc is List && loc.isNotEmpty ? '${loc.last}' : '';
        final msg = '${first['msg'] ?? ''}'.replaceFirst('Value error, ', '');
        final label = switch (field) {
          'email' => 'Email',
          'password' || 'new_password' => 'Password',
          'username' => 'Username',
          'first_name' => 'First name',
          'last_name' => 'Last name',
          'phone' => 'Phone number',
          _ => '',
        };
        if (msg.isNotEmpty) {
          return FriendsException(label.isEmpty ? msg : '$label: $msg');
        }
      }
      return const FriendsException('Please check what you entered.');
    }
    return const FriendsException(_unavailable);
  }

  // --- mapping -------------------------------------------------------------

  Person _person(dynamic j) => Person(
    id: j['id'] as String,
    username: j['username'] as String,
    displayName: j['display_name'] as String,
  );

  List<Person> _people(dynamic j) => [for (final p in j as List) _person(p)];

  Account _account(dynamic j) => Account(
    id: j['id'] as String,
    email: j['email'] as String,
    username: j['username'] as String,
    firstName: j['first_name'] as String,
    lastName: j['last_name'] as String,
    hasPhone: j['has_phone'] as bool,
    discoverableByPhone: j['discoverable_by_phone'] as bool,
  );

  static const _statusNames = {
    BookStatus.reading: 'reading',
    BookStatus.wantToRead: 'want_to_read',
    BookStatus.finished: 'finished',
  };

  Map<String, Object?> _finishJson(PartialDate d) => {
    'precision': d.precision.name,
    'year': d.year,
    'month': d.month,
    'day': d.precision == DatePrecision.day
        ? int.parse(d.value!.substring(8, 10))
        : null,
  };

  PartialDate _finish(dynamic j) {
    final precision = DatePrecision.values.byName(j['precision'] as String);
    String two(Object? n) => '$n'.padLeft(2, '0');
    final year = '${j['year']}'.padLeft(4, '0');
    return switch (precision) {
      DatePrecision.unknown => const PartialDate.unknown(),
      DatePrecision.year => PartialDate(precision, year),
      DatePrecision.month => PartialDate(precision, '$year-${two(j['month'])}'),
      DatePrecision.day => PartialDate(
        precision,
        '$year-${two(j['month'])}-${two(j['day'])}',
      ),
    };
  }

  SharedShelf _shelf(dynamic j) => SharedShelf(
    updatedAt: DateTime.parse(j['updated_at'] as String),
    books: [
      for (final b in j['books'] as List)
        SharedBook(
          id: b['id'] as String,
          title: b['title'] as String,
          author: b['author'] as String,
          status: _statusNames.entries
              .firstWhere((e) => e.value == b['status'])
              .key,
          finishes: [for (final f in b['finishes'] as List) _finish(f)],
        ),
    ],
  );

  // --- account -------------------------------------------------------------

  @override
  Future<bool> signedIn() async => await _session.read() != null;

  @override
  Future<Account?> me() async {
    if (await _session.read() == null) return null;
    try {
      return _account(await _call('GET', '/me'));
    } on FriendsException catch (e) {
      if (e.signedOut) return null;
      rethrow;
    }
  }

  Future<Account> _signedInWith(int status, dynamic json) async {
    if (status != 200 && status != 201) throw _failure(status, json);
    await _session.write(_tokens(json as Map));
    return _account(await _call('GET', '/me'));
  }

  @override
  Future<Account> register({
    required String email,
    required String password,
    required String username,
    required String firstName,
    required String lastName,
  }) async {
    final (status, json) = await _send(
      'POST',
      '/auth/register',
      body: {
        'email': email.trim(),
        'password': password,
        'username': username.trim(),
        'first_name': firstName.trim(),
        'last_name': lastName.trim(),
      },
    );
    return _signedInWith(status, json);
  }

  @override
  Future<Account> signIn({
    required String email,
    required String password,
  }) async {
    final (status, json) = await _send(
      'POST',
      '/auth/login',
      body: {'email': email.trim(), 'password': password},
    );
    return _signedInWith(status, json);
  }

  @override
  Future<void> signOut() async {
    final session = await _session.read();
    await _session.clear();
    if (session == null) return;
    try {
      await _send(
        'POST',
        '/auth/logout',
        body: {'refresh_token': session.refreshToken},
      );
    } on FriendsException {
      /* Signed out here either way; the token expires on its own. */
    }
  }

  @override
  Future<void> deleteAccount({required String password}) async {
    await _call('DELETE', '/me', body: {'password': password});
    await _session.clear();
  }

  @override
  Future<Account> updateProfile({
    String? firstName,
    String? lastName,
    String? username,
  }) async => _account(
    await _call(
      'PATCH',
      '/me',
      body: {
        'first_name': ?firstName?.trim(),
        'last_name': ?lastName?.trim(),
        'username': ?username?.trim(),
      },
    ),
  );

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final json = await _call(
      'POST',
      '/me/password',
      body: {'current_password': currentPassword, 'new_password': newPassword},
    );
    // The server ended every session; these are this device's new ones.
    await _session.write(_tokens(json as Map));
  }

  @override
  Future<Account> setPhone(String phone, {String? region}) async => _account(
    await _call('PUT', '/me/phone', body: {'phone': phone, 'region': ?region}),
  );

  @override
  Future<Account> removePhone() async =>
      _account(await _call('DELETE', '/me/phone'));

  @override
  Future<Account> setDiscoverable(bool value) async => _account(
    await _call('PATCH', '/me', body: {'discoverable_by_phone': value}),
  );

  // --- people --------------------------------------------------------------

  @override
  Future<List<Person>> friends() async =>
      _people(await _call('GET', '/friends'));

  @override
  Future<FriendRequests> requests() async {
    final json = await _call('GET', '/friends/requests');
    return FriendRequests(
      incoming: _people(json['incoming']),
      outgoing: _people(json['outgoing']),
    );
  }

  @override
  Future<Person> sendRequest(String userId) async => _person(
    await _call('POST', '/friends/requests', body: {'user_id': userId}),
  );

  @override
  Future<Person> acceptRequest(String userId) async =>
      _person(await _call('POST', '/friends/requests/$userId/accept'));

  @override
  Future<void> declineOrCancelRequest(String userId) =>
      _call('DELETE', '/friends/requests/$userId');

  @override
  Future<void> removeFriend(String userId) =>
      _call('DELETE', '/friends/$userId');

  @override
  Future<Person?> lookup(String username) async {
    final json = await _call(
      'GET',
      '/users/lookup',
      query: {'username': username.trim()},
      allow: {404},
    );
    return json == null ? null : _person(json);
  }

  @override
  Future<List<Person>> matchContacts(
    List<String> numbers, {
    String? region,
  }) async {
    final found = <String, Person>{};
    for (var i = 0; i < numbers.length; i += 1000) {
      final chunk = numbers.skip(i).take(1000).toList();
      final json = await _call(
        'POST',
        '/contacts/match',
        body: {'numbers': chunk, 'region': ?region},
      );
      for (final person in _people(json)) {
        found[person.id] = person;
      }
    }
    return found.values.toList();
  }

  @override
  Future<List<Person>> blocked() async =>
      _people(await _call('GET', '/blocks'));

  @override
  Future<void> block(String userId) => _call('PUT', '/blocks/$userId');

  @override
  Future<void> unblock(String userId) => _call('DELETE', '/blocks/$userId');

  // --- shelf ---------------------------------------------------------------

  @override
  Future<SharedShelf> publishShelf(List<SharedBook> books) async {
    if (books.length > maxSharedBooks) {
      throw const FriendsException(
        'Your library is too large to share (the limit is 5000 books).',
      );
    }
    return _shelf(
      await _call(
        'PUT',
        '/me/shelf',
        body: {
          'books': [
            for (final b in books)
              {
                'id': b.id,
                'title': b.title,
                'author': b.author,
                'status': _statusNames[b.status],
                'finishes': [for (final f in b.finishes) _finishJson(f)],
              },
          ],
        },
      ),
    );
  }

  @override
  Future<SharedShelf?> myShelf() async {
    final json = await _call('GET', '/me/shelf', allow: {404});
    return json == null ? null : _shelf(json);
  }

  @override
  Future<void> unpublishShelf() => _call('DELETE', '/me/shelf');

  @override
  Future<SharedShelf?> friendShelf(String userId) async {
    final json = await _call('GET', '/friends/$userId/shelf', allow: {404});
    return json == null ? null : _shelf(json);
  }

  // --- library -------------------------------------------------------------

  @override
  Future<String?> accountId() async {
    try {
      final json = await _call('GET', '/me');
      return (json as Map)['id'] as String;
    } on FriendsException catch (e) {
      if (e.signedOut) return null;
      rethrow;
    }
  }

  LibraryRevision _revision(dynamic j) => LibraryRevision(
    j['revision'] as int,
    DateTime.parse(j['updated_at'] as String),
  );

  @override
  Future<LibraryRevision?> libraryRevision() async {
    final json = await _call('GET', '/me/library/meta', allow: {404});
    return json == null ? null : _revision(json);
  }

  @override
  Future<RemoteLibrary?> fetchLibrary() async {
    final json = await _call(
      'GET',
      '/me/library',
      allow: {404},
      limit: _libraryLimit,
    );
    if (json == null) return null;
    final revision = _revision(json);
    return RemoteLibrary(
      revision.revision,
      revision.updatedAt,
      Map<String, dynamic>.from(json['data'] as Map),
    );
  }

  @override
  Future<LibraryRevision> saveLibrary(
    Map<String, dynamic> data, {
    required int baseRevision,
  }) async {
    final json = await _call(
      'PUT',
      '/me/library',
      body: {'base_revision': baseRevision, 'data': data},
      allow: {409},
    );
    if (json == null) throw const LibraryConflictException();
    return _revision(json);
  }
}
