// Offline sunset time (ADR-039): NOAA's general solar position equations
// (Global Monitoring Laboratory, "General Solar Position Calculations"),
// accurate to about a minute at the church's latitude. Pure Dart.

import 'dart:math' as math;

import 'cairo_time.dart';

/// The church (end of Street 45, El-Asafra, Alexandria): settings/church
/// lat / lng, used when the settings carry no coordinates.
const churchLat = 31.260138;
const churchLng = 30.01129;

double _rad(double d) => d * math.pi / 180;
double _deg(double r) => r * 180 / math.pi;

/// Sunset on the calendar date [date] (y/m/d) at [lat] / [lng] (degrees,
/// east positive) as a UTC instant, or null when the sun does not set that
/// day (polar latitudes; never in Egypt).
DateTime? sunsetUtc(DateTime date, {double lat = churchLat, double lng = churchLng}) {
  final day = DateTime.utc(date.year, date.month, date.day);
  final leap = (day.year % 4 == 0 && day.year % 100 != 0) || day.year % 400 == 0;
  final doy = day.difference(DateTime.utc(day.year)).inDays + 1;
  // Fractional year at local noon.
  final g = 2 * math.pi / (leap ? 366 : 365) * (doy - 1);
  final eqTime = 229.18 *
      (0.000075 + 0.001868 * math.cos(g) - 0.032077 * math.sin(g) - 0.014615 * math.cos(2 * g) -
          0.040849 * math.sin(2 * g));
  final decl = 0.006918 - 0.399912 * math.cos(g) + 0.070257 * math.sin(g) - 0.006758 * math.cos(2 * g) +
      0.000907 * math.sin(2 * g) - 0.002697 * math.cos(3 * g) + 0.00148 * math.sin(3 * g);
  final latR = _rad(lat);
  // 90.833°: refraction + the sun's apparent radius (official sunset).
  final cosHa = math.cos(_rad(90.833)) / (math.cos(latR) * math.cos(decl)) - math.tan(latR) * math.tan(decl);
  if (cosHa < -1 || cosHa > 1) return null;
  final ha = _deg(math.acos(cosHa));
  final minutesUtc = 720 - 4 * (lng - ha) - eqTime;
  return day.add(Duration(seconds: (minutesUtc * 60).round()));
}

/// Sunset at the church as minutes after local (Alexandria = Africa/Cairo)
/// midnight on the calendar date [date], e.g. 1019 for 16:59.
int sunsetLocalMinutes(DateTime date, {double lat = churchLat, double lng = churchLng}) {
  final s = sunsetUtc(date, lat: lat, lng: lng);
  if (s == null) return 18 * 60;
  final local = CairoTime.fromInstant(s);
  final start = CairoTime.at(date.year, date.month, date.day);
  return local.difference(start).inMinutes;
}
