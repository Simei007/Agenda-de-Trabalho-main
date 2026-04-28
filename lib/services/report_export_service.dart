import 'dart:io';

import 'package:excel/excel.dart' as xls;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../config/app_constants.dart';
import '../models/day_record.dart';
import '../utils/date_utils.dart';
import '../utils/workday_calculator.dart';

Future<Directory> _defaultReportDirectoryProvider() {
  return getApplicationDocumentsDirectory();
}

class ReportExportService {
  ReportExportService({
    WorkdayCalculator? calculator,
    Future<Directory> Function()? documentsDirectoryProvider,
    DateTime Function()? now,
  })  : _calculator = calculator ?? const WorkdayCalculator(),
        _documentsDirectoryProvider =
            documentsDirectoryProvider ?? _defaultReportDirectoryProvider,
        _now = now ?? DateTime.now;

  final WorkdayCalculator _calculator;
  final Future<Directory> Function() _documentsDirectoryProvider;
  final DateTime Function() _now;

  Future<File> buildRangeXlsxFile({
    required Map<String, DayRecord> records,
    required DateTime startDay,
    required DateTime endDay,
  }) async {
    final from = dateOnly(startDay);
    final to = dateOnly(endDay);
    final rows = _calculator.rangeEntriesWithWork(records, from, to);
    if (rows.isEmpty) {
      throw StateError(
        'Nao ha dias com entrada e saida no periodo selecionado.',
      );
    }

    final workbook = xls.Excel.createExcel();
    final sheet = workbook['Relatorio'];
    final summary = _calculator.rangeSummary(records, from, to);
    final now = _now();

    sheet.appendRow(['Relatorio de jornada']);
    sheet.appendRow(['Periodo', '${_dateLabel(from)} ate ${_dateLabel(to)}']);
    sheet.appendRow([
      'Gerado em',
      '${_dateLabel(now)} ${_timeLabel(TimeOfDay.fromDateTime(now))}',
    ]);
    sheet.appendRow(['Dias com registro', summary.days]);
    sheet.appendRow(['Trabalhadas', _minutesLabel(summary.worked)]);
    sheet.appendRow(['Extras', _minutesLabel(summary.extra)]);
    sheet.appendRow(['Saldo', _signedMinutesLabel(summary.balance)]);
    sheet.appendRow([
      'Adicional noturno (22h-5h)',
      _minutesLabel(summary.night),
    ]);
    sheet.appendRow(['']);
    sheet.appendRow([
      'Data',
      'Entrada',
      'Saida',
      'Intervalos',
      'Trabalhadas',
      'Extras',
      'Saldo',
      'Adicional noturno (22h-5h)',
      'Anotacoes',
      'Qtd fotos',
    ]);

    for (final row in rows) {
      final day = row.key;
      final record = row.value;
      final workedMinutes = _calculator.workedMinutesForRecord(record);
      final extraMinutes = workedMinutes > normalWorkMinutes
          ? workedMinutes - normalWorkMinutes
          : 0;
      final balanceMinutes = workedMinutes - normalWorkMinutes;
      final nightMinutes = _calculator.nightWorkedMinutesForRecord(day, record);
      final notes = record.notes.trim();

      sheet.appendRow([
        _dateLabel(day),
        _timeLabel(record.start),
        _timeLabel(record.end),
        _intervalsLabel(record),
        _minutesLabel(workedMinutes),
        _minutesLabel(extraMinutes),
        _signedMinutesLabel(balanceMinutes),
        _minutesLabel(nightMinutes),
        notes.isEmpty ? '-' : notes,
        record.photos.length,
      ]);
    }

    final bytes = workbook.encode();
    if (bytes == null || bytes.isEmpty) {
      throw const FileSystemException('Falha ao gerar o arquivo XLSX.');
    }

    final reportDirectory = await _ensureReportDirectory();
    final file = File(
      '${reportDirectory.path}${Platform.pathSeparator}'
      'jornada_${dayKey(from)}_a_${dayKey(to)}_${_fileTimestamp(now)}.xlsx',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<Directory> _ensureReportDirectory() async {
    final docsDirectory = await _documentsDirectoryProvider();
    final reportDirectory = Directory(
      '${docsDirectory.path}${Platform.pathSeparator}relatorios',
    );
    if (!await reportDirectory.exists()) {
      await reportDirectory.create(recursive: true);
    }
    return reportDirectory;
  }

  String _minutesLabel(int totalMinutes) {
    final safe = totalMinutes < 0 ? 0 : totalMinutes;
    final hours = safe ~/ 60;
    final minutes = safe % 60;
    return '${hours}h ${minutes.toString().padLeft(2, '0')}min';
  }

  String _signedMinutesLabel(int totalMinutes) {
    final sign = totalMinutes >= 0 ? '+' : '-';
    return '$sign ${_minutesLabel(totalMinutes.abs())}';
  }

  String _dateLabel(DateTime day) {
    final monthDay = day.day.toString().padLeft(2, '0');
    final month = day.month.toString().padLeft(2, '0');
    final year = day.year.toString().padLeft(4, '0');
    return '$monthDay/$month/$year';
  }

  String _timeLabel(TimeOfDay? time) {
    return encodeTime(time) ?? '-';
  }

  String _intervalsLabel(DayRecord record) {
    final labels = <String>[];
    for (final interval in record.intervals) {
      if (interval.start == null || interval.end == null) continue;
      labels.add('${_timeLabel(interval.start)}-${_timeLabel(interval.end)}');
    }
    return labels.isEmpty ? '-' : labels.join(' | ');
  }

  String _fileTimestamp(DateTime instant) {
    final year = instant.year.toString().padLeft(4, '0');
    final month = instant.month.toString().padLeft(2, '0');
    final monthDay = instant.day.toString().padLeft(2, '0');
    final hours = instant.hour.toString().padLeft(2, '0');
    final minutes = instant.minute.toString().padLeft(2, '0');
    final seconds = instant.second.toString().padLeft(2, '0');
    return '$year$month${monthDay}_$hours$minutes$seconds';
  }
}
