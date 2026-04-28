import 'dart:io';

import 'package:agenda_trabalho/models/day_record.dart';
import 'package:agenda_trabalho/services/app_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppStorageService', () {
    late Directory tempDir;
    late AppStorageService storageService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('agenda_trabalho_test_');
      storageService = AppStorageService(
        documentsDirectoryProvider: () async => tempDir,
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('stores day records individually and reloads them', () async {
      await storageService.saveDayRecord(
        '2026-04-22',
        DayRecord(
          start: const TimeOfDay(hour: 8, minute: 0),
          end: const TimeOfDay(hour: 16, minute: 20),
          intervals: const [
            WorkInterval(
              start: TimeOfDay(hour: 12, minute: 0),
              end: TimeOfDay(hour: 12, minute: 30),
            ),
          ],
          notes: 'Plantao regular',
        ),
      );

      final loaded = await storageService.loadAppData();
      final restored = loaded.savedByDay['2026-04-22'];

      expect(restored, isNotNull);
      expect(restored!.notes, 'Plantao regular');
      expect(restored.intervals, hasLength(1));
      expect(restored.intervals.single.start, const TimeOfDay(hour: 12, minute: 0));
      expect(restored.end, const TimeOfDay(hour: 16, minute: 20));
    });

    test('builds portable backup with embedded photos and restores them', () async {
      final sourcePhoto = File(
        '${tempDir.path}${Platform.pathSeparator}origem.jpg',
      );
      await sourcePhoto.writeAsBytes(const [1, 2, 3, 4], flush: true);

      final backup = await storageService.buildBackupJson(
        savedByDay: {
          '2026-04-22': DayRecord(
            start: const TimeOfDay(hour: 8, minute: 0),
            end: const TimeOfDay(hour: 16, minute: 20),
            photos: [
              RecordedPhoto(
                path: sourcePhoto.path,
                capturedAt: '2026-04-22T10:00:00.000',
              ),
            ],
            notes: 'Dia com foto',
          ),
        },
        installUrl: 'https://example.com/app.apk',
      );

      final restored = await storageService.restoreBackup(backup);
      final restoredPhoto = restored.savedByDay['2026-04-22']!.photos.single;
      final restoredFile = File(restoredPhoto.path);

      expect(restored.apkInstallUrl, 'https://example.com/app.apk');
      expect(restored.embeddedPhotosRestored, 1);
      expect(restoredPhoto.path, isNot(sourcePhoto.path));
      expect(await restoredFile.exists(), isTrue);
      expect(await restoredFile.readAsBytes(), orderedEquals(const [1, 2, 3, 4]));
    });
  });
}
