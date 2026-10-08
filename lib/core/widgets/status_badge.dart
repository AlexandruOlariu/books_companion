import 'package:flutter/material.dart';

import '../../features/library/domain/models.dart';
import '../theme/app_theme.dart';

/// Icon and colours that stand for a reading status. The shelf badge and the
/// filter chips both use them, so the chips double as the legend.
extension BookStatusLook on BookStatus {
  IconData get icon => switch (this) {
    BookStatus.reading => Icons.auto_stories,
    BookStatus.wantToRead => Icons.favorite_border,
    BookStatus.finished => Icons.check,
  };

  Color get fill => switch (this) {
    BookStatus.reading => const Color(0xFFDBBA78),
    BookStatus.wantToRead => RoomColors.surface,
    BookStatus.finished => RoomColors.forest,
  };

  Color get mark => switch (this) {
    BookStatus.reading => RoomColors.ink,
    BookStatus.wantToRead => RoomColors.terra,
    BookStatus.finished => Colors.white,
  };
}

/// A small round seal for a book's status. Decorative: whoever needs the status
/// in words gets it from the surrounding label.
class StatusBadge extends StatelessWidget {
  final BookStatus status;
  final double size;
  const StatusBadge({super.key, required this.status, this.size = 20});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: status.fill,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            offset: Offset(0, 1),
            blurRadius: 2,
          ),
        ],
      ),
      child: Icon(status.icon, size: size * .62, color: status.mark),
    ),
  );
}
