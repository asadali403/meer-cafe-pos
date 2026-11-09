import 'package:intl/intl.dart';

/// Date helpers. Timestamps are stored as local time text `yyyy-MM-dd HH:mm:ss`
/// (sortable, SQLite date-function friendly). Business dates are `yyyy-MM-dd`.
class Dates {
  Dates._();

  static final _db = DateFormat('yyyy-MM-dd HH:mm:ss');
  static final _day = DateFormat('yyyy-MM-dd');
  static final _compact = DateFormat('yyyyMMdd');
  static final _display = DateFormat('dd MMM yyyy, hh:mm a');
  static final _displayDay = DateFormat('dd MMM yyyy');

  static String dbNow() => _db.format(DateTime.now());
  static String db(DateTime d) => _db.format(d);
  static String day(DateTime d) => _day.format(d);
  static String compact(DateTime d) => _compact.format(d);

  static DateTime parseDb(String s) => _db.parse(s);
  static DateTime parseDay(String s) => _day.parse(s);

  static String display(String dbText) {
    try {
      return _display.format(_db.parse(dbText));
    } catch (_) {
      return dbText;
    }
  }

  static String displayDay(String dayText) {
    try {
      return _displayDay.format(_day.parse(dayText));
    } catch (_) {
      return dayText;
    }
  }

  static DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  /// The cafe's day closes at 5 AM, not midnight: a bill at 2 AM belongs to the previous day.
  static const businessDayStartHour = 5;

  /// Calendar day (midnight) of the business day that [d] falls in.
  static DateTime businessDay(DateTime d) =>
      startOfDay(DateTime(d.year, d.month, d.day, d.hour - businessDayStartHour, d.minute, d.second));

  static String businessDate(DateTime d) => day(businessDay(d));

  /// Monday of the week containing [d].
  static DateTime startOfWeek(DateTime d) =>
      startOfDay(d).subtract(Duration(days: d.weekday - DateTime.monday));

  static DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
}
