import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reading_library/core/storage/session_store.dart';
import 'package:reading_library/features/friends/data/http_friends_api.dart';
import 'package:reading_library/features/friends/domain/friends_models.dart';
import 'package:reading_library/features/library/domain/models.dart';
import 'package:reading_library/features/sync/domain/sync_models.dart';

class Seen {
  final String method, path;
  final Map<String, String> query;
  final String? auth;
  final dynamic body;
  Seen(this.method, this.path, this.query, this.auth, this.body);
}

typedef Reply = (int, Object?);

/// A local stand-in for the server: one handler decides each reply, and every
/// request is recorded so tests can check what the app actually sent.
class Harness {
  final seen = <Seen>[];
  late final HttpServer server;
  late final HttpFriendsApi api;
  final session = MemorySessionStore();
  Reply Function(Seen) handler = (_) => (500, null);

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final text = await utf8.decoder.bind(request).join();
      final path = request.uri.path.replaceFirst('/books-api', '');
      final s = Seen(
        request.method,
        path,
        request.uri.queryParameters,
        request.headers.value('authorization'),
        text.isEmpty ? null : jsonDecode(text),
      );
      seen.add(s);
      final (status, body) = handler(s);
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.json;
      if (body != null) request.response.write(jsonEncode(body));
      await request.response.close();
    });
    api = HttpFriendsApi(
      session: session,
      origin: Uri.parse('http://127.0.0.1:${server.port}/books-api'),
    );
  }

  Future<void> stop() => server.close(force: true);
}

const meJson = {
  'id': 'u1',
  'email': 'ana@example.com',
  'username': 'ana',
  'first_name': 'Ana',
  'last_name': 'Pop',
  'has_phone': false,
  'discoverable_by_phone': false,
};
Map<String, Object?> tokens(String n) => {
  'access_token': 'access-$n',
  'refresh_token': 'refresh-$n',
  'token_type': 'bearer',
};

void main() {
  late Harness h;
  setUp(() async {
    h = Harness();
    await h.start();
  });
  tearDown(() => h.stop());

  Future<void> signedIn() => h.session.write(
    const Session(accessToken: 'access-1', refreshToken: 'refresh-1'),
  );

  group('account', () {
    test('register stores the session and returns the account', () async {
      h.handler = (r) => switch (r.path) {
        '/auth/register' => (201, tokens('1')),
        '/me' => (200, meJson),
        _ => (404, null),
      };
      final account = await h.api.register(
        email: ' ana@example.com ',
        password: 'a long password',
        username: 'ana',
        firstName: 'Ana',
        lastName: 'Pop',
      );
      expect(account.displayName, 'Ana Pop');
      final sent = h.seen.first.body as Map;
      expect(sent['email'], 'ana@example.com', reason: 'trimmed');
      expect(sent.keys.toSet(), {
        'email',
        'password',
        'username',
        'first_name',
        'last_name',
      });
      expect((await h.session.read())?.refreshToken, 'refresh-1');
      expect(h.seen.last.auth, 'Bearer access-1');
    });

    test(
      'a wrong password shows the server message and stores nothing',
      () async {
        h.handler = (_) => (401, {'detail': 'Wrong email or password.'});
        await expectLater(
          h.api.signIn(email: 'a@b.co', password: 'x'),
          throwsA(
            isA<FriendsException>().having(
              (e) => e.message,
              'message',
              'Wrong email or password.',
            ),
          ),
        );
        expect(await h.session.read(), isNull);
      },
    );

    test(
      'me() is null when nobody is signed in, without any request',
      () async {
        expect(await h.api.me(), isNull);
        expect(h.seen, isEmpty);
      },
    );

    test(
      'sign out forgets the session even if the server is unreachable',
      () async {
        await signedIn();
        await h.stop();
        await h.api.signOut();
        expect(await h.session.read(), isNull);
      },
    );

    test(
      'deleting the account sends the password and clears the session',
      () async {
        await signedIn();
        h.handler = (_) => (204, null);
        await h.api.deleteAccount(password: 'secret password');
        expect(h.seen.single.method, 'DELETE');
        expect(h.seen.single.path, '/me');
        expect((h.seen.single.body as Map)['password'], 'secret password');
        expect(await h.session.read(), isNull);
      },
    );
  });

  group('sessions', () {
    test(
      'an expired access token is refreshed once and the call retried',
      () async {
        await signedIn();
        h.handler = (r) {
          if (r.path == '/auth/refresh') return (200, tokens('2'));
          if (r.auth == 'Bearer access-2') return (200, meJson);
          return (401, {'detail': 'Not signed in.'});
        };
        expect((await h.api.me())?.username, 'ana');
        expect(h.seen.map((s) => s.path), ['/me', '/auth/refresh', '/me']);
        expect((await h.session.read())?.refreshToken, 'refresh-2');
      },
    );

    test('concurrent expired calls share one refresh', () async {
      await signedIn();
      h.handler = (r) {
        if (r.path == '/auth/refresh') return (200, tokens('2'));
        if (r.auth == 'Bearer access-2') return (200, <Object>[]);
        return (401, {'detail': 'Not signed in.'});
      };
      await Future.wait([h.api.friends(), h.api.blocked()]);
      expect(h.seen.where((s) => s.path == '/auth/refresh'), hasLength(1));
    });

    test('a refused refresh token ends the session', () async {
      await signedIn();
      h.handler = (_) => (401, {'detail': 'Sign in again.'});
      await expectLater(
        h.api.friends(),
        throwsA(
          isA<FriendsException>().having((e) => e.signedOut, 'signedOut', true),
        ),
      );
      expect(await h.session.read(), isNull);
      expect(await h.api.me(), isNull);
    });

    test('losing the connection never signs the reader out', () async {
      await signedIn();
      await h.stop();
      await expectLater(
        h.api.friends(),
        throwsA(
          isA<FriendsException>()
              .having((e) => e.signedOut, 'signedOut', false)
              .having((e) => e.message, 'message', contains('Could not reach')),
        ),
      );
      expect(await h.session.read(), isNotNull);
    });

    test('a server error is not mistaken for a lost session', () async {
      await signedIn();
      h.handler = (_) => (500, {'oops': true});
      await expectLater(h.api.friends(), throwsA(isA<FriendsException>()));
      expect(await h.session.read(), isNotNull);
    });
  });

  group('errors become readable messages', () {
    Future<String> message(int status, Object? body) async {
      await signedIn();
      h.handler = (_) => (status, body);
      try {
        await h.api.sendRequest('x');
      } on FriendsException catch (e) {
        return e.message;
      }
      return '';
    }

    test('a server detail is shown as is', () async {
      expect(
        await message(409, {'detail': 'Request already sent.'}),
        'Request already sent.',
      );
    });
    test('too many requests', () async {
      expect(await message(429, {'detail': ''}), contains('Too many attempts'));
    });
    test('validation errors name the field', () async {
      final text = await message(422, {
        'detail': [
          {
            'loc': ['body', 'username'],
            'msg': 'Value error, 3 to 30 characters',
          },
        ],
      });
      expect(text, 'Username: 3 to 30 characters');
    });
  });

  group('people', () {
    test('lookup returns null for an unknown username', () async {
      await signedIn();
      h.handler = (_) => (404, {'detail': 'No one has that username.'});
      expect(await h.api.lookup(' nobody '), isNull);
      expect(h.seen.single.query['username'], 'nobody');
    });

    test('lookup parses a person', () async {
      await signedIn();
      h.handler = (_) =>
          (200, {'id': 'u2', 'username': 'bob', 'display_name': 'Bob Ionescu'});
      final p = await h.api.lookup('bob');
      expect(
        (p?.id, p?.username, p?.displayName),
        ('u2', 'bob', 'Bob Ionescu'),
      );
    });

    test(
      'contacts are sent in batches of at most 1000 with the region',
      () async {
        await signedIn();
        h.handler = (r) => (200, <Object>[]);
        await h.api.matchContacts([
          for (var i = 0; i < 2500; i++) '+4071$i',
        ], region: 'RO');
        final calls = h.seen.where((s) => s.path == '/contacts/match').toList();
        expect(calls.map((c) => (c.body['numbers'] as List).length), [
          1000,
          1000,
          500,
        ]);
        expect(calls.every((c) => c.body['region'] == 'RO'), isTrue);
      },
    );

    test('requests parse both directions', () async {
      await signedIn();
      h.handler = (_) => (
        200,
        {
          'incoming': [
            {'id': 'a', 'username': 'a1', 'display_name': 'A One'},
          ],
          'outgoing': [],
        },
      );
      final r = await h.api.requests();
      expect(r.incoming.single.username, 'a1');
      expect(r.outgoing, isEmpty);
    });
  });

  group('shelf', () {
    final books = [
      SharedBook(
        id: 'b1',
        title: 'Dune',
        author: 'Frank Herbert',
        status: BookStatus.finished,
        finishes: [
          PartialDate(DatePrecision.day, '2020-02-29'),
          PartialDate(DatePrecision.month, '2019-07'),
          PartialDate(DatePrecision.year, '2018'),
          const PartialDate.unknown(),
        ],
      ),
      const SharedBook(
        id: 'b2',
        title: 'Emma',
        author: '',
        status: BookStatus.wantToRead,
      ),
    ];

    test('publishing sends exactly the allowed fields, with dates split by precision', () async {
      await signedIn();
      h.handler = (r) => (
        200,
        {
          'books': (r.body as Map)['books'],
          'updated_at': '2026-10-07T10:00:00Z',
        },
      );
      await h.api.publishShelf(books);
      final sent = h.seen.single.body as Map;
      expect(sent.keys, ['books']);
      final first = (sent['books'] as List).first as Map;
      expect(first.keys.toSet(), {
        'id',
        'title',
        'author',
        'status',
        'finishes',
      });
      expect(first['status'], 'finished');
      expect(first['finishes'], [
        {'precision': 'day', 'year': 2020, 'month': 2, 'day': 29},
        {'precision': 'month', 'year': 2019, 'month': 7, 'day': null},
        {'precision': 'year', 'year': 2018, 'month': null, 'day': null},
        {'precision': 'unknown', 'year': null, 'month': null, 'day': null},
      ]);
      expect(((sent['books'] as List).last as Map)['status'], 'want_to_read');
    });

    test('a friend\'s shelf is parsed back with precision intact', () async {
      await signedIn();
      h.handler = (_) => (
        200,
        {
          'updated_at': '2026-10-07T10:00:00Z',
          'books': [
            {
              'id': 'b1',
              'title': 'Dune',
              'author': 'FH',
              'status': 'finished',
              'finishes': [
                {'precision': 'month', 'year': 2019, 'month': 7, 'day': null},
                {'precision': 'year', 'year': 987, 'month': null, 'day': null},
                {
                  'precision': 'unknown',
                  'year': null,
                  'month': null,
                  'day': null,
                },
              ],
            },
          ],
        },
      );
      final shelf = await h.api.friendShelf('u2');
      final f = shelf!.books.single.finishes;
      expect(f.map((d) => (d.precision, d.value)), [
        (DatePrecision.month, '2019-07'),
        (DatePrecision.year, '0987'),
        (DatePrecision.unknown, null),
      ]);
      expect(h.seen.single.path, '/friends/u2/shelf');
    });

    test('no shelf is null, not an error', () async {
      await signedIn();
      h.handler = (_) => (404, {'detail': 'Not found.'});
      expect(await h.api.friendShelf('u2'), isNull);
      expect(await h.api.myShelf(), isNull);
    });

    test(
      'a library over the server limit is refused before anything is sent',
      () async {
        await signedIn();
        final many = [
          for (var i = 0; i < 5001; i++)
            SharedBook(
              id: '$i',
              title: 't',
              author: '',
              status: BookStatus.wantToRead,
            ),
        ];
        await expectLater(
          h.api.publishShelf(many),
          throwsA(isA<FriendsException>()),
        );
        expect(h.seen, isEmpty);
      },
    );
  });

  group('library', () {
    const library = {
      'version': 1,
      'books': [],
      'authors': [],
      'bookAuthors': [],
      'editions': [],
      'userBooks': [],
      'records': [],
      'sessions': [],
      'pins': [
        {'id': 'p1', 'textContent': 'private'},
      ],
    };

    test(
      'being signed in is known on the device, without the server',
      () async {
        expect(await h.api.signedIn(), isFalse);
        await signedIn();
        expect(await h.api.signedIn(), isTrue);
        expect(h.seen, isEmpty);
      },
    );

    test(
      'the account id comes from the server, or null when signed out',
      () async {
        expect(await h.api.accountId(), isNull);
        await signedIn();
        h.handler = (_) => (200, meJson);
        expect(await h.api.accountId(), 'u1');
      },
    );

    test('nothing saved yet is null, not an error', () async {
      await signedIn();
      h.handler = (_) => (404, {'detail': 'No library saved yet.'});
      expect(await h.api.libraryRevision(), isNull);
      expect(await h.api.fetchLibrary(), isNull);
    });

    test('the revision and the library are read back', () async {
      await signedIn();
      h.handler = (r) => switch (r.path) {
        '/me/library/meta' => (
          200,
          {'revision': 3, 'updated_at': '2026-10-07T10:00:00Z'},
        ),
        '/me/library' => (
          200,
          {
            'revision': 3,
            'updated_at': '2026-10-07T10:00:00Z',
            'data': library,
          },
        ),
        _ => (404, null),
      };
      expect((await h.api.libraryRevision())!.revision, 3);
      final fetched = (await h.api.fetchLibrary())!;
      expect(fetched.revision, 3);
      expect((fetched.data['pins'] as List).single['textContent'], 'private');
      expect(h.seen.every((r) => r.auth == 'Bearer access-1'), isTrue);
    });

    test('saving sends the base revision and the data, nothing else', () async {
      await signedIn();
      h.handler = (_) =>
          (200, {'revision': 4, 'updated_at': '2026-10-07T10:00:00Z'});
      final saved = await h.api.saveLibrary(library, baseRevision: 3);
      expect(saved.revision, 4);
      final sent = h.seen.single;
      expect(sent.method, 'PUT');
      expect(sent.path, '/me/library');
      expect((sent.body as Map).keys.toSet(), {'base_revision', 'data'});
      expect(sent.body['base_revision'], 3);
      expect(sent.body['data'], library);
    });

    test(
      'a newer library on the server is a conflict, not a failure',
      () async {
        await signedIn();
        h.handler = (_) =>
            (409, {'detail': 'Your library changed on another device.'});
        await expectLater(
          h.api.saveLibrary(library, baseRevision: 1),
          throwsA(isA<LibraryConflictException>()),
        );
      },
    );

    test('a library that is too large is explained', () async {
      await signedIn();
      h.handler = (_) =>
          (413, {'detail': 'Your library is too large to save.'});
      await expectLater(
        h.api.saveLibrary(library, baseRevision: 0),
        throwsA(
          isA<FriendsException>().having(
            (e) => e.message,
            'message',
            'Your library is too large to save.',
          ),
        ),
      );
    });

    test('an expired token is refreshed once and the save retried', () async {
      await signedIn();
      var puts = 0;
      h.handler = (r) {
        if (r.path == '/auth/refresh') return (200, tokens('2'));
        puts++;
        return puts == 1
            ? (401, {'detail': 'Not signed in.'})
            : (200, {'revision': 1, 'updated_at': '2026-10-07T10:00:00Z'});
      };
      expect((await h.api.saveLibrary(library, baseRevision: 0)).revision, 1);
      expect(h.seen.last.auth, 'Bearer access-2');
    });

    test('losing the connection never signs the reader out', () async {
      await signedIn();
      await h.stop();
      await expectLater(
        h.api.saveLibrary(library, baseRevision: 0),
        throwsA(
          isA<FriendsException>().having(
            (e) => e.signedOut,
            'signedOut',
            false,
          ),
        ),
      );
      expect(await h.api.signedIn(), isTrue);
      // tearDown closes the server again.
      h = Harness();
      await h.start();
    });
  });
}
