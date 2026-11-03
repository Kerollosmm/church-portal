import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' as web;

import 'hero_feather.dart';
import 'hero_youtube_common.dart';

/// Muted looping YouTube background (web): the IFrame player in a masked
/// `<div>`, covering the stage, faded in on the first "playing" state.
class HeroYouTube extends StatefulWidget {
  final String videoId;
  final Alignment alignment;
  final bool play;

  /// CSS filter for the frame ('none', or the sombre filter of a dark theme).
  final String cssFilter;
  final VoidCallback onFailed;
  const HeroYouTube({
    super.key,
    required this.videoId,
    required this.alignment,
    required this.play,
    required this.onFailed,
    this.cssFilter = 'none',
  });

  @override
  State<HeroYouTube> createState() => _HeroYouTubeState();
}

const _origins = {'https://www.youtube-nocookie.com', 'https://www.youtube.com'};
int _nextId = 1;

class _HeroYouTubeState extends State<HeroYouTube> {
  final int _id = _nextId++;
  web.HTMLDivElement? _box;
  web.HTMLIFrameElement? _frame;
  JSFunction? _onMessage;
  Timer? _timeout;
  bool _playing = false;
  bool _failed = false;
  Size _size = Size.zero;

  void _created(Object o) {
    final box = o as web.HTMLDivElement;
    _box = box;
    final mask = BottomFeather.cssMask;
    box
      ..setAttribute('aria-hidden', 'true')
      ..style.cssText = 'position:relative;width:100%;height:100%;overflow:hidden;pointer-events:none;'
          'filter:${widget.cssFilter};-webkit-mask-image:$mask;mask-image:$mask;';
    final id = widget.videoId;
    final origin = Uri.encodeComponent(web.window.location.origin);
    final f = web.HTMLIFrameElement()
      ..src = 'https://www.youtube-nocookie.com/embed/$id?autoplay=1&mute=1&loop=1&playlist=$id&controls=0'
          '&playsinline=1&rel=0&disablekb=1&fs=0&iv_load_policy=3&modestbranding=1&enablejsapi=1&origin=$origin'
      ..title = ''
      ..allow = 'autoplay; encrypted-media; picture-in-picture'
      ..referrerPolicy = 'strict-origin-when-cross-origin'
      ..tabIndex = -1
      ..setAttribute('aria-hidden', 'true')
      ..setAttribute('frameborder', '0')
      ..style.cssText = 'position:absolute;border:0;pointer-events:none;opacity:0;transition:opacity 1.2s ease-out;';
    f.addEventListener(
        'load',
        ((web.Event _) {
          // Subscribe to the player's events (the IFrame API channel).
          _post({'event': 'listening', 'id': _id, 'channel': 'widget'});
          _sync();
        }).toJS);
    _frame = f;
    _layout();
    box.appendChild(f);
    _onMessage = ((web.MessageEvent e) => _message(e)).toJS;
    web.window.addEventListener('message', _onMessage);
    _timeout = Timer(kHeroYouTubeTimeout, () {
      if (!_playing) _fail();
    });
  }

  void _post(Map<String, Object?> msg) {
    final w = _frame?.contentWindow;
    if (w == null) return;
    w.postMessage(jsonEncode(msg).toJS, 'https://www.youtube-nocookie.com'.toJS);
  }

  void _command(String func) => _post({'event': 'command', 'func': func, 'args': <Object>[], 'id': _id});

  void _message(web.MessageEvent e) {
    if (!_origins.contains(e.origin) || _failed) return;
    final data = e.data;
    if (data == null || !data.isA<JSString>()) return;
    Object? m;
    try {
      m = jsonDecode((data as JSString).toDart);
    } on FormatException {
      return;
    }
    if (m is! Map || (m['id'] != null && m['id'] != _id)) return;
    final event = m['event'];
    final info = m['info'];
    int? state;
    if (event == 'onStateChange' && info is num) state = info.toInt();
    if (event == 'infoDelivery' && info is Map && info['playerState'] is num) state = (info['playerState'] as num).toInt();
    if (event == 'onReady') {
      _command('mute');
      _sync();
    } else if (event == 'onError' || event == 'onAutoplayBlocked') {
      _fail();
    } else if (state == 1 && !_playing) {
      _playing = true;
      _timeout?.cancel();
      _frame?.style.opacity = '1';
    }
  }

  void _fail() {
    if (_failed) return;
    _failed = true;
    _timeout?.cancel();
    _frame?.style.opacity = '0';
    if (mounted) widget.onFailed();
  }

  void _sync() => _command(widget.play ? 'playVideo' : 'pauseVideo');

  void _layout() {
    final f = _frame;
    if (f == null || _size.isEmpty) return;
    final c = youtubeCover(_size.width, _size.height, widget.alignment);
    f.style
      ..left = '${c.left}px'
      ..top = '${c.top}px'
      ..width = '${c.width}px'
      ..height = '${c.height}px';
  }

  @override
  void didUpdateWidget(covariant HeroYouTube old) {
    super.didUpdateWidget(old);
    if (old.play != widget.play) _sync();
    if (old.cssFilter != widget.cssFilter) _box?.style.filter = widget.cssFilter;
  }

  @override
  void dispose() {
    _timeout?.cancel();
    if (_onMessage != null) web.window.removeEventListener('message', _onMessage);
    final f = _frame;
    _frame = null;
    if (f != null) {
      f.src = 'about:blank'; // stops the stream
      f.remove();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final s = Size(c.maxWidth, c.maxHeight);
        if (s != _size) {
          _size = s;
          _layout();
        }
        return IgnorePointer(
          child: HtmlElementView.fromTagName(tagName: 'div', isVisible: true, onElementCreated: _created),
        );
      });
}
