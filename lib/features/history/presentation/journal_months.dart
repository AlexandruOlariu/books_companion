import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/book_cover.dart';
import '../../../core/widgets/common.dart';
import '../../library/domain/models.dart';
import '../../library/presentation/library_screen.dart';
import '../domain/journal_buckets.dart';

/// The Journal's main picture: the books you finished, grouped by when you
/// remember finishing them. For one year it is twelve month tiles; for all
/// time it is one row per year. Nothing is placed more precisely than it was
/// remembered.
class MonthsView extends StatelessWidget {
  final LibrarySnapshot data;
  final int? year;
  final ValueChanged<int> onPickYear;
  const MonthsView({
    super.key,
    required this.data,
    required this.year,
    required this.onPickYear,
  });

  @override
  Widget build(BuildContext context) {
    final books = {for (final b in data.books) b.id: b};
    List<BookEntry> resolve(List<Completion> cs) => [
      for (final c in cs)
        if (books[c.userBookId] != null) books[c.userBookId]!,
    ];
    void open(String title, List<Completion> cs) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FormSheet(
        title: title,
        children: [for (final b in resolve(cs)) BookListTile(book: b)],
      ),
    );
    final all = data.completions;
    return year == null
        ? _Years(all: all, resolve: resolve, open: open, onPickYear: onPickYear)
        : _Months(all: all, year: year!, resolve: resolve, open: open);
  }
}

typedef _Resolve = List<BookEntry> Function(List<Completion>);
typedef _Open = void Function(String title, List<Completion> cs);

class _Months extends StatelessWidget {
  final List<Completion> all;
  final int year;
  final _Resolve resolve;
  final _Open open;
  const _Months({
    required this.all,
    required this.year,
    required this.resolve,
    required this.open,
  });
  @override
  Widget build(BuildContext context) {
    final months = JournalBuckets.months(all, year);
    final yearOnly = JournalBuckets.yearOnly(all, year);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Each book sits in the month you remember finishing it. Tap a month to see its books.',
          style: TextStyle(color: RoomColors.muted, height: 1.5),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) {
            const gap = 10.0;
            final width = (c.maxWidth - 2 * gap) / 3;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var m = 0; m < 12; m++)
                  _Tile(
                    width: width,
                    height: 124,
                    label: DateFormat.MMM().format(DateTime(year, m + 1)),
                    semantic: DateFormat.yMMMM().format(DateTime(year, m + 1)),
                    books: resolve(months[m]),
                    onTap: months[m].isEmpty
                        ? null
                        : () => open(
                            DateFormat.yMMMM().format(DateTime(year, m + 1)),
                            months[m],
                          ),
                  ),
              ],
            );
          },
        ),
        if (yearOnly.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Tile(
            width: double.infinity,
            height: 96,
            label: 'Sometime in $year',
            caption: 'Remembered as a year only. The month is unknown.',
            semantic: 'Sometime in $year, month unknown',
            books: resolve(yearOnly),
            wide: true,
            onTap: () => open('Sometime in $year', yearOnly),
          ),
        ],
        if (months.every((m) => m.isEmpty) && yearOnly.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 20),
            child: Text(
              'No finished books are recorded for this year yet.',
              style: TextStyle(color: RoomColors.muted),
            ),
          ),
      ],
    );
  }
}

class _Years extends StatelessWidget {
  final List<Completion> all;
  final _Resolve resolve;
  final _Open open;
  final ValueChanged<int> onPickYear;
  const _Years({
    required this.all,
    required this.resolve,
    required this.open,
    required this.onPickYear,
  });
  @override
  Widget build(BuildContext context) {
    final years = JournalBuckets.years(all);
    final undated = JournalBuckets.undated(all);
    if (years.isEmpty && undated.isEmpty) {
      return const Text(
        'Finished books will appear here, year by year.',
        style: TextStyle(color: RoomColors.muted),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your reading life, year by year. Tap a year to see it month by month.',
          style: TextStyle(color: RoomColors.muted, height: 1.5),
        ),
        const SizedBox(height: 16),
        for (final (y, finishes) in years)
          _YearRow(
            title: '$y',
            books: resolve(finishes),
            onTap: () => onPickYear(y),
          ),
        if (undated.isNotEmpty)
          _YearRow(
            title: 'Date unknown',
            books: resolve(undated),
            onTap: () => open('Date unknown', undated),
          ),
      ],
    );
  }
}

class _YearRow extends StatelessWidget {
  final String title;
  final List<BookEntry> books;
  final VoidCallback onTap;
  const _YearRow({
    required this.title,
    required this.books,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '$title, ${books.length} ${books.length == 1 ? 'book' : 'books'}',
    child: Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: RoomColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: RoomColors.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${books.length} ${books.length == 1 ? 'book' : 'books'}',
                          style: const TextStyle(color: RoomColors.muted),
                        ),
                      ],
                    ),
                  ),
                  _Covers(
                    books: books,
                    max: 5,
                    width: 30,
                    height: 45,
                    step: 24,
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, color: RoomColors.muted),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _Tile extends StatelessWidget {
  final double width, height;
  final String label, semantic;
  final String? caption;
  final List<BookEntry> books;
  final bool wide;
  final VoidCallback? onTap;
  const _Tile({
    required this.width,
    required this.height,
    required this.label,
    required this.semantic,
    required this.books,
    this.caption,
    this.wide = false,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final empty = books.isEmpty;
    return Semantics(
      button: !empty,
      label: empty
          ? '$semantic, no books'
          : '$semantic, ${books.length} ${books.length == 1 ? 'book' : 'books'}: ${books.take(3).map((b) => b.title).join(', ')}',
      // Month tiles are a fixed square-ish size; the wide tile grows with its
      // text so large type is never cut off.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: width,
          maxWidth: width,
          minHeight: height,
          maxHeight: wide ? double.infinity : height,
        ),
        child: Material(
          color: empty ? Colors.transparent : RoomColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: empty ? const Color(0xFFE8E3D8) : RoomColors.line,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: wide
                    ? Row(
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  label,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                if (caption != null)
                                  Text(
                                    caption!,
                                    style: const TextStyle(
                                      color: RoomColors.muted,
                                      fontSize: 12.5,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          _Covers(
                            books: books,
                            max: 3,
                            width: 30,
                            height: 45,
                            step: 24,
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 22,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    label.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.6,
                                      color: empty
                                          ? const Color(0xFFA8A89E)
                                          : RoomColors.muted,
                                    ),
                                  ),
                                ),
                                if (!empty)
                                  Text(
                                    '${books.length}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          if (!empty)
                            _Covers(
                              books: books,
                              max: 3,
                              width: 38,
                              height: 57,
                              step: 24,
                            ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small fan of covers, overlapping, with "+N" for the rest. It shows as
/// many covers as fit the space it is given, so a narrow tile never overflows.
class _Covers extends StatelessWidget {
  final List<BookEntry> books;
  final int max;
  final double width, height, step;
  const _Covers({
    required this.books,
    required this.max,
    required this.width,
    required this.height,
    required this.step,
  });
  static const _more = 30.0;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final room = c.hasBoundedWidth ? c.maxWidth : double.infinity;
      var n = max < books.length ? max : books.length;
      double span(int n) =>
          width + step * (n - 1) + (books.length > n ? _more : 0);
      while (n > 1 && span(n) > room) {
        n--;
      }
      final shown = books.take(n).toList();
      final extra = books.length - n;
      return SizedBox(
        height: height,
        width: span(n),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < shown.length; i++)
              Positioned(
                left: i * step,
                child: BookCover(book: shown[i], width: width, height: height),
              ),
            if (extra > 0)
              Positioned(
                left: width + step * (n - 1) + 6,
                bottom: 0,
                child: Text(
                  '+$extra',
                  style: const TextStyle(
                    color: RoomColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
