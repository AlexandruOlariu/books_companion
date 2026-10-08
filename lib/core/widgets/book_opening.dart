import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../features/library/domain/models.dart';
import 'book_cover.dart';

/// Where a tapped book is on screen, handed to the details route so the page
/// can open out of that exact spot (and close back into it).
class BookOpening {
  final BookEntry book;

  /// The book's bounds on screen when it was tapped.
  final Rect from;

  /// True for a spine, which turns into a cover as it grows.
  final bool fromSpine;
  const BookOpening({
    required this.book,
    required this.from,
    required this.fromSpine,
  });
}

/// The book opens like a real one. First the cover grows from its place on the
/// shelf until it fills the screen; then it swings open on its left edge and
/// the details page shows where the pages would be. Played backwards on pop.
Widget bookOpeningTransition(
  BuildContext context,
  Animation<double> animation,
  BookOpening opening,
  Widget page,
) {
  final screen = Offset.zero & MediaQuery.sizeOf(context);
  return AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      final t = animation.value;
      final grow = Curves.easeInOutCubic.transform(
        const Interval(0, .5).transform(t),
      );
      final open = Curves.easeInOutCubic.transform(
        const Interval(.45, 1).transform(t),
      );
      final pageOpacity = const Interval(
        .3,
        .8,
        curve: Curves.easeOut,
      ).transform(t);
      // Fades only at the end of the swing, so it never vanishes half open.
      final coverOpacity = open < .7 ? 1.0 : 1 - (open - .7) / .3;
      return Stack(
        fit: StackFit.expand,
        children: [
          Opacity(opacity: pageOpacity, child: page),
          if (coverOpacity > 0)
            Positioned.fromRect(
              rect: Rect.lerp(opening.from, screen, grow)!,
              child: IgnorePointer(
                // The cover is drawn above the page, outside any Scaffold, so
                // it needs a Material for a plain text style (without it the
                // title gets the yellow double underline of unstyled text).
                child: Material(
                  type: MaterialType.transparency,
                  child: Opacity(
                    opacity: coverOpacity,
                    child: Transform(
                      alignment: Alignment.centerLeft,
                      // A little perspective, and the free edge comes towards
                      // the reader as the cover swings open.
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, .0012)
                        ..rotateY(-open * math.pi * .56),
                      child: _GrowingCover(
                        book: opening.book,
                        progress: grow,
                        fromSpine: opening.fromSpine,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

/// A spine fades into the cover as the box grows, instead of stretching.
class _GrowingCover extends StatelessWidget {
  final BookEntry book;
  final double progress;
  final bool fromSpine;
  const _GrowingCover({
    required this.book,
    required this.progress,
    required this.fromSpine,
  });
  @override
  Widget build(BuildContext context) {
    // The cover stays solid underneath while the spine fades off it, so the
    // shelf never shows through a half-faded book.
    final spineOpacity = fromSpine ? (1 - progress * 2.5).clamp(0.0, 1.0) : 0.0;
    return LayoutBuilder(
      builder: (context, box) => Stack(
        fit: StackFit.expand,
        children: [
          BookCover(book: book, width: box.maxWidth, height: box.maxHeight),
          if (spineOpacity > 0)
            Opacity(
              opacity: spineOpacity,
              child: BookCover(
                book: book,
                width: box.maxWidth,
                height: box.maxHeight,
                spine: true,
              ),
            ),
        ],
      ),
    );
  }
}
