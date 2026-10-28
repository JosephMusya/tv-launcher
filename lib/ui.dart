import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'platform.dart';

const kPrimary = Color(0xFFFFFFFF);
const kSecondary = Color(0xB8FFFFFF);
const kTertiary = Color(0x85FFFFFF);
const kTextShadow = [Shadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 1))];
const kFast = Duration(milliseconds: 220);
const kEase = Curves.easeOutCubic;

bool isSelectKey(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.select ||
    key == LogicalKeyboardKey.enter ||
    key == LogicalKeyboardKey.numpadEnter ||
    key == LogicalKeyboardKey.gameButtonA;

/// A D-pad focusable that fires [onSelect] when OK is released.
class TvFocusable extends StatefulWidget {
  const TvFocusable({super.key, required this.onSelect, required this.builder, this.autofocus = false});

  final VoidCallback onSelect;
  final Widget Function(BuildContext context, bool focused) builder;
  final bool autofocus;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _focused = false;
  // Only act on a key-up whose key-down we saw, so the OK release that opened
  // a screen doesn't also activate whatever gets focus on it.
  bool _pressed = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!isSelectKey(event.logicalKey)) return KeyEventResult.ignored;
    if (event is KeyDownEvent) _pressed = true;
    if (event is KeyUpEvent && _pressed) {
      _pressed = false;
      widget.onSelect();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      onFocusChange: (focused) {
        setState(() {
          _focused = focused;
          _pressed = false;
        });
        if (focused) Scrollable.ensureVisible(context, alignment: 0.5, duration: kFast);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        child: widget.builder(context, _focused),
      ),
    );
  }
}

/// Frosted panel, like an iOS widget.
class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.radius = 26});

  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0x33000000),
            borderRadius: shape,
            border: Border.all(color: const Color(0x1FFFFFFF)),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Rounded app icon with its name underneath; lifts when focused.
class AppIcon extends StatelessWidget {
  const AppIcon({super.key, required this.app, required this.size, required this.focused});

  final App app;
  final double size;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(size * 0.225);
    return SizedBox(
      width: size + 40,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedScale(
            scale: focused ? 1.14 : 1,
            duration: kFast,
            curve: kEase,
            child: AnimatedContainer(
              duration: kFast,
              curve: kEase,
              width: size,
              height: size,
              decoration: BoxDecoration(
                borderRadius: shape,
                color: const Color(0x2EFFFFFF),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: focused ? 0.45 : 0.22),
                    blurRadius: focused ? 30 : 12,
                    offset: Offset(0, focused ? 14 : 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: shape,
                child: Image.memory(
                  app.icon,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
          ),
          AnimatedPadding(
            duration: kFast,
            curve: kEase,
            padding: EdgeInsets.only(top: focused ? 16 : 10),
            child: Text(
              app.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: focused ? FontWeight.w600 : FontWeight.w500,
                color: focused ? kPrimary : kSecondary,
                shadows: kTextShadow,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Text or icon button that turns into a white pill when focused, like tvOS.
class PillButton extends StatelessWidget {
  const PillButton({super.key, this.label, this.icon, required this.onSelect, this.autofocus = false});

  final String? label;
  final IconData? icon;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
      onSelect: onSelect,
      builder:
          (context, focused) => AnimatedScale(
            scale: focused ? 1.06 : 1,
            duration: kFast,
            curve: kEase,
            child: AnimatedContainer(
              duration: kFast,
              curve: kEase,
              padding: EdgeInsets.symmetric(horizontal: label == null ? 11 : 18, vertical: 9),
              decoration: BoxDecoration(
                color: focused ? kPrimary : const Color(0x00FFFFFF),
                borderRadius: BorderRadius.circular(100),
                boxShadow:
                    focused ? const [BoxShadow(color: Color(0x40000000), blurRadius: 20, offset: Offset(0, 8))] : null,
              ),
              child: AnimatedDefaultTextStyle(
                duration: kFast,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: focused ? Colors.black : kPrimary,
                  shadows: focused ? const [] : kTextShadow,
                ),
                child:
                    label != null
                        ? Text(label!)
                        : Icon(
                          icon,
                          size: 20,
                          color: focused ? Colors.black : kPrimary,
                          shadows: focused ? null : kTextShadow,
                        ),
              ),
            ),
          ),
    );
  }
}

/// Fades and blurs the screen behind an overlay route as it opens.
class BlurredOverlay extends StatelessWidget {
  const BlurredOverlay({super.key, required this.animation, required this.child, this.blur = 26, this.dim = 0.3});

  final Animation<double> animation;
  final Widget child;
  final double blur;
  final double dim;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final t = kEase.transform(animation.value);
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur * t, sigmaY: blur * t),
            child: ColoredBox(color: Colors.black.withValues(alpha: dim * t), child: Opacity(opacity: t, child: child)),
          );
        },
        child: child,
      ),
    );
  }
}

Route<void> overlayRoute(Widget Function(Animation<double> animation) builder) => PageRouteBuilder(
  opaque: false,
  transitionDuration: const Duration(milliseconds: 320),
  reverseTransitionDuration: const Duration(milliseconds: 240),
  pageBuilder: (context, animation, _) => builder(animation),
);
