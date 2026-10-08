import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'update_controller.dart';

class UpdateNotice extends ConsumerWidget {
  const UpdateNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateControllerProvider);
    final update = state.available;
    if (update == null || state.dismissed) return const SizedBox.shrink();
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version ${update.version} is available.'),
            if (state.message != null) Text(state.message!),
            Wrap(
              spacing: 12,
              children: [
                TextButton(
                  onPressed: () =>
                      ref.read(updateControllerProvider.notifier).download(),
                  child: const Text('Download update'),
                ),
                TextButton(
                  onPressed: () =>
                      ref.read(updateControllerProvider.notifier).dismiss(),
                  child: const Text('Later'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class UpdateSettings extends ConsumerWidget {
  const UpdateSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(updateServiceProvider) == null) {
      return const SizedBox.shrink();
    }
    final state = ref.watch(updateControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('App updates', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (state.installed != null)
          Text('Installed version: ${state.installed!.version}'),
        if (state.available != null) ...[
          Text('Version ${state.available!.version} is available.'),
          const SizedBox(height: 12),
          const Text(
            'Download the update, open the downloaded file, and confirm Update on your phone. Your library stays in place.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () =>
                ref.read(updateControllerProvider.notifier).download(),
            icon: const Icon(Icons.download_outlined),
            label: const Text('Download update'),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: state.busy
              ? null
              : () => ref.read(updateControllerProvider.notifier).check(),
          icon: const Icon(Icons.refresh),
          label: Text(state.busy ? 'Checking…' : 'Check for updates'),
        ),
        if (state.message != null) ...[
          const SizedBox(height: 12),
          Text(state.message!),
        ],
        const SizedBox(height: 32),
      ],
    );
  }
}
