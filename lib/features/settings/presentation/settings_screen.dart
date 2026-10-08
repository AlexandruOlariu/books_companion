import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../core/storage/backup_service.dart';
import '../../../core/widgets/common.dart';
import '../../sync/presentation/sync_controller.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool busy = false;
  String? message;
  Future<void> export() async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final bytes = await BackupService(ref.read(repositoryProvider)).export();
      final destination = await FilePicker.saveFile(
        dialogTitle: 'Save your library backup',
        fileName:
            'reading-library-${DateTime.now().toIso8601String().substring(0, 10)}.json',
        bytes: bytes,
      );
      if (mounted) {
        setState(
          () => message = destination == null
              ? 'Export cancelled.'
              : 'Backup saved, including your covers and private pins.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => message = e is FormatException
              ? e.message
              : 'Could not export the library. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> restore() async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final picked = await FilePicker.pickFile(type: FileType.any);
      if (picked == null) return;
      final path = picked.path;
      if (path == null) {
        throw const FormatException('This file cannot be read.');
      }
      final file = File(path);
      if (await file.length() > 150 * 1024 * 1024) {
        throw const FormatException('Backup is too large (maximum 150 MB).');
      }
      final bytes = await file.readAsBytes();
      final service = BackupService(ref.read(repositoryProvider));
      final envelope = service.inspect(bytes);
      final count = (envelope['data']['userBooks'] as List?)?.length ?? 0;
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Replace this library?'),
          content: Text(
            'Restore $count books from this backup. Your current books, history, sessions, and pins will be replaced. Export your current library first if you want to keep it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Restore backup'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await service.restore(bytes);
      ref.invalidate(libraryProvider);
      if (mounted) setState(() => message = 'Your library has been restored.');
    } catch (e) {
      if (mounted) {
        setState(
          () => message = e is FormatException ? e.message : 'This backup could not be restored. Your existing library is unchanged.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Your reading room')),
    body: ListView(
      padding: screenPadding(context),
      children: [
        const Eyebrow('Your account'),
        const SizedBox(height: 16),
        Text(
          'Just you.\nAnd your books.',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 20),
        Text(
          ref.watch(demoProvider)
              ? 'This is a demo: everything here is a sample and nothing is saved or sent.'
              : 'Your library, reading history, and private notes are kept on this phone and saved to your account, so they survive a lost or new phone. There is no tracking.',
        ),
        if (!ref.watch(demoProvider)) const _SaveStatus(),
        const SizedBox(height: 32),
        Text(
          'Keep your collection safe',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        const Text(
          'A backup includes your books, dates, sessions, notes, and cover files. Keep a copy somewhere you trust before changing devices.',
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: busy ? null : export,
          icon: const Icon(Icons.file_download_outlined),
          label: const Text('Export library'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: busy ? null : restore,
          icon: const Icon(Icons.restore),
          label: const Text('Restore a backup'),
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Text(message!),
          ),
        if (!ref.watch(demoProvider)) ...[
          const SizedBox(height: 32),
          Text(
            'Read with friends',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          const Text(
            'Find friends and share a list of the books you have read. Friends only see what you publish: titles, authors, status, and finish dates. Never your notes, pins, or reading sessions.',
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => context.push('/friends'),
            icon: const Icon(Icons.people_outline),
            label: const Text('Friends and sharing'),
          ),
        ],
        const SizedBox(height: 40),
        const Text('Reading Library · 0.1.1'),
        TextButton(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'Reading Library',
            applicationVersion: '0.1.1',
          ),
          child: const Text('Open-source licenses'),
        ),
      ],
    ),
  );
}

/// Whether the library is saved to the account, with a way to retry now.
class _SaveStatus extends ConsumerWidget {
  const _SaveStatus();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(accountRequiredProvider)) return const SizedBox.shrink();
    final sync = ref.watch(syncControllerProvider);
    final saved = sync.lastSaved?.toLocal();
    final text = switch (sync.phase) {
      SyncPhase.syncing => 'Saving to your account…',
      SyncPhase.saved =>
        'Saved to your account${saved == null ? '' : ' at ${DateFormat.yMMMd().add_jm().format(saved)}'}.',
      SyncPhase.waiting => 'Waiting for a connection. Your changes are safe on this phone and will be saved when it is back.',
      SyncPhase.conflict => 'Choose which library to keep to continue saving.',
      SyncPhase.problem =>
        sync.message ?? 'Your library could not be saved. Try again.',
      SyncPhase.off => 'Not saved yet.',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
          TextButton(
            onPressed: sync.phase == SyncPhase.syncing
                ? null
                : () => ref.read(syncControllerProvider.notifier).sync(),
            child: const Text('Save now'),
          ),
        ],
      ),
    );
  }
}
