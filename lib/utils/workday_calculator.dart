import 'package:flutter/material.dart';

import '../config/app_constants.dart' as app_constants;
import '../models/day_record.dart';
import 'date_utils.dart';

class WorkSummary {
  const WorkSummary({
    this.worked = 0,
    this.extra = 0,
    this.balance = 0,
    this.night = 0,
    this.days = 0,
  });

  final int worked;
  final int extra;
  final int balance;
  final int night;
  final int days;
}

class WorkdayCalculator {
  const WorkdayCalculator({
    this.normalWorkMinutes = app_constants.normalWorkMinutes,
    this.nightStartMinutes = app_constants.nightStartMinutes,
    this.nightEndMinutes = app_constants.nightEndMinutes,
  });

  final int normalWorkMinutes;
  final int nightStartMinutes;
  final int nightEndMinutes;

  Duration workedDurationForRecord(DayRecord record) {
    return Duration(minutes: workedMinutesForRecord(record));
  }

  int workedMinutesForRecord(DayRecord record) {
    return calculateWorkedMinutes(record.start, record.end, record.intervals);
  }

  int nightWorkedMinutesForRecord(DateTime referenceDay, DayRecord record) {
    return calculateNightWorkedMinutes(
      referenceDay: referenceDay,
      dayStart: record.start,
      dayEnd: record.end,
      dayIntervals: record.intervals,
    );
  }

  int calculateWorkedMinutes(
    TimeOfDay? dayStart,
    TimeOfDay? dayEnd,
    List<WorkInterval> dayIntervals,
  ) {
    if (dayStart == null || dayEnd == null) return 0;

    var total = _minutesDiff(
      start: dayStart,
      end: dayEnd,
      equalMeansFullDay: true,
    );

    for (final interval in dayIntervals) {
      if (interval.start != null && interval.end != null) {
        total -= _minutesDiff(
          start: interval.start!,
          end: interval.end!,
        );
      }
    }

    if (total < 0) return 0;
    return total;
  }

  int calculateNightWorkedMinutes({
    required DateTime referenceDay,
    required TimeOfDay? dayStart,
    required TimeOfDay? dayEnd,
    required List<WorkInterval> dayIntervals,
  }) {
    if (dayStart == null || dayEnd == null) return 0;

    final shiftStart = _combineDateAndTime(referenceDay, dayStart);
    var shiftEnd = _combineDateAndTime(referenceDay, dayEnd);
    if (!shiftEnd.isAfter(shiftStart)) {
      shiftEnd = shiftEnd.add(const Duration(days: 1));
    }

    final intervalRanges = <MapEntry<DateTime, DateTime>>[];
    for (final interval in dayIntervals) {
      if (interval.start == null || interval.end == null) continue;

      final resolvedRange = _resolveIntervalRangeForShift(
        referenceDay: referenceDay,
        shiftStart: shiftStart,
        shiftEnd: shiftEnd,
        shiftStartTime: dayStart,
        intervalStart: interval.start!,
        intervalEnd: interval.end!,
      );
      if (resolvedRange != null) {
        intervalRanges.add(resolvedRange);
      }
    }

    var nightWorkedMinutes = 0;
    for (
      var cursor = shiftStart;
      cursor.isBefore(shiftEnd);
      cursor = cursor.add(const Duration(minutes: 1))
    ) {
      final isOnBreak = intervalRanges.any(
        (range) => !cursor.isBefore(range.key) && cursor.isBefore(range.value),
      );
      if (isOnBreak) continue;
      if (_isMinuteInNightWindow(cursor)) {
        nightWorkedMinutes++;
      }
    }

    return nightWorkedMinutes;
  }

  WorkSummary monthSummary(
    Map<String, DayRecord> records,
    DateTime referenceDay,
  ) {
    var worked = 0;
    var extra = 0;
    var balance = 0;
    var night = 0;
    var days = 0;

    for (final entry in records.entries) {
      final day = parseDayKey(entry.key);
      final record = entry.value;
      if (day == null || !record.hasWorkEntry) continue;
      if (day.year != referenceDay.year || day.month != referenceDay.month) {
        continue;
      }

      final dayWorked = workedMinutesForRecord(record);
      worked += dayWorked;
      extra += dayWorked > normalWorkMinutes ? dayWorked - normalWorkMinutes : 0;
      balance += dayWorked - normalWorkMinutes;
      night += nightWorkedMinutesForRecord(day, record);
      days++;
    }

    return WorkSummary(
      worked: worked,
      extra: extra,
      balance: balance,
      night: night,
      days: days,
    );
  }

  WorkSummary rangeSummary(
    Map<String, DayRecord> records,
    DateTime startDay,
    DateTime endDay,
  ) {
    final normalizedStart = dateOnly(startDay);
    final normalizedEnd = dateOnly(endDay);
    final from = normalizedStart.isAfter(normalizedEnd)
        ? normalizedEnd
        : normalizedStart;
    final to = normalizedStart.isAfter(normalizedEnd)
        ? normalizedStart
        : normalizedEnd;

    var worked = 0;
    var extra = 0;
    var balance = 0;
    var night = 0;
    var days = 0;

    for (final entry in records.entries) {
      final day = parseDayKey(entry.key);
      final record = entry.value;
      if (day == null || !record.hasWorkEntry) continue;
      if (day.isBefore(from) || day.isAfter(to)) continue;

      final dayWorked = workedMinutesForRecord(record);
      worked += dayWorked;
      extra += dayWorked > normalWorkMinutes ? dayWorked - normalWorkMinutes : 0;
      balance += dayWorked - normalWorkMinutes;
      night += nightWorkedMinutesForRecord(day, record);
      days++;
    }

    return WorkSummary(
      worked: worked,
      extra: extra,
      balance: balance,
      night: night,
      days: days,
    );
  }

  List<MapEntry<DateTime, DayRecord>> rangeEntriesWithWork(
    Map<String, DayRecord> records,
    DateTime startDay,
    DateTime endDay,
  ) {
    final normalizedStart = dateOnly(startDay);
    final normalizedEnd = dateOnly(endDay);
    final from = normalizedStart.isAfter(normalizedEnd)
        ? normalizedEnd
        : normalizedStart;
    final to = normalizedStart.isAfter(normalizedEnd)
        ? normalizedStart
        : normalizedEnd;

    final entries = <MapEntry<DateTime, DayRecord>>[];
    for (final entry in records.entries) {
      final day = parseDayKey(entry.key);
      if (day == null || !entry.value.hasWorkEntry) continue;
      if (day.isBefore(from) || day.isAfter(to)) continue;
      entries.add(MapEntry(day, entry.value));
    }

    entries.sort((left, right) => left.key.compareTo(right.key));
    return entries;
  }

  int _minutesDiff({
    required TimeOfDay start,
    required TimeOfDay end,
    bool equalMeansFullDay = false,
  }) {
    final startMinutes = start.hour * 60 + start.minute;
    var endMinutes = end.hour * 60 + end.minute;

    if (endMinutes < startMinutes) {
      endMinutes += 24 * 60;
    } else if (equalMeansFullDay && endMinutes == startMinutes) {
      endMinutes += 24 * 60;
    }

    return endMinutes - startMinutes;
  }

  DateTime _combineDateAndTime(DateTime day, TimeOfDay time) {
    return DateTime(day.year, day.month, day.day, time.hour, time.minute);
  }

  MapEntry<DateTime, DateTime>? _resolveIntervalRangeForShift({
    required DateTime referenceDay,
    required DateTime shiftStart,
    required DateTime shiftEnd,
    required TimeOfDay shiftStartTime,
    required TimeOfDay intervalStart,
    required TimeOfDay intervalEnd,
  }) {
    var intervalStartDateTime = _combineDateAndTime(referenceDay, intervalStart);
    var intervalEndDateTime = _combineDateAndTime(referenceDay, intervalEnd);

    final shiftCrossesMidnight = shiftEnd.day != shiftStart.day ||
        shiftEnd.month != shiftStart.month ||
        shiftEnd.year != shiftStart.year;
    final shiftStartTotalMinutes =
        shiftStartTime.hour * 60 + shiftStartTime.minute;
    final intervalStartTotalMinutes =
        intervalStart.hour * 60 + intervalStart.minute;

    if (shiftCrossesMidnight &&
        intervalStartTotalMinutes < shiftStartTotalMinutes) {
      intervalStartDateTime = intervalStartDateTime.add(const Duration(days: 1));
      intervalEndDateTime = intervalEndDateTime.add(const Duration(days: 1));
    }

    if (!intervalEndDateTime.isAfter(intervalStartDateTime)) {
      intervalEndDateTime = intervalEndDateTime.add(const Duration(days: 1));
    }

    if (!intervalEndDateTime.isAfter(shiftStart) ||
        !intervalStartDateTime.isBefore(shiftEnd)) {
      return null;
    }

    if (intervalStartDateTime.isBefore(shiftStart)) {
      intervalStartDateTime = shiftStart;
    }
    if (intervalEndDateTime.isAfter(shiftEnd)) {
      intervalEndDateTime = shiftEnd;
    }

    if (!intervalEndDateTime.isAfter(intervalStartDateTime)) {
      return null;
    }

    return MapEntry(intervalStartDateTime, intervalEndDateTime);
  }

  bool _isMinuteInNightWindow(DateTime instant) {
    final minuteOfDay = instant.hour * 60 + instant.minute;
    return minuteOfDay >= nightStartMinutes || minuteOfDay < nightEndMinutes;
  }
}
