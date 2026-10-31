import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// All schedule logic runs on Africa/Cairo wall-clock time.
///
/// Egypt alternates between UTC+2 (EET, winter) and UTC+3 (EEST, summer
/// daylight saving: last Friday of April -> last Thursday of October). The
/// IANA database bundled in the `timezone` package carries those rules, so
/// we never hard-code an offset.
class CairoTime {
  CairoTime._();

  static bool _initialized = false;
  static late tz.Location _cairo;

  static void ensureInitialized() {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    _cairo = tz.getLocation('Africa/Cairo');
    _initialized = true;
  }

  static tz.Location get location {
    ensureInitialized();
    return _cairo;
  }

  /// Converts any instant to Cairo wall time.
  static tz.TZDateTime fromInstant(DateTime instant) {
    ensureInitialized();
    return tz.TZDateTime.from(instant, _cairo);
  }

  static tz.TZDateTime now() => fromInstant(DateTime.now());

  /// Builds a Cairo wall-clock moment. Overflowing minutes (e.g. 24:30) roll
  /// into the next day.
  static tz.TZDateTime at(int year, int month, int day, [int minutesOfDay = 0]) {
    ensureInitialized();
    return tz.TZDateTime(_cairo, year, month, day, 0, minutesOfDay);
  }

  /// Cairo midnight at the start of the given Cairo calendar day.
  static tz.TZDateTime startOfDay(tz.TZDateTime t) => at(t.year, t.month, t.day);

  /// Cairo calendar date of a stored date value. Date-only strings parse as
  /// local (non-UTC) DateTimes and keep their y/m/d; UTC instants (e.g.
  /// Firestore Timestamps) are converted to Cairo first.
  static DateTime calendarDate(DateTime d) {
    if (d.isUtc) {
      final c = fromInstant(d);
      return DateTime(c.year, c.month, c.day);
    }
    return DateTime(d.year, d.month, d.day);
  }
}
