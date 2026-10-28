import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'info.dart';
import 'catalog.dart';
import 'control.dart';
import 'platform.dart';
import 'scene.dart';
import 'ui.dart';
import 'wallpaper.dart';

const _topCount = 3;

// v2: the default changed to the dynamic wallpaper.
const _wallpaperKey = 'wallpaper.v2';

// Fill the row with these when there isn't enough usage history yet.
const _defaultTop = ['com.google.android.youtube.tv', 'com.google.android.youtube.tvmusic', 'com.android.vending'];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  SharedPreferences? _prefs;
  late final AppLifecycleListener _lifecycle;
  Timer? _refresh;
  Timer? _tick;
  bool _controlsOpen = false;

  List<App> _apps = [];
  List<String> _top = [];
  String _wallpaper = kDefaultWallpaper;
  String _day = '';

  Place? _place;
  Weather? _weather;
  Quote? _quote;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _loadApps);
    Launcher.onHome(_onHome);
    _refresh = Timer.periodic(const Duration(minutes: 20), (_) => _loadInfo());
    // Re-check the scene so the dynamic wallpaper follows dawn, dusk and night.
    _tick = Timer.periodic(const Duration(minutes: 5), (_) => setState(() {}));
    _init();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _refresh?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    setState(() => _wallpaper = _prefs!.getString(_wallpaperKey) ?? kDefaultWallpaper);
    await Future.wait([_loadApps(), _loadInfo()]);
  }

  Future<void> _loadApps() async {
    final apps = await Launcher.apps();
    // Usage stats see apps opened from anywhere; without that permission,
    // fall back to how often each app was opened from this launcher.
    final top = await Launcher.mostUsed() ?? _launchCounts();
    if (mounted) {
      setState(() {
        _apps = apps;
        _top = top;
      });
    }
  }

  List<String> _launchCounts() {
    final counts = <String, int>{};
    for (final p in _prefs?.getStringList('launches') ?? <String>[]) {
      counts[p] = (counts[p] ?? 0) + 1;
    }
    return (counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!)));
  }

  Future<void> _loadInfo() async {
    final now = DateTime.now();
    final day = '${now.year}-${now.month}-${now.day}';
    if (day != _day) {
      // New day: new quote and a new photo of the day.
      setState(() => _day = day);
      fetchQuote().then((q) => mounted ? setState(() => _quote = q) : null);
    }
    final place = _place ?? await fetchPlace();
    if (place == null || !mounted) return;
    setState(() => _place = place);
    final weather = await fetchWeather(place);
    if (mounted && weather != null) setState(() => _weather = weather);
  }

  /// Home pressed: closes overlays, or, if already on the home screen, opens Controls.
  void _onHome(bool inFront) {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.popUntil((route) => route.isFirst);
    } else if (inFront) {
      _openControls();
    }
  }

  void _openControls() {
    if (_controlsOpen) return;
    _controlsOpen = true;
    Navigator.of(context)
        .push(overlayRoute((animation) => ControlCenter(animation: animation, onWallpaper: _openWallpaperPicker)))
        .whenComplete(() => _controlsOpen = false);
  }

  DateTime get _localNow {
    final offset = _place?.utcOffset;
    return offset == null ? DateTime.now() : DateTime.now().toUtc().add(offset);
  }

  CatalogPhoto get _photo {
    final now = _localNow;
    return pickPhoto(SceneContext.now(local: now, weather: _weather), now);
  }

  void _launch(App app) {
    Launcher.launch(app.package);
    final launches = [app.package, ...?_prefs?.getStringList('launches')];
    _prefs?.setStringList('launches', launches.take(200).toList());
  }

  void _openAllApps() {
    Navigator.of(context).push(
      overlayRoute(
        (animation) => AllAppsScreen(
          animation: animation,
          apps: _apps,
          onLaunch: (app) {
            _launch(app);
            Navigator.of(context).pop();
          },
          onWallpaper: _openWallpaperPicker,
          onSettings: () {
            Launcher.openSettings();
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  void _openWallpaperPicker() {
    Navigator.of(context).push(
      overlayRoute(
        (animation) => WallpaperPicker(
          animation: animation,
          current: _wallpaper,
          photo: _photo,
          onPick: (spec) {
            setState(() => _wallpaper = spec);
            _prefs?.setString(_wallpaperKey, spec);
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final byPackage = {for (final a in _apps) a.package: a};
    final top =
        [
          ..._top,
          ..._defaultTop,
          ..._apps.map((a) => a.package),
        ].toSet().map((p) => byPackage[p]).whereType<App>().take(_topCount).toList();

    return PopScope(
      canPop: false,
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.contextMenu): _openControls},
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              Wallpaper(spec: _wallpaper, photo: _photo),
              const _Scrim(),
              Padding(
                padding: const EdgeInsets.fromLTRB(64, 44, 64, 40),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Clock(utcOffset: _place?.utcOffset),
                          if (_quote != null) ...[const SizedBox(height: 22), _QuoteView(_quote!)],
                          const Spacer(),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final (i, app) in top.indexed)
                                Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: TvFocusable(
                                    key: ValueKey(app.package),
                                    autofocus: i == 0,
                                    onSelect: () => _launch(app),
                                    builder: (context, focused) => AppIcon(app: app, size: 64, focused: focused),
                                  ),
                                ),
                              SizedBox(
                                height: 64,
                                child: Center(child: PillButton(label: 'More', onSelect: _openAllApps)),
                              ),
                              const SizedBox(width: 4),
                              SizedBox(
                                height: 64,
                                child: Center(
                                  child: PillButton(icon: CupertinoIcons.slider_horizontal_3, onSelect: _openControls),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 40),
                    SizedBox(
                      width: 272,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [_WeatherCard(place: _place, weather: _weather)],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Darkens the top-left and bottom of the wallpaper so text stays readable.
class _Scrim extends StatelessWidget {
  const _Scrim();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-1, -1),
              radius: 1.3,
              colors: [Color(0x66000000), Color(0x00000000)],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(0, 0.2),
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0x80000000)],
            ),
          ),
        ),
      ],
    );
  }
}

class _Clock extends StatefulWidget {
  const _Clock({this.utcOffset});

  final Duration? utcOffset;

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  late final Timer _timer;

  static const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offset = widget.utcOffset;
    final now = offset == null ? DateTime.now() : DateTime.now().toUtc().add(offset);
    final hour =
        MediaQuery.alwaysUse24HourFormatOf(context)
            ? now.hour.toString().padLeft(2, '0')
            : '${now.hour % 12 == 0 ? 12 : now.hour % 12}';
    final time = '$hour:${now.minute.toString().padLeft(2, '0')}';
    final date = '${_days[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          date,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: kSecondary, shadows: kTextShadow),
        ),
        Text(
          time,
          style: const TextStyle(
            fontSize: 108,
            fontWeight: FontWeight.w700,
            color: kPrimary,
            height: 1.05,
            letterSpacing: -4,
            shadows: kTextShadow,
          ),
        ),
      ],
    );
  }
}

class _QuoteView extends StatelessWidget {
  const _QuoteView(this.quote);

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '“${quote.text}”',
            style: const TextStyle(
              fontSize: 17,
              height: 1.4,
              fontWeight: FontWeight.w500,
              color: kPrimary,
              shadows: kTextShadow,
            ),
          ),
          if (quote.author.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(quote.author, style: const TextStyle(fontSize: 13, color: kSecondary, shadows: kTextShadow)),
          ],
        ],
      ),
    );
  }
}

class _WeatherCard extends StatelessWidget {
  const _WeatherCard({required this.place, required this.weather});

  final Place? place;
  final Weather? weather;

  @override
  Widget build(BuildContext context) {
    final w = weather;
    return Glass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  place?.city ?? 'Weather',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kPrimary),
                ),
              ),
              if (place != null) ...const [
                SizedBox(width: 5),
                Icon(CupertinoIcons.location_fill, size: 11, color: kPrimary),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                w == null ? '--' : '${w.temp}°',
                style: const TextStyle(fontSize: 46, fontWeight: FontWeight.w300, color: kPrimary, height: 1.15),
              ),
              const Spacer(),
              if (w != null) Icon(w.icon, size: 30, color: kPrimary),
            ],
          ),
          const SizedBox(height: 4),
          Text(w?.condition ?? ' ', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kPrimary)),
          Text(w == null ? ' ' : 'H:${w.high}°  L:${w.low}°', style: const TextStyle(fontSize: 13, color: kSecondary)),
        ],
      ),
    );
  }
}

class AllAppsScreen extends StatelessWidget {
  const AllAppsScreen({
    super.key,
    required this.animation,
    required this.apps,
    required this.onLaunch,
    required this.onWallpaper,
    required this.onSettings,
  });

  final Animation<double> animation;
  final List<App> apps;
  final ValueChanged<App> onLaunch;
  final VoidCallback onWallpaper;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return BlurredOverlay(
      animation: animation,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(64, 40, 64, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Apps',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: kPrimary, shadows: kTextShadow),
                ),
                const Spacer(),
                PillButton(label: 'Wallpaper', onSelect: onWallpaper),
                const SizedBox(width: 6),
                PillButton(label: 'Settings', onSelect: onSettings),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.only(top: 20, bottom: 40),
                clipBehavior: Clip.none,
                cacheExtent: 2000,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 112,
                  mainAxisExtent: 116,
                  mainAxisSpacing: 16,
                ),
                itemCount: apps.length,
                itemBuilder:
                    (context, i) => Center(
                      child: TvFocusable(
                        autofocus: i == 0,
                        onSelect: () => onLaunch(apps[i]),
                        builder: (context, focused) => AppIcon(app: apps[i], size: 60, focused: focused),
                      ),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
