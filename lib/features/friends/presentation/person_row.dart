import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/friends_models.dart';

/// A person with the actions that apply to them. Actions sit under the name so
/// the row survives a 360 px screen and large text.
class PersonRow extends StatelessWidget {
  final Person person;
  final List<Widget> actions;
  final VoidCallback? onTap;
  const PersonRow({
    super.key,
    required this.person,
    this.actions = const [],
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              ExcludeSemantics(
                child: CircleAvatar(
                  backgroundColor: RoomColors.shelfBack,
                  foregroundColor: RoomColors.forest,
                  child: Text(
                    person.displayName.isEmpty
                        ? '?'
                        : person.displayName.characters.first.toUpperCase(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '@${person.username}',
                      style: const TextStyle(color: RoomColors.muted),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(Icons.chevron_right, color: RoomColors.muted),
            ],
          ),
        ),
      ),
      if (actions.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 52, bottom: 8),
          child: Wrap(spacing: 8, runSpacing: 4, children: actions),
        ),
    ],
  );
}
