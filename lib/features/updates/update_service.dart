import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

const releasesOrigin =
    'https://github.com/AlexandruOlariu/books_companion/releases';

class InstalledApp {
  final String version;
  final int buildNumber;
  final String applicationId;
  const InstalledApp(this.version, this.buildNumber, this.applicationId);
}

class AppUpdate {
  final String version;
  final int buildNumber;
  final Uri download;
  const AppUpdate(this.version, this.buildNumber, this.download);

  /// Only the project's signed release pipeline produces this manifest.
  /// Android also verifies the APK's signature before installing an update.
  static AppUpdate? fromManifest(
    Map<String, dynamic> json,
    InstalledApp installed,
  ) {
    final version = json['version'];
    final build = json['buildNumber'];
    final download = Uri.tryParse(json['downloadUrl'] as String? ?? '');
    if (json['schema'] != 1 ||
        json['applicationId'] != installed.applicationId ||
        version is! String ||
        !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version) ||
        build is! int ||
        build <= 0 ||
        download == null ||
        download.scheme != 'https' ||
        download.host != 'github.com' ||
        download.hasPort ||
        download.userInfo.isNotEmpty ||
        download.hasQuery ||
        download.hasFragment ||
        download.path !=
            '/AlexandruOlariu/books_companion/releases/download/v$version/reading-library.apk') {
      throw const FormatException('Invalid update information.');
    }
    return build > installed.buildNumber
        ? AppUpdate(version, build, download)
        : null;
  }
}

abstract class UpdateService {
  Future<InstalledApp> installed();
  Future<AppUpdate?> latest(InstalledApp app);
  Future<void> download(AppUpdate update);
}

class AndroidUpdateService implements UpdateService {
  static const _channel = MethodChannel('reading_library/updates');

  @override
  Future<InstalledApp> installed() async {
    final info = await _channel.invokeMapMethod<String, dynamic>('installed');
    return InstalledApp(
      info!['version'] as String,
      info['buildNumber'] as int,
      info['applicationId'] as String,
    );
  }

  @override
  Future<AppUpdate?> latest(InstalledApp app) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      return await _fetch(client, app).timeout(const Duration(seconds: 15));
    } finally {
      client.close(force: true);
    }
  }

  Future<AppUpdate?> _fetch(HttpClient client, InstalledApp app) async {
    final request = await client.getUrl(
      Uri.parse('$releasesOrigin/latest/download/update.json'),
    );
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw const HttpException('Update information is unavailable.');
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      if (bytes.length + chunk.length > 64 * 1024) {
        throw const FormatException('Update information is too large.');
      }
      bytes.addAll(chunk);
    }
    return AppUpdate.fromManifest(
      jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
      app,
    );
  }

  @override
  Future<void> download(AppUpdate update) =>
      _channel.invokeMethod<void>('download', update.download.toString());
}
