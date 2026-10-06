import 'dart:convert';
import 'dart:io';

/// Small device-local settings that should survive restarts (for example the
/// shelf's sort order). Plain text values keyed by name; never part of a backup
/// and never sent anywhere.
abstract class PreferencesStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class MemoryPreferencesStore implements PreferencesStore {
  final _values = <String, String>{};
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}

class FilePreferencesStore implements PreferencesStore {
  final File file;
  FilePreferencesStore(this.file);
  Map<String, String>? _cache;
  Future<void> _writes = Future.value();

  Future<Map<String, String>> _load() async {
    final cached = _cache;
    if (cached != null) return cached;
    final values = <String, String>{};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        decoded.forEach((k, v) {
          if (k is String && v is String) values[k] = v;
        });
      }
    } on FileSystemException {
      /* No file yet. */
    } on FormatException {
      /* A damaged file is ignored; defaults apply. */
    }
    return _cache = values;
  }

  @override
  Future<String?> read(String key) async => (await _load())[key];

  @override
  Future<void> write(String key, String value) {
    return _writes = _writes.then((_) async {
      final values = await _load();
      values[key] = value;
      try {
        await file.parent.create(recursive: true);
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(jsonEncode(values), flush: true);
        await temp.rename(file.path);
      } on FileSystemException {
        /* Best effort: the choice still applies until the app closes. */
      }
    });
  }
}
