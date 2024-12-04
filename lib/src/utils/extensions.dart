import 'package:flutter/material.dart';

///
extension CapitalizedString on String {
  /// Returns new [String] which has the first letter in upper case.
  String capitalized() => '${this[0].toUpperCase()}${substring(1)}';
}

///
extension DurationInWeeks on Duration {
  /// The number of entire weeks spanned by this Duration.
  int inWeeks(int visibleDay) => inDays ~/ visibleDay;
}

///
extension WeekUtils on DateTime {
  /// Returns all day dates of current week from Monday (1) to Sunday (7).
  DateTimeRange weekRange(int visibleDays, {bool weekStartsOnSunday = true}) {
    if (visibleDays == 7) {
      return DateTimeRange(
        start: DateUtils.addDaysToDate(this, 1 - weekday - (weekStartsOnSunday ? 1 : 0)),
        end: DateUtils.addDaysToDate(this, 8 - weekday - (weekStartsOnSunday ? 1 : 0)),
      );
    }
    final range = DateTimeRange(
      start: DateUtils.addDaysToDate(this, 0),
      end: DateUtils.addDaysToDate(this, visibleDays),
    );
    return range;
  }

  DateTime addWeeks(int visibleDays, int weeks) {
    return DateUtils.addDaysToDate(
      this,
      weeks * visibleDays,
    );
  }

  /// Returns result of check whether both dates are in the same week range.
  bool isSameWeekAs(int visibleDays, DateTime? other) {
    if (other == null) return false;
    final week = weekRange(visibleDays);
    return !other.isBefore(week.start) && other.isBefore(week.end);
  }
}

///
extension MonthUtils on DateTime {
  /// Returns day dates of 6 weeks which include current month.
  DateTimeRange monthViewRange({
    bool weekStartsOnSunday = false,
    int numberOfWeeks = 6,
  }) {
    final first = DateUtils.addDaysToDate(
      this,
      1 - day,
    );
    final startDate = DateUtils.addDaysToDate(
      first,
      1 - first.weekday - (weekStartsOnSunday ? 1 : 0),
    );

    /// In case of clock change, set end day to 12:00
    return DateTimeRange(
      start: startDate,
      end: DateUtils.addDaysToDate(
        startDate,
        numberOfWeeks * 7,
      ).add(const Duration(hours: 12)),
    );
  }
}

///
extension DaysList on DateTimeRange {
  /// Returns all days dates between [start] and [end] values.
  List<DateTime> get days => List.generate(
        duration.inDays,
        (index) => DateUtils.addDaysToDate(start, index),
      );
}
