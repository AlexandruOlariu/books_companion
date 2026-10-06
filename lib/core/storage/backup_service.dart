import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../features/library/domain/models.dart';
import 'cover_store.dart';

/// Versioned JSON envelope. Covers are portable bytes, never external paths.
class BackupService {
  final LibraryRepository repository;
  final Future<Directory> Function() coverDirectory;
  BackupService(this.repository, {Future<Directory> Function()? coverDirectory})
    : coverDirectory = coverDirectory ?? CoverStore.directory;
  Future<Uint8List> export() async {
    final data = await repository.exportData();
    final covers = <String, String>{};
    for (final edition in data['editions'] as List) {
      final path = edition['coverLocalPath'] as String?;
      if (path == null) continue;
      final key = '${edition['id']}.cover';
      final file = File(path);
      if (!await file.exists()) {
        throw const FormatException(
          'A cover file is missing. Replace it before exporting.',
        );
      }
      covers[key] = base64Encode(await file.readAsBytes());
      edition['coverLocalPath'] = key;
    }
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': 'reading-library',
          'version': 1,
          'data': data,
          'covers': covers,
        }),
      ),
    );
  }

  Map<String, dynamic> inspect(Uint8List bytes) {
    if (bytes.length > 150 * 1024 * 1024) {
      throw const FormatException('Backup is too large (maximum 150 MB).');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != 'reading-library' ||
        decoded['version'] != 1 ||
        decoded['data'] is! Map ||
        decoded['covers'] is! Map) {
      throw const FormatException(
        'This is not a supported Reading Library backup.',
      );
    }
    return decoded;
  }

  Future<void> restore(Uint8List bytes) async {
    final envelope = inspect(bytes);
    final data = Map<String, dynamic>.from(envelope['data'] as Map),
        covers = Map<String, dynamic>.from(envelope['covers'] as Map);
    if (data['editions'] is! List) {
      throw const FormatException('Missing editions.');
    }
    // Stage files under fresh names. Existing files survive all validation failures.
    final staged = <File>[];
    try {
      for (final edition in data['editions'] as List) {
        final key = edition['coverLocalPath'];
        if (key == null) continue;
        if (key is! String ||
            !RegExp(r'^[a-zA-Z0-9-]+\.cover$').hasMatch(key) ||
            covers[key] is! String) {
          throw const FormatException('Missing or invalid cover.');
        }
        final contents = base64Decode(covers[key] as String);
        if (contents.isEmpty || contents.length > 20 * 1024 * 1024) {
          throw const FormatException('Invalid cover size.');
        }
        final file = File(
          p.join((await coverDirectory()).path, '${const Uuid().v4()}.cover'),
        );
        staged.add(file);
        await file.writeAsBytes(contents, flush: true);
        edition['coverLocalPath'] = file.path;
      }
      await repository.restoreData(data);
    } catch (_) {
      for (final file in staged) {
        if (await file.exists()) await file.delete();
      }
      rethrow;
    }
  }
}
