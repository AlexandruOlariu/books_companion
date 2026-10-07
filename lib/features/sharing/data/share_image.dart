import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/book_cover.dart';
import '../../library/domain/models.dart';
import '../../library/domain/sorting.dart';

class ShareImage {
  static void _text(
    Canvas canvas,
    String text,
    Offset offset,
    double width,
    double size, {
    bool serif = false,
    Color color = RoomColors.ink,
    int maxLines = 4,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: serif ? 'Literata' : 'DM Sans',
          fontSize: size,
          color: color,
          height: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: width);
    painter.paint(canvas, offset);
  }

  static Future<void> _cover(Canvas canvas, BookEntry book, Rect rect) async {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(5)),
      Paint()..color = bookPalette[bookSeed(book.title) % bookPalette.length],
    );
    if (book.coverPath != null && await File(book.coverPath!).exists()) {
      try {
        final codec = await ui.instantiateImageCodec(
          await File(book.coverPath!).readAsBytes(),
          targetWidth: rect.width.toInt() * 2,
        );
        final frame = await codec.getNextFrame();
        paintImage(
          canvas: canvas,
          rect: rect,
          image: frame.image,
          fit: BoxFit.contain,
        );
        frame.image.dispose();
        codec.dispose();
        return;
      } catch (_) {
        /* A damaged cover uses the generated design. */
      }
    }
    _text(
      canvas,
      book.title,
      Offset(rect.left + 14, rect.top + 24),
      rect.width - 28,
      rect.width / 9,
      serif: true,
      color: Colors.white,
    );
    _text(
      canvas,
      book.author,
      Offset(rect.left + 14, rect.bottom - 42),
      rect.width - 28,
      rect.width / 17,
      color: Colors.white,
      maxLines: 2,
    );
  }

  static Rect _origin(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    return box == null
        ? const Rect.fromLTWH(0, 0, 1, 1)
        : box.localToGlobal(Offset.zero) & box.size;
  }

  static Future<void> finishedBook(BookEntry book, BuildContext context) async {
    final origin = _origin(context);
    final recorder = ui.PictureRecorder();
    // Use a single recorder per image so rendering remains completely local.
    final c = Canvas(recorder);
    c.drawColor(RoomColors.paper, BlendMode.src);
    _text(c, 'A STORY FINISHED', const Offset(48, 46), 504, 17);
    await _cover(c, book, const Rect.fromLTWH(180, 110, 240, 350));
    _text(
      c,
      book.title,
      const Offset(48, 510),
      504,
      36,
      serif: true,
      maxLines: 3,
    );
    _text(c, book.author, const Offset(48, 665), 504, 22);
    _text(c, 'My reading library', const Offset(48, 752), 504, 16);
    await _share(recorder, 600, 800, 'finished-book', origin);
    // Keep the API independent from widgets/repaint boundaries.
  }

  /// The tallest image a phone GPU is sure to render; a bigger shelf is drawn
  /// smaller instead of being cut short.
  static const _maxImageHeight = 8000;

  /// Every book finished in [year] (all time when null), in the Library's
  /// [sort] order.
  static Future<void> yearShelf(
    LibrarySnapshot data,
    int? year,
    LibrarySort sort,
    BuildContext context,
  ) async {
    final origin = _origin(context);
    final ids = data.finishesIn(year).map((c) => c.userBookId).toSet();
    final books = sortBooks(data.books.where((b) => ids.contains(b.id)), sort);
    final rows = (books.length / 4).ceil();
    final height = 250 + rows * 222;
    final scale = height > _maxImageHeight ? _maxImageHeight / height : 1.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(scale);
    canvas.drawColor(RoomColors.paper, BlendMode.src);
    _text(
      canvas,
      year == null ? 'My reading shelf' : '$year, in books.',
      const Offset(40, 40),
      640,
      38,
      serif: true,
    );
    _text(
      canvas,
      '${data.finishesIn(year).length} books finished',
      const Offset(40, 102),
      640,
      20,
    );
    for (var i = 0; i < books.length; i++) {
      await _cover(
        canvas,
        books[i],
        Rect.fromLTWH(40 + (i % 4) * 165, 160 + (i ~/ 4) * 222, 142, 200),
      );
    }
    _text(canvas, 'My reading library', Offset(40, height - 42.0), 640, 16);
    await _share(
      recorder,
      (720 * scale).round(),
      (height * scale).round(),
      'reading-shelf',
      origin,
    );
  }

  static Future<void> _share(
    ui.PictureRecorder recorder,
    int width,
    int height,
    String name,
    Rect origin,
  ) async {
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(
      p.join(
        (await getTemporaryDirectory()).path,
        '$name-${DateTime.now().microsecondsSinceEpoch}.png',
      ),
    );
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
    picture.dispose();
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], sharePositionOrigin: origin),
    );
  }
}
