import 'dart:io';

import 'package:flutter/material.dart';

import '../../features/library/domain/models.dart';
import 'status_badge.dart';

const bookPalette = [
  Color(0xFF35554C),
  Color(0xFF934B3A),
  Color(0xFF27475B),
  Color(0xFF745637),
  Color(0xFF655273),
  Color(0xFF4B645E),
  Color(0xFF8A6420),
  Color(0xFF6E2F3B),
  Color(0xFF22304F),
  Color(0xFF5E6134),
  Color(0xFF4F5F6B),
  Color(0xFF2B6B6B),
  Color(0xFF9A4A28),
  Color(0xFF3A3F3D),
];

/// A stable hash of the title (FNV-1a), so neighbouring titles don't share
/// colours and heights the way a simple character sum would.
int bookSeed(String title) {
  var h = 0x811C9DC5;
  for (final unit in title.codeUnits) {
    h = ((h ^ unit) * 0x01000193) & 0x7FFFFFFF;
  }
  return h;
}

class BookCover extends StatelessWidget {
  final BookEntry book;
  final double width, height;
  final bool spine;

  /// Adds a [StatusBadge], so the shelf shows at a glance which books are being
  /// read or wished for. A finished book has no seal (finished is the quiet,
  /// default state), see [hasStatusBadge].
  final bool showStatus;
  const BookCover({
    super.key,
    required this.book,
    this.width = 100,
    this.height = 148,
    this.spine = false,
    this.showStatus = false,
  });
  @override
  Widget build(BuildContext context) {
    final sealed = showStatus && hasStatusBadge(book.status);
    final color = bookPalette[bookSeed(book.title) % bookPalette.length];
    final cover = book.coverPath;
    // Generated typography is cover artwork; the accessible title is outside it.
    final fallback = ColoredBox(
      color: color,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: 120,
          height: 180,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 24, height: 2, color: const Color(0xFFE1C89D)),
                const SizedBox(height: 16),
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      book.title,
                      textScaler: TextScaler.noScaling,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Literata',
                        color: Color(0xFFFFF8E8),
                        fontSize: 17,
                        height: 1.15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  book.author.toUpperCase(),
                  textScaler: TextScaler.noScaling,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFEAE4D4),
                    fontSize: 9,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return ExcludeSemantics(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          boxShadow: const [
            BoxShadow(
              color: Color(0x28000000),
              offset: Offset(4, 6),
              blurRadius: 7,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (spine)
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color.lerp(color, Colors.black, .22)!,
                        color,
                        Color.lerp(color, Colors.white, .10)!,
                        color,
                        Color.lerp(color, Colors.black, .26)!,
                      ],
                      stops: const [0, .22, .5, .8, 1],
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Gilt bands near the head and tail, as on a bound spine.
                      for (final y in [12.0, 17.0])
                        Positioned(
                          left: 0,
                          right: 0,
                          top: y,
                          height: 1.5,
                          child: const ColoredBox(color: Color(0xAAE1C89D)),
                        ),
                      for (final y in [17.0, 12.0])
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: y,
                          height: 1.5,
                          child: const ColoredBox(color: Color(0xAAE1C89D)),
                        ),
                      RotatedBox(
                        quarterTurns: 3,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            sealed ? 44 : 28,
                            6,
                            28,
                            6,
                          ),
                          child: Center(
                            child: Text(
                              book.title,
                              textScaler: TextScaler.noScaling,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Literata',
                                color: Color(0xFFFFF8E8),
                                fontSize: 12.5,
                                height: 1.15,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else if (cover != null)
                Container(
                  color: color,
                  child: Image.file(
                    File(cover),
                    fit: BoxFit.contain,
                    cacheWidth: (width * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                    errorBuilder: (_, _, _) => fallback,
                  ),
                )
              else
                fallback,
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 7,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: .22),
                        Colors.white.withValues(alpha: .13),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              if (!spine)
                Positioned(
                  right: 0,
                  top: 2,
                  bottom: 2,
                  width: 3,
                  child: Container(color: const Color(0x88E8DFCE)),
                ),
              if (book.status == BookStatus.reading && !spine)
                Positioned(
                  right: 10,
                  top: 0,
                  child: Container(
                    width: 9,
                    height: 25,
                    color: const Color(0xFFDBBA78),
                  ),
                ),
              if (sealed)
                Positioned(
                  bottom: spine ? 22 : 8,
                  left: spine ? (width - 20) / 2 : null,
                  right: spine ? null : 8,
                  child: StatusBadge(status: book.status),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
