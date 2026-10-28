import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'catalog.dart';
import 'platform.dart';
import 'ui.dart';

// A wallpaper is stored as a spec string:
//   dynamic          a photo matched to the time, weather and mood (see scene.dart)
//   asset:<path>     a specific photo from the bundled catalog
//   bing:daily       Bing photo of the day, changes daily
//   url:<https url>  a specific photo
//   gradient:<n>     one of kGradients
//   device:<uri>     a photo stored on the TV
const kDefaultWallpaper = 'dynamic';

const kGradients = <List<Color>>[
  [Color(0xFF1B2845), Color(0xFF5A3E7A), Color(0xFFC9776B)],
  [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
  [Color(0xFF134E5E), Color(0xFF4F8A6E)],
  [Color(0xFF1C1C1E), Color(0xFF3A3A3C)],
];

class BingImage {
  const BingImage(this.url, this.thumb, this.title);

  final String url;
  final String thumb;
  final String title;
}

Future<List<BingImage>> fetchBingImages() async {
  try {
    final response = await http
        .get(Uri.parse('https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=8&mkt=en-US'))
        .timeout(const Duration(seconds: 10));
    final images = (jsonDecode(utf8.decode(response.bodyBytes))['images'] as List).cast<Map>();
    return [
      for (final i in images)
        BingImage(
          'https://www.bing.com${i['urlbase']}_1920x1080.jpg',
          'https://www.bing.com${i['urlbase']}_640x360.jpg',
          i['title'] as String? ?? '',
        ),
    ];
  } catch (_) {
    return [];
  }
}

Widget _gradient(int index) => DecoratedBox(
  decoration: BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: kGradients[index % kGradients.length],
    ),
  ),
);

/// Full-screen background for a wallpaper spec. The bundled [photo] shows
/// right away and stays as the fallback when offline; online images fade in
/// over it once they load.
class Wallpaper extends StatefulWidget {
  const Wallpaper({super.key, required this.spec, required this.photo});

  final String spec;
  final CatalogPhoto photo;

  @override
  State<Wallpaper> createState() => _WallpaperState();
}

class _WallpaperState extends State<Wallpaper> {
  ImageProvider? _image;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(Wallpaper old) {
    super.didUpdateWidget(old);
    if (old.spec != widget.spec || old.photo != widget.photo) _resolve();
  }

  Future<void> _resolve() async {
    final spec = widget.spec;
    final photo = widget.photo;
    ImageProvider? image;
    if (spec == 'dynamic') {
      image = NetworkImage(photo.url);
    } else if (spec.startsWith('url:')) {
      image = NetworkImage(spec.substring(4));
    } else if (spec == 'bing:daily') {
      final images = await fetchBingImages();
      if (images.isNotEmpty) image = NetworkImage(images.first.url);
    } else if (spec.startsWith('device:')) {
      final bytes = await Launcher.image(spec.substring(7), 1920);
      if (bytes != null) image = MemoryImage(bytes);
    }
    if (mounted && spec == widget.spec && photo == widget.photo) setState(() => _image = image);
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final Widget base =
        spec.startsWith('gradient:')
            ? _gradient(int.tryParse(spec.substring(9)) ?? 0)
            : Image.asset(
              spec.startsWith('asset:') ? spec.substring(6) : widget.photo.asset,
              key: ValueKey(spec.startsWith('asset:') ? spec : widget.photo.asset),
              fit: BoxFit.cover,
            );
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(duration: const Duration(milliseconds: 900), child: base),
        if (_image != null)
          Image(
            key: ObjectKey(_image),
            image: _image!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            frameBuilder:
                (context, child, frame, sync) => AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: const Duration(milliseconds: 900),
                  child: child,
                ),
            errorBuilder: (context, error, stack) => const SizedBox.shrink(),
          ),
      ],
    );
  }
}

class WallpaperPicker extends StatefulWidget {
  const WallpaperPicker({
    super.key,
    required this.animation,
    required this.current,
    required this.photo,
    required this.onPick,
  });

  final Animation<double> animation;
  final String current;
  final CatalogPhoto photo;
  final ValueChanged<String> onPick;

  @override
  State<WallpaperPicker> createState() => _WallpaperPickerState();
}

class _WallpaperPickerState extends State<WallpaperPicker> {
  List<BingImage> _bing = [];
  List<String> _device = [];

  @override
  void initState() {
    super.initState();
    fetchBingImages().then((v) => mounted ? setState(() => _bing = v) : null);
    Launcher.deviceImages().then((v) => mounted ? setState(() => _device = v) : null);
  }

  Widget _row(String title, List<Widget> tiles) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kSecondary)),
        const SizedBox(height: 14),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: tiles.length,
            separatorBuilder: (_, __) => const SizedBox(width: 20),
            itemBuilder: (_, i) => tiles[i],
          ),
        ),
        const SizedBox(height: 22),
      ],
    );
  }

  Widget _tile(String spec, String caption, Widget preview, {bool autofocus = false}) {
    final selected = spec == widget.current;
    return TvFocusable(
      autofocus: autofocus,
      onSelect: () => widget.onPick(spec),
      builder:
          (context, focused) => SizedBox(
            width: 192,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedScale(
                  scale: focused ? 1.08 : 1,
                  duration: kFast,
                  curve: kEase,
                  child: AnimatedContainer(
                    duration: kFast,
                    width: 192,
                    height: 108,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: focused ? 0.5 : 0.25),
                          blurRadius: focused ? 26 : 10,
                          offset: Offset(0, focused ? 12 : 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          preview,
                          if (selected)
                            const Align(
                              alignment: Alignment.topRight,
                              child: Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(CupertinoIcons.checkmark_circle_fill, color: kPrimary, size: 22),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: focused ? kPrimary : kTertiary),
                ),
              ],
            ),
          ),
    );
  }

  Widget _asset(String path) => Image.asset(path, fit: BoxFit.cover, cacheWidth: 384);

  Widget _network(String url) => Image.network(
    url,
    fit: BoxFit.cover,
    errorBuilder: (context, error, stack) => const ColoredBox(color: Color(0x22FFFFFF)),
  );

  @override
  Widget build(BuildContext context) {
    return BlurredOverlay(
      animation: widget.animation,
      dim: 0.45,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(64, 44, 64, 40),
        children: [
          const Text('Wallpaper', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: kPrimary)),
          const SizedBox(height: 26),
          _row('Dynamic', [
            _tile('dynamic', 'Matches time, weather & mood', _asset(widget.photo.asset), autofocus: true),
          ]),
          _row('Collection', [for (final p in kCatalog) _tile('asset:${p.asset}', p.credit, _asset(p.asset))]),
          _row('Photos', [
            _tile('bing:daily', 'Photo of the Day', _bing.isEmpty ? _gradient(0) : _network(_bing.first.thumb)),
            for (final image in _bing) _tile('url:${image.url}', image.title, _network(image.thumb)),
          ]),
          _row('Colors', [for (var i = 0; i < kGradients.length; i++) _tile('gradient:$i', '', _gradient(i))]),
          if (_device.isNotEmpty)
            _row('On This TV', [for (final uri in _device) _tile('device:$uri', '', _DeviceThumb(uri))])
          else
            const Text(
              'Add photos to this TV (for example with Send Files to TV) and they will appear here.',
              style: TextStyle(fontSize: 13, color: kTertiary),
            ),
        ],
      ),
    );
  }
}

class _DeviceThumb extends StatefulWidget {
  const _DeviceThumb(this.uri);

  final String uri;

  @override
  State<_DeviceThumb> createState() => _DeviceThumbState();
}

class _DeviceThumbState extends State<_DeviceThumb> {
  late final Future<Uint8List?> _bytes = Launcher.image(widget.uri, 400);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _bytes,
      builder:
          (context, snapshot) =>
              snapshot.data == null
                  ? const ColoredBox(color: Color(0x22FFFFFF))
                  : Image.memory(snapshot.data!, fit: BoxFit.cover),
    );
  }
}
