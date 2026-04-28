import 'package:agenda_trabalho/models/day_record.dart';
import 'package:agenda_trabalho/utils/workday_calculator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const calculator = WorkdayCalculator();

  group('WorkdayCalculator', () {
    test('calculates worked and night minutes across midnight', () {
      final record = DayRecord(
        start: const TimeOfDay(hour: 21, minute: 30),
        end: const TimeOfDay(hour: 5, minute: 30),
        intervals: const [
          WorkInterval(
            start: TimeOfDay(hour: 0, minute: 0),
            end: TimeOfDay(hour: 0, minute: 30),
          ),
        ],
      );

      expect(calculator.workedMinutesForRecord(record), 450);
      expect(
        calculator.nightWorkedMinutesForRecord(DateTime(2026, 4, 22), record),
        390,
      );
    });

    test('builds month and range summaries from saved records', () {
      final records = <String, DayRecord>{
        '2026-04-22': DayRecord(
          start: const TimeOfDay(hour: 8, minute: 0),
          end: const TimeOfDay(hour: 16, minute: 20),
        ),
        '2026-04-23': DayRecord(
          start: const TimeOfDay(hour: 8, minute: 0),
          end: const TimeOfDay(hour: 15, minute: 20),
        ),
        '2026-05-01': DayRecord(
          start: const TimeOfDay(hour: 22, minute: 0),
          end: const TimeOfDay(hour: 2, minute: 0),
        ),
      };

      final aprilSummary = calculator.monthSummary(records, DateTime(2026, 4, 30));
      expect(aprilSummary.worked, 940);
      expect(aprilSummary.extra, 60);
      expect(aprilSummary.balance, 60);
      expect(aprilSummary.night, 0);
      expect(aprilSummary.days, 2);

      final rangeSummary = calculator.rangeSummary(
        records,
        DateTime(2026, 5, 1),
        DateTime(2026, 4, 23),
      );
      expect(rangeSummary.worked, 680);
      expect(rangeSummary.extra, 0);
      expect(rangeSummary.balance, -200);
      expect(rangeSummary.night, 240);
      expect(rangeSummary.days, 2);
    });
  });
}
