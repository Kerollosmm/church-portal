import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../domain/rules.dart' show toArabicDigits;
import 'admin_strings.dart';
import 'session_policy_stub.dart' if (dart.library.js_interop) 'session_policy_web.dart' as focus_impl;
import 'unsaved_guard.dart';

/// Pure idle-timeout policy for shared office admin sessions (P1-13, D1).
class SessionPolicy {
  final Duration idleLimit;
  final Duration warnBefore;
  final Duration confirmTimeout;

  const SessionPolicy({
    this.idleLimit = const Duration(minutes: 30),
    this.warnBefore = const Duration(seconds: 60),
    this.confirmTimeout = const Duration(seconds: 60),
  });

  Duration get warnAt => idleLimit > warnBefore ? idleLimit - warnBefore : Duration.zero;
}

/// Tracks pointer and keyboard activity around the dashboard when [enabled] is
/// true (shared device / "Remember me" unticked), warns [SessionPolicy.warnBefore]
/// before [SessionPolicy.idleLimit], and signs out cleanly after checking
/// [unsaved] edits.
class AdminSessionGuard extends StatefulWidget {
  final bool enabled;
  final SessionPolicy policy;
  final UnsavedGuardRegistry unsaved;
  final VoidCallback onSignOut;
  final DateTime Function()? now;
  final Widget child;

  const AdminSessionGuard({
    super.key,
    required this.enabled,
    required this.unsaved,
    required this.onSignOut,
    required this.child,
    this.policy = const SessionPolicy(),
    this.now,
  });

  @override
  State<AdminSessionGuard> createState() => _AdminSessionGuardState();
}

class _AdminSessionGuardState extends State<AdminSessionGuard> with WidgetsBindingObserver {
  Timer? _warnTimer;
  Timer? _signOutTimer;
  Timer? _countdownTimer;
  Timer? _confirmTimer;
  DateTime? _lastActivityAt;
  DateTime? _confirmShownAt;
  void Function(bool discard)? _dismissConfirmDialog;
  VoidCallback? _removeFocusListener;
  bool _warning = false;
  bool _confirmingUnsaved = false;
  bool _listenersAttached = false;
  int _secondsLeft = 0;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _attachListeners();
      _resetTimers();
    }
  }

  @override
  void didUpdateWidget(covariant AdminSessionGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !oldWidget.enabled) {
      _attachListeners();
      _resetTimers();
    } else if (!widget.enabled && oldWidget.enabled) {
      _detachListeners();
      _cancelTimers();
      _lastActivityAt = null;
      _dismissConfirmDialog?.call(false);
      if (_warning) setState(() => _warning = false);
    } else if (widget.enabled && widget.policy != oldWidget.policy) {
      _resetTimers();
    }
  }

  @override
  void dispose() {
    _detachListeners();
    _cancelTimers();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkWallClock();
    }
  }

  void _attachListeners() {
    if (_listenersAttached) return;
    _listenersAttached = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onGlobalPointer);
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    WidgetsBinding.instance.addObserver(this);
    _removeFocusListener = focus_impl.addWindowFocusListener(_checkWallClock);
  }

  void _detachListeners() {
    if (!_listenersAttached) return;
    _listenersAttached = false;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onGlobalPointer);
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    WidgetsBinding.instance.removeObserver(this);
    _removeFocusListener?.call();
    _removeFocusListener = null;
  }

  void _onGlobalPointer(PointerEvent event) {
    if (event is PointerDownEvent ||
        event is PointerMoveEvent ||
        event is PointerHoverEvent ||
        event is PointerSignalEvent ||
        event is PointerPanZoomStartEvent) {
      _recordActivity();
    }
  }

  bool _onKeyEvent(KeyEvent event) {
    _recordActivity();
    return false;
  }

  void _cancelTimers() {
    _warnTimer?.cancel();
    _warnTimer = null;
    _signOutTimer?.cancel();
    _signOutTimer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _confirmTimer?.cancel();
    _confirmTimer = null;
  }

  void _recordActivity() {
    if (!mounted || !widget.enabled || _confirmingUnsaved) return;
    final last = _lastActivityAt;
    if (last != null && _now().difference(last) >= widget.policy.idleLimit) {
      _onIdleLimit();
      return;
    }
    if (_warning) {
      setState(() => _warning = false);
    }
    _resetTimers();
  }

  void _resetTimers() {
    _cancelTimers();
    if (!widget.enabled) {
      _lastActivityAt = null;
      return;
    }
    _lastActivityAt = _now();
    _scheduleFromElapsed(Duration.zero);
  }

  void _scheduleFromElapsed(Duration elapsed) {
    _warnTimer?.cancel();
    _warnTimer = null;
    _signOutTimer?.cancel();
    _signOutTimer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;

    final policy = widget.policy;
    if (elapsed >= policy.idleLimit) {
      _onIdleLimit();
      return;
    }
    final untilSignOut = policy.idleLimit - elapsed;
    if (elapsed >= policy.warnAt) {
      final remaining = untilSignOut.inSeconds;
      if (!_warning || _secondsLeft != remaining) {
        setState(() {
          _warning = true;
          _secondsLeft = remaining > 0 ? remaining : 0;
        });
      }
      _startCountdown();
      _signOutTimer = Timer(untilSignOut, _onIdleLimit);
      return;
    }
    if (_warning) {
      setState(() => _warning = false);
    }
    _secondsLeft = policy.warnBefore.inSeconds;
    _warnTimer = Timer(policy.warnAt - elapsed, _showWarning);
    _signOutTimer = Timer(untilSignOut, _onIdleLimit);
  }

  void _checkWallClock() {
    if (!mounted || !widget.enabled) return;
    if (_confirmingUnsaved) {
      final shownAt = _confirmShownAt;
      if (shownAt != null && _now().difference(shownAt) >= widget.policy.confirmTimeout) {
        _confirmTimer?.cancel();
        _confirmTimer = null;
        _dismissConfirmDialog?.call(true);
      }
      return;
    }
    final last = _lastActivityAt;
    if (last == null) return;
    final elapsed = _now().difference(last);
    if (elapsed.isNegative) {
      _resetTimers();
      return;
    }
    _scheduleFromElapsed(elapsed);
  }

  void _showWarning() {
    if (!mounted || !widget.enabled || _confirmingUnsaved) return;
    final remaining = (widget.policy.idleLimit - widget.policy.warnAt).inSeconds;
    setState(() {
      _warning = true;
      _secondsLeft = remaining > 0 ? remaining : 0;
    });
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_warning) return;
      if (_secondsLeft > 0) {
        setState(() => _secondsLeft--);
      }
    });
  }

  Future<void> _onIdleLimit() async {
    _warnTimer?.cancel();
    _warnTimer = null;
    _signOutTimer?.cancel();
    _signOutTimer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (!mounted || !widget.enabled || _confirmingUnsaved) return;
    if (!widget.unsaved.isDirty) {
      widget.onSignOut();
      return;
    }
    _confirmingUnsaved = true;
    _confirmShownAt = _now();
    if (_warning) setState(() => _warning = false);
    _confirmTimer?.cancel();
    _confirmTimer = Timer(widget.policy.confirmTimeout, () {
      _dismissConfirmDialog?.call(true);
    });
    final discard = await confirmDiscardChanges(
      context,
      onOpen: (dismiss) => _dismissConfirmDialog = dismiss,
    );
    _confirmTimer?.cancel();
    _confirmTimer = null;
    _confirmShownAt = null;
    _dismissConfirmDialog = null;
    _confirmingUnsaved = false;
    if (!mounted || !widget.enabled) return;
    if (discard) {
      widget.onSignOut();
    } else {
      _resetTimers();
    }
  }

  @override
  Widget build(BuildContext context) {
    registerAdminStrings();
    final content = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, _) {
        _recordActivity();
        return KeyEventResult.ignored;
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _recordActivity(),
        onPointerMove: (_) => _recordActivity(),
        onPointerHover: (_) => _recordActivity(),
        onPointerSignal: (_) => _recordActivity(),
        child: widget.child,
      ),
    );
    final showBanner = widget.enabled && _warning;
    final secs = context.isAr ? toArabicDigits('$_secondsLeft') : '$_secondsLeft';
    return Stack(
      fit: StackFit.passthrough,
      children: [
        content,
        if (showBanner)
          Positioned(
            top: 8,
            left: 12,
            right: 12,
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Material(
                    key: const ValueKey('session-idle-warning'),
                    elevation: 6,
                    borderRadius: BorderRadius.circular(12),
                    color: context.pal.surface,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.pal.alert, width: 1.5),
                      ),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 360),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.timer_outlined, color: context.pal.alert),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        context.tr('sessionWarnTitle', {'s': secs}),
                                        style: TextStyle(fontWeight: FontWeight.w800, color: context.pal.alert),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        context.tr('sessionWarnBody'),
                                        style: TextStyle(fontSize: 13, color: context.pal.ink),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          FilledButton(
                            key: const ValueKey('session-stay-btn'),
                            onPressed: _recordActivity,
                            child: Text(context.tr('staySignedIn')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
