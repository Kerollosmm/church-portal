import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' as web;

import 'hero_feather.dart';

/// Muted looping background video (web): a native `<video>` element, covered
/// and positioned with CSS, its bottom feathered with a CSS mask (the same
/// stops as [BottomFeather]), faded in with a CSS transition on `playing`.
class HeroVideo extends StatefulWidget {
  final String asset;
  final Alignment alignment;
  final bool play;
  const HeroVideo({super.key, required this.asset, required this.alignment, required this.play});

  @override
  State<HeroVideo> createState() => _HeroVideoState();
}

class _HeroVideoState extends State<HeroVideo> {
  web.HTMLVideoElement? _el;

  void _created(Object o) {
    final v = o as web.HTMLVideoElement;
    _el = v;
    final x = ((widget.alignment.x + 1) * 50).toStringAsFixed(1);
    final y = ((widget.alignment.y + 1) * 50).toStringAsFixed(1);
    final mask = BottomFeather.cssMask;
    v
      ..muted = true
      ..defaultMuted = true
      ..loop = true
      ..autoplay = false
      ..preload = 'auto'
      ..playsInline = true
      ..disablePictureInPicture = true
      ..setAttribute('muted', '')
      ..setAttribute('playsinline', '')
      ..setAttribute('webkit-playsinline', '')
      ..setAttribute('disableremoteplayback', '')
      ..setAttribute('aria-hidden', 'true')
      ..setAttribute('tabindex', '-1')
      ..style.cssText = 'width:100%;height:100%;display:block;object-fit:cover;object-position:$x% $y%;'
          'pointer-events:none;background:transparent;opacity:0;transition:opacity 1.2s ease-out;'
          '-webkit-mask-image:$mask;mask-image:$mask;';
    v.addEventListener(
        'playing',
        ((web.Event _) {
          v.style.opacity = '1';
        }).toJS);
    v.src = ui_web.assetManager.getAssetUrl(widget.asset);
    _sync();
  }

  void _sync() {
    final v = _el;
    if (v == null) return;
    if (widget.play) {
      // Autoplay can be refused (e.g. low-power mode): the poster stays.
      v.play().toDart.then((_) {}, onError: (_) {});
    } else {
      v.pause();
    }
  }

  @override
  void didUpdateWidget(covariant HeroVideo old) {
    super.didUpdateWidget(old);
    if (old.play != widget.play) _sync();
  }

  @override
  void dispose() {
    final v = _el;
    _el = null;
    if (v != null) {
      v.pause();
      v.removeAttribute('src');
      v.load(); // releases the network stream
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: HtmlElementView.fromTagName(tagName: 'video', isVisible: true, onElementCreated: _created),
      );
}
