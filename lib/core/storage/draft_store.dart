import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Unsaved form input that should survive the process being killed.
///
/// Drafts are plain device-local text, kept next to the library and removed as
/// soon as they are saved or discarded. They are never part of a backup.
abstract class DraftStore {
  Future<Map<String, String>?> load(String key);
  void save(String key, Map<String, String> fields);
  Future<void> clear(String key);
}

class MemoryDraftStore implements DraftStore {
  final _drafts = <String, Map<String, String>>{};
  @override
  Future<Map<String, String>?> load(String key) async => _drafts[key];
  @override
  void save(String key, Map<String, String> fields) =>
      _drafts[key] = Map.of(fields);
  @override
  Future<void> clear(String key) async => _drafts.remove(key);
}

class FileDraftStore implements DraftStore {
  final File file;
  final Duration maxAge;
  final Duration delay;
  final DateTime Function() clock;
  FileDraftStore(
    this.file, {
    this.maxAge = const Duration(days: 30),
    this.delay = const Duration(milliseconds: 400),
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  Map<String, Map<String, dynamic>>? _cache;
  Timer? _timer;
  Future<void> _writes = Future.value();

  Future<Map<String, Map<String, dynamic>>> _read() async {
    final cached = _cache;
    if (cached != null) return cached;
    final drafts = <String, Map<String, dynamic>>{};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        final cutoff = clock().subtract(maxAge);
        decoded.forEach((key, value) {
          if (key is! String || value is! Map) return;
          final saved = DateTime.tryParse('${value['savedAt']}');
          if (saved == null || saved.isBefore(cutoff)) return;
          if (value['fields'] is! Map) return;
          drafts[key] = Map<String, dynamic>.from(value);
        });
      }
    } on FileSystemException {
      /* No draft file yet. */
    } on FormatException {
      /* A damaged draft file is discarded; it never blocks the app. */
    }
    return _cache = drafts;
  }

  @override
  Future<Map<String, String>?> load(String key) async {
    final entry = (await _read())[key];
    if (entry == null) return null;
    return (entry['fields'] as Map).map((k, v) => MapEntry('$k', '$v'));
  }

  @override
  void save(String key, Map<String, String> fields) {
    _writes = _writes.then((_) async {
      (await _read())[key] = {
        'savedAt': clock().toIso8601String(),
        'fields': fields,
      };
    });
    _timer?.cancel();
    _timer = Timer(delay, flush);
  }

  /// Writes pending changes now. Safe to call at any time, including when the
  /// app moves to the background.
  Future<void> flush() {
    _timer?.cancel();
    return _writes = _writes.then((_) async {
      final drafts = await _read();
      try {
        if (drafts.isEmpty) {
          if (await file.exists()) await file.delete();
          return;
        }
        await file.parent.create(recursive: true);
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(jsonEncode(drafts), flush: true);
        await temp.rename(file.path);
      } on FileSystemException {
        /* Drafts are best effort; the form itself keeps working. */
      }
    });
  }

  @override
  Future<void> clear(String key) async {
    _writes = _writes.then((_) async => (await _read()).remove(key));
    await flush();
  }
}

/// Connects one form to one draft entry. Blank input removes the draft so an
/// emptied form does not offer to restore nothing.
class DraftBinding {
  final DraftStore store;
  final String key;
  const DraftBinding(this.store, this.key);
  Future<Map<String, String>?> restore() => store.load(key);
  void update(Map<String, String> fields) {
    final filled = fields.values.any((v) => v.trim().isNotEmpty);
    filled ? store.save(key, fields) : store.clear(key);
  }

  Future<void> discard() => store.clear(key);
}
