import 'models.dart';

const _folds = {
  'ă': 'a',
  'â': 'a',
  'á': 'a',
  'à': 'a',
  'ä': 'a',
  'ã': 'a',
  'å': 'a',
  'ā': 'a',
  'æ': 'ae',
  'î': 'i',
  'í': 'i',
  'ì': 'i',
  'ï': 'i',
  'ī': 'i',
  'ș': 's',
  'ş': 's',
  'š': 's',
  'ś': 's',
  'ß': 'ss',
  'ț': 't',
  'ţ': 't',
  'ť': 't',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'ę': 'e',
  'ě': 'e',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'ø': 'o',
  'ō': 'o',
  'œ': 'oe',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ū': 'u',
  'ů': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ç': 'c',
  'ć': 'c',
  'č': 'c',
  'ñ': 'n',
  'ń': 'n',
  'ň': 'n',
  'ł': 'l',
  'đ': 'd',
  'ď': 'd',
  'ř': 'r',
  'ž': 'z',
  'ź': 'z',
  'ż': 'z',
  'ğ': 'g',
};

/// Lowercases, removes diacritics (so "calinescu" finds "Călinescu"), and
/// turns punctuation into single spaces.
String foldForSearch(String text) {
  final out = StringBuffer();
  var lastSpace = true;
  for (final rune in text.toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    final folded = _folds[ch] ?? ch;
    final isWord = RegExp(r'[a-z0-9]').hasMatch(folded);
    if (isWord) {
      out.write(folded);
      lastSpace = false;
    } else if (!lastSpace) {
      out.write(' ');
      lastSpace = true;
    }
  }
  return out.toString().trim();
}

/// Every word typed must appear, in any order, so "mcfadden freida" and
/// "freida mcf" both find Freida McFadden. An empty query matches everything.
bool matchesQuery(BookEntry book, String query) =>
    _score(book, foldForSearch(query)) > 0;

/// Books that match [query], best first. With no query the order is unchanged.
List<BookEntry> searchBooks(Iterable<BookEntry> books, String query) {
  final q = foldForSearch(query);
  if (q.isEmpty) return books.toList();
  final scored = <(int, int, BookEntry)>[];
  var i = 0;
  for (final b in books) {
    final s = _score(b, q);
    if (s > 0) scored.add((s, i++, b));
  }
  // Stable: ties keep the library's own order.
  scored.sort((a, b) => b.$1 != a.$1 ? b.$1.compareTo(a.$1) : a.$2 - b.$2);
  return [for (final s in scored) s.$3];
}

int _score(BookEntry book, String q) {
  if (q.isEmpty) return 1;
  final title = foldForSearch(book.title), author = foldForSearch(book.author);
  final all = '$title $author ${foldForSearch(book.seriesName ?? '')}';
  final words = q.split(' ');
  if (!words.every(all.contains)) return 0;
  var score = 1;
  if (title == q) score += 100;
  if (title.startsWith(q)) score += 40;
  if (author.startsWith(q)) score += 30;
  // Whole-word and word-start hits beat matches buried inside a word.
  final titleWords = title.split(' '), authorWords = author.split(' ');
  for (final w in words) {
    if ([...titleWords, ...authorWords].contains(w)) {
      score += 6;
    } else if ([...titleWords, ...authorWords].any((t) => t.startsWith(w))) {
      score += 3;
    }
    if (titleWords.any((t) => t.startsWith(w))) score += 2;
  }
  return score;
}
