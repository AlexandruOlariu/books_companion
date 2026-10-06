import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/storage/cover_store.dart';
import 'core/storage/database.dart';
import 'core/storage/draft_store.dart';
import 'core/storage/preferences_store.dart';
import 'core/storage/session_store.dart';
import 'features/library/data/local_library_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final font in ['DMSans', 'Literata']) {
      yield LicenseEntryWithLineBreaks([
        font,
      ], await rootBundle.loadString('assets/fonts/$font-LICENSE.txt'));
    }
  });
  try {
    final directory = await getApplicationDocumentsDirectory();
    final db = AppDatabase(
      NativeDatabase.createInBackground(
        File(p.join(directory.path, 'reading-library.sqlite')),
      ),
    );
    final repository = LocalLibraryRepository(db);
    await repository.load();
    final support = await getApplicationSupportDirectory();
    final drafts = FileDraftStore(File(p.join(support.path, 'drafts.json')));
    // Android may kill a backgrounded process without further callbacks.
    AppLifecycleListener(onInactive: drafts.flush, onPause: drafts.flush);
    // Housekeeping must never delay or break startup.
    unawaited(
      repository
          .coverPaths()
          .then(CoverStore.collectGarbage)
          .then((_) {}, onError: (_) {}),
    );
    runApp(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repository),
          draftStoreProvider.overrideWithValue(drafts),
          sessionStoreProvider.overrideWithValue(SecureSessionStore()),
          preferencesProvider.overrideWithValue(
            FilePreferencesStore(
              File(p.join(support.path, 'preferences.json')),
            ),
          ),
        ],
        child: const ReadingLibraryApp(),
      ),
    );
  } catch (_) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Your library could not be opened. Your saved files have not been removed.',
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: main,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
