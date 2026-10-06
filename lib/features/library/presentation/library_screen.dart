import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/book_cover.dart';
import '../../../core/widgets/common.dart';
import '../domain/models.dart';
import '../domain/search.dart';
import '../domain/sorting.dart';
import 'keepsakes.dart';
import 'shelf.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  final LibrarySnapshot data;
  const LibraryScreen({super.key, required this.data});
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  static const _sortKey = 'librarySort';
  LibrarySort sort = LibrarySort.title;
  BookStatus? status;
  int? year;
  bool list = false;
  String search = '';
  final searchField = TextEditingController();
  String? selectedId;

  @override
  void initState() {
    super.initState();
    // The reader's last choice is remembered between launches.
    ref.read(preferencesProvider).read(_sortKey).then((saved) {
      if (saved != null && mounted) {
        setState(() => sort = LibrarySort.fromName(saved));
      }
    });
  }

  @override
  void dispose() {
    searchField.dispose();
    super.dispose();
  }

  Future<void> _chooseSort() async {
    final picked = await showModalBottomSheet<LibrarySort>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'Sort the shelf',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            for (final option in LibrarySort.values)
              ListTile(
                minVerticalPadding: 12,
                leading: Icon(
                  option == sort
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: option == sort ? RoomColors.forest : RoomColors.muted,
                ),
                title: Text(option.label),
                subtitle: Text(option.description),
                selected: option == sort,
                onTap: () => Navigator.pop(context, option),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      sort = picked;
      selectedId = null;
    });
    await ref.read(preferencesProvider).write(_sortKey, picked.name);
  }

  Widget _emptyState(LibrarySnapshot data, int hidden) {
    final typed = search.trim();
    if (data.books.isEmpty) {
      return EmptyRoom(
        title: 'A shelf of possibilities.',
        message: 'The stories you’ve loved. The ones still waiting.\nKeep them all here, just for you.',
        action: Column(
          children: [
            FilledButton.icon(
              onPressed: () => context.push('/add'),
              icon: const Icon(Icons.add),
              label: const Text('Add your first book'),
            ),
            TextButton(
              onPressed: () => context.push('/add?past=true'),
              child: const Text('Add books I’ve already read'),
            ),
          ],
        ),
      );
    }
    if (typed.isNotEmpty && hidden > 0) {
      // The search found something, but a filter is hiding it.
      final where = status == null
          ? 'the selected year'
          : 'the ${status!.label} filter';
      return EmptyRoom(
        title: 'Nothing here for “$typed”.',
        message:
            '$hidden matching ${hidden == 1 ? 'book is' : 'books are'} hidden by $where.',
        action: FilledButton(
          onPressed: () => setState(() {
            status = null;
            year = null;
            selectedId = null;
          }),
          child: Text('Show ${hidden == 1 ? 'it' : 'all $hidden'}'),
        ),
      );
    }
    if (typed.isNotEmpty) {
      return EmptyRoom(
        title: 'No book matches “$typed”.',
        message: 'Check the spelling, or add it to your library. You can search online from there.',
        action: FilledButton.icon(
          onPressed: () => context.push('/add'),
          icon: const Icon(Icons.add),
          label: const Text('Add a book'),
        ),
      );
    }
    return EmptyRoom(
      title: 'A little space on this shelf.',
      message: 'Try a different filter, or add a book to this collection.',
      action: FilledButton.icon(
        onPressed: () => context.push('/add'),
        icon: const Icon(Icons.add),
        label: const Text('Add a book'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final showYears = status == null || status == BookStatus.finished;
    final finishedIds = data.finishesIn(year).map((c) => c.userBookId).toSet();
    final inFilter = data.books.where(
      (b) =>
          (status == null || b.status == status) &&
          (!showYears || year == null || finishedIds.contains(b.id)),
    );
    // Sort first; a typed search then ranks by relevance, and equally good
    // matches keep the chosen sort order.
    final books = searchBooks(sortBooks(inFilter, sort), search);
    // Matches the status/year filter is hiding, so an empty result can say so.
    final hidden = search.trim().isEmpty
        ? 0
        : data.books.where((b) => matchesQuery(b, search)).length -
              books.length;
    final finishedCount = data.books
        .where((b) => b.status == BookStatus.finished)
        .length;
    // Keepsakes belong to the whole shelf: not while a filter or search is
    // narrowing it to a few books.
    final showKeepsakes =
        status == null && year == null && search.trim().isEmpty;
    final selected =
        books.where((b) => b.id == selectedId).firstOrNull ?? books.firstOrNull;
    final accessibleList =
        list || MediaQuery.textScalerOf(context).scale(16) > 23;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/add'),
        backgroundColor: RoomColors.forest,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add book'),
      ),
      body: CustomScrollView(
        key: const PageStorageKey('library'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('Your own little reading room'),
                  const SizedBox(height: 12),
                  Text(
                    'My library',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 12),
                  if (showYears)
                    Row(
                      children: [
                        DropdownButton<int>(
                          value: year ?? 0,
                          underline: const SizedBox(),
                          borderRadius: BorderRadius.circular(12),
                          items: [
                            const DropdownMenuItem(
                              value: 0,
                              child: Text('All time'),
                            ),
                            ...data.years.map(
                              (y) =>
                                  DropdownMenuItem(value: y, child: Text('$y')),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => year = v == 0 ? null : v),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextButton(
                            onPressed: () => context.go(
                              '/journal${year == null ? '' : '?year=$year'}',
                            ),
                            child: Text(
                              '${data.finishesIn(year).length} books finished',
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (showYears && year != null)
                    const Text(
                      'Filtered by completion year',
                      style: TextStyle(color: RoomColors.muted, fontSize: 12),
                    ),
                  const SizedBox(height: 12),
                  // Wraps instead of scrolling so no filter is ever off-screen.
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final s in <BookStatus?>[null, ...BookStatus.values])
                        ChoiceChip(
                          label: Text(s?.label ?? 'All'),
                          selected: status == s,
                          showCheckmark: false,
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          onSelected: (_) => setState(() {
                            status = s;
                            selectedId = null;
                            if (s == BookStatus.reading ||
                                s == BookStatus.wantToRead) {
                              year = null;
                            }
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: searchField,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Find a book or author',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: search.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                searchField.clear();
                                setState(() => search = '');
                              },
                            ),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() {
                      search = v;
                      selectedId = null;
                    }),
                  ),
                  const SizedBox(height: 16),
                  Eyebrow(
                    '${books.length} ${books.length == 1 ? 'book' : 'books'} on the shelf',
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _chooseSort,
                            icon: const Icon(Icons.sort, size: 18),
                            label: Text('Sort: ${sort.shortLabel}'),
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => setState(() => list = !list),
                        icon: Icon(
                          accessibleList
                              ? Icons.view_week_outlined
                              : Icons.view_list_outlined,
                          size: 18,
                        ),
                        label: Text(accessibleList ? 'Shelf' : 'List'),
                      ),
                    ],
                  ),
                  if (!accessibleList && books.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 16),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 136),
                        child: selected == null
                            ? const Center(
                                child: Text(
                                  'Select a spine. Rediscover a story.',
                                  style: TextStyle(
                                    fontFamily: 'Literata',
                                    color: RoomColors.muted,
                                  ),
                                ),
                              )
                            : _Selection(
                                book: selected,
                                pins: data.pins
                                    .where((p) => p.userBookId == selected.id)
                                    .length,
                              ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (books.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              // Bottom space keeps the actions clear of the floating button.
              child: Padding(
                padding: const EdgeInsets.only(bottom: 96),
                child: _emptyState(data, hidden),
              ),
            ),
          if (accessibleList)
            SliverList.builder(
              itemCount: books.length,
              itemBuilder: (context, i) {
                final b = books[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: BookListTile(book: b),
                );
              },
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverShelf(
                books: books,
                selectedId: selectedId,
                onSelect: (id) => setState(() => selectedId = id),
                // Keepsakes stay out of the way while the reader is searching.
                keepsakes: showKeepsakes
                    ? Keepsake.earned(finishedCount)
                    : const [],
              ),
            ),
            if (books.isNotEmpty && showKeepsakes)
              SliverToBoxAdapter(child: KeepsakeNote(finished: finishedCount)),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 108)),
        ],
      ),
    );
  }
}

class _Selection extends StatelessWidget {
  final BookEntry book;
  final int pins;
  const _Selection({required this.book, required this.pins});
  @override
  Widget build(BuildContext context) => Material(
    color: RoomColors.surface,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push('/book/${book.id}'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Hero(
              tag: 'book-${book.id}',
              child: BookCover(book: book, width: 50, height: 74),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    book.author,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: RoomColors.muted),
                  ),
                  if (book.seriesLabel != null)
                    Text(
                      book.seriesLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: RoomColors.forest,
                        fontSize: 13,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    book.status == BookStatus.reading
                        ? book.progressLabel
                        : book.status.label,
                  ),
                  if (pins > 0) Text('$pins private pins'),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward, size: 20),
          ],
        ),
      ),
    ),
  );
}

class BookListTile extends StatelessWidget {
  final BookEntry book;
  final String? subtitle;
  const BookListTile({super.key, required this.book, this.subtitle});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => context.push('/book/${book.id}'),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          BookCover(book: book, width: 54, height: 80),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  book.author,
                  style: const TextStyle(color: RoomColors.muted),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle ?? book.status.label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: RoomColors.forest,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 20),
        ],
      ),
    ),
  );
}
