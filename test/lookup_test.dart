import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reading_library/features/book_search/data/open_library_lookup.dart';
import 'package:reading_library/features/book_search/domain/book_lookup.dart';

void main() {
  late HttpServer server;
  late OpenLibraryLookup lookup;
  late List<Uri> requests;
  var saved = <String>[];
  final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
  Future<void> Function(HttpRequest) handler = (_) async {};

  setUp(() async {
    requests = [];
    saved = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) {
      requests.add(r.uri);
      handler(r);
    });
    final origin = 'http://127.0.0.1:${server.port}';
    lookup = OpenLibraryLookup(
      catalogue: Uri.parse(origin),
      coverOrigin: origin,
      saveCover: (bytes, ext) async {
        saved.add(ext);
        return '/covers/new$ext';
      },
    );
  });
  tearDown(() => server.close(force: true));

  test('parses suggestions and drops unusable rows', () async {
    handler = (r) async {
      r.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'docs': [
              {
                'title': 'Dune',
                'author_name': ['Frank Herbert'],
                'number_of_pages_median': 412,
                'language': ['eng'],
                'cover_i': 99,
                'first_publish_year': 1965,
              },
              {
                'title': 'Multilingual',
                'language': ['eng', 'fre'],
                'number_of_pages_median': 0,
              },
              {
                'author_name': ['No title'],
              },
            ],
          }),
        );
      await r.response.close();
    };
    final found = await lookup.search('dune');
    expect(found, hasLength(2));
    expect(found[0].author, 'Frank Herbert');
    expect(found[0].pageCount, 412);
    expect(found[0].language, 'English');
    expect(found[0].coverUrl, endsWith('/b/id/99-L.jpg?default=false'));
    // Ambiguous language and a zero page count are left for the reader.
    expect(found[1].language, isNull);
    expect(found[1].pageCount, isNull);
    expect(found[1].coverUrl, isNull);
  });

  test('ISBN input becomes an isbn query', () async {
    handler = (r) async {
      r.response.write('{"docs": []}');
      await r.response.close();
    };
    await lookup.search('978-0-441-17271-9');
    expect(requests.single.queryParameters['q'], 'isbn:9780441172719');
    expect(isbnFrom('0-306-40615-2'), '0306406152');
    expect(isbnFrom('dune'), isNull);
  });

  test('a misspelled multi-word query falls back to close matches', () async {
    handler = (r) async {
      final q = r.uri.queryParameters['q']!;
      r.response.write(
        q.contains(' OR ')
            ? jsonEncode({
                'docs': [
                  {'title': 'The Housemaid'},
                ],
              })
            : '{"docs": []}',
      );
      await r.response.close();
    };
    final found = await lookup.search('freida mcfaden housemaid');
    expect(found.single.title, 'The Housemaid');
    expect(found.single.approximate, isTrue);
    expect(
      requests.last.queryParameters['q'],
      'freida OR mcfaden OR housemaid',
    );
    // Short words are not worth matching on.
    await lookup.search('of a housmaid');
    expect(requests.last.queryParameters['q'], 'of a housmaid');
    // Common words would match the whole catalogue and time Open Library out.
    await lookup.search('Frieda The Coworker');
    expect(requests.last.queryParameters['q'], 'Frieda OR Coworker');
    await lookup.search('the housmaid');
    expect(requests.last.queryParameters['q'], 'the housmaid');
  });

  test(
    'no retry for one word or an ISBN, and a failed retry is not an error',
    () async {
      handler = (r) async {
        r.response.write('{"docs": []}');
        await r.response.close();
      };
      expect(await lookup.search('housmaid'), isEmpty);
      expect(requests, hasLength(1));
      expect(await lookup.search('9780441172719'), isEmpty);
      expect(requests, hasLength(2));
      var calls = 0;
      handler = (r) async {
        if (++calls == 1) {
          r.response.write('{"docs": []}');
        } else {
          r.response.statusCode = 500;
        }
        await r.response.close();
      };
      expect(await lookup.search('freida mcfaden'), isEmpty);
    },
  );

  test('server errors and bad bodies become a friendly message', () async {
    handler = (r) async {
      r.response.statusCode = 503;
      await r.response.close();
    };
    await expectLater(lookup.search('dune'), throwsA(isA<LookupException>()));
    handler = (r) async {
      r.response.write('<html>nope</html>');
      await r.response.close();
    };
    await expectLater(lookup.search('dune'), throwsA(isA<LookupException>()));
    await expectLater(lookup.search('  '), throwsA(isA<LookupException>()));
  });

  test('an unreachable catalogue is a LookupException', () async {
    await server.close(force: true);
    await expectLater(lookup.search('dune'), throwsA(isA<LookupException>()));
  });

  test('covers are stored only when the bytes are a real image', () async {
    handler = (r) async {
      r.response.add(r.uri.path.contains('42') ? jpeg : utf8.encode('<html>'));
      await r.response.close();
    };
    String url(int id) => lookup.coverUrlFor(id);
    expect(
      await lookup.fetchCover(
        BookSuggestion(title: 't', author: 'a', coverUrl: url(42)),
      ),
      '/covers/new.jpg',
    );
    expect(
      await lookup.fetchCover(
        BookSuggestion(title: 't', author: 'a', coverUrl: url(7)),
      ),
      isNull,
    );
    expect(saved, ['.jpg']);
    expect(
      await lookup.fetchCover(const BookSuggestion(title: 't', author: 'a')),
      isNull,
    );
  });
}
