import 'package:intl/intl.dart';

/// Preset report periods. Weeks start on Monday.
enum PeriodKind {
  today('Today'),
  yesterday('Yesterday'),
  thisWeek('This week'),
  lastWeek('Last week'),
  thisMonth('This month'),
  lastMonth('Last month'),
  last30('Last 30 days'),
  thisYear('This year'),
  custom('Custom');

  const PeriodKind(this.label);
  final String label;
}

/// A local-time range [start, end). Stored dates are UTC ISO text, so
/// queries use [fromIso] / [toIso].
class ReportRange {
  const ReportRange(this.start, this.end, {this.kind = PeriodKind.custom});

  final DateTime start;
  final DateTime end;
  final PeriodKind kind;

  String get fromIso => start.toUtc().toIso8601String();
  String get toIso => end.toUtc().toIso8601String();
  int get days => DateTime(end.year, end.month, end.day)
      .difference(DateTime(start.year, start.month, start.day))
      .inDays;

  /// The period just before, of the same kind (calendar month for months).
  ReportRange get previous {
    switch (kind) {
      case PeriodKind.thisMonth:
      case PeriodKind.lastMonth:
        return ReportRange(DateTime(start.year, start.month - 1, 1), start, kind: kind);
      case PeriodKind.thisYear:
        return ReportRange(DateTime(start.year - 1, 1, 1), start, kind: kind);
      default:
        final len = days;
        return ReportRange(
            DateTime(start.year, start.month, start.day - len), start, kind: kind);
    }
  }

  String get label {
    final d = DateFormat('d MMM yyyy');
    final last = end.subtract(const Duration(milliseconds: 1));
    if (days <= 1) return d.format(start);
    return '${d.format(start)} – ${d.format(last)}';
  }

  @override
  bool operator ==(Object other) =>
      other is ReportRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

ReportRange rangeFor(PeriodKind kind, {DateTime? now, ReportRange? custom}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  DateTime day(int offset) => DateTime(today.year, today.month, today.day + offset);
  final monday = day(-(today.weekday - 1));
  switch (kind) {
    case PeriodKind.today:
      return ReportRange(today, day(1), kind: kind);
    case PeriodKind.yesterday:
      return ReportRange(day(-1), today, kind: kind);
    case PeriodKind.thisWeek:
      return ReportRange(monday, DateTime(monday.year, monday.month, monday.day + 7), kind: kind);
    case PeriodKind.lastWeek:
      return ReportRange(DateTime(monday.year, monday.month, monday.day - 7), monday, kind: kind);
    case PeriodKind.thisMonth:
      return ReportRange(DateTime(today.year, today.month, 1),
          DateTime(today.year, today.month + 1, 1), kind: kind);
    case PeriodKind.lastMonth:
      return ReportRange(DateTime(today.year, today.month - 1, 1),
          DateTime(today.year, today.month, 1), kind: kind);
    case PeriodKind.last30:
      return ReportRange(day(-29), day(1), kind: kind);
    case PeriodKind.thisYear:
      return ReportRange(DateTime(today.year, 1, 1), DateTime(today.year + 1, 1, 1), kind: kind);
    case PeriodKind.custom:
      return custom ?? ReportRange(today, day(1));
  }
}

/// Percent change from [before] to [now], or null when there is nothing to compare.
double? percentChange(num now, num before) {
  if (before == 0) return null;
  return (now - before) / before.abs() * 100;
}
