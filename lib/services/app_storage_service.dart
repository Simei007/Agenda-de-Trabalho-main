import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_constants.dart';
import '../models/day_record.dart';

Future<Directory> _defaultDocumentsDirectoryProvider() {
  return getApplicationDocumentsDirectory();
}

class LoadedAppData {
  const LoadedAppData({
    required this.savedByDay,
    required this.apkInstallUrl,
  });

  final Map<String, DayRecord> savedByDay;
  final String apkInstallUrl;
}

class RestoredBackupData {
  const RestoredBackupData({
    required this.savedByDay,
    required this.apkInstallUrl,
    required this.embeddedPhotosRestored,
  });

  final Map<String, DayRecord> savedByDay;
  final String apkInstallUrl;
  final int embeddedPhotosRestored;
}

class AppStorageService {
  AppStorageService({
    Future<SharedPreferences> Function()? preferencesProvider,
    Future<Directory> Function()? documentsDirectoryProvider,
  })  : _preferencesProvider =
            preferencesProvider ?? SharedPreferences.getInstance,
        _documentsDirectoryProvider =
            documentsDirectoryProvider ?? _defaultDocumentsDirectoryProvider;

  static const String _legacyStorageKey = 'agenda_trabalho_daily_data_v1';
  static const String _dayIndexKey = 'agenda_trabalho_daily_index_v2';
  static const String _dayStoragePrefix = 'agenda_trabalho_day_v2_';
  static const String _apkLinkKey = 'agenda_trabalho_apk_link_v1';

  final Future<SharedPreferences> Function() _preferencesProvider;
  final Future<Directory> Function() _documentsDirectoryProvider;

  bool isValidInstallUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        (uri.scheme.toLowerCase() == 'http' ||
            uri.scheme.toLowerCase() == 'https') &&
        uri.host.isNotEmpty;
  }

  Future<LoadedAppData> loadAppData() async {
    final prefs = await _preferencesProvider();
    final savedByDay = await _loadSavedByDay(prefs);
    final savedApkLink = prefs.getString(_apkLinkKey);
    final resolvedApkLink = isValidInstallUrl(savedApkLink ?? '')
        ? savedApkLink!.trim()
        : defaultApkInstallUrl;

    if (!isValidInstallUrl(savedApkLink ?? '')) {
      await prefs.setString(_apkLinkKey, resolvedApkLink);
    }

    return LoadedAppData(
      savedByDay: savedByDay,
      apkInstallUrl: resolvedApkLink,
    );
  }

  Future<void> saveInstallLink(String value) async {
    final prefs = await _preferencesProvider();
    await prefs.setString(_apkLinkKey, value);
  }

  Future<void> saveDayRecord(String dayKey, DayRecord? record) async {
    final prefs = await _preferencesProvider();
    final dayKeys = _readDayIndex(prefs);

    if (record == null || record.isEmpty) {
      dayKeys.remove(dayKey);
      await prefs.remove(_recordStorageKey(dayKey));
    } else {
      dayKeys.add(dayKey);
      await prefs.setString(
        _recordStorageKey(dayKey),
        jsonEncode(record.toMap()),
      );
    }

    await prefs.setStringList(_dayIndexKey, _sortedKeys(dayKeys));
    await prefs.remove(_legacyStorageKey);
  }

  Future<void> replaceAllDays(Map<String, DayRecord> records) async {
    final prefs = await _preferencesProvider();
    final existingKeys = _readDayIndex(prefs);
    for (final key in existingKeys) {
      await prefs.remove(_recordStorageKey(key));
    }

    final nextKeys = <String>{};
    for (final entry in records.entries) {
      if (entry.value.isEmpty) continue;
      nextKeys.add(entry.key);
      await prefs.setString(
        _recordStorageKey(entry.key),
        jsonEncode(entry.value.toMap()),
      );
    }

    await prefs.setStringList(_dayIndexKey, _sortedKeys(nextKeys));
    await prefs.remove(_legacyStorageKey);
  }

  Future<String> buildBackupJson({
    required Map<String, DayRecord> savedByDay,
    required String installUrl,
  }) async {
    final serializedDays = <String, dynamic>{};
    final orderedKeys = savedByDay.keys.toList()..sort();
    for (final key in orderedKeys) {
      serializedDays[key] = await _serializeBackupRecord(savedByDay[key]!);
    }

    final payload = {
      'schemaVersion': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'apkInstallUrl': installUrl,
      'savedByDay': serializedDays,
      'embeddedPhotos': true,
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<RestoredBackupData> restoreBackup(String backupText) async {
    final decoded = jsonDecode(backupText);
    if (decoded is! Map) {
      throw const FormatException('Formato invalido');
    }

    final root = Map<String, dynamic>.from(decoded);
    final savedRaw = root['savedByDay'] ?? root;
    if (savedRaw is! Map) {
      throw const FormatException('Campo savedByDay nao encontrado');
    }

    final restored = <String, DayRecord>{};
    var embeddedPhotosRestored = 0;
    for (final entry in savedRaw.entries) {
      final restoredRecord = await _restoreRecord(entry.value);
      embeddedPhotosRestored += restoredRecord.$2;
      if (!restoredRecord.$1.isEmpty) {
        restored[entry.key.toString()] = restoredRecord.$1;
      }
    }

    final restoredApkUrl = root['apkInstallUrl']?.toString().trim() ?? '';
    final effectiveApkUrl = isValidInstallUrl(restoredApkUrl)
        ? restoredApkUrl
        : defaultApkInstallUrl;

    return RestoredBackupData(
      savedByDay: restored,
      apkInstallUrl: effectiveApkUrl,
      embeddedPhotosRestored: embeddedPhotosRestored,
    );
  }

  Future<Map<String, DayRecord>> _loadSavedByDay(SharedPreferences prefs) async {
    final indexedKeys = _readDayIndex(prefs);
    if (indexedKeys.isNotEmpty) {
      final loaded = <String, DayRecord>{};
      for (final key in indexedKeys) {
        final raw = prefs.getString(_recordStorageKey(key));
        if (raw == null || raw.isEmpty) continue;
        try {
          loaded[key] = DayRecord.fromMap(jsonDecode(raw));
        } catch (_) {
          // Ignore invalid persisted day and keep loading the rest.
        }
      }
      return loaded;
    }

    final legacyRaw = prefs.getString(_legacyStorageKey);
    if (legacyRaw == null || legacyRaw.isEmpty) {
      return {};
    }

    try {
      final decoded = jsonDecode(legacyRaw);
      final migrated = decodeDayRecordMap(decoded);
      if (migrated.isNotEmpty) {
        await replaceAllDays(migrated);
      }
      return migrated;
    } catch (_) {
      return {};
    }
  }

  Set<String> _readDayIndex(SharedPreferences prefs) {
    return (prefs.getStringList(_dayIndexKey) ?? const <String>[]).toSet();
  }

  List<String> _sortedKeys(Set<String> keys) {
    final ordered = keys.toList()..sort();
    return ordered;
  }

  String _recordStorageKey(String dayKey) => '$_dayStoragePrefix$dayKey';

  Future<Map<String, dynamic>> _serializeBackupRecord(DayRecord record) async {
    final serialized = record.toMap();
    final photos = <Map<String, dynamic>>[];

    for (final photo in record.photos) {
      final photoMap = photo.toMap();
      final file = File(photo.path);
      if (await file.exists()) {
        final fileName =
            file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : '';
        final bytes = await file.readAsBytes();
        photoMap['fileName'] = fileName;
        photoMap['bytesBase64'] = base64Encode(bytes);
      }
      photos.add(photoMap);
    }

    serialized['photos'] = photos;
    return serialized;
  }

  Future<(DayRecord, int)> _restoreRecord(dynamic raw) async {
    if (raw is! Map) {
      return (const DayRecord(), 0);
    }

    final baseRecord = DayRecord.fromMap(raw);
    final rawPhotos = raw['photos'];
    if (rawPhotos is! List || rawPhotos.isEmpty) {
      return (baseRecord, 0);
    }

    final restoredPhotos = <RecordedPhoto>[];
    var restoredEmbeddedPhotos = 0;
    for (final entry in rawPhotos) {
      final restored = await _restorePhoto(entry);
      restoredEmbeddedPhotos += restored.$2 ? 1 : 0;
      if (restored.$1.path.isNotEmpty) {
        restoredPhotos.add(restored.$1);
      }
    }

    return (
      DayRecord(
        start: baseRecord.start,
        end: baseRecord.end,
        intervals: baseRecord.intervals,
        photos: restoredPhotos,
        notes: baseRecord.notes,
      ),
      restoredEmbeddedPhotos,
    );
  }

  Future<(RecordedPhoto, bool)> _restorePhoto(dynamic raw) async {
    final basePhoto = RecordedPhoto.fromMap(raw);
    if (raw is! Map) {
      return (basePhoto, false);
    }

    final encodedBytes = raw['bytesBase64']?.toString().trim() ?? '';
    if (encodedBytes.isEmpty) {
      return (basePhoto, false);
    }

    try {
      final bytes = base64Decode(encodedBytes);
      final photosDirectory = await _ensurePhotosDirectory();
      final extension =
          _photoExtension(raw['fileName']?.toString(), basePhoto.path);
      final targetName =
          'foto_restaurada_${DateTime.now().microsecondsSinceEpoch}$extension';
      final restoredFile = File(
        '${photosDirectory.path}${Platform.pathSeparator}$targetName',
      );
      await restoredFile.writeAsBytes(bytes, flush: true);

      return (
        RecordedPhoto(
          path: restoredFile.path,
          capturedAt: basePhoto.capturedAt,
        ),
        true,
      );
    } catch (_) {
      return (basePhoto, false);
    }
  }

  Future<Directory> _ensurePhotosDirectory() async {
    final docsDirectory = await _documentsDirectoryProvider();
    final photoDirectory = Directory(
      '${docsDirectory.path}${Platform.pathSeparator}agenda_fotos',
    );
    if (!await photoDirectory.exists()) {
      await photoDirectory.create(recursive: true);
    }
    return photoDirectory;
  }

  String _photoExtension(String? fileName, String fallbackPath) {
    final trimmedFileName = fileName?.trim() ?? '';
    final source = trimmedFileName.isNotEmpty ? trimmedFileName : fallbackPath;
    final dotIndex = source.lastIndexOf('.');
    if (dotIndex == -1) return '.jpg';
    return source.substring(dotIndex);
  }
}
