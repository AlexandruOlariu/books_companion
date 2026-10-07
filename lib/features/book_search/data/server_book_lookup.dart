import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../friends/data/http_friends_api.dart';
import '../domain/book_lookup.dart';
import 'open_library_lookup.dart';

/// Searches through the Reading Library server (`POST /books/search`, see
/// docs/backend.md), so the search rules can be fixed without an app release.
/// Sends only the typed text, with no account or identifiers. If the server
/// cannot answer for any reason, the search goes to Open Library directly, as
/// before. Covers are always downloaded from Open Library by [_direct].
class ServerBookLookup implements BookLookup {
  final OpenLibraryLookup _direct;
  final Uri _origin;
  final HttpClient Function() _client;
  ServerBookLookup({
    OpenLibraryLookup? direct,
    Uri? origin,
    HttpClient Function()? client,
  }) : _direct = direct ?? OpenLibraryLookup(),
       _origin = origin ?? Uri.parse(HttpFriendsApi.defaultOrigin),
       _client = client ?? HttpClient.new;

  static const _agent = 'ReadingLibrary/0.1';

  @override
  Future<List<BookSuggestion>> search(String query) async {
    if (query.trim().isEmpty) return _direct.search(query);
    try {
      return await _viaServer(query.trim());
    } on Object {
      return _direct.search(query);
    }
  }

  Future<List<BookSuggestion>> _viaServer(String text) async {
    final client = _client()..connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = _origin.replace(path: '${_origin.path}/books/search');
      final request = await client.postUrl(uri);
      request.headers
        ..set(HttpHeaders.userAgentHeader, _agent)
        ..set(HttpHeaders.acceptHeader, 'application/json')
        ..contentType = ContentType.json;
      // In the body, not the URL, so the text stays out of request logs.
      request.add(utf8.encode(jsonEncode({'q': text})));
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        bytes.add(chunk);
        if (bytes.length > 1024 * 1024) throw const HttpException('Too big');
      }
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final json = jsonDecode(utf8.decode(bytes.takeBytes()));
      final books = json is Map ? json['books'] : null;
      if (books is! List) throw const FormatException('Unexpected response');
      final approximate = json['approximate'] == true;
      return books
          .map((b) => _suggestion(b, approximate))
          .whereType<BookSuggestion>()
          .toList();
    } finally {
      client.close(force: true);
    }
  }

  BookSuggestion? _suggestion(dynamic b, bool approximate) {
    if (b is! Map) return null;
    final title = b['title'];
    if (title is! String || title.trim().isEmpty) return null;
    final author = b['author'];
    final pages = b['page_count'];
    final year = b['first_publish_year'];
    final language = b['language'];
    final cover = b['cover_id'];
    // Only a cover id comes from the server; the address is built here, so a
    // cover is never fetched from anywhere but Open Library's cover host.
    return BookSuggestion(
      title: title.trim(),
      author: author is String ? author : '',
      pageCount: pages is int && pages > 0 ? pages : null,
      firstPublishYear: year is int ? year : null,
      language: language is String ? language : null,
      coverUrl: cover is int ? _direct.coverUrlFor(cover) : null,
      thumbnailUrl: cover is int ? _direct.coverUrlFor(cover, size: 'S') : null,
      approximate: approximate,
    );
  }

  @override
  Future<String?> fetchCover(BookSuggestion suggestion) =>
      _direct.fetchCover(suggestion);
}
