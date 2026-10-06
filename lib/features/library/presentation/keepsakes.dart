import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Small objects that appear on the shelf as books are finished.
///
/// They are earned only by the number of books marked finished: never by
/// streaks, daily opening, pages, or time, so nothing here rewards pressure or
/// invents activity.
enum Keepsake {
  bookend('Brass bookend', 1, Size(30, 76)),
  plant('Potted plant', 3, Size(64, 96)),
  mug('Tea mug', 5, Size(54, 48)),
  candle('Candle', 8, Size(40, 70)),
  globe('Globe', 12, Size(72, 100)),
  hourglass('Hourglass', 18, Size(44, 76)),
  cat('Reading cat', 25, Size(66, 74));

  const Keepsake(this.label, this.unlockAt, this.size);
  final String label;
  final int unlockAt;
  final Size size;

  static List<Keepsake> earned(int finished) =>
      values.where((k) => finished >= k.unlockAt).toList();
  static Keepsake? next(int finished) =>
      values.where((k) => k.unlockAt > finished).firstOrNull;

  String get earnedBy =>
      'Earned by finishing $unlockAt ${unlockAt == 1 ? 'book' : 'books'}.';

  CustomPainter get painter => switch (this) {
    Keepsake.bookend => _BookendPainter(),
    Keepsake.plant => _PlantPainter(),
    Keepsake.mug => _MugPainter(),
    Keepsake.candle => _CandlePainter(),
    Keepsake.globe => _GlobePainter(),
    Keepsake.hourglass => _HourglassPainter(),
    Keepsake.cat => _CatPainter(),
  };
}

Paint _fill(Color c) => Paint()..color = c;
Paint _stroke(Color c, double w) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round;

abstract class _Painter extends CustomPainter {
  @override
  bool shouldRepaint(CustomPainter old) => false;
}

class _BookendPainter extends _Painter {
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, s.width * .34, s.height),
        const Radius.circular(3),
      ),
      _fill(const Color(0xFF6F5329)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, s.height - 9, s.width, 9),
        const Radius.circular(3),
      ),
      _fill(const Color(0xFF8C6B3A)),
    );
    canvas.drawLine(
      Offset(s.width * .12, 6),
      Offset(s.width * .12, s.height - 12),
      _stroke(const Color(0x55FFFFFF), 2),
    );
  }
}

class _PlantPainter extends _Painter {
  @override
  void paint(Canvas canvas, Size s) {
    final potTop = s.height * .58;
    final leaves = [
      (-52.0, 30.0, RoomColors.forest),
      (-26.0, 42.0, const Color(0xFF3F7A66)),
      (0.0, 46.0, RoomColors.forest),
      (24.0, 40.0, const Color(0xFF3F7A66)),
      (50.0, 30.0, const Color(0xFF356B58)),
    ];
    for (final (deg, len, color) in leaves) {
      canvas
        ..save()
        ..translate(s.width / 2, potTop)
        ..rotate(deg * math.pi / 180)
        ..drawOval(Rect.fromLTWH(-7, -len, 14, len), _fill(color))
        ..restore();
    }
    final pot = Path()
      ..moveTo(s.width * .1, potTop)
      ..lineTo(s.width * .9, potTop)
      ..lineTo(s.width * .72, s.height)
      ..lineTo(s.width * .28, s.height)
      ..close();
    canvas.drawPath(pot, _fill(RoomColors.terra));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s.width * .06, potTop - 2, s.width * .88, 9),
        const Radius.circular(2),
      ),
      _fill(const Color(0xFF9C5440)),
    );
  }
}

class _MugPainter extends _Painter {
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawArc(
      Rect.fromLTWH(30, 18, 20, 20),
      -math.pi / 2,
      math.pi,
      false,
      _stroke(const Color(0xFF3F7A7A), 5),
    );
    final body = RRect.fromRectAndRadius(
      const Rect.fromLTWH(2, 14, 38, 33),
      const Radius.circular(6),
    );
    canvas
      ..drawRRect(body, _fill(const Color(0xFF3F7A7A)))
      ..save()
      ..clipRRect(body)
      ..drawRect(
        const Rect.fromLTWH(2, 26, 38, 6),
        _fill(const Color(0xFFF2E8D5)),
      )
      ..restore();
    for (final x in [14.0, 26.0]) {
      final steam = Path()
        ..moveTo(x, 10)
        ..quadraticBezierTo(x - 5, 5, x, 0);
      canvas.drawPath(steam, _stroke(const Color(0x66242B28), 1.6));
    }
  }
}

class _CandlePainter extends _Painter {
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawCircle(const Offset(20, 14), 15, _fill(const Color(0x30F2B84B)));
    canvas.drawOval(
      Rect.fromLTWH(3, s.height - 11, s.width - 6, 10),
      _fill(RoomColors.woodDark),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(11, 28, 18, s.height - 36),
        const Radius.circular(3),
      ),
      _fill(const Color(0xFFF4ECD8)),
    );
    canvas.drawLine(
      const Offset(20, 22),
      const Offset(20, 28),
      _stroke(const Color(0xFF242B28), 1.6),
    );
    final flame = Path()
      ..moveTo(20, 2)
      ..quadraticBezierTo(28, 12, 20, 22)
      ..quadraticBezierTo(12, 12, 20, 2);
    canvas
      ..drawPath(flame, _fill(const Color(0xFFF2B84B)))
      ..drawOval(
        Rect.fromCenter(center: const Offset(20, 16), width: 5, height: 9),
        _fill(const Color(0xFFFFE9A8)),
      );
  }
}

class _GlobePainter extends _Painter {
  @override
  void paint(Canvas canvas, Size s) {
    final c = Offset(s.width / 2, 38);
    const r = 34.0;
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(s.width * .26, s.height - 10, s.width * .48, 10),
          const Radius.circular(3),
        ),
        _fill(RoomColors.woodDark),
      )
      ..drawRect(
        Rect.fromLTWH(
          s.width / 2 - 3,
          c.dy + r - 4,
          6,
          s.height - c.dy - r - 4,
        ),
        _fill(RoomColors.woodDark),
      )
      ..drawCircle(c, r, _fill(const Color(0xFF6E97A3)))
      ..save()
      ..clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    for (final land in [
      Rect.fromCenter(center: c + const Offset(-10, -8), width: 22, height: 16),
      Rect.fromCenter(center: c + const Offset(12, 6), width: 18, height: 24),
      Rect.fromCenter(center: c + const Offset(-14, 18), width: 14, height: 9),
    ]) {
      canvas.drawOval(land, _fill(const Color(0xFF58805F)));
    }
    canvas
      ..drawCircle(
        c + const Offset(-11, -12),
        9,
        _fill(const Color(0x33FFFFFF)),
      )
      ..restore()
      ..drawArc(
        Rect.fromCircle(center: c, radius: r + 4),
        math.pi * .62,
        math.pi * 1.35,
        false,
        _stroke(const Color(0xFF8C6B3A), 3),
      );
  }
}

class _HourglassPainter extends _Painter {
  @override
  void paint(Canvas canvas, Size s) {
    final h = s.height, w = s.width;
    final glass = Path()
      ..moveTo(7, 8)
      ..lineTo(w - 7, 8)
      ..lineTo(w / 2 + 2, h / 2)
      ..lineTo(w - 7, h - 8)
      ..lineTo(7, h - 8)
      ..lineTo(w / 2 - 2, h / 2)
      ..close();
    canvas
      ..drawPath(glass, _fill(const Color(0x33FFFFFF)))
      ..drawPath(
        Path()
          ..moveTo(w / 2, h / 2)
          ..lineTo(w - 14, h - 9)
          ..lineTo(14, h - 9)
          ..close(),
        _fill(const Color(0xFFD9A441)),
      )
      ..drawPath(
        Path()
          ..moveTo(12, 12)
          ..lineTo(w - 12, 12)
          ..lineTo(w / 2, h / 2 - 8)
          ..close(),
        _fill(const Color(0x88D9A441)),
      )
      ..drawPath(glass, _stroke(const Color(0x88242B28), 1.6));
    for (final y in [0.0, h - 8]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(2, y, w - 4, 8),
          const Radius.circular(2),
        ),
        _fill(RoomColors.woodDark),
      );
    }
  }
}

class _CatPainter extends _Painter {
  @override
  void paint(Canvas canvas, Size s) {
    const ink = Color(0xFF2F3432);
    canvas
      ..drawPath(
        Path()
          ..moveTo(48, 68)
          ..quadraticBezierTo(70, 62, 60, 38),
        _stroke(ink, 7),
      )
      ..drawOval(const Rect.fromLTWH(6, 34, 42, 38), _fill(ink))
      ..drawCircle(const Offset(27, 28), 15, _fill(ink))
      ..drawPath(
        Path()
          ..moveTo(14, 20)
          ..lineTo(15, 5)
          ..lineTo(26, 14)
          ..close(),
        _fill(ink),
      )
      ..drawPath(
        Path()
          ..moveTo(40, 20)
          ..lineTo(39, 5)
          ..lineTo(28, 14)
          ..close(),
        _fill(ink),
      );
    for (final x in [21.0, 33.0]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, 28), width: 5, height: 6),
        _fill(const Color(0xFFE8C46A)),
      );
    }
  }
}

/// A keepsake sized for the shelf. Tapping tells the reader how it was earned.
class KeepsakeView extends StatelessWidget {
  final Keepsake keepsake;
  final VoidCallback onTap;
  const KeepsakeView({super.key, required this.keepsake, required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Shelf keepsake: ${keepsake.label}. ${keepsake.earnedBy}',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: ExcludeSemantics(
        child: SizedBox.fromSize(
          size: keepsake.size,
          child: CustomPaint(painter: keepsake.painter),
        ),
      ),
    ),
  );
}
