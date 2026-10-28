import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'platform.dart';
import 'ui.dart';

const _blue = Color(0xFF0A84FF);
const _tileColor = Color(0x2EFFFFFF);
const _idleTimeout = Duration(seconds: 10);

/// Quick settings, like the panel you pull down from the top of a phone.
class ControlCenter extends StatefulWidget {
  const ControlCenter({super.key, required this.animation, required this.onWallpaper});

  final Animation<double> animation;
  final VoidCallback onWallpaper;

  @override
  State<ControlCenter> createState() => _ControlCenterState();
}

class _ControlCenterState extends State<ControlCenter> {
  DeviceStatus? _status;
  Timer? _poll;
  Timer? _idle;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _load());
    HardwareKeyboard.instance.addHandler(_onAnyKey);
    _resetIdle();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _idle?.cancel();
    HardwareKeyboard.instance.removeHandler(_onAnyKey);
    super.dispose();
  }

  // Any remote press keeps the panel open; it hides itself after 10s of none.
  bool _onAnyKey(KeyEvent event) {
    _resetIdle();
    return false;
  }

  void _resetIdle() {
    _idle?.cancel();
    _idle = Timer(_idleTimeout, () {
      final route = ModalRoute.of(context);
      // Only close if Controls is still on top (not under the wallpaper picker).
      if (mounted && route != null && route.isCurrent) Navigator.of(context).pop();
    });
  }

  Future<void> _load() async {
    final status = await Launcher.status();
    if (mounted) setState(() => _status = status);
  }

  void _open(String page) {
    Launcher.openSettings(page);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    final (wifiOn, wifiText) = switch (s?.network) {
      null => (false, ''),
      'ethernet' => (true, s!.online ? 'Ethernet' : 'Ethernet · No internet'),
      'wifi' => (true, s!.online ? 'Connected' : 'No internet'),
      _ => (false, s!.wifiEnabled ? 'Not connected' : 'Off'),
    };
    final slide = CurvedAnimation(parent: widget.animation, curve: kEase);

    return BlurredOverlay(
      animation: widget.animation,
      child: Align(
        alignment: Alignment.topRight,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, -0.08), end: Offset.zero).animate(slide),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(64, 44, 64, 40),
            child: SizedBox(
              width: 372,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Controls',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: kPrimary, shadows: kTextShadow),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _WideTile(
                          autofocus: true,
                          icon: s?.network == 'ethernet' ? CupertinoIcons.link : CupertinoIcons.wifi,
                          title: s?.network == 'ethernet' ? 'Network' : 'Wi-Fi',
                          subtitle: wifiText,
                          on: wifiOn,
                          onSelect: () => _open('wifi'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _WideTile(
                          icon: CupertinoIcons.bluetooth,
                          title: 'Bluetooth',
                          subtitle: s == null ? '' : (s.bluetooth ? 'On' : 'Off'),
                          on: s?.bluetooth ?? false,
                          onSelect: () => _open('bluetooth'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _VolumeSlider(status: s, onChanged: _load),
                  const SizedBox(height: 10),
                  GridView.count(
                    shrinkWrap: true,
                    crossAxisCount: 4,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    clipBehavior: Clip.none,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _SmallTile(icon: CupertinoIcons.tv, label: 'Display', onSelect: () => _open('display')),
                      _SmallTile(icon: CupertinoIcons.speaker_2_fill, label: 'Sound', onSelect: () => _open('sound')),
                      _SmallTile(
                        icon: CupertinoIcons.square_grid_2x2_fill,
                        label: 'Apps',
                        onSelect: () => _open('apps'),
                      ),
                      _SmallTile(
                        icon: CupertinoIcons.leaf_arrow_circlepath,
                        label: 'Energy',
                        onSelect: () => _open('energy'),
                      ),
                      _SmallTile(
                        icon: CupertinoIcons.person_crop_circle,
                        label: 'Accessibility',
                        onSelect: () => _open('accessibility'),
                      ),
                      _SmallTile(icon: CupertinoIcons.clock_fill, label: 'Date & Time', onSelect: () => _open('date')),
                      _SmallTile(icon: CupertinoIcons.photo_fill, label: 'Wallpaper', onSelect: widget.onWallpaper),
                      _SmallTile(icon: CupertinoIcons.gear_alt_fill, label: 'Settings', onSelect: () => _open('all')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rounded tile that lifts and turns white when focused, like tvOS.
class _Tile extends StatelessWidget {
  const _Tile({required this.focused, required this.child, this.padding = const EdgeInsets.all(16)});

  final bool focused;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: focused ? 1.06 : 1,
      duration: kFast,
      curve: kEase,
      child: AnimatedContainer(
        duration: kFast,
        curve: kEase,
        padding: padding,
        decoration: BoxDecoration(
          color: focused ? const Color(0xF2FFFFFF) : _tileColor,
          borderRadius: BorderRadius.circular(18),
          boxShadow:
              focused ? const [BoxShadow(color: Color(0x50000000), blurRadius: 26, offset: Offset(0, 10))] : null,
        ),
        child: child,
      ),
    );
  }
}

class _WideTile extends StatelessWidget {
  const _WideTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.on,
    required this.onSelect,
    this.autofocus = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool on;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
      onSelect: onSelect,
      builder:
          (context, focused) => _Tile(
            focused: focused,
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: kFast,
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on ? _blue : (focused ? const Color(0x1F000000) : const Color(0x33FFFFFF)),
                  ),
                  child: Icon(icon, size: 16, color: on ? kPrimary : (focused ? Colors.black : kPrimary)),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: focused ? Colors.black : kPrimary,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: focused ? const Color(0x99000000) : kSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
    );
  }
}

class _SmallTile extends StatelessWidget {
  const _SmallTile({required this.icon, required this.label, required this.onSelect});

  final IconData icon;
  final String label;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onSelect: onSelect,
      builder:
          (context, focused) => _Tile(
            focused: focused,
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: focused ? Colors.black : kPrimary),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: focused ? FontWeight.w600 : FontWeight.w500,
                    color: focused ? Colors.black : kPrimary,
                  ),
                ),
              ],
            ),
          ),
    );
  }
}

/// Media volume. Left and right change it while focused; up and down move on.
class _VolumeSlider extends StatefulWidget {
  const _VolumeSlider({required this.status, required this.onChanged});

  final DeviceStatus? status;
  final VoidCallback onChanged;

  @override
  State<_VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends State<_VolumeSlider> {
  bool _focused = false;
  int? _level; // set while adjusting, so the bar doesn't wait for the next poll

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final delta = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => -1,
      LogicalKeyboardKey.arrowRight => 1,
      _ => 0,
    };
    if (delta == 0) return KeyEventResult.ignored;
    Launcher.changeVolume(delta).then((level) {
      if (mounted) setState(() => _level = level);
      widget.onChanged();
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.status;
    final max = s?.maxVolume ?? 1;
    final level = _level ?? s?.volume ?? 0;
    final fraction = (level / max).clamp(0.0, 1.0);
    final icon =
        s?.muted == true || level == 0
            ? CupertinoIcons.speaker_slash_fill
            : fraction < 0.5
            ? CupertinoIcons.speaker_1_fill
            : CupertinoIcons.speaker_3_fill;
    final ink = _focused ? Colors.black : kPrimary;

    return Focus(
      onKeyEvent: _onKey,
      onFocusChange:
          (f) => setState(() {
            _focused = f;
            _level = null;
          }),
      child: _Tile(
        focused: _focused,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Icon(icon, size: 16, color: ink),
            const SizedBox(width: 10),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: SizedBox(
                  height: 6,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: _focused ? const Color(0x1F000000) : const Color(0x33FFFFFF)),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: fraction,
                        child: ColoredBox(color: ink),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 26,
              child: Text(
                '${(fraction * 100).round()}',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
