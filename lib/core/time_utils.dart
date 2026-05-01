import 'package:intl/intl.dart';

DateTime shanghaiNow() {
  return DateTime.now().toUtc().add(const Duration(hours: 8));
}

String formatShanghaiDay(DateTime value) {
  return DateFormat(
    'yyyy-MM-dd',
  ).format(value.toUtc().add(const Duration(hours: 8)));
}

String formatDateTime(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return '-';
  }
  final normalized = raw.replaceFirst('T', ' ');
  if (normalized.length >= 19) {
    return normalized.substring(0, 19);
  }
  return normalized;
}

String monthOf(DateTime value) {
  return DateFormat('yyyy-MM').format(value);
}

String monthLabel(String month) {
  if (month.length != 7) {
    return month;
  }
  return '${month.substring(0, 4)}年${month.substring(5)}月';
}

String monthStart(String month) {
  return '$month-01';
}

String monthEnd(String month) {
  final parts = month.split('-');
  if (parts.length != 2) {
    return '$month-01';
  }
  final year = int.tryParse(parts[0]) ?? 1970;
  final mon = int.tryParse(parts[1]) ?? 1;
  final days = DateTime.utc(year, mon + 1, 0).day;
  return '$month-${days.toString().padLeft(2, '0')}';
}

int monthDays(String month) {
  final parts = month.split('-');
  if (parts.length != 2) {
    return 30;
  }
  final year = int.tryParse(parts[0]) ?? 1970;
  final mon = int.tryParse(parts[1]) ?? 1;
  return DateTime.utc(year, mon + 1, 0).day;
}

String addMonths(String month, int delta) {
  final parts = month.split('-');
  if (parts.length != 2) {
    return month;
  }
  final year = int.tryParse(parts[0]) ?? 1970;
  final mon = int.tryParse(parts[1]) ?? 1;
  final value = DateTime.utc(year, mon - 1 + delta, 1);
  return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}';
}

List<String> monthsBetween(String startMonth, String endMonth) {
  final out = <String>[];
  var cursor = startMonth;
  while (cursor.compareTo(endMonth) <= 0) {
    out.add(cursor);
    cursor = addMonths(cursor, 1);
  }
  return out;
}

List<String> daysBetween(String startDay, String endDay) {
  final begin = DateTime.parse('${startDay}T00:00:00');
  final end = DateTime.parse('${endDay}T00:00:00');
  final out = <String>[];
  var cursor = begin;
  while (!cursor.isAfter(end)) {
    out.add(DateFormat('yyyy-MM-dd').format(cursor));
    cursor = cursor.add(const Duration(days: 1));
  }
  return out;
}
