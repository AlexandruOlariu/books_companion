import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/book_cover.dart';
import '../../../core/widgets/common.dart';
import '../../library/domain/models.dart';
import '../../recommendations/presentation/recommendations_section.dart';
import 'reading_actions.dart';

class ReadingScreen extends StatefulWidget {
  final LibrarySnapshot data;
  const ReadingScreen({super.key, required this.data});
  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends State<ReadingScreen> {
  String? expanded;
  @override
  Widget build(BuildContext context) {
    final books = widget.data.books
        .where((b) => b.status == BookStatus.reading)
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      children: [
        const Eyebrow('One page at a time'),
        const SizedBox(height: 12),
        Text(
          'In good company.',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 12),
        const Text(
          'Pick up where you left off.',
          style: TextStyle(color: RoomColors.muted),
        ),
        const SizedBox(height: 28),
        if (books.isEmpty)
          EmptyRoom(
            title: 'Your next chapter awaits.',
            message:
                'Add a book you’re reading, or start one from your library.',
            action: FilledButton(
              onPressed: () => context.push('/add'),
              child: const Text('Add a book'),
            ),
          ),
        for (final book in books)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Container(
              decoration: BoxDecoration(
                color: RoomColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: RoomColors.line),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InkWell(
                    onTap: () => setState(() => expanded = book.id),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BookCover(book: book, width: 88, height: 132),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                book.title,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                book.author,
                                style: const TextStyle(color: RoomColors.muted),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                book.progressLabel,
                                style: const TextStyle(fontSize: 13),
                              ),
                              if (book.progress != null) ...[
                                const SizedBox(height: 8),
                                LinearProgressIndicator(
                                  value: book.progress,
                                  minHeight: 4,
                                  borderRadius: BorderRadius.circular(4),
                                  backgroundColor: RoomColors.line,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () =>
                        showReadingAction(context, book, ReadingAction.page),
                    child: const Text('Update page'),
                  ),
                  if (book.id == (expanded ?? books.first.id)) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: () => showReadingAction(
                            context,
                            book,
                            ReadingAction.pin,
                          ),
                          icon: const Icon(Icons.push_pin_outlined, size: 18),
                          label: const Text('Add pin'),
                        ),
                        TextButton.icon(
                          onPressed: () => showReadingAction(
                            context,
                            book,
                            ReadingAction.session,
                          ),
                          icon: const Icon(Icons.schedule, size: 18),
                          label: const Text('Log session'),
                        ),
                        TextButton(
                          onPressed: () => showReadingAction(
                            context,
                            book,
                            ReadingAction.finish,
                          ),
                          child: const Text('Finish book'),
                        ),
                        TextButton(
                          onPressed: () => context.push('/book/${book.id}'),
                          child: const Text('Book details'),
                        ),
                      ],
                    ),
                  ] else
                    TextButton(
                      onPressed: () => setState(() => expanded = book.id),
                      child: const Text('More reading actions'),
                    ),
                ],
              ),
            ),
          ),
        RecommendationsSection(data: widget.data),
        if (books.isNotEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Make a little room for reading.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Literata',
                fontStyle: FontStyle.italic,
                color: RoomColors.muted,
              ),
            ),
          ),
      ],
    );
  }
}
