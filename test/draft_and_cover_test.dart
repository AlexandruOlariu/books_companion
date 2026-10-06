import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reading_library/core/storage/cover_store.dart';
import 'package:reading_library/core/storage/draft_store.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('rl_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('cover garbage collection', () {
    Future<File> cover(String name, {DateTime? modified}) async {
      final file = File('${dir.path}/$name')..writeAsStringSync('x');
      if (modified != null) await file.setLastModified(modified);
      return file;
    }

    test('removes only old, unreferenced files', () async {
      final old = DateTime.now().subtract(const Duration(days: 3));
      final kept = await cover('kept.jpg', modified: old);
      final orphan = await cover('orphan.jpg', modified: old);
      final fresh = await cover('fresh.jpg'); // imported moments ago, unsaved
      final removed = await CoverStore.collectGarbage({
        '/some/other/container/kept.jpg',
      }, directory: dir);
      expect(removed, 1);
      expect(kept.existsSync(), isTrue);
      expect(orphan.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
    });

    test('does nothing for an empty or missing directory entry set', () async {
      final old = DateTime.now().subtract(const Duration(days: 3));
      await cover('a.jpg', modified: old);
      Directory('${dir.path}/nested').createSync();
      // Referencing everything keeps everything; subdirectories are ignored.
      expect(await CoverStore.collectGarbage({'a.jpg'}, directory: dir), 0);
      expect(Directory('${dir.path}/nested').existsSync(), isTrue);
    });
  });

  group('draft store', () {
    FileDraftStore open([DateTime Function()? clock]) => FileDraftStore(
      File('${dir.path}/drafts.json'),
      delay: const Duration(milliseconds: 10),
      clock: clock,
    );

    test('a draft survives a new process (a new store instance)', () async {
      final first = open()..save('note', {'note': 'remember this'});
      await first.flush();
      final second = open();
      expect(await second.load('note'), {'note': 'remember this'});
    });

    test('clearing removes the entry and the file', () async {
      final store = open()..save('a', {'t': 'x'});
      await store.flush();
      await store.clear('a');
      expect(await open().load('a'), isNull);
      expect(File('${dir.path}/drafts.json').existsSync(), isFalse);
    });

    test('old drafts expire and a damaged file is ignored', () async {
      final store = open()..save('a', {'t': 'x'});
      await store.flush();
      final later = DateTime.now().add(const Duration(days: 31));
      expect(await open(() => later).load('a'), isNull);
      File('${dir.path}/drafts.json').writeAsStringSync('{not json');
      expect(await open().load('a'), isNull);
    });

    test('blank input discards the draft', () async {
      final store = MemoryDraftStore();
      final binding = DraftBinding(store, 'k');
      binding.update({'a': 'hello', 'b': ''});
      expect(await store.load('k'), isNotNull);
      binding.update({'a': ' ', 'b': ''});
      await Future<void>.delayed(Duration.zero);
      expect(await store.load('k'), isNull);
    });
  });
}
