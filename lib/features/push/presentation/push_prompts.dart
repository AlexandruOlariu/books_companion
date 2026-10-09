import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/common.dart';
import 'push_controller.dart';

/// What to tell the reader when the system or the server stops notifications
/// from being turned on; null when it worked.
String? pushProblem(PushResult result) => switch (result) {
  PushResult.enabled => null,
  PushResult.denied => 'Notifications are blocked. Allow them for Reading Library in your phone\'s settings, then try again.',
  PushResult.unavailable =>
    'This build of the app cannot receive notifications.',
  PushResult.offline => 'Could not reach the Reading Library server. Check your connection and try again.',
};

/// Offered once after signing in. "Not now" is remembered, so the reader is not
/// asked again; the switch under Friends stays available.
Future<void> offerPushNotifications(BuildContext context, WidgetRef ref) async {
  final controller = ref.read(pushControllerProvider.notifier);
  final yes = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Know when a friend writes?'),
      content: const Text(
        'Get a notification when someone sends you a friend request or accepts yours. It only says that something happened, never a name or a book. Google delivers it, so Google learns this phone\'s notification address. You can turn it off any time under Friends.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Not now'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Turn on'),
        ),
      ],
    ),
  );
  if (yes != true) {
    await controller.disable();
    return;
  }
  final problem = pushProblem(await controller.enable());
  if (problem != null && context.mounted) notifyUser(context, problem);
}
