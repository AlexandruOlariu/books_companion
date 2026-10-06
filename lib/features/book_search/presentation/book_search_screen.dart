import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/book_lookup.dart';

/// What the reader picked. [coverPath] is already copied into app storage.
class BookChoice {
  final BookSuggestion suggestion;
  final String? coverPath;
  const BookChoice(this.suggestion, this.coverPath);
}

class BookSearchScreen extends ConsumerStatefulWidget {
  final String initialQuery;
  const BookSearchScreen({super.key, this.initialQuery = ''});
  @override
  ConsumerState<BookSearchScreen> createState() => _BookSearchScreenState();
}

class _BookSearchScreenState extends ConsumerState<BookSearchScreen> {
  late final query = TextEditingController(text: widget.initialQuery);
  List<BookSuggestion>? results;
  String? error;
  bool searching = false, choosing = false;

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> search() async {
    if (searching) return;
    FocusScope.of(context).unfocus();
    setState(() {
      searching = true;
      error = null;
    });
    try {
      final found = await ref.read(bookLookupProvider).search(query.text);
      if (mounted) setState(() => results = found);
    } on LookupException catch (e) {
      // The typed text stays in the field; manual entry is one tap away.
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  Future<void> choose(BookSuggestion suggestion) async {
    setState(() => choosing = true);
    final cover = await ref.read(bookLookupProvider).fetchCover(suggestion);
    if (mounted) Navigator.pop(context, BookChoice(suggestion, cover));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Search online')),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: query,
                  autofocus: results == null,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => search(),
                  decoration: const InputDecoration(
                    labelText: 'Title, author, or ISBN',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Searches Open Library. Only your search text is sent, and only when you search.',
                  style: TextStyle(color: RoomColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: searching || choosing ? null : search,
                  icon: const Icon(Icons.search),
                  label: Text(searching ? 'Searching…' : 'Search'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _body(context)),
        ],
      ),
    ),
  );

  Widget _body(BuildContext context) {
    if (choosing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return _Message(
        message: error!,
        action: TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Add manually instead'),
        ),
      );
    }
    final found = results;
    if (found == null) return const SizedBox.shrink();
    if (found.isEmpty) {
      return _Message(
        message: 'No matches. Try fewer words, or add the book manually.',
        action: TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Add manually instead'),
        ),
      );
    }
    final close = found.any((s) => s.approximate);
    return ListView.builder(
      itemCount: found.length + 1 + (close ? 1 : 0),
      itemBuilder: (context, i) {
        if (close && i == 0) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(24, 4, 24, 8),
            child: Text(
              'No exact match. These are the closest results; check the spelling if none look right.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          );
        }
        i -= close ? 1 : 0;
        if (i == found.length) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Text(
              'Page counts are typical across editions. Check yours before saving.',
              style: TextStyle(color: RoomColors.muted, fontSize: 13),
            ),
          );
        }
        final s = found[i];
        final detail = [
          if (s.author.isNotEmpty) s.author,
          if (s.firstPublishYear != null) '${s.firstPublishYear}',
          if (s.pageCount != null) '${s.pageCount} pages',
          if (s.coverUrl == null) 'no cover',
        ].join(' · ');
        return ListTile(
          minVerticalPadding: 12,
          leading: SizedBox(
            width: 40,
            height: 60,
            child: s.thumbnailUrl == null
                ? const Icon(Icons.menu_book_outlined)
                : ExcludeSemantics(
                    child: Image.network(
                      s.thumbnailUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.menu_book_outlined),
                    ),
                  ),
          ),
          title: Text(s.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: detail.isEmpty ? null : Text(detail),
          onTap: () => choose(s),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  final String message;
  final Widget action;
  const _Message({required this.message, required this.action});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        Text(message, textAlign: TextAlign.center),
        action,
      ],
    ),
  );
}
