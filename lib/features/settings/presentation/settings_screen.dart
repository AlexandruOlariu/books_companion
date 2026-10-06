import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/storage/backup_service.dart';
import '../../../core/widgets/common.dart';

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
      padding: const EdgeInsets.all(24),
      children: [
        const Eyebrow('Personal by design'),
        const SizedBox(height: 16),
        Text(
          'Just you.\nAnd your books.',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 20),
        const Text(
          'Your library, reading history, and private pins are stored on this device. No account, no cloud, no tracking.',
        ),
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
        const SizedBox(height: 40),
        const Text('Reading Library · 0.1.0'),
        TextButton(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'Reading Library',
            applicationVersion: '0.1.0',
          ),
          child: const Text('Open-source licenses'),
        ),
      ],
    ),
  );
}
