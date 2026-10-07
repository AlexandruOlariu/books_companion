import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../domain/sync_models.dart';
import 'sync_controller.dart';

String _books(int n) => '$n ${n == 1 ? 'book' : 'books'}';

/// Both the phone and the account hold a library. They are not merged (that
/// would mean guessing dates and activity), so the reader keeps one; the other
/// is replaced.
Future<void> showSyncConflict(
  BuildContext context,
  WidgetRef ref,
  SyncConflict conflict,
) async {
  final keepPhone = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ConflictDialog(conflict),
  );
  if (keepPhone == null) return;
  await ref.read(syncControllerProvider.notifier).resolve(keepPhone: keepPhone);
}

class _ConflictDialog extends StatelessWidget {
  final SyncConflict conflict;
  const _ConflictDialog(this.conflict);
  @override
  Widget build(BuildContext context) {
    final saved = conflict.accountUpdatedAt?.toLocal();
    return AlertDialog(
      title: const Text('Which library do you want to keep?'),
      content: SingleChildScrollView(
        child: Text(
          'This phone has ${_books(conflict.phoneBooks)}. Your account has ${_books(conflict.accountBooks)}${saved == null ? '' : ', saved ${DateFormat.yMMMd().add_jm().format(saved)}'}.\n\n'
          'They cannot be combined without guessing, so keep one. The other one is replaced and cannot be brought back.',
          style: const TextStyle(height: 1.5),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('Keep this phone (${_books(conflict.phoneBooks)})'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Use my account (${_books(conflict.accountBooks)})'),
        ),
      ],
    );
  }
}
