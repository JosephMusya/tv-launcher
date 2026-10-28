import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;

const _timeout = Duration(seconds: 10);

Future<dynamic> _json(String url) async {
  try {
    final response = await http.get(Uri.parse(url)).timeout(_timeout);
    if (response.statusCode != 200) return null;
    return jsonDecode(utf8.decode(response.bodyBytes));
  } catch (_) {
    return null;
  }
}

class Place {
  const Place({
    required this.city,
    required this.country,
    required this.countryCode,
    required this.lat,
    required this.lon,
    this.utcOffset,
  });

  final String city;
  final String country;
  final String countryCode;
  final double lat;
  final double lon;

  /// Offset of the viewer's timezone, so the clock is right even if the TV's isn't.
  final Duration? utcOffset;
}

Future<Place?> fetchPlace() async {
  final a = await _json('https://ipwho.is/');
  if (a is Map && a['success'] == true) {
    final tz = a['timezone'];
    return Place(
      city: a['city'] ?? '',
      country: a['country'] ?? '',
      countryCode: a['country_code'] ?? '',
      lat: (a['latitude'] as num).toDouble(),
      lon: (a['longitude'] as num).toDouble(),
      utcOffset: tz is Map && tz['offset'] is num ? Duration(seconds: (tz['offset'] as num).toInt()) : null,
    );
  }
  final b = await _json('https://ipapi.co/json/');
  if (b is Map && b['latitude'] is num) {
    Duration? offset;
    final s = b['utc_offset'];
    if (s is String && s.length == 5) {
      offset =
          Duration(hours: int.parse(s.substring(1, 3)), minutes: int.parse(s.substring(3))) *
          (s.startsWith('-') ? -1 : 1);
    }
    return Place(
      city: b['city'] ?? '',
      country: b['country_name'] ?? '',
      countryCode: b['country_code'] ?? '',
      lat: (b['latitude'] as num).toDouble(),
      lon: (b['longitude'] as num).toDouble(),
      utcOffset: offset,
    );
  }
  return null;
}

class Weather {
  const Weather({
    required this.temp,
    required this.high,
    required this.low,
    required this.code,
    required this.isDay,
    this.fahrenheit = false,
    this.sunrise,
    this.sunset,
  });

  final int temp;
  final int high;
  final int low;
  final int code;
  final bool isDay;
  final bool fahrenheit;

  /// Local sunrise and sunset, in minutes after midnight.
  final int? sunrise;
  final int? sunset;

  // WMO weather interpretation codes, as used by Open-Meteo.
  String get condition => switch (code) {
    0 => isDay ? 'Sunny' : 'Clear',
    1 => 'Mostly Clear',
    2 => 'Partly Cloudy',
    3 => 'Cloudy',
    45 || 48 => 'Foggy',
    >= 51 && <= 57 => 'Drizzle',
    >= 61 && <= 67 => 'Rain',
    >= 71 && <= 77 => 'Snow',
    >= 80 && <= 82 => 'Showers',
    85 || 86 => 'Snow Showers',
    >= 95 => 'Thunderstorms',
    _ => '',
  };

  IconData get icon => switch (code) {
    0 => isDay ? CupertinoIcons.sun_max_fill : CupertinoIcons.moon_stars_fill,
    1 || 2 => isDay ? CupertinoIcons.cloud_sun_fill : CupertinoIcons.cloud_moon_fill,
    3 => CupertinoIcons.cloud_fill,
    45 || 48 => CupertinoIcons.cloud_fog_fill,
    >= 51 && <= 57 => CupertinoIcons.cloud_drizzle_fill,
    >= 61 && <= 67 => CupertinoIcons.cloud_rain_fill,
    >= 71 && <= 77 || 85 || 86 => CupertinoIcons.cloud_snow_fill,
    >= 80 && <= 82 => CupertinoIcons.cloud_heavyrain_fill,
    >= 95 => CupertinoIcons.cloud_bolt_rain_fill,
    _ => CupertinoIcons.cloud_fill,
  };
}

Future<Weather?> fetchWeather(Place place) async {
  final unit = place.countryCode == 'US' ? '&temperature_unit=fahrenheit' : '';
  final j = await _json(
    'https://api.open-meteo.com/v1/forecast'
    '?latitude=${place.lat}&longitude=${place.lon}'
    '&current=temperature_2m,weather_code,is_day'
    '&daily=temperature_2m_max,temperature_2m_min,sunrise,sunset&forecast_days=1&timezone=auto$unit',
  );
  if (j is! Map || j['current'] is! Map || j['daily'] is! Map) return null;
  final current = j['current'] as Map;
  final daily = j['daily'] as Map;
  return Weather(
    temp: (current['temperature_2m'] as num).round(),
    high: ((daily['temperature_2m_max'] as List).first as num).round(),
    low: ((daily['temperature_2m_min'] as List).first as num).round(),
    code: (current['weather_code'] as num).toInt(),
    isDay: current['is_day'] == 1,
    fahrenheit: unit.isNotEmpty,
    sunrise: _minutes(daily['sunrise']),
    sunset: _minutes(daily['sunset']),
  );
}

// Open-Meteo returns local times like "2026-10-28T06:17".
int? _minutes(Object? times) {
  if (times is! List || times.isEmpty || times.first is! String) return null;
  final t = DateTime.tryParse(times.first as String);
  return t == null ? null : t.hour * 60 + t.minute;
}

class Quote {
  const Quote(this.text, this.author);

  final String text;
  final String author;
}

const _fallbackQuotes = [
  Quote('Less, but better.', 'Dieter Rams'),
  Quote('Design is not just what it looks like and feels like. Design is how it works.', 'Steve Jobs'),
  Quote('The best way to predict the future is to invent it.', 'Alan Kay'),
  Quote('Simple can be harder than complex.', 'Steve Jobs'),
  Quote('Well begun is half done.', 'Aristotle'),
  Quote('Stay hungry. Stay foolish.', 'Stewart Brand'),
];

Future<Quote> fetchQuote() async {
  final j = await _json('https://zenquotes.io/api/today');
  if (j is List && j.isNotEmpty && j.first is Map) {
    final q = j.first as Map;
    final text = q['q'];
    if (text is String && text.isNotEmpty && !text.startsWith('Too many requests')) {
      return Quote(text.trim(), (q['a'] as String? ?? '').trim());
    }
  }
  return _fallbackQuotes[DateTime.now().day % _fallbackQuotes.length];
}
