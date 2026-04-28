import 'package:flutter/material.dart';

String? encodeTime(TimeOfDay? time) {
  if (time == null) return null;
  final hours = time.hour.toString().padLeft(2, '0');
  final minutes = time.minute.toString().padLeft(2, '0');
  return '$hours:$minutes';
}

TimeOfDay? decodeTime(dynamic raw) {
  if (raw is! String) return null;
  final parts = raw.split(':');
  if (parts.length != 2) return null;

  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;

  return TimeOfDay(hour: hour, minute: minute);
}

class WorkInterval {
  const WorkInterval({
    this.start,
    this.end,
  });

  final TimeOfDay? start;
  final TimeOfDay? end;

  bool get isEmpty => start == null && end == null;

  Map<String, dynamic> toMap() {
    return {
      'start': encodeTime(start),
      'end': encodeTime(end),
    };
  }

  Map<String, TimeOfDay?> toLegacyMap() {
    return {
      'start': start,
      'end': end,
    };
  }

  factory WorkInterval.fromMap(dynamic raw) {
    if (raw is! Map) {
      return const WorkInterval();
    }

    return WorkInterval(
      start: decodeTime(raw['start']),
      end: decodeTime(raw['end']),
    );
  }

  factory WorkInterval.fromLegacyMap(Map<String, TimeOfDay?> raw) {
    return WorkInterval(
      start: raw['start'],
      end: raw['end'],
    );
  }
}

class RecordedPhoto {
  const RecordedPhoto({
    required this.path,
    required this.capturedAt,
  });

  final String path;
  final String capturedAt;

  Map<String, dynamic> toMap() {
    return {
      'path': path,
      'capturedAt': capturedAt,
    };
  }

  Map<String, String> toLegacyMap() {
    return {
      'path': path,
      'capturedAt': capturedAt,
    };
  }

  factory RecordedPhoto.fromMap(dynamic raw) {
    if (raw is! Map) {
      return const RecordedPhoto(path: '', capturedAt: '');
    }

    return RecordedPhoto(
      path: raw['path']?.toString() ?? '',
      capturedAt: raw['capturedAt']?.toString() ?? '',
    );
  }

  factory RecordedPhoto.fromLegacyMap(Map<String, String> raw) {
    return RecordedPhoto(
      path: raw['path'] ?? '',
      capturedAt: raw['capturedAt'] ?? '',
    );
  }
}

class DayRecord {
  const DayRecord({
    this.start,
    this.end,
    this.intervals = const [],
    this.photos = const [],
    this.notes = '',
  });

  final TimeOfDay? start;
  final TimeOfDay? end;
  final List<WorkInterval> intervals;
  final List<RecordedPhoto> photos;
  final String notes;

  bool get isEmpty {
    return start == null &&
        end == null &&
        intervals.every((interval) => interval.isEmpty) &&
        photos.isEmpty &&
        notes.trim().isEmpty;
  }

  bool get hasWorkEntry => start != null && end != null;

  Map<String, dynamic> toMap() {
    return {
      'start': encodeTime(start),
      'end': encodeTime(end),
      'intervals': intervals.map((interval) => interval.toMap()).toList(),
      'photos': photos.map((photo) => photo.toMap()).toList(),
      'notes': notes,
    };
  }

  List<Map<String, TimeOfDay?>> toLegacyIntervals() {
    return intervals.map((interval) => interval.toLegacyMap()).toList();
  }

  List<Map<String, String>> toLegacyPhotos() {
    return photos.map((photo) => photo.toLegacyMap()).toList();
  }

  factory DayRecord.fromMap(dynamic raw) {
    if (raw is! Map) {
      return const DayRecord();
    }

    final intervalList = <WorkInterval>[];
    final rawIntervals = raw['intervals'];
    if (rawIntervals is List) {
      for (final entry in rawIntervals) {
        intervalList.add(WorkInterval.fromMap(entry));
      }
    }

    final photoList = <RecordedPhoto>[];
    final rawPhotos = raw['photos'];
    if (rawPhotos is List) {
      for (final entry in rawPhotos) {
        final photo = RecordedPhoto.fromMap(entry);
        if (photo.path.isNotEmpty) {
          photoList.add(photo);
        }
      }
    }

    return DayRecord(
      start: decodeTime(raw['start']),
      end: decodeTime(raw['end']),
      intervals: intervalList,
      photos: photoList,
      notes: raw['notes']?.toString() ?? '',
    );
  }
}

Map<String, DayRecord> decodeDayRecordMap(dynamic raw) {
  if (raw is! Map) {
    return {};
  }

  final decoded = <String, DayRecord>{};
  for (final entry in raw.entries) {
    decoded[entry.key.toString()] = DayRecord.fromMap(entry.value);
  }
  return decoded;
}

Map<String, dynamic> encodeDayRecordMap(Map<String, DayRecord> records) {
  return {
    for (final entry in records.entries) entry.key: entry.value.toMap(),
  };
}
