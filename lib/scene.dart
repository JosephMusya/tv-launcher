import 'catalog.dart';
import 'info.dart';

// Picks a wallpaper for the moment by scoring every scene in the catalog
// against the time of day, the weather, the temperature and a mood derived
// from the hour and day of the week.

enum Period { dawn, day, dusk, night }

enum Sky { clear, cloudy, rain, storm, fog, snow }

enum Temp { hot, mild, cool, cold }

enum Mood { fresh, energetic, relaxed, calm }

class SceneContext {
  const SceneContext({required this.period, required this.sky, required this.temp, required this.mood});

  final Period period;
  final Set<Sky> sky; // empty when the weather is unknown (offline)
  final Temp? temp;
  final Mood mood;

  /// Changes only when the scene would, so the photo stays put between refreshes.
  String get key => '${period.name}/${sky.map((s) => s.name).join('+')}/${temp?.name}/${mood.name}';

  factory SceneContext.now({DateTime? local, Weather? weather}) {
    final now = local ?? DateTime.now();
    final minutes = now.hour * 60 + now.minute;
    final sunrise = weather?.sunrise ?? 6 * 60 + 15;
    final sunset = weather?.sunset ?? 18 * 60 + 30;

    final period = switch (minutes) {
      _ when minutes >= sunrise - 45 && minutes < sunrise + 90 => Period.dawn,
      _ when minutes >= sunrise + 90 && minutes < sunset - 75 => Period.day,
      _ when minutes >= sunset - 75 && minutes < sunset + 40 => Period.dusk,
      _ => Period.night,
    };

    final sky = <Sky>{
      if (weather != null)
        ...switch (weather.code) {
          0 || 1 => {Sky.clear},
          2 => {Sky.clear, Sky.cloudy},
          3 => {Sky.cloudy},
          45 || 48 => {Sky.fog},
          >= 51 && <= 67 || >= 80 && <= 82 => {Sky.rain},
          >= 71 && <= 77 || 85 || 86 => {Sky.snow},
          >= 95 => {Sky.storm},
          _ => <Sky>{},
        },
    };

    final c = weather == null ? null : (weather.fahrenheit ? (weather.temp - 32) * 5 / 9 : weather.temp.toDouble());
    final temp =
        c == null
            ? null
            : c >= 27
            ? Temp.hot
            : c >= 16
            ? Temp.mild
            : c >= 6
            ? Temp.cool
            : Temp.cold;

    final weekend = now.weekday >= DateTime.saturday;
    final mood = switch (now.hour) {
      >= 5 && < 11 => weekend ? Mood.relaxed : Mood.fresh,
      >= 11 && < 17 => weekend ? Mood.relaxed : Mood.energetic,
      >= 17 && < 22 => Mood.relaxed,
      _ => Mood.calm,
    };

    return SceneContext(period: period, sky: sky, temp: temp, mood: mood);
  }
}

class _Scene {
  const _Scene(this.periods, this.skies, {this.temps = const {}, this.moods = const {}});

  final Set<Period> periods;
  final Set<Sky> skies;
  final Set<Temp> temps;
  final Set<Mood> moods;

  double score(SceneContext c) {
    var s = 0.0;
    if (periods.contains(c.period)) s += 4;
    if (c.sky.isNotEmpty) {
      if (c.sky.any(skies.contains)) {
        s += 5;
      } else if (!c.sky.contains(Sky.clear) || !skies.contains(Sky.cloudy)) {
        // Showing a sunny beach while it pours outside is worse than a near miss.
        s -= 3;
      }
    }
    if (c.temp != null && temps.contains(c.temp)) s += 1.5;
    if (moods.contains(c.mood)) s += 1;
    return s;
  }
}

const _scenes = <String, _Scene>{
  'sunrise': _Scene({Period.dawn}, {Sky.clear, Sky.cloudy}, moods: {Mood.fresh, Mood.relaxed}),
  'sunset': _Scene({Period.dusk}, {Sky.clear, Sky.cloudy}, moods: {Mood.relaxed}),
  'stars': _Scene({Period.night}, {Sky.clear}, moods: {Mood.calm}),
  'citynight': _Scene({Period.night}, {Sky.cloudy, Sky.rain, Sky.fog}, moods: {Mood.relaxed, Mood.energetic}),
  'sunny': _Scene({Period.day}, {Sky.clear}, temps: {Temp.mild}, moods: {Mood.fresh}),
  'savanna': _Scene({Period.day}, {Sky.clear}, temps: {Temp.hot, Temp.mild}, moods: {Mood.energetic}),
  'beach': _Scene({Period.day}, {Sky.clear}, temps: {Temp.hot}, moods: {Mood.relaxed}),
  'mountain': _Scene(
    {Period.day},
    {Sky.clear, Sky.cloudy},
    temps: {Temp.cool, Temp.cold},
    moods: {Mood.fresh, Mood.energetic},
  ),
  'lake': _Scene(
    {Period.day, Period.dawn},
    {Sky.clear},
    temps: {Temp.mild, Temp.cool},
    moods: {Mood.calm, Mood.relaxed},
  ),
  'clouds': _Scene({Period.day, Period.dusk}, {Sky.cloudy}, moods: {Mood.calm, Mood.relaxed}),
  'forest': _Scene({Period.day}, {Sky.cloudy, Sky.fog, Sky.rain}, temps: {Temp.cool, Temp.mild}, moods: {Mood.calm}),
  'rain': _Scene({Period.day, Period.dawn, Period.dusk}, {Sky.rain}, moods: {Mood.calm}),
  'storm': _Scene({Period.day, Period.dusk, Period.night}, {Sky.storm}),
  'fog': _Scene({Period.dawn, Period.day}, {Sky.fog}, moods: {Mood.calm, Mood.fresh}),
  'snow': _Scene({Period.dawn, Period.day, Period.dusk}, {Sky.snow}, temps: {Temp.cold}),
};

/// The photo for this moment. The best-scoring scenes (within a point of the top)
/// pool their photos; which one is shown is fixed for the day and context.
CatalogPhoto pickPhoto(SceneContext c, DateTime day) {
  final scores = {for (final e in _scenes.entries) e.key: e.value.score(c)};
  final best = scores.values.reduce((a, b) => a > b ? a : b);
  final pool = kCatalog.where((p) => (scores[p.scene] ?? -99) >= best - 1).toList();
  // FNV-1a, since Object.hash isn't stable across app restarts.
  var seed = 0x811c9dc5;
  for (final unit in '${day.year}-${day.month}-${day.day}/${c.key}'.codeUnits) {
    seed = ((seed ^ unit) * 0x01000193) & 0xFFFFFFFF;
  }
  return pool[seed % pool.length];
}
