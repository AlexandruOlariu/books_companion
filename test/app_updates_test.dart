import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_library/features/updates/update_controller.dart';
import 'package:reading_library/features/updates/update_service.dart';
import 'package:reading_library/features/updates/update_widgets.dart';

const currentApp = InstalledApp('0.1.1', 10, 'app.readingroom.reading_library');
final newer = AppUpdate(
  '0.1.2',
  11,
  Uri.parse('$releasesOrigin/download/v0.1.2/reading-library.apk'),
);

class FakeUpdates implements UpdateService {
  int checks = 0;
  bool offline = false;
  bool browserFails = false;
  AppUpdate? update = newer;
  AppUpdate? downloaded;
  Completer<void>? pause;
  @override
  Future<InstalledApp> installed() async => installedApp;
  InstalledApp installedApp = currentApp;
  @override
  Future<AppUpdate?> latest(InstalledApp app) async {
    checks++;
    if (pause != null) await pause!.future;
    if (offline) throw Exception('offline');
    return update;
  }

  @override
  Future<void> download(AppUpdate update) async {
    if (browserFails) throw Exception('no browser');
    downloaded = update;
  }
}

void main() {
  Map<String, dynamic> manifest() => {
    'schema': 1,
    'version': '0.1.2',
    'buildNumber': 11,
    'applicationId': currentApp.applicationId,
    'downloadUrl': newer.download.toString(),
  };

  test('updates require a newer installed build number', () {
    expect(AppUpdate.fromManifest(manifest(), currentApp)?.version, '0.1.2');
    expect(
      AppUpdate.fromManifest(manifest()..['buildNumber'] = 10, currentApp),
      isNull,
    );
    expect(
      AppUpdate.fromManifest(manifest()..['buildNumber'] = 9, currentApp),
      isNull,
    );
  });

  test('wrong application, schema, version, and external downloads fail', () {
    for (final patch in [
      {'applicationId': 'another.app'},
      {'schema': 2},
      {'version': '0.1.2-dev'},
      {'buildNumber': '11'},
      {'buildNumber': 0},
      {'downloadUrl': 'https://example.com/app.apk'},
      {'downloadUrl': 'http://github.com/app.apk'},
      {'downloadUrl': '${newer.download}?redirect=elsewhere'},
      {'downloadUrl': '${newer.download}#fragment'},
      {'downloadUrl': newer.download.toString().replaceAll('v0.1.2', 'v0.1.3')},
      {
        'downloadUrl': newer.download.toString().replaceAll(
          'AlexandruOlariu',
          'other',
        ),
      },
    ]) {
      expect(
        () => AppUpdate.fromManifest(manifest()..addAll(patch), currentApp),
        throwsFormatException,
        reason: '$patch',
      );
    }
  });

  late FakeUpdates service;
  late ProviderContainer container;
  setUp(() {
    service = FakeUpdates();
    container = ProviderContainer(
      overrides: [updateServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
  });

  test(
    'automatic checks are throttled; manual checks bypass the pause',
    () async {
      final controller = container.read(updateControllerProvider.notifier);
      await controller.check(automatic: true);
      await controller.check(automatic: true);
      expect(service.checks, 1);
      await controller.check();
      expect(service.checks, 2);
      expect(
        container.read(updateControllerProvider).installed?.version,
        '0.1.1',
      );
    },
  );

  test(
    'offline check keeps a known update and allows a manual retry',
    () async {
      final controller = container.read(updateControllerProvider.notifier);
      await controller.check();
      service.offline = true;
      await controller.check();
      expect(container.read(updateControllerProvider).available, newer);
      expect(
        container.read(updateControllerProvider).message,
        contains('online'),
      );
      service.offline = false;
      service.update = null;
      await controller.check();
      expect(container.read(updateControllerProvider).available, isNull);
      expect(
        container.read(updateControllerProvider).message,
        contains('latest'),
      );
    },
  );

  test(
    'dismissal lasts for the same update, a newer one appears again',
    () async {
      final controller = container.read(updateControllerProvider.notifier);
      await controller.check();
      service.pause = Completer<void>();
      final checking = controller.check();
      await Future<void>.delayed(Duration.zero);
      controller.dismiss();
      service.pause!.complete();
      await checking;
      expect(container.read(updateControllerProvider).dismissed, isTrue);
      service.pause = null;
      await controller.check();
      expect(container.read(updateControllerProvider).dismissed, isTrue);
      service.update = AppUpdate('0.1.3', 12, newer.download);
      await controller.check();
      expect(container.read(updateControllerProvider).dismissed, isFalse);
    },
  );

  test(
    'download opens only on request and a browser failure is explained',
    () async {
      final controller = container.read(updateControllerProvider.notifier);
      await controller.check();
      expect(service.downloaded, isNull);
      await controller.download();
      expect(service.downloaded, newer);
      service.browserFails = true;
      await controller.download();
      expect(
        container.read(updateControllerProvider).message,
        contains('download'),
      );
      expect(container.read(updateControllerProvider).available, newer);
    },
  );

  test('overlapping checks use one request and disposal is safe', () async {
    service.pause = Completer<void>();
    final local = ProviderContainer(
      overrides: [updateServiceProvider.overrideWithValue(service)],
    );
    final controller = local.read(updateControllerProvider.notifier);
    final checking = controller.check();
    await Future<void>.delayed(Duration.zero);
    await controller.check();
    expect(service.checks, 1);
    local.dispose();
    service.pause!.complete();
    await checking;
  });

  testWidgets('notice downloads, Later hides it, Settings keeps the download', (
    tester,
  ) async {
    await container.read(updateControllerProvider.notifier).check();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(children: [UpdateNotice(), UpdateSettings()]),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Download update').first);
    await tester.pumpAndSettle();
    expect(service.downloaded, newer);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text('Later'), findsNothing);
    expect(find.text('Download update'), findsOneWidget);
    expect(find.text('Installed version: 0.1.1'), findsOneWidget);
  });

  testWidgets('notice and Settings fit a small phone at 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await container.read(updateControllerProvider.notifier).check();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(children: [UpdateNotice(), UpdateSettings()]),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
