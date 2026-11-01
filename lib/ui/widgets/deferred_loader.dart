import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import 'common.dart';

/// Loads a deferred library (`import '...' deferred as x;`) before building
/// the widget it provides, so heavy routes (the admin dashboard, the
/// Gemini-backed assistant) ship as separate web chunks fetched only when
/// visited. Shows a spinner while the chunk downloads and a retry on failure
/// (a flaky connection must not leave a blank page). On non-web platforms
/// `loadLibrary()` completes at once.
class DeferredLoader extends StatefulWidget {
  /// The deferred prefix's `loadLibrary` (e.g. `admin_page.loadLibrary`).
  final Future<void> Function() loadLibrary;

  /// Builds the page once the library is loaded.
  final WidgetBuilder builder;

  /// Wrap the placeholder in its own [Scaffold] (routes outside the shell,
  /// like `/admin`).
  final bool fullScreen;

  const DeferredLoader({super.key, required this.loadLibrary, required this.builder, this.fullScreen = false});

  @override
  State<DeferredLoader> createState() => _DeferredLoaderState();
}

class _DeferredLoaderState extends State<DeferredLoader> {
  late Future<void> _future = widget.loadLibrary();

  void _retry() {
    // Block body: an arrow would hand the assigned Future back to setState.
    setState(() {
      _future = widget.loadLibrary();
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.done && !snap.hasError) return widget.builder(context);
          final Widget placeholder = snap.hasError
              ? Center(child: ErrorState(onRetry: _retry))
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Semantics(
                      liveRegion: true,
                      label: context.tr('loadingPage'),
                      child: const CircularProgressIndicator(),
                    ),
                  ),
                );
          return widget.fullScreen ? Scaffold(body: placeholder) : placeholder;
        },
      );
}
