import 'dart:async';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import 'admin_strings.dart';
import 'unsaved_guard_stub.dart' if (dart.library.js_interop) 'unsaved_guard_web.dart' as impl;

typedef DiscardHandler = Future<bool> Function();

void addDirtyToken() => impl.registerDirtyToken();
void removeDirtyToken() => impl.unregisterDirtyToken();
VoidCallback addBeforeUnloadFlush(VoidCallback callback) => impl.addBeforeUnloadFlush(callback);

void registerDiscardHandler(DiscardHandler handler) => impl.registerDiscardHandler(handler);
void unregisterDiscardHandler(DiscardHandler handler) => impl.unregisterDiscardHandler(handler);

@visibleForTesting
void debugTriggerBeforeUnload() => impl.debugTriggerBeforeUnload();

@visibleForTesting
Future<bool> debugSimulatePopState() => impl.debugSimulatePopState();

/// Prompts the user before discarding unsaved edits.
///
/// The primary action button is «متابعة التعديل» (`discard-keep`), returning `false`.
/// The discard button is «تجاهل» (`discard-confirm`), returning `true`.
Future<bool> confirmDiscardChanges(
  BuildContext context, {
  void Function(void Function(bool discard) dismiss)? onOpen,
}) async {
  registerAdminStrings();
  BuildContext? dialogCtx;
  var settled = false;
  onOpen?.call((discard) {
    if (settled) return;
    final ctx = dialogCtx;
    if (ctx != null && ctx.mounted) {
      Navigator.of(ctx).pop(discard);
    }
  });
  try {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        dialogCtx = ctx;
        return AlertDialog(
          content: Text(context.tr('discardChanges')),
          actions: [
            TextButton(
              key: const ValueKey('discard-confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.tr('discard')),
            ),
            FilledButton(
              key: const ValueKey('discard-keep'),
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.tr('keepEditing')),
            ),
          ],
        );
      },
    );
    return res == true;
  } finally {
    settled = true;
  }
}

/// Tracks unsaved / dirty states across embedded admin sections.
class UnsavedGuardRegistry extends ChangeNotifier {
  final Set<Object> _dirtyTokens = <Object>{};
  bool _notificationScheduled = false;
  bool _disposed = false;

  bool get isDirty => _dirtyTokens.isNotEmpty;
  int get dirtyCount => _dirtyTokens.length;

  void register(Object token) {
    if (_dirtyTokens.add(token)) {
      _scheduleNotification();
    }
  }

  void unregister(Object token) {
    if (_dirtyTokens.remove(token)) {
      _scheduleNotification();
    }
  }

  void _scheduleNotification() {
    if (_notificationScheduled || _disposed) return;
    _notificationScheduled = true;
    scheduleMicrotask(() {
      _notificationScheduled = false;
      if (!_disposed) {
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Exposes [UnsavedGuardRegistry] down the widget tree.
class UnsavedGuardScope extends InheritedNotifier<UnsavedGuardRegistry> {
  const UnsavedGuardScope({
    super.key,
    required UnsavedGuardRegistry registry,
    required super.child,
  }) : super(notifier: registry);

  static UnsavedGuardRegistry? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<UnsavedGuardScope>()?.notifier;
  }

  static UnsavedGuardRegistry of(BuildContext context) {
    final reg = maybeOf(context);
    assert(reg != null, 'No UnsavedGuardScope found in context');
    return reg!;
  }

  static UnsavedGuardRegistry? registryOf(BuildContext context) {
    final elem = context.getElementForInheritedWidgetOfExactType<UnsavedGuardScope>();
    return (elem?.widget as UnsavedGuardScope?)?.notifier;
  }
}

/// Protects unsaved edits against accidental navigation and browser closing.
class UnsavedGuard extends StatefulWidget {
  final bool dirty;
  final Widget child;
  final bool handlePop;
  final VoidCallback? onBrowserBackDiscard;

  const UnsavedGuard({
    super.key,
    required this.dirty,
    required this.child,
    this.handlePop = true,
    this.onBrowserBackDiscard,
  });

  @override
  State<UnsavedGuard> createState() => _UnsavedGuardState();
}

class _UnsavedGuardState extends State<UnsavedGuard> {
  UnsavedGuardRegistry? _registry;
  bool _registeredDirty = false;
  DiscardHandler? _discardHandler;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newRegistry = UnsavedGuardScope.registryOf(context);
    if (_registry != newRegistry) {
      if (_registeredDirty && _registry != null) {
        _registry!.unregister(this);
      }
      _registry = newRegistry;
      if (_registeredDirty && _registry != null) {
        _registry!.register(this);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _syncDirtiness(widget.dirty);
  }

  @override
  void didUpdateWidget(UnsavedGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.dirty != oldWidget.dirty) {
      _syncDirtiness(widget.dirty);
    }
  }

  void _syncDirtiness(bool dirty) {
    if (dirty == _registeredDirty) return;
    _registeredDirty = dirty;
    if (dirty) {
      addDirtyToken();
      _registry?.register(this);
      _discardHandler = _handlePopDiscard;
      registerDiscardHandler(_discardHandler!);
    } else {
      if (_discardHandler != null) {
        unregisterDiscardHandler(_discardHandler!);
        _discardHandler = null;
      }
      removeDirtyToken();
      _registry?.unregister(this);
    }
  }

  Future<bool> _handlePopDiscard() async {
    if (!mounted) return true;
    final discard = await confirmDiscardChanges(context);
    if (discard && mounted) {
      if (widget.handlePop) {
        final nav = Navigator.of(context);
        if (nav.canPop()) {
          nav.pop();
        }
      } else if (widget.onBrowserBackDiscard != null) {
        widget.onBrowserBackDiscard!.call();
      } else {
        final nav = Navigator.of(context);
        if (nav.canPop()) {
          nav.pop();
        }
      }
    }
    return discard;
  }

  @override
  void dispose() {
    if (_registeredDirty) {
      if (_discardHandler != null) {
        unregisterDiscardHandler(_discardHandler!);
        _discardHandler = null;
      }
      removeDirtyToken();
      _registry?.unregister(this);
      _registeredDirty = false;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.handlePop || !widget.dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final discard = await confirmDiscardChanges(context);
        if (discard && context.mounted) {
          final nav = Navigator.of(context);
          if (nav.canPop()) {
            nav.pop(result);
          }
        }
      },
      child: widget.child,
    );
  }
}
