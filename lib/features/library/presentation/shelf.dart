import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/book_cover.dart';
import '../../../core/widgets/book_opening.dart';
import '../../../core/widgets/common.dart';
import '../domain/models.dart';
import 'keepsakes.dart';

const double _gap = 3, _plank = 12, _beam = 10, _frame = 8, _inset = 4;

sealed class ShelfSlot {
  double get width;
  double get height;
}

class BookSlot extends ShelfSlot {
  final BookEntry book;
  final bool faceOut;
  BookSlot(this.book) : faceOut = shelvedFaceOut(book);
  @override
  double get width =>
      faceOut ? 96 : (48 + (book.pageCount ?? 250) / 35).clamp(48, 68);
  @override
  double get height => faceOut
      ? 144 + (bookSeed(book.title) >> 12) % 14
      : 138 + (bookSeed(book.title) >> 4) % 40;
}

class KeepsakeSlot extends ShelfSlot {
  final Keepsake keepsake;
  KeepsakeSlot(this.keepsake);
  @override
  double get width => keepsake.size.width;
  @override
  double get height => keepsake.size.height;
}

/// Books being read stand face-out so their cover and bookmark are visible; a
/// steady share of the rest do too, as on a real shelf. Everything else shows
/// its spine.
bool shelvedFaceOut(BookEntry book) =>
    book.status == BookStatus.reading || (bookSeed(book.title) >> 8) % 7 == 0;

class ShelfRow {
  final List<ShelfSlot> slots = [];
  double get used =>
      slots.fold<double>(0, (n, s) => n + s.width) +
      _gap * (slots.length - 1).clamp(0, 1 << 20);
  double get height =>
      slots.fold<double>(0, (a, s) => a > s.height ? a : s.height);
}

/// Packs books and keepsakes left to right into rows no wider than [width].
/// Keepsakes are spaced evenly through the books, so they read as ornaments
/// among them rather than piling up at the end.
List<ShelfRow> packShelves(
  List<BookEntry> books,
  double width,
  List<Keepsake> keepsakes,
) {
  final slots = <ShelfSlot>[];
  var placed = 0;
  for (var i = 0; i < books.length; i++) {
    slots.add(BookSlot(books[i]));
    // After the (k+1)/(n+1) share of the books, set the next keepsake down.
    while (placed < keepsakes.length &&
        i + 1 >=
            ((placed + 1) * books.length / (keepsakes.length + 1)).round()) {
      slots.add(KeepsakeSlot(keepsakes[placed++]));
    }
  }
  final rows = <ShelfRow>[];
  for (final slot in slots) {
    if (rows.isEmpty ||
        (rows.last.slots.isNotEmpty &&
            rows.last.used + _gap + slot.width > width)) {
      rows.add(ShelfRow());
    }
    rows.last.slots.add(slot);
  }
  return rows;
}

class SliverShelf extends StatelessWidget {
  final List<BookEntry> books;

  /// Opens a book's details out of the spot it stands in. The shelf waits for
  /// it to finish, so the book can slide back when the reader returns.
  final Future<void> Function(BookOpening opening) onOpen;
  final List<Keepsake> keepsakes;
  const SliverShelf({
    super.key,
    required this.books,
    required this.onOpen,
    this.keepsakes = const [],
  });
  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final inner = constraints.crossAxisExtent - 2 * (_frame + _inset);
      final rows = packShelves(books, inner, keepsakes);
      return SliverList.builder(
        itemCount: rows.length,
        itemBuilder: (context, i) =>
            _ShelfRowView(row: rows[i], first: i == 0, onOpen: onOpen),
      );
    },
  );
}

class _ShelfRowView extends StatelessWidget {
  final ShelfRow row;
  final bool first;
  final Future<void> Function(BookOpening opening) onOpen;
  const _ShelfRowView({
    required this.row,
    required this.first,
    required this.onOpen,
  });

  Widget _slot(BuildContext context, ShelfSlot slot) => switch (slot) {
    BookSlot() => _ShelfBook(slot: slot, onOpen: onOpen),
    KeepsakeSlot() => _keepsake(context, slot),
  };

  Widget _keepsake(BuildContext context, KeepsakeSlot slot) => KeepsakeView(
    keepsake: slot.keepsake,
    onTap: () => notifyUser(
      context,
      '${slot.keepsake.label}. ${slot.keepsake.earnedBy}',
    ),
  );

  @override
  Widget build(BuildContext context) {
    // Room above the tallest book for a pulled-out one to rise into.
    final height = row.height + _plank + (first ? _beam : 0) + 22;
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [RoomColors.shelfBackDeep, RoomColors.shelfBack],
                  stops: [0, .5],
                ),
                border: Border.symmetric(
                  vertical: BorderSide(
                    color: RoomColors.woodDark,
                    width: _frame,
                  ),
                ),
              ),
            ),
          ),
          if (first)
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: _beam,
              child: _Wood(vertical: false),
            ),
          Positioned(
            left: _frame + _inset,
            right: _frame + _inset,
            bottom: _plank,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < row.slots.length; i++) ...[
                  if (i > 0) const SizedBox(width: _gap),
                  _slot(context, row.slots[i]),
                ],
              ],
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _plank,
            child: _Wood(vertical: true),
          ),
        ],
      ),
    );
  }
}

/// A plank: light top edge fading to darker wood, with a soft shadow beneath.
class _Wood extends StatelessWidget {
  final bool vertical;
  const _Wood({required this.vertical});
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [RoomColors.woodLight, RoomColors.wood, RoomColors.woodDark],
        stops: [0, .35, 1],
      ),
      boxShadow: vertical
          ? const [
              BoxShadow(
                color: Color(0x33000000),
                offset: Offset(0, 3),
                blurRadius: 4,
              ),
            ]
          : null,
    ),
  );
}

/// A book on the shelf. Tapping pulls it out a little, tilted, and then opens
/// its details with the book opening (see `bookOpeningTransition`). It settles
/// back when the reader returns.
class _ShelfBook extends StatefulWidget {
  final BookSlot slot;
  final Future<void> Function(BookOpening opening) onOpen;
  const _ShelfBook({required this.slot, required this.onOpen});
  @override
  State<_ShelfBook> createState() => _ShelfBookState();
}

class _ShelfBookState extends State<_ShelfBook> {
  static const _pull = Duration(milliseconds: 180);
  bool pulled = false;
  final coverKey = GlobalKey();

  Future<void> _open() async {
    if (pulled) return;
    final still = MediaQuery.disableAnimationsOf(context);
    setState(() => pulled = true);
    if (!still) await Future<void>.delayed(_pull);
    if (!mounted) return;
    // Where the cover is now, tilt and all, so the page opens from that spot.
    final box = coverKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) {
      setState(() => pulled = false);
      return;
    }
    final from = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    unawaited(HapticFeedback.lightImpact());
    await widget.onOpen(
      BookOpening(
        book: widget.slot.book,
        from: from,
        fromSpine: !widget.slot.faceOut,
      ),
    );
    if (mounted) setState(() => pulled = false);
  }

  @override
  Widget build(BuildContext context) {
    final slot = widget.slot;
    final book = slot.book;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return Semantics(
      button: true,
      label:
          '${book.title}, ${book.author}, ${book.status.label}. Opens details.',
      child: InkWell(
        onTap: _open,
        borderRadius: BorderRadius.circular(4),
        child: AnimatedPadding(
          duration: duration,
          curve: Curves.easeOutBack,
          padding: EdgeInsets.only(bottom: pulled ? 8 : 0),
          child: AnimatedRotation(
            duration: duration,
            curve: Curves.easeOutBack,
            turns: pulled ? -.007 : 0,
            alignment: Alignment.bottomCenter,
            child: AnimatedScale(
              duration: duration,
              curve: Curves.easeOutBack,
              scale: pulled ? 1.06 : 1,
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                key: coverKey,
                width: slot.width,
                height: slot.height,
                child: BookCover(
                  book: book,
                  width: slot.width,
                  height: slot.height,
                  spine: !slot.faceOut,
                  showStatus: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A calm line under the shelf: what has been earned, and what is next.
class KeepsakeNote extends StatelessWidget {
  final int finished;
  const KeepsakeNote({super.key, required this.finished});
  @override
  Widget build(BuildContext context) {
    final next = Keepsake.next(finished);
    final earned = Keepsake.earned(finished).length;
    final left = next == null ? 0 : next.unlockAt - finished;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Text(
        '${next == null ? 'All ${Keepsake.values.length} keepsakes are on your shelf.' : 'Keepsakes: $earned of ${Keepsake.values.length}. Finish $left more ${left == 1 ? 'book' : 'books'} for a ${next.label.toLowerCase()}.'}\n'
        'Earned by books you finish, never by streaks.',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: RoomColors.muted,
          fontSize: 12.5,
          height: 1.5,
        ),
      ),
    );
  }
}
