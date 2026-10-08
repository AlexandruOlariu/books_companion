import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_library/app/app.dart';
import 'package:reading_library/app/providers.dart';
import 'package:reading_library/demo.dart';
import 'package:reading_library/features/settings/presentation/settings_screen.dart';
import 'package:reading_library/features/sharing/presentation/share_app_button.dart';

void main() {
  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> shares;
  String? copied;
  bool failSharing = false;

  setUp(() {
    shares = [];
    copied = null;
    failSharing = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(shareChannel, (
      call,
    ) async {
      shares.add(call);
      if (failSharing) throw PlatformException(code: 'unavailable');
      return ''; // Reader dismissed the native sheet.
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(shareChannel, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  testWidgets('toolbar shares a public Android link only, even at 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final repo = await createDemoRepository();
    addTearDown(repo.db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          demoProvider.overrideWithValue(true),
        ],
        child: const ReadingLibraryApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(shares, isEmpty);
    await tester.tap(find.byTooltip('Share app'));
    await tester.pumpAndSettle();
    final payload = shares.single.arguments as Map;
    expect(payload['text'], appShareMessage);
    expect(
      payload['text'],
      contains('/releases/latest/download/reading-library.apk'),
    );
    expect(payload['text'], contains('Download for Android'));
    expect(payload['subject'], 'Reading Library for Android');
    expect(payload.containsKey('paths'), isFalse);
    expect(payload['originWidth'], greaterThan(0));
    expect(payload['originHeight'], greaterThan(0));
    expect(find.textContaining('Could not open sharing'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Settings can share the app and copy the permanent download link',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: SettingsScreen())),
      );
      await tester.pumpAndSettle();
      final share = find.widgetWithText(OutlinedButton, 'Share app');
      await tester.ensureVisible(share);
      await tester.tap(share);
      await tester.pumpAndSettle();
      expect(shares, hasLength(1));
      final copy = find.text('Copy download link');
      await tester.ensureVisible(copy);
      await tester.tap(copy);
      await tester.pumpAndSettle();
      expect(copied, appDownloadUrl);
      expect(find.text('Download link copied.'), findsOneWidget);
    },
  );

  testWidgets('sharing failure offers copy fallback and can be retried', (
    tester,
  ) async {
    failSharing = true;
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ShareAppButton())),
    );
    await tester.tap(find.text('Share app'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not open sharing'), findsOneWidget);
    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();
    expect(copied, appDownloadUrl);
    failSharing = false;
    await tester.tap(find.text('Share app'));
    await tester.pumpAndSettle();
    expect(shares, hasLength(2));
    expect(tester.takeException(), isNull);
  });
}
