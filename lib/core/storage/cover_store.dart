import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class CoverStore {
  static Future<Directory> directory() async => Directory(
    p.join((await getApplicationDocumentsDirectory()).path, 'covers'),
  ).create(recursive: true);
  static Future<String> importFile(String source) async {
    final file = File(source);
    if (await file.length() > 20 * 1024 * 1024) {
      throw const FormatException('Cover is too large.');
    }
    final target = p.join(
      (await directory()).path,
      '${const Uuid().v4()}${p.extension(source)}',
    );
    await file.copy(target);
    return target;
  }

  static Future<String> saveBytes(Uint8List bytes, String extension) async {
    if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
      throw const FormatException('Cover is too large.');
    }
    final target = p.join(
      (await directory()).path,
      '${const Uuid().v4()}$extension',
    );
    await File(target).writeAsBytes(bytes, flush: true);
    return target;
  }

  /// Deletes files in [directory] that no edition references. Files younger than
  /// [minAge] are kept because a form may hold a freshly imported cover that is
  /// not saved yet. Names are compared by basename so a moved app container
  /// never causes live covers to look unreferenced.
  static Future<int> collectGarbage(
    Set<String> referencedPaths, {
    Directory? directory,
    Duration minAge = const Duration(days: 1),
    DateTime? now,
  }) async {
    final root = directory ?? await CoverStore.directory();
    final keep = referencedPaths.map(p.basename).toSet();
    final cutoff = (now ?? DateTime.now()).subtract(minAge);
    var removed = 0;
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File || keep.contains(p.basename(entity.path))) continue;
      if ((await entity.lastModified()).isAfter(cutoff)) continue;
      try {
        await entity.delete();
        removed++;
      } on FileSystemException {
        /* Left for the next pass. */
      }
    }
    return removed;
  }
}
