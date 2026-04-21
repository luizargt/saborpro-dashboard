import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum PeriodMode { day, week, month, year, custom }

class DateRange {
  final DateTime start;
  final DateTime end;
  final PeriodMode mode;

  DateRange({required this.start, required this.end, required this.mode});

  factory DateRange.today() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    return DateRange(start: start, end: end, mode: PeriodMode.day);
  }

  DateRange previous() {
    switch (mode) {
      case PeriodMode.day:
        final d = start.subtract(const Duration(days: 1));
        return DateRange(
          start: DateTime(d.year, d.month, d.day),
          end: DateTime(d.year, d.month, d.day, 23, 59, 59),
          mode: PeriodMode.day,
        );
      case PeriodMode.week:
        final d = start.subtract(const Duration(days: 7));
        final weekStart = d.subtract(Duration(days: d.weekday - 1));
        return DateRange(
          start: DateTime(weekStart.year, weekStart.month, weekStart.day),
          end: DateTime(weekStart.year, weekStart.month, weekStart.day + 6, 23, 59, 59),
          mode: PeriodMode.week,
        );
      case PeriodMode.month:
        final month = start.month == 1 ? 12 : start.month - 1;
        final year = start.month == 1 ? start.year - 1 : start.year;
        final lastDay = DateUtils.getDaysInMonth(year, month);
        return DateRange(
          start: DateTime(year, month, 1),
          end: DateTime(year, month, lastDay, 23, 59, 59),
          mode: PeriodMode.month,
        );
      case PeriodMode.year:
        return DateRange(
          start: DateTime(start.year - 1, 1, 1),
          end: DateTime(start.year - 1, 12, 31, 23, 59, 59),
          mode: PeriodMode.year,
        );
      case PeriodMode.custom:
        final diff = end.difference(start);
        return DateRange(
          start: start.subtract(diff + const Duration(days: 1)),
          end: start.subtract(const Duration(days: 1, hours: 0, minutes: 0, seconds: 1)),
          mode: PeriodMode.custom,
        );
    }
  }

  DateRange next() {
    switch (mode) {
      case PeriodMode.day:
        final d = start.add(const Duration(days: 1));
        return DateRange(
          start: DateTime(d.year, d.month, d.day),
          end: DateTime(d.year, d.month, d.day, 23, 59, 59),
          mode: PeriodMode.day,
        );
      case PeriodMode.week:
        final d = start.add(const Duration(days: 7));
        final weekStart = d.subtract(Duration(days: d.weekday - 1));
        return DateRange(
          start: DateTime(weekStart.year, weekStart.month, weekStart.day),
          end: DateTime(weekStart.year, weekStart.month, weekStart.day + 6, 23, 59, 59),
          mode: PeriodMode.week,
        );
      case PeriodMode.month:
        final month = start.month == 12 ? 1 : start.month + 1;
        final year = start.month == 12 ? start.year + 1 : start.year;
        final lastDay = DateUtils.getDaysInMonth(year, month);
        return DateRange(
          start: DateTime(year, month, 1),
          end: DateTime(year, month, lastDay, 23, 59, 59),
          mode: PeriodMode.month,
        );
      case PeriodMode.year:
        return DateRange(
          start: DateTime(start.year + 1, 1, 1),
          end: DateTime(start.year + 1, 12, 31, 23, 59, 59),
          mode: PeriodMode.year,
        );
      case PeriodMode.custom:
        return this;
    }
  }

  bool get isToday {
    final now = DateTime.now();
    return mode == PeriodMode.day &&
        start.year == now.year &&
        start.month == now.month &&
        start.day == now.day;
  }

  bool get isFuture => start.isAfter(DateTime.now());

  String get label {
    final locale = 'es';
    switch (mode) {
      case PeriodMode.day:
        if (isToday) return 'Hoy';
        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        if (start.year == yesterday.year &&
            start.month == yesterday.month &&
            start.day == yesterday.day) {
          return 'Ayer';
        }
        return DateFormat('d MMM yyyy', locale).format(start);
      case PeriodMode.week:
        final sameMonth = start.month == end.month && start.year == end.year;
        if (sameMonth) {
          return '${start.day}–${end.day} ${DateFormat('MMM', locale).format(start)}';
        }
        return '${DateFormat('d MMM', locale).format(start)} – ${DateFormat('d MMM', locale).format(end)}';
      case PeriodMode.month:
        return DateFormat('MMMM yyyy', locale).format(start);
      case PeriodMode.year:
        return start.year.toString();
      case PeriodMode.custom:
        return '${DateFormat('d MMM', locale).format(start)} – ${DateFormat('d MMM yyyy', locale).format(end)}';
    }
  }

  String get prevLabel {
    return previous().label;
  }
}
