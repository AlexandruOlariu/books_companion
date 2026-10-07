import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reading_library/features/book_search/data/open_library_lookup.dart';
import 'package:reading_library/features/book_search/data/server_book_lookup.dart';

void main() {
  late HttpServer server;
  late ServerBookLookup lookup;
  late List<String> requests;
  late String origin;
  Future<void> Function(HttpRequest) handler = (_) async {};

  setUp(() async {
    requests = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      requests.add('${r.method} ${r.uri.path}');
      await handler(r);
    });
    origin = 'http://127.0.0.1:${server.port}';
    lookup = ServerBookLookup(
      origin: Uri.parse('$origin/books-api'),
      direct: OpenLibraryLookup(
        catalogue: Uri.parse(origin),
        coverOrigin: '$origin/covers',
      ),
    );
  });
  tearDown(() => server.close(force: true));

  Future<void> openLibrary(HttpRequest r) async {
    r.response.write(
      jsonEncode({
        'docs': [
          {'title': 'Direct result', 'cover_i': 7},
        ],
      }),
    );
    await r.response.close();
  }

  test(
    'searches through the server and builds cover addresses itself',
    () async {
      String? sent;
      handler = (r) async {
        sent = await utf8.decodeStream(r);
        r.response.write(
          jsonEncode({
            'approximate': true,
            'books': [
              {
                'title': 'The Coworker',
                'author': 'Freida McFadden',
                'page_count': 344,
                'first_publish_year': 2023,
                'language': 'English',
                'cover_id': 15125038,
              },
              {'title': ' '},
            ],
          }),
        );
        await r.response.close();
      };
      final found = await lookup.search(' Frieda The Coworker ');
      expect(requests, ['POST /books-api/books/search']);
      // Only the typed text, in the body rather than the URL.
      expect(jsonDecode(sent!), {'q': 'Frieda The Coworker'});
      expect(found, hasLength(1));
      final book = found.single;
      expect(book.title, 'The Coworker');
      expect(book.author, 'Freida McFadden');
      expect(book.pageCount, 344);
      expect(book.firstPublishYear, 2023);
      expect(book.language, 'English');
      expect(book.approximate, isTrue);
      expect(book.coverUrl, '$origin/covers/b/id/15125038-L.jpg?default=false');
      expect(
        book.thumbnailUrl,
        '$origin/covers/b/id/15125038-S.jpg?default=false',
      );
    },
  );

  test('falls back to Open Library when the server fails', () async {
    for (final failure in [502, 429, 404]) {
      requests.clear();
      handler = (r) async {
        if (r.uri.path.startsWith('/books-api')) {
          r.response.statusCode = failure;
          await r.response.close();
        } else {
          await openLibrary(r);
        }
      };
      final found = await lookup.search('dune');
      expect(found.single.title, 'Direct result', reason: 'HTTP $failure');
      expect(requests, ['POST /books-api/books/search', 'GET /search.json']);
    }
  });

  test('falls back on a bad body and when the server is unreachable', () async {
    handler = (r) async {
      if (r.uri.path.startsWith('/books-api')) {
        r.response.write('<html>not json</html>');
        await r.response.close();
      } else {
        await openLibrary(r);
      }
    };
    expect((await lookup.search('dune')).single.title, 'Direct result');

    handler = openLibrary;
    final unreachable = ServerBookLookup(
      origin: Uri.parse('http://127.0.0.1:1/books-api'),
      direct: OpenLibraryLookup(catalogue: Uri.parse(origin)),
    );
    expect((await unreachable.search('dune')).single.title, 'Direct result');
  });
}
