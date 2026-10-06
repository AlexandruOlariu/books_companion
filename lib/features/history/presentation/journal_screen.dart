import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../library/domain/models.dart';
import '../../library/presentation/library_screen.dart';
import '../../sharing/data/share_image.dart';
import 'journal_months.dart';

/// The three ways to look at the Journal.
enum JournalView { months, days, history }

class JournalScreen extends StatefulWidget {
  final LibrarySnapshot data;
  final int? initialYear;
  const JournalScreen({super.key, required this.data, this.initialYear});
  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  late int? year = widget.initialYear;
  late DateTime month = DateTime(
    widget.initialYear ?? DateTime.now().year,
    DateTime.now().month,
  );
  JournalView view = JournalView.months;
  @override
  Widget build(BuildContext context) {
    final data = widget.data, records = widget.data.finishesIn(year);
    final bookMap = {for (final b in data.books) b.id: b};
    final groups = <String, List<Completion>>{};
    records.sort(
      (a, b) => (b.finish.value ?? '').compareTo(a.finish.value ?? ''),
    );
    for (final record in records) {
      final date = record.finish;
      final group = date.year == null
          ? 'Date unknown'
          : date.month == null
          ? '${date.year} · Month unknown'
          : DateFormat.yMMMM().format(DateTime(date.year!, date.month!));
      (groups[group] ??= []).add(record);
    }
    final completedPages = records.fold<int>(
      0,
      (n, r) => n + (bookMap[r.userBookId]?.pageCount ?? 0),
    );
    final unknownPages = records
        .where((r) => bookMap[r.userBookId]?.pageCount == null)
        .length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      children: [
        const Eyebrow('A life in stories'),
        const SizedBox(height: 12),
        Text(
          'Reading journal',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 12),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          children: [
            SizedBox(
              width: 140,
              child: DropdownButton<int>(
                value: year ?? 0,
                isExpanded: true,
                underline: const SizedBox(),
                items: [
                  const DropdownMenuItem(value: 0, child: Text('All time')),
                  ...({
                    ...data.years,
                    ?year,
                  }.toList()..sort((a, b) => b.compareTo(a))).map(
                    (y) => DropdownMenuItem(value: y, child: Text('$y')),
                  ),
                ],
                onChanged: (v) => setState(() {
                  year = v == 0 ? null : v;
                  month = DateTime(year ?? DateTime.now().year, month.month);
                }),
              ),
            ),
            if (records.isNotEmpty)
              TextButton.icon(
                onPressed: () async {
                  try {
                    await ShareImage.yearShelf(data, year, context);
                  } catch (_) {
                    if (context.mounted) {
                      notifyUser(context, 'Could not create the share image.');
                    }
                  }
                },
                icon: const Icon(Icons.ios_share, size: 18),
                label: const Text('Share shelf'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _Stat('${records.length}', 'Books finished')),
            Expanded(child: _Stat('${data.pagesLogged(year)}', 'Pages logged')),
          ],
        ),
        const SizedBox(height: 24),
        SegmentedButton<JournalView>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: JournalView.months, label: Text('Months')),
            ButtonSegment(value: JournalView.days, label: Text('Days')),
            ButtonSegment(value: JournalView.history, label: Text('History')),
          ],
          selected: {view},
          onSelectionChanged: (v) => setState(() => view = v.first),
        ),
        const SizedBox(height: 24),
        if (view == JournalView.months)
          MonthsView(
            data: data,
            year: year,
            onPickYear: (y) => setState(() {
              year = y;
              month = DateTime(y, month.month);
            }),
          ),
        if (view == JournalView.days) ...[
          const Text(
            'The days you logged a reading session. Log one from the Reading tab and that day lights up.',
            style: TextStyle(color: RoomColors.muted, height: 1.5),
          ),
          if (data.sessions.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'No sessions logged yet, so the calendar is empty. Books you finished in the past do not count as reading days.',
                style: TextStyle(color: RoomColors.muted, height: 1.5),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                onPressed: () => setState(() {
                  month = DateTime(month.year, month.month - 1);
                  if (year != null) year = month.year;
                }),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  DateFormat.yMMMM().format(month),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: () => setState(() {
                  month = DateTime(month.year, month.month + 1);
                  if (year != null) year = month.year;
                }),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          _Calendar(month: month, data: data),
          const SizedBox(height: 16),
          const Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              Text(
                '■  A day you read',
                style: TextStyle(color: RoomColors.forest, fontSize: 12.5),
              ),
              Text(
                '•  You finished a book that day',
                style: TextStyle(color: RoomColors.terra, fontSize: 12.5),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Only logged sessions color a day. Finishing a book marks the day with a dot but is not counted as reading.',
            style: TextStyle(
              color: RoomColors.muted,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
        if (view == JournalView.history) ...[
          if (records.isEmpty)
            const EmptyRoom(
              title: 'Memories, in the making.',
              message: 'Finished books will appear here. It’s fine if you don’t remember the exact date.',
            ),
          for (final group in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 4),
              child: Text(
                group.key,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final r in group.value)
              if (bookMap[r.userBookId] != null)
                BookListTile(
                  book: bookMap[r.userBookId]!,
                  subtitle:
                      '${r.finish.label} · ${r.source == 'entered_past' ? 'Remembered' : 'Finished'}',
                ),
            const Divider(),
          ],
        ],
        const SizedBox(height: 24),
        const Eyebrow('A little perspective'),
        const SizedBox(height: 16),
        Text(
          '${data.secondsLogged(year) ~/ 60} minutes logged',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          '$completedPages pages in completed editions${unknownPages > 0 ? ' · $unknownPages without a page count' : ''}',
        ),
        const SizedBox(height: 8),
        const Text(
          'Time includes only sessions with a duration. Completed-edition pages are separate from pages logged.',
          style: TextStyle(color: RoomColors.muted, height: 1.5),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String value, label;
  const _Stat(this.value, this.label);
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(color: RoomColors.muted)),
    ],
  );
}

class _Calendar extends StatelessWidget {
  final DateTime month;
  final LibrarySnapshot data;
  const _Calendar({required this.month, required this.data});
  @override
  Widget build(BuildContext context) {
    final offset = DateTime(month.year, month.month).weekday - 1;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final count = ((offset + days) / 7).ceil() * 7;
    return Column(
      children: [
        Row(
          children: [
            for (final day in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      day,
                      style: const TextStyle(
                        fontSize: 12,
                        color: RoomColors.muted,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            // Narrow phones scroll the calendar horizontally to keep 48px targets.
            final width = constraints.maxWidth < 364
                ? 364.0
                : constraints.maxWidth;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                child: Wrap(
                  children: List.generate(count, (i) {
                    final day = i - offset + 1;
                    if (day < 1 || day > days) {
                      return SizedBox(width: width / 7, height: 52);
                    }
                    final date = DateTime(month.year, month.month, day);
                    final sessions = data.sessions
                        .where((s) => DateUtils.isSameDay(s.startedAt, date))
                        .toList();
                    final finishes = data.completions
                        .where(
                          (c) =>
                              c.finish.precision == DatePrecision.day &&
                              c.finish.value ==
                                  DateFormat('yyyy-MM-dd').format(date),
                        )
                        .toList();
                    final pages = sessions.fold(0, (n, s) => n + s.pages);
                    return SizedBox(
                      width: width / 7,
                      height: 52,
                      child: Semantics(
                        button: true,
                        label:
                            '${DateFormat.yMMMMd().format(date)}, ${sessions.length} sessions, $pages pages, ${finishes.length} completions',
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Material(
                            color: sessions.isEmpty
                                ? RoomColors.surface
                                : RoomColors.forest,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(9),
                              onTap: () => showModalBottomSheet<void>(
                                context: context,
                                isScrollControlled: true,
                                builder: (c) => FormSheet(
                                  title: DateFormat.MMMd().format(date),
                                  children: [
                                    Text(
                                      '$pages pages logged · ${sessions.length} sessions',
                                    ),
                                    const SizedBox(height: 16),
                                    if (sessions.isEmpty)
                                      const Text(
                                        'No reading activity logged on this day.',
                                      ),
                                    for (final s in sessions)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        child: Text(
                                          '${data.books.where((b) => b.id == s.userBookId).first.title}\n${s.pages} pages${s.durationSeconds == null ? ' · duration unknown' : ' · ${s.durationSeconds! ~/ 60} minutes'}',
                                        ),
                                      ),
                                    if (finishes.isNotEmpty) ...[
                                      const Divider(),
                                      const Text('Finished on this date'),
                                      for (final f in finishes)
                                        Text(
                                          data.books
                                              .where(
                                                (b) => b.id == f.userBookId,
                                              )
                                              .first
                                              .title,
                                        ),
                                    ],
                                  ],
                                ),
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Text(
                                    '$day',
                                    style: TextStyle(
                                      color: sessions.isEmpty
                                          ? RoomColors.ink
                                          : Colors.white,
                                    ),
                                  ),
                                  // A dot, not a colour: finishing a book is not reading time.
                                  if (finishes.isNotEmpty)
                                    Positioned(
                                      bottom: 6,
                                      child: Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: sessions.isEmpty
                                              ? RoomColors.terra
                                              : Colors.white,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
