import 'package:flutter/services.dart';

const _channel = MethodChannel('tv_home/apps');

class App {
  App(this.package, this.label, this.icon);

  factory App.fromMap(Map map) => App(map['package'] as String, map['label'] as String, map['icon'] as Uint8List);

  final String package;
  final String label;
  final Uint8List icon;
}

class Launcher {
  static Future<List<App>> apps() async {
    final list = await _channel.invokeListMethod<Map>('list') ?? [];
    return list.map(App.fromMap).toList();
  }

  /// Packages by screen time over the last 30 days, or null without usage access.
  static Future<List<String>?> mostUsed() => _channel.invokeListMethod<String>('top');

  static Future<void> launch(String package) => _channel.invokeMethod('launch', {'package': package});

  /// Opens a settings page: wifi, bluetooth, display, sound, apps, accessibility,
  /// date, keyboard, energy, or all.
  static Future<void> openSettings([String page = 'all']) => _channel.invokeMethod('settings', {'page': page});

  static Future<DeviceStatus?> status() async {
    final map = await _channel.invokeMapMethod<String, Object?>('status');
    return map == null ? null : DeviceStatus(map);
  }

  /// Steps media volume and returns the new level.
  static Future<int> changeVolume(int delta) async => await _channel.invokeMethod<int>('volume', {'delta': delta}) ?? 0;

  static Future<List<String>> deviceImages() async => await _channel.invokeListMethod<String>('images') ?? [];

  static Future<Uint8List?> image(String uri, int size) =>
      _channel.invokeMethod<Uint8List>('image', {'uri': uri, 'size': size});

  /// Called when Home is pressed; [inFront] is true if the launcher was already showing.
  static void onHome(void Function(bool inFront) callback) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'home') callback(call.arguments == true);
    });
  }
}

class DeviceStatus {
  DeviceStatus(Map<String, Object?> map)
    : network = map['network'] as String? ?? 'none',
      online = map['online'] == true,
      wifiEnabled = map['wifiEnabled'] == true,
      bluetooth = map['bluetooth'] == true,
      volume = map['volume'] as int? ?? 0,
      maxVolume = map['maxVolume'] as int? ?? 1,
      muted = map['muted'] == true;

  final String network; // wifi, ethernet, other or none
  final bool online;
  final bool wifiEnabled;
  final bool bluetooth;
  final int volume;
  final int maxVolume;
  final bool muted;
}
