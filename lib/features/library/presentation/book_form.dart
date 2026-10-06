import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/providers.dart';
import '../../../core/storage/cover_store.dart';
import '../../../core/storage/draft_store.dart';
import '../../../core/widgets/common.dart';
import '../../book_search/presentation/book_search_screen.dart';
import '../../history/presentation/finish_date_field.dart';
import '../domain/models.dart';
import '../domain/search.dart';

class BookForm extends ConsumerStatefulWidget {
  final BookEntry? book;
  final bool historical;
  const BookForm({super.key, this.book, this.historical = false});
  @override
  ConsumerState<BookForm> createState() => _BookFormState();
}

class _BookFormState extends ConsumerState<BookForm> {
  late final title = TextEditingController(text: widget.book?.title);
  late final author = TextEditingController(text: widget.book?.author);
  late final pages = TextEditingController(
    text: widget.book?.pageCount?.toString(),
  );
  late final language = TextEditingController(text: widget.book?.language);
  late final series = TextEditingController(text: widget.book?.seriesName);
  late final seriesNumber = TextEditingController(
    text: widget.book?.seriesNumber?.toString(),
  );
  late BookStatus status =
      widget.book?.status ??
      (widget.historical ? BookStatus.finished : BookStatus.wantToRead);
  late String? cover = widget.book?.coverPath;
  PartialDate? finish;
  bool busy = false, dirty = false, allowPop = false, another = false;
  int dateKey = 0;
  String? error, savedMessage;
  String metadataSource = 'manual';
  bool restored = false;
  // Only new books are drafted; an edit starts from the saved record.
  DraftBinding? draft;

  @override
  void initState() {
    super.initState();
    if (widget.book != null) return;
    draft = DraftBinding(ref.read(draftStoreProvider), 'book:new');
    draft!.restore().then((fields) {
      if (fields == null || !mounted) return;
      setState(() {
        title.text = fields['title'] ?? '';
        author.text = fields['author'] ?? '';
        pages.text = fields['pages'] ?? '';
        language.text = fields['language'] ?? '';
        series.text = fields['series'] ?? '';
        seriesNumber.text = fields['seriesNumber'] ?? '';
        final add = fields['add'];
        if (!widget.historical && add != null) {
          // 'past' was an option in an earlier version; it meant Finished.
          status = add == 'past'
              ? BookStatus.finished
              : BookStatus.values.asNameMap()[add] ?? status;
        }
        restored = dirty = true;
      });
    });
  }

  void changed() {
    setState(() => dirty = true);
    final text = {
      'title': title.text,
      'author': author.text,
      'pages': pages.text,
      'language': language.text,
      'series': series.text,
      'seriesNumber': seriesNumber.text,
    };
    if (text.values.every((v) => v.trim().isEmpty)) {
      draft?.discard();
    } else {
      draft?.update({...text, 'add': status.name});
    }
  }

  Future<void> searchOnline() async {
    final choice = await Navigator.push<BookChoice>(
      context,
      MaterialPageRoute(
        builder: (_) => BookSearchScreen(
          initialQuery: '${title.text} ${author.text}'.trim(),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final s = choice.suggestion;
    setState(() {
      title.text = s.title;
      author.text = s.author;
      pages.text = s.pageCount?.toString() ?? '';
      language.text = s.language ?? '';
      cover = choice.coverPath;
      metadataSource = 'open_library';
      savedMessage = switch ((choice.coverPath, s.coverUrl)) {
        (String _, _) =>
          'Filled from Open Library. Check the details against your edition.',
        (_, null) => 'Filled from Open Library, which has no cover for this book. Choose one from your photos, or keep the generated cover.',
        _ => 'Filled from Open Library, but the cover could not be downloaded. Choose one from your photos, or keep the generated cover.',
      };
    });
    changed();
  }

  @override
  void dispose() {
    title.dispose();
    author.dispose();
    pages.dispose();
    language.dispose();
    series.dispose();
    seriesNumber.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final total = pages.text.trim().isEmpty ? null : int.tryParse(pages.text);
      if (pages.text.trim().isNotEmpty && total == null) {
        throw const FormatException('Enter a whole number of pages.');
      }
      if (widget.book == null &&
          status == BookStatus.finished &&
          finish == null) {
        throw const FormatException('Choose and confirm when you finished it.');
      }
      final number = seriesNumber.text.trim().isEmpty
          ? null
          : int.tryParse(seriesNumber.text.trim());
      if (seriesNumber.text.trim().isNotEmpty && number == null) {
        throw const FormatException(
          'Enter a whole number for the book number in the series.',
        );
      }
      final savedTitle = title.text.trim();
      await ref
          .read(repositoryProvider)
          .saveBook(
            id: widget.book?.id,
            title: title.text,
            author: author.text,
            pageCount: total,
            language: language.text.trim().isEmpty
                ? null
                : language.text.trim(),
            coverPath: cover,
            status: status,
            finish: finish,
            // A book added straight as Finished is a remembered finish; books
            // finished from the Reading tab are recorded as tracked.
            historical: true,
            metadataSource: metadataSource,
            seriesName: series.text,
            seriesNumber: number,
          );
      await draft?.discard();
      ref.invalidate(libraryProvider);
      if (!mounted) return;
      if (another && widget.book == null) {
        setState(() {
          savedMessage =
              '$savedTitle added${finish?.year != null ? ' to ${finish!.year}' : ''}. Ready for another book.';
          title.clear();
          author.clear();
          pages.clear();
          language.clear();
          // The next book is probably the next in the same series: keep the
          // name and move the number on. Everything else starts blank.
          seriesNumber.text = series.text.trim().isEmpty || number == null
              ? ''
              : '${number + 1}';
          if (series.text.trim().isEmpty) series.clear();
          cover = null;
          metadataSource = 'manual';
          restored = false;
          finish = null;
          dateKey++;
          dirty = false;
          busy = false;
        });
      } else {
        setState(() {
          allowPop = true;
          dirty = false;
        });
        notifyUser(context, '$savedTitle saved to your library.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = readableError(e);
          busy = false;
        });
      }
    }
  }

  /// Quick picks from series already in the library, so a new book joins the
  /// right one without retyping. Choosing one suggests the next number.
  List<Widget> _seriesSuggestions() {
    final books = ref.watch(libraryProvider).value?.books ?? const [];
    final typed = foldForSearch(series.text);
    final names = <String>{
      for (final b in books)
        if (b.seriesName != null) b.seriesName!,
    }.toList()..sort((a, b) => foldForSearch(a).compareTo(foldForSearch(b)));
    final matches = [
      for (final n in names)
        if (foldForSearch(n) != typed && foldForSearch(n).contains(typed)) n,
    ].take(5).toList();
    if (matches.isEmpty) return const [];
    return [
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final name in matches)
            ActionChip(
              label: Text(name),
              materialTapTargetSize: MaterialTapTargetSize.padded,
              onPressed: () {
                final inSeries = [
                  for (final b in books)
                    if (b.seriesName == name && b.seriesNumber != null)
                      b.seriesNumber!,
                ];
                setState(() {
                  series.text = name;
                  if (seriesNumber.text.trim().isEmpty && inSeries.isNotEmpty) {
                    seriesNumber.text =
                        '${inSeries.reduce((a, b) => a > b ? a : b) + 1}';
                  }
                });
                changed();
              },
            ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: allowPop || !dirty,
    onPopInvokedWithResult: (didPop, result) async {
      if (!didPop && !busy && await confirmDiscard(context) && mounted) {
        await draft?.discard();
        setState(() => allowPop = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context);
        });
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.book == null ? 'Add a book' : 'Edit book'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Eyebrow('Make room for a story'),
            const SizedBox(height: 12),
            Text(
              widget.historical
                  ? 'A book you remember.'
                  : 'Every book belongs.',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter your edition’s details. Everything stays on this device.',
            ),
            const SizedBox(height: 24),
            if (widget.book == null) ...[
              FilledButton.tonalIcon(
                onPressed: busy ? null : searchOnline,
                icon: const Icon(Icons.search),
                label: const Text('Search online'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Or enter the details yourself below.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
            ],
            if (restored)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Restored your unsaved draft.',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await draft?.discard();
                        if (!mounted) return;
                        setState(() {
                          title.clear();
                          author.clear();
                          pages.clear();
                          language.clear();
                          series.clear();
                          seriesNumber.clear();
                          restored = dirty = false;
                        });
                      },
                      child: const Text('Start fresh'),
                    ),
                  ],
                ),
              ),
            if (savedMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Text(
                  savedMessage!,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            TextField(
              controller: title,
              onChanged: (_) => changed(),
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: author,
              onChanged: (_) => changed(),
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Author'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: series,
              onChanged: (_) => changed(),
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Series (optional)',
                hintText: 'e.g. Dune',
              ),
            ),
            ..._seriesSuggestions(),
            const SizedBox(height: 16),
            TextField(
              controller: seriesNumber,
              onChanged: (_) => changed(),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Book number in the series (optional)',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: pages,
              onChanged: (_) => changed(),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Page count (optional)',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: language,
              onChanged: (_) => changed(),
              decoration: const InputDecoration(
                labelText: 'Language (optional)',
              ),
            ),
            const SizedBox(height: 16),
            if (cover != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Semantics(
                  label: 'Selected cover',
                  image: true,
                  child: Image.file(
                    File(cover!),
                    height: 180,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Text(
                      'This cover file could not be read. Choose another.',
                    ),
                  ),
                ),
              ),
            OutlinedButton.icon(
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(cover == null ? 'Choose a cover' : 'Change cover'),
              onPressed: () async {
                try {
                  final picked = await ImagePicker().pickImage(
                    source: ImageSource.gallery,
                    maxWidth: 1600,
                    maxHeight: 2400,
                    imageQuality: 90,
                  );
                  if (picked != null) {
                    final path = await CoverStore.importFile(picked.path);
                    if (mounted) {
                      setState(() {
                        cover = path;
                        dirty = true;
                      });
                    }
                  }
                } catch (_) {
                  if (mounted) {
                    setState(
                      () => error =
                          'Could not open that image. Please choose another.',
                    );
                  }
                }
              },
            ),
            if (cover != null)
              TextButton(
                onPressed: () => setState(() {
                  cover = null;
                  dirty = true;
                }),
                child: const Text('Use a generated cover'),
              ),
            if (widget.book == null) ...[
              const SizedBox(height: 24),
              DropdownButtonFormField<String>(
                initialValue: status.name,
                decoration: const InputDecoration(labelText: 'Add to'),
                items: const [
                  DropdownMenuItem(
                    value: 'wantToRead',
                    child: Text('Wishlist'),
                  ),
                  DropdownMenuItem(
                    value: 'reading',
                    child: Text('Reading now'),
                  ),
                  DropdownMenuItem(value: 'finished', child: Text('Finished')),
                ],
                onChanged: (v) {
                  setState(() {
                    status = BookStatus.values.byName(v!);
                    finish = null;
                    dateKey++;
                  });
                  changed();
                },
              ),
              if (status == BookStatus.finished) ...[
                const SizedBox(height: 24),
                FinishDateField(
                  key: ValueKey(dateKey),
                  onChanged: (v) => setState(() {
                    finish = v;
                    dirty = true;
                  }),
                ),
              ],
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Add another book after saving'),
                value: another,
                onChanged: (v) => setState(() => another = v!),
              ),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: busy ? null : save,
              icon: const Icon(Icons.add),
              label: Text(
                busy
                    ? 'Saving…'
                    : widget.book == null
                    ? 'Save book'
                    : 'Save changes',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
