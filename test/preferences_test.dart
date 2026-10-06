import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reading_library/core/storage/preferences_store.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('rl_prefs'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a value survives a new store instance (a restart)', () async {
    final file = File('${dir.path}/preferences.json');
    await FilePreferencesStore(file).write('librarySort', 'author');
    expect(await FilePreferencesStore(file).read('librarySort'), 'author');
    expect(await FilePreferencesStore(file).read('missing'), isNull);
  });

  test('later writes win, and several keys coexist', () async {
    final store = FilePreferencesStore(File('${dir.path}/p.json'));
    await store.write('a', '1');
    await store.write('b', '2');
    await store.write('a', '3');
    expect(await store.read('a'), '3');
    expect(await store.read('b'), '2');
  });

  test('a damaged file is ignored and can be written over', () async {
    final file = File('${dir.path}/p.json')..writeAsStringSync('{broken');
    final store = FilePreferencesStore(file);
    expect(await store.read('a'), isNull);
    await store.write('a', 'x');
    expect(await FilePreferencesStore(file).read('a'), 'x');
  });

  test('the in-memory store behaves the same', () async {
    final store = MemoryPreferencesStore();
    await store.write('k', 'v');
    expect(await store.read('k'), 'v');
    expect(await store.read('z'), isNull);
  });
}
