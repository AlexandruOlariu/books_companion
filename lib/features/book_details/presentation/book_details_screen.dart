import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/book_cover.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/rating_stars.dart';
import '../../library/domain/models.dart';
import '../../reading/presentation/reading_actions.dart';
import '../../sharing/data/share_image.dart';

class BookDetailsScreen extends ConsumerWidget {
  final String id;
  const BookDetailsScreen({super.key, required this.id});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(libraryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Your book')),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Could not load this book.')),
        data: (data) {
          final book = data.books.where((b) => b.id == id).firstOrNull;
          if (book == null) {
            return const Center(
              child: Text('This book is no longer in your library.'),
            );
          }
          final pins = data.pins.where((p) => p.userBookId == id).toList();
          final records = data.completions
              .where((c) => c.userBookId == id)
              .toList();
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: Hero(
                  tag: 'book-$id',
                  child: BookCover(book: book, width: 144, height: 212),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                book.title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                book.author,
                textAlign: TextAlign.center,
                style: const TextStyle(color: RoomColors.muted, fontSize: 16),
              ),
              const SizedBox(height: 12),
              Center(child: Chip(label: Text(book.status.label))),
              if (records.isNotEmpty) ...[
                const SizedBox(height: 12),
                Center(
                  child: RatingStars(
                    value: book.rating,
                    onChanged: (rating) async {
                      try {
                        await ref
                            .read(repositoryProvider)
                            .setRating(id, rating);
                        ref.invalidate(libraryProvider);
                      } catch (e) {
                        if (context.mounted) {
                          notifyUser(context, readableError(e));
                        }
                      }
                    },
                  ),
                ),
                Text(
                  book.rating == null
                      ? 'Your rating: not rated. Only you see it.'
                      : 'Your rating: ${book.rating} of $maxRating. Only you see it.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: RoomColors.muted, fontSize: 13),
                ),
              ],
              const SizedBox(height: 20),
              if (book.status == BookStatus.reading) ...[
                Text(book.progressLabel, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () =>
                      showReadingAction(context, book, ReadingAction.page),
                  child: const Text('Update page'),
                ),
              ] else
                FilledButton(
                  onPressed: () async {
                    try {
                      await ref
                          .read(repositoryProvider)
                          .setStatus(id, BookStatus.reading);
                      ref.invalidate(libraryProvider);
                    } catch (e) {
                      if (context.mounted) {
                        notifyUser(context, readableError(e));
                      }
                    }
                  },
                  child: Text(
                    book.status == BookStatus.finished
                        ? 'Read again'
                        : 'Start reading',
                  ),
                ),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                children: [
                  if (book.status == BookStatus.reading)
                    TextButton(
                      onPressed: () => showReadingAction(
                        context,
                        book,
                        ReadingAction.finish,
                      ),
                      child: const Text('Finish book'),
                    ),
                  if (book.status == BookStatus.finished)
                    TextButton.icon(
                      onPressed: () async {
                        try {
                          await ShareImage.finishedBook(book, context);
                        } catch (_) {
                          if (context.mounted) {
                            notifyUser(context, 'Could not share this book.');
                          }
                        }
                      },
                      icon: const Icon(Icons.ios_share, size: 18),
                      label: const Text('Share book'),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Pins',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        showReadingAction(context, book, ReadingAction.pin),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add pin'),
                  ),
                ],
              ),
              if (pins.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'A sentence, a question, a thought. Keep it here.',
                    style: TextStyle(color: RoomColors.muted),
                  ),
                ),
              for (final pin in pins)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
                  decoration: const BoxDecoration(
                    color: RoomColors.surface,
                    border: Border(
                      left: BorderSide(color: RoomColors.terra, width: 3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${pin.type}${pin.page == null ? '' : ' · p. ${pin.page}'}${pin.percent == null ? '' : ' · ${pin.percent}%'}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: RoomColors.muted,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete pin',
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () async {
                              final confirmed = await _confirmDelete(
                                context,
                                'Delete this pin?',
                                'This private note will be removed.',
                              );
                              if (confirmed) {
                                try {
                                  await ref
                                      .read(repositoryProvider)
                                      .deletePin(pin.id);
                                  ref.invalidate(libraryProvider);
                                } catch (e) {
                                  if (context.mounted) {
                                    notifyUser(context, readableError(e));
                                  }
                                }
                              }
                            },
                          ),
                        ],
                      ),
                      Text(
                        pin.text,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              Text('History', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (records.isEmpty) const Text('No finishes recorded yet.'),
              for (final record in records)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(record.finish.label),
                  subtitle: Text(
                    record.source == 'entered_past'
                        ? 'Entered from memory'
                        : 'Finished in your reading journal',
                  ),
                ),
              for (final s in data.sessions.where((s) => s.userBookId == id))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule),
                  title: Text(
                    '${s.startedAt.day}/${s.startedAt.month}/${s.startedAt.year} · ${s.pages} pages',
                  ),
                  subtitle: Text(
                    s.durationSeconds == null
                        ? 'Duration not recorded'
                        : '${s.durationSeconds! ~/ 60} minutes',
                  ),
                ),
              const SizedBox(height: 24),
              Text('Details', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(
                '${book.pageCount == null ? 'Page count unknown' : '${book.pageCount} pages'}${book.language == null ? '' : ' · ${book.language}'}',
              ),
              if (book.seriesLabel != null) Text('Series: ${book.seriesLabel}'),
              TextButton.icon(
                onPressed: () => context.push('/edit/$id'),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit edition and cover'),
              ),
              const Divider(),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () async {
                  if (await _confirmDelete(
                    context,
                    'Remove this book?',
                    'The book, its reading history, sessions, and private pins will be deleted.',
                  )) {
                    try {
                      await ref.read(repositoryProvider).deleteBook(id);
                      ref.invalidate(libraryProvider);
                      if (context.mounted) context.pop();
                    } catch (e) {
                      if (context.mounted) {
                        notifyUser(context, readableError(e));
                      }
                    }
                  }
                },
                child: Text(
                  'Remove from library',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<bool> _confirmDelete(
    BuildContext context,
    String title,
    String message,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;
}
