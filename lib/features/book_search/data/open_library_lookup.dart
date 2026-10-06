import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../../core/storage/cover_store.dart';
import '../domain/book_lookup.dart';

/// Optional metadata from https://openlibrary.org. Requests are made only when
/// the reader presses Search or picks a result, and carry no identifiers.
class OpenLibraryLookup implements BookLookup {
  final HttpClient Function() _client;
  final Future<String> Function(Uint8List bytes, String extension) _saveCover;
  final Uri _catalogue;
  final String _coverOrigin;
  OpenLibraryLookup({
    HttpClient Function()? client,
    Future<String> Function(Uint8List bytes, String extension)? saveCover,
    Uri? catalogue,
    this._coverOrigin = 'https://covers.openlibrary.org',
  }) : _client = client ?? HttpClient.new,
       _saveCover = saveCover ?? CoverStore.saveBytes,
       _catalogue = catalogue ?? Uri.https('openlibrary.org');

  static const _agent = 'ReadingLibrary/0.1';
  static const _unavailable =
      'Could not reach Open Library. Check your connection, or add the book manually.';

  Future<Uint8List> _get(Uri uri, {required int limit}) async {
    final client = _client()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, _agent);
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw HttpException('HTTP ${response.statusCode}');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        bytes.add(chunk);
        if (bytes.length > limit) throw const HttpException('Too large');
      }
      return bytes.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<List<BookSuggestion>> search(String query) async {
    final text = query.trim();
    if (text.isEmpty) {
      throw const LookupException('Enter a title, author, or ISBN.');
    }
    final isbn = isbnFrom(text);
    try {
      final exact = await _query(isbn == null ? text : 'isbn:$isbn');
      if (exact.isNotEmpty || isbn != null) return exact;
      // Nothing matched every word, often because one is misspelled. Retry
      // with any-word matching and say so, rather than show an empty list.
      final words = text
          .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
          .where((w) => w.length >= 3)
          .toList();
      if (words.length < 2) return exact;
      try {
        final loose = await _query(words.join(' OR '), limit: 10);
        return [for (final s in loose) s.copyWith(approximate: true)];
      } on Object {
        return exact; // The retry is a bonus; never turn "no match" into an error.
      }
    } on LookupException {
      rethrow;
    } on Object {
      // Network, timeout, status, and parse failures all mean the same thing to
      // the reader: lookup is unavailable and manual entry is still there.
      throw const LookupException(_unavailable);
    }
  }

  Future<List<BookSuggestion>> _query(String q, {int limit = 15}) async {
    final uri = _catalogue.replace(
      path: '/search.json',
      queryParameters: {
        'q': q,
        'limit': '$limit',
        'fields': 'title,author_name,number_of_pages_median,language,cover_i,first_publish_year',
      },
    );
    final body = await _get(uri, limit: 2 * 1024 * 1024);
    final json = jsonDecode(utf8.decode(body));
    final docs = json is Map ? json['docs'] : null;
    if (docs is! List) throw const FormatException('Unexpected response');
    return docs.map(_suggestion).whereType<BookSuggestion>().toList();
  }

  @visibleForTesting
  String coverUrlFor(int id) => '$_coverOrigin/b/id/$id-L.jpg?default=false';

  BookSuggestion? _suggestion(dynamic doc) {
    if (doc is! Map) return null;
    final title = doc['title'];
    if (title is! String || title.trim().isEmpty) return null;
    final authors = doc['author_name'];
    final names = authors is List
        ? authors.whereType<String>().take(3).join(', ')
        : '';
    final pages = doc['number_of_pages_median'];
    final year = doc['first_publish_year'];
    final cover = doc['cover_i'];
    final languages = doc['language'];
    return BookSuggestion(
      title: title.trim(),
      author: names,
      pageCount: pages is num && pages > 0 ? pages.round() : null,
      firstPublishYear: year is int ? year : null,
      // A work's language list covers every edition; only one entry is
      // unambiguous enough to prefill.
      language: languages is List && languages.length == 1
          ? languageName(languages.first)
          : null,
      coverUrl: cover is int
          ? '$_coverOrigin/b/id/$cover-L.jpg?default=false'
          : null,
      thumbnailUrl: cover is int
          ? '$_coverOrigin/b/id/$cover-S.jpg?default=false'
          : null,
    );
  }

  static const _languages = {
    'eng': 'English',
    'fre': 'French',
    'ger': 'German',
    'spa': 'Spanish',
    'ita': 'Italian',
    'rum': 'Romanian',
    'por': 'Portuguese',
    'dut': 'Dutch',
    'rus': 'Russian',
    'pol': 'Polish',
    'lat': 'Latin',
    'jpn': 'Japanese',
    'chi': 'Chinese',
    'swe': 'Swedish',
    'dan': 'Danish',
    'nor': 'Norwegian',
    'fin': 'Finnish',
    'hun': 'Hungarian',
    'cze': 'Czech',
    'gre': 'Greek',
    'tur': 'Turkish',
    'ara': 'Arabic',
    'heb': 'Hebrew',
    'kor': 'Korean',
    'hin': 'Hindi',
  };
  static String? languageName(dynamic code) => _languages[code];

  @override
  Future<String?> fetchCover(BookSuggestion suggestion) async {
    final url = suggestion.coverUrl;
    if (url == null) return null;
    try {
      final bytes = await _get(Uri.parse(url), limit: 5 * 1024 * 1024);
      final extension = imageExtension(bytes);
      return extension == null ? null : await _saveCover(bytes, extension);
    } on Object {
      return null;
    }
  }

  /// Recognises JPEG and PNG by content, so an error page or a placeholder
  /// served with an image type is never stored as a cover.
  static String? imageExtension(Uint8List b) {
    if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return '.jpg';
    }
    if (b.length > 4 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47) {
      return '.png';
    }
    return null;
  }
}
