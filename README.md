# TV Launcher

A minimal, Apple-style home screen for Google TV / Android TV, built with Flutter.

- **One page**: large clock, date, quote of the day and a frosted weather card (location from your IP address).
- **Your 3 most-used apps** at the bottom left, ranked by screen time over the last 30 days. **More** opens every app over a blurred background.
- **Dynamic wallpaper** that follows the time of day (using your local sunrise and sunset), the weather, the temperature and a mood based on the hour and weekday. 103 photos from Wikimedia Commons Featured Pictures are bundled for offline use. When online, a full-resolution copy loads on top.
- **Controls**: Wi-Fi and Bluetooth status, a volume slider, and shortcuts to Display, Sound, Apps, Energy, Accessibility, Date & Time, Wallpaper and Settings. It hides itself after 10 seconds without a button press.

## Using it

| Remote | What it does |
| --- | --- |
| **OK** on an app | Open it |
| **More** | All apps (with Wallpaper and Settings buttons) |
| Sliders button next to More, **Home** while already on the home screen, or **Menu** | Open Controls (press Home again to close) |
| Left / right on the volume bar | Change the volume |
| **Home** from any app | Back to this launcher |

Long-pressing Home can't open Controls. Android sends that press to Google Assistant before any launcher sees it.

## Installation

### 1. What you need

- A computer with [Flutter](https://docs.flutter.dev/get-started/install) (3.29 or newer) and the Android SDK, including `adb` (it comes with Android Studio or the SDK platform tools).
- The TV and the computer on the same network.

### 2. Turn on network debugging on the TV

1. **Settings → System → About**, then select **Android TV OS build** 7 times until it says you're a developer.
2. **Settings → System → Developer options**: turn on **USB debugging** and, if listed, **Network debugging** or **Wireless debugging**.
3. Find the TV's IP address under **Settings → Network & Internet → (your network)**.

### 3. Connect from the computer

```bash
adb connect <TV-IP>:5555      # e.g. adb connect 192.168.8.18:5555
adb devices                   # the TV should be listed as "device"
```

Accept the **Allow USB debugging?** prompt on the TV the first time (tick **Always allow**).

### 4. Build and install

```bash
cd ~/Desktop/MyCode/tv-launcher
flutter pub get
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

### 5. Grant permissions

```bash
# Rank the 3 most-used apps (usage access). Without it, apps are ranked by launches from this launcher.
adb shell appops set com.mucia.tv_home GET_USAGE_STATS allow

# Show photos stored on the TV in the wallpaper picker (optional)
adb shell pm grant com.mucia.tv_home android.permission.READ_MEDIA_IMAGES
```

### 6. Make it the home screen

```bash
adb shell cmd role add-role-holder android.app.role.HOME com.mucia.tv_home 0
adb shell cmd package set-home-activity --user 0 com.mucia.tv_home/.MainActivity
```

On Google TV, the stock launcher and its setup-recovery screen still take over the Home button. Disable them:

```bash
adb shell pm disable-user --user 0 com.google.android.apps.tv.launcherx
adb shell pm disable-user --user 0 com.google.android.tungsten.setupwraith
```

Press **Home** on the remote. If a chooser appears, pick **Home** (this launcher) and then **Always**.

### Updating

Run step 4 again. Settings, the chosen wallpaper and the permissions are kept.

### Undo / go back to Google TV

```bash
adb shell pm enable com.google.android.apps.tv.launcherx
adb shell pm enable com.google.android.tungsten.setupwraith
adb uninstall com.mucia.tv_home
```

Keep `adb` handy before uninstalling. If the stock launcher is still disabled with no other home app installed, Home does nothing until you re-enable it.

## Troubleshooting

- **Home opens Google TV or a setup screen**: run the `pm disable-user` commands in step 6, then the role command again.
- **Top apps never change**: usage access isn't granted; re-run the `appops` command in step 5.
- **Clock is wrong**: the launcher uses the time zone of your IP location, so it's right even when the TV's isn't. To fix other apps, set the TV's time zone in **Controls → Date & Time**.
- **Bluetooth tile opens Settings**: Google TV doesn't let other apps open its Remotes & Accessories screen directly; it's listed in Settings. If Bluetooth is off, the tile asks to turn it on instead.
- **No weather or quote**: these need internet. The wallpaper falls back to the bundled photos when offline.

## Data sources (free, no API keys)

- Location: [ipwho.is](https://ipwho.is), falling back to [ipapi.co](https://ipapi.co)
- Weather, sunrise and sunset: [Open-Meteo](https://open-meteo.com)
- Quote of the day: [ZenQuotes](https://zenquotes.io), with built-in fallbacks
- Wallpapers: [Wikimedia Commons Featured Pictures](https://commons.wikimedia.org/wiki/Commons:Featured_pictures) (credits are shown in the wallpaper picker) and Bing's photo of the day

## Project layout

| File | Contents |
| --- | --- |
| `lib/home.dart` | Home screen, clock, quote, weather card, All Apps |
| `lib/control.dart` | Controls panel |
| `lib/scene.dart` | Scores scenes against time, weather, temperature and mood to choose the wallpaper |
| `lib/catalog.dart` | The bundled photo catalog (generated) |
| `lib/wallpaper.dart` | Wallpaper rendering and picker |
| `lib/info.dart` | Location, weather and quote fetching |
| `lib/platform.dart` | Bridge to the Android side |
| `android/app/src/main/kotlin/.../MainActivity.kt` | App list, usage stats, settings, volume, Home button handling |
| `assets/wallpapers/` | Offline photos (720p) |
