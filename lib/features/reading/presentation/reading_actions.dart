import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../core/storage/draft_store.dart';
import '../../../core/widgets/common.dart';
import '../../history/presentation/finish_date_field.dart';
import '../../library/domain/models.dart';

enum ReadingAction { page, session, pin, finish }

Future<void> showReadingAction(
  BuildContext context,
  BookEntry book,
  ReadingAction action,
) {
  // A previous confirmation must not obscure the next sheet's Save button.
  ScaffoldMessenger.of(context).removeCurrentSnackBar();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => _ActionSheet(book: book, action: action),
  );
}

class _ActionSheet extends ConsumerStatefulWidget {
  final BookEntry book;
  final ReadingAction action;
  const _ActionSheet({required this.book, required this.action});
  @override
  ConsumerState<_ActionSheet> createState() => _ActionSheetState();
}

class _ActionSheetState extends ConsumerState<_ActionSheet> {
  late final page = TextEditingController(
    text: widget.action == ReadingAction.page
        ? '${widget.book.currentPage}'
        : '',
  );
  final start = TextEditingController(),
      end = TextEditingController(),
      minutes = TextEditingController(),
      note = TextEditingController(),
      percent = TextEditingController();
  String type = 'Thought';
  DateTime date = DateUtils.dateOnly(DateTime.now());
  PartialDate? finish;
  bool dirty = false,
      busy = false,
      allowPop = false,
      duration = false,
      restored = false;
  String? error;
  // Finishing needs a freshly confirmed date, so it is never drafted.
  DraftBinding? draft;

  @override
  void initState() {
    super.initState();
    if (widget.action == ReadingAction.finish) return;
    draft = DraftBinding(
      ref.read(draftStoreProvider),
      'action:${widget.book.id}:${widget.action.name}',
    );
    draft!.restore().then((f) {
      if (f == null || !mounted) return;
      setState(() {
        page.text = f['page'] ?? page.text;
        start.text = f['start'] ?? '';
        end.text = f['end'] ?? '';
        minutes.text = f['minutes'] ?? '';
        note.text = f['note'] ?? '';
        percent.text = f['percent'] ?? '';
        type = f['type'] ?? type;
        final saved = DateTime.tryParse(f['date'] ?? '');
        if (saved != null && !saved.isAfter(DateTime.now())) date = saved;
        duration = minutes.text.isNotEmpty;
        restored = dirty = true;
      });
    });
  }

  void changed() {
    setState(() => dirty = true);
    final d = draft;
    if (d == null) return;
    final fields = {
      'page': page.text,
      'start': start.text,
      'end': end.text,
      'minutes': minutes.text,
      'note': note.text,
      'percent': percent.text,
      'type': type,
      'date': DateUtils.dateOnly(date).toIso8601String(),
    };
    // The prefilled current page alone is not worth restoring.
    final typed = widget.action == ReadingAction.page
        ? page.text.trim() != '${widget.book.currentPage}'
        : [
            start,
            end,
            minutes,
            note,
            percent,
            page,
          ].any((c) => c.text.trim().isNotEmpty);
    typed ? d.update(fields) : d.discard();
  }

  @override
  void dispose() {
    for (final c in [page, start, end, minutes, note, percent]) {
      c.dispose();
    }
    super.dispose();
  }

  int? integer(TextEditingController c, String field) {
    if (c.text.trim().isEmpty) return null;
    final n = int.tryParse(c.text.trim());
    if (n == null) throw FormatException('$field must be a whole number.');
    return n;
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final repo = ref.read(repositoryProvider), book = widget.book;
      switch (widget.action) {
        case ReadingAction.page:
          final value = integer(page, 'Page');
          if (value == null) {
            throw const FormatException('Enter your current page.');
          }
          await repo.updatePage(book.id, value);
        case ReadingAction.session:
          final time = integer(minutes, 'Minutes');
          await repo.logSession(
            book.id,
            date,
            start: integer(start, 'Start page'),
            end: integer(end, 'End page'),
            seconds: time == null ? null : time * 60,
          );
        case ReadingAction.pin:
          final progress = percent.text.trim().isEmpty
              ? null
              : double.tryParse(percent.text);
          if (percent.text.trim().isNotEmpty && progress == null) {
            throw const FormatException('Enter a valid percentage.');
          }
          await repo.addPin(
            book.id,
            note.text,
            type,
            page: integer(page, 'Page'),
            percent: progress,
          );
        case ReadingAction.finish:
          if (finish == null) {
            throw const FormatException(
              'Choose and confirm when you finished it.',
            );
          }
          await repo.setStatus(book.id, BookStatus.finished, finish: finish);
      }
      await draft?.discard();
      ref.invalidate(libraryProvider);
      if (!mounted) return;
      final message = switch (widget.action) {
        ReadingAction.page => 'Position saved. Reading activity is unchanged.',
        ReadingAction.session => 'Reading session logged.',
        ReadingAction.pin => 'Pin saved, just for you.',
        ReadingAction.finish => 'A story finished. Added to your history.',
      };
      final container = ProviderScope.containerOf(context, listen: false);
      notifyUser(
        context,
        message,
        action: widget.action == ReadingAction.page
            ? SnackBarAction(
                label: 'Undo',
                onPressed: () async {
                  try {
                    await repo.updatePage(book.id, book.currentPage);
                    container.invalidate(libraryProvider);
                  } catch (_) {
                    /* The book may have been deleted after saving. */
                  }
                },
              )
            : null,
      );
      setState(() {
        allowPop = true;
        dirty = false;
      });
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = readableError(e);
        });
      }
    }
  }

  Widget number(TextEditingController c, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      controller: c,
      keyboardType: TextInputType.number,
      onChanged: (_) => changed(),
      decoration: InputDecoration(labelText: label),
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: allowPop || (!dirty && !busy),
    onPopInvokedWithResult: (didPop, _) async {
      if (!didPop && !busy && await confirmDiscard(context) && mounted) {
        await draft?.discard();
        setState(() => allowPop = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context);
        });
      }
    },
    child: FormSheet(
      title: switch (widget.action) {
        ReadingAction.page => 'Update page',
        ReadingAction.session => 'Log a session',
        ReadingAction.pin => 'A thought to keep',
        ReadingAction.finish => 'Finish book',
      },
      children: [
        Text(widget.book.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        if (restored)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'Restored your unsaved draft.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        if (widget.action == ReadingAction.page) ...[
          number(page, 'Current page'),
          Text(
            widget.book.pageCount == null
                ? 'Total pages unknown'
                : 'Of ${widget.book.pageCount} pages',
          ),
          const SizedBox(height: 12),
          const Text(
            'This saves your place. Log a session separately to record reading activity.',
          ),
        ],
        if (widget.action == ReadingAction.session) ...[
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: date,
                firstDate: DateTime(1),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                setState(() => date = picked);
                changed();
              }
            },
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(DateFormat.yMMMd().format(date)),
          ),
          const SizedBox(height: 16),
          number(start, 'Starting page (optional)'),
          number(end, 'Ending page (optional)'),
          TextButton.icon(
            onPressed: () => setState(() => duration = !duration),
            icon: const Icon(Icons.schedule),
            label: Text(duration ? 'Hide duration' : 'Add reading duration'),
          ),
          if (duration) number(minutes, 'Minutes spent reading'),
          const Text(
            'Only log pages and time you actually read. Leave anything you don’t know blank.',
          ),
        ],
        if (widget.action == ReadingAction.pin) ...[
          TextField(
            controller: note,
            minLines: 4,
            maxLines: 10,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => changed(),
            decoration: const InputDecoration(
              labelText: 'Your note',
              hintText: 'What would you like to remember?',
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: type,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [
              'Thought',
              'Favorite',
              'Quote',
              'Question',
              'Idea',
            ].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
            onChanged: (v) {
              setState(() => type = v!);
              changed();
            },
          ),
          const SizedBox(height: 16),
          number(page, 'Page (optional)'),
          number(percent, 'Percentage (optional)'),
        ],
        if (widget.action == ReadingAction.finish)
          FinishDateField(
            onChanged: (v) => setState(() {
              finish = v;
              dirty = true;
            }),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(busy ? 'Saving…' : 'Save'),
        ),
      ],
    ),
  );
}
