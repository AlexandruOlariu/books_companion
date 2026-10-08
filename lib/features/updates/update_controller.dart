import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'update_service.dart';

final updateServiceProvider = Provider<UpdateService?>(
  (ref) => Platform.isAndroid && !ref.watch(demoProvider)
      ? AndroidUpdateService()
      : null,
);

class UpdateState {
  final InstalledApp? installed;
  final AppUpdate? available;
  final bool busy;
  final bool dismissed;
  final String? message;
  const UpdateState({
    this.installed,
    this.available,
    this.busy = false,
    this.dismissed = false,
    this.message,
  });
}

final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateState>(UpdateController.new);

class UpdateController extends Notifier<UpdateState> {
  DateTime? _lastAttempt;

  @override
  UpdateState build() => const UpdateState();

  Future<void> check({bool automatic = false}) async {
    final service = ref.read(updateServiceProvider);
    if (service == null || state.busy) return;
    final now = DateTime.now();
    if (automatic &&
        _lastAttempt != null &&
        now.difference(_lastAttempt!) < const Duration(hours: 6)) {
      return;
    }
    _lastAttempt = now;
    final previous = state;
    state = UpdateState(
      installed: previous.installed,
      available: previous.available,
      dismissed: previous.dismissed,
      busy: true,
    );
    try {
      final installed = await service.installed();
      if (!ref.mounted) return;
      state = UpdateState(
        installed: installed,
        available: previous.available,
        dismissed: previous.dismissed,
        busy: true,
      );
      final update = await service.latest(installed);
      if (!ref.mounted) return;
      state = UpdateState(
        installed: installed,
        available: update,
        dismissed:
            state.dismissed &&
            previous.available?.buildNumber == update?.buildNumber,
        message: update == null ? 'You have the latest version.' : null,
      );
    } catch (_) {
      if (!ref.mounted) return;
      state = UpdateState(
        installed: state.installed,
        available: previous.available,
        dismissed: state.dismissed,
        message: 'Could not check for updates. Try again when you are online.',
      );
    }
  }

  void dismiss() => state = UpdateState(
    installed: state.installed,
    available: state.available,
    busy: state.busy,
    dismissed: true,
    message: state.message,
  );

  Future<void> download() async {
    final update = state.available;
    final service = ref.read(updateServiceProvider);
    if (update == null || service == null) return;
    try {
      await service.download(update);
    } catch (_) {
      if (!ref.mounted) return;
      state = UpdateState(
        installed: state.installed,
        available: state.available,
        busy: state.busy,
        dismissed: state.dismissed,
        message: 'Could not open the download. Please try again.',
      );
    }
  }
}
