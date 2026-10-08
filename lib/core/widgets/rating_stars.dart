import 'package:flutter/material.dart';

import '../../features/library/domain/models.dart';
import '../theme/app_theme.dart';

/// Five stars the reader taps to rate a book. Tapping the chosen star again
/// clears the rating, so "not rated" is always one tap away. Each star is a
/// 48 x 48 target and announces itself ("3 of 5 stars", selected or not).
class RatingStars extends StatelessWidget {
  final int? value;
  final ValueChanged<int?> onChanged;
  const RatingStars({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var star = 1; star <= maxRating; star++)
        Semantics(
          key: ValueKey('rating-star-$star'),
          button: true,
          selected: value == star,
          label: '$star of $maxRating stars',
          // The child's own semantics are replaced, so the tap is declared here
          // too; otherwise a screen reader could hear the star but not use it.
          onTap: () => onChanged(value == star ? null : star),
          excludeSemantics: true,
          child: InkResponse(
            onTap: () => onChanged(value == star ? null : star),
            radius: 24,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(
                value != null && star <= value!
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                size: 34,
                color: value != null && star <= value!
                    ? RoomColors.terra
                    : RoomColors.muted,
              ),
            ),
          ),
        ),
    ],
  );
}
