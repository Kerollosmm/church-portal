import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:ui_web' as ui_web;

import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' as web;

import 'hero_ambient_spec.dart';
import 'hero_feather.dart';

/// Web: the ambient layers live in the DOM and are animated with CSS.
const bool heroAmbientInDom = true;

/// The hero's gold haze drift and light-ray shimmer as one platform view
/// (ADR-037), stacked right above the hero `<video>`:
///
/// - **Haze**: the cloud texture, its mirror image and the texture again in
///   a 3-wide strip, veiled top-to-bottom ([HeroAmbientSpec.hazeVeil]) with a
///   CSS mask and slid two stage widths per minute with a CSS transform
///   animation, exactly like the Flutter `_HazeDrift`.
/// - **Rays**: [HeroAmbientSpec.shimmerPhases] canvases, each drawn once (per
///   size) with the same 14 rays as [LightRaysPainter] at evenly spaced
///   shimmer phases; CSS opacity animations crossfade between neighbouring
///   phases ([HeroAmbientSpec.phaseWeight]), added with `plus-lighter`.
///
/// Transform / opacity animations run on the compositor, so the main thread
/// stays idle; the whole layer pauses when the hero leaves the viewport
/// ([play]) and takes the theme's [cssFilter] and the bottom feather like the
/// video does.
class HeroAmbientLayer extends StatefulWidget {
  final bool haze;
  final double rays;
  final bool play;
  final String cssFilter;
  final String clouds;
  const HeroAmbientLayer({
    super.key,
    required this.haze,
    required this.rays,
    required this.play,
    required this.clouds,
    this.cssFilter = 'none',
  });

  @override
  State<HeroAmbientLayer> createState() => _HeroAmbientLayerState();
}

class _HeroAmbientLayerState extends State<HeroAmbientLayer> {
  /// Canvas resolution of the (blurred, soft) rays relative to CSS pixels.
  static const _rayScale = 0.5;

  web.HTMLDivElement? _host;
  final List<web.HTMLCanvasElement> _canvases = [];
  web.ResizeObserver? _observer;
  Size _drawn = Size.zero;
  int _generation = 0;

  static String _css() {
    final veil = [
      for (final (a, s) in HeroAmbientSpec.hazeVeil)
        'rgba(0,0,0,${a.toStringAsFixed(3)}) ${(s * 100).toStringAsFixed(1)}%',
    ].join(', ');
    final n = HeroAmbientSpec.shimmerPhases;
    // Keyframes of phase 0's weight over one shimmer cycle (a cyclic
    // triangle: 1 at 0, 0 from 1/n to 1 - 1/n, 1 again at the end).
    final tri = '0%{opacity:1}${(100 / n).toStringAsFixed(3)}%{opacity:0}'
        '${(100 - 100 / n).toStringAsFixed(3)}%{opacity:0}100%{opacity:1}';
    return '@keyframes hk-haze{from{transform:translate3d(0,0,0)}to{transform:translate3d(-66.6667%,0,0)}}'
        '@keyframes hk-ray{$tri}'
        '.hk-host{position:relative;width:100%;height:100%;overflow:hidden;pointer-events:none;direction:ltr;isolation:isolate}'
        '.hk-haze{position:absolute;top:0;left:0;width:300%;height:100%;display:flex;'
        'will-change:transform;animation:hk-haze ${HeroAmbientSpec.hazeCycle.inMilliseconds}ms linear infinite;'
        '-webkit-mask-image:linear-gradient(to bottom, $veil);mask-image:linear-gradient(to bottom, $veil)}'
        '.hk-tile{flex:0 0 33.33334%;height:100%;background-position:center;background-size:cover;background-repeat:no-repeat}'
        '.hk-rays{position:absolute;inset:0;isolation:isolate;opacity:0;transition:opacity .6s ease-out}'
        '.hk-rays.hk-ready{opacity:1}'
        '.hk-ray{position:absolute;inset:0;width:100%;height:100%;mix-blend-mode:plus-lighter;opacity:0;'
        'animation:hk-ray ${HeroAmbientSpec.shimmerCycle.inMilliseconds}ms linear infinite}'
        '.hk-paused .hk-haze,.hk-paused .hk-ray{animation-play-state:paused}';
  }

  void _created(Object o) {
    final host = o as web.HTMLDivElement;
    _host = host;
    final mask = BottomFeather.cssMask;
    host
      ..className = 'hk-host'
      ..setAttribute('aria-hidden', 'true')
      ..style.cssText = 'filter:${widget.cssFilter};-webkit-mask-image:$mask;mask-image:$mask;';
    final style = web.document.createElement('style') as web.HTMLStyleElement..textContent = _css();
    host.append(style);
    if (widget.haze) {
      final strip = web.document.createElement('div') as web.HTMLDivElement..className = 'hk-haze';
      final url = ui_web.assetManager.getAssetUrl(widget.clouds);
      for (final mirror in [false, true, false]) {
        final tile = web.document.createElement('div') as web.HTMLDivElement
          ..className = 'hk-tile'
          ..style.backgroundImage = 'url("$url")';
        if (mirror) tile.style.transform = 'scaleX(-1)';
        strip.append(tile);
      }
      host.append(strip);
    }
    if (widget.rays > 0) {
      final rays = web.document.createElement('div') as web.HTMLDivElement..className = 'hk-rays';
      final n = HeroAmbientSpec.shimmerPhases;
      final cycle = HeroAmbientSpec.shimmerCycle.inMilliseconds;
      for (var k = 0; k < n; k++) {
        final c = web.document.createElement('canvas') as web.HTMLCanvasElement..className = 'hk-ray';
        // Phase k peaks at shimmer k/n: start its animation (1 - k/n) into
        // the cycle (a negative delay), so its weight is tri(t - k/n).
        c.style.animationDelay = '-${((n - k) % n) * cycle ~/ n}ms';
        _canvases.add(c);
        rays.append(c);
      }
      host.append(rays);
      _observer = web.ResizeObserver(((JSArray<web.ResizeObserverEntry> _, web.ResizeObserver _) {
        _scheduleDraw();
      }).toJS)
        ..observe(host);
    }
    _syncPlay();
  }

  void _scheduleDraw() {
    final host = _host;
    if (host == null) return;
    final size = Size(host.clientWidth.toDouble(), host.clientHeight.toDouble());
    if (size.isEmpty || size == _drawn) return;
    _drawn = size;
    final gen = ++_generation;
    final layer = _canvases.first.parentElement as web.HTMLElement?;
    if (layer != null && layer.classList.contains('hk-ready')) {
      // Resize of a visible layer: redraw every phase in this one task, so no
      // canvas shows its old bitmap stretched to the new size.
      for (var k = 0; k < _canvases.length; k++) {
        _drawPhase(_canvases[k], size, k / _canvases.length);
      }
      return;
    }
    // First draw (layer still hidden): one phase per task keeps every task
    // short while the page starts.
    for (var k = 0; k < _canvases.length; k++) {
      Future<void>.delayed(Duration(milliseconds: 16 * k), () {
        if (gen != _generation || _host == null) return;
        _drawPhase(_canvases[k], size, k / _canvases.length);
        if (k == _canvases.length - 1) (_canvases.first.parentElement as web.HTMLElement?)?.classList.add('hk-ready');
      });
    }
  }

  void _drawPhase(web.HTMLCanvasElement c, Size size, double shimmer) {
    final w = math.max(1, (size.width * _rayScale).round());
    final h = math.max(1, (size.height * _rayScale).round());
    c
      ..width = w
      ..height = h;
    final ctx = c.getContext('2d') as web.CanvasRenderingContext2D?;
    if (ctx == null) return;
    final sigma = HeroAmbientSpec.raySigma(size);
    ctx
      ..clearRect(0, 0, w, h)
      ..save()
      ..scale(_rayScale, _rayScale);
    if (ctx.has('filter')) {
      // The filter works in canvas pixels (not the transformed space).
      ctx.filter = 'blur(${(sigma * _rayScale).toStringAsFixed(2)}px)';
      c.style.filter = 'none';
    } else {
      // Safari / WebKit have no CanvasRenderingContext2D.filter: blur the
      // (static) canvas element with CSS instead, same sigma in CSS pixels,
      // so the rays stay soft beams rather than hard-edged wedges.
      c.style.filter = 'blur(${sigma.toStringAsFixed(2)}px)';
    }
    final (r, g, b) = HeroAmbientSpec.rayColor;
    for (final ray in HeroAmbientSpec.rays(size, shimmer: shimmer, strength: widget.rays)) {
      final gc = ray.gradientCenter;
      final grad = ctx.createRadialGradient(gc.dx, gc.dy, 0, gc.dx, gc.dy, ray.gradientRadius)
        ..addColorStop(0, 'rgba($r,$g,$b,${ray.alpha.toStringAsFixed(4)})')
        ..addColorStop(1, 'rgba($r,$g,$b,0)');
      ctx
        ..fillStyle = grad
        ..beginPath()
        ..moveTo(ray.origin.dx, ray.origin.dy)
        ..lineTo(ray.p1.dx, ray.p1.dy)
        ..lineTo(ray.p2.dx, ray.p2.dy)
        ..closePath()
        ..fill();
    }
    ctx.restore();
  }

  void _syncPlay() {
    final host = _host;
    if (host == null) return;
    if (widget.play) {
      host.classList.remove('hk-paused');
    } else {
      host.classList.add('hk-paused');
    }
  }

  @override
  void didUpdateWidget(covariant HeroAmbientLayer old) {
    super.didUpdateWidget(old);
    if (old.play != widget.play) _syncPlay();
    if (old.cssFilter != widget.cssFilter) _host?.style.filter = widget.cssFilter;
    if (old.rays != widget.rays) {
      _drawn = Size.zero;
      _scheduleDraw();
    }
  }

  @override
  void dispose() {
    _observer?.disconnect();
    _observer = null;
    _generation++;
    _host = null;
    _canvases.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: HtmlElementView.fromTagName(tagName: 'div', isVisible: true, onElementCreated: _created),
      );
}
