// TEMPORARY diagnostics (PR #23 investigation) — removed before merge.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';

class DiagApp extends StatefulWidget {
  final String boot;
  const DiagApp({super.key, required this.boot});
  @override
  State<DiagApp> createState() => _DiagAppState();
}

class _DiagAppState extends State<DiagApp> {
  final _sw = Stopwatch()..start();
  final _lines = <String>[];
  final _subs = <StreamSubscription<Object?>>[];

  void _log(String s) => setState(() => _lines.add('[${(_sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s] $s'));

  @override
  void initState() {
    super.initState();
    _lines.add('boot: ${widget.boot}');
    final db = FirebaseFirestore.instance;
    db.doc('settings/church').get().timeout(const Duration(seconds: 20)).then(
        (d) => _log('GET settings/church exists=${d.exists} fromCache=${d.metadata.isFromCache}'),
        onError: (Object e) => _log('GET settings/church ERROR $e'));
    db.doc('settings/church').get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 20)).then(
        (d) => _log('GET(server) settings/church exists=${d.exists}'),
        onError: (Object e) => _log('GET(server) settings/church ERROR $e'));
    for (final c in ['categories', 'entries', 'pages', 'meetings', 'alerts']) {
      _subs.add(db.collection(c).snapshots(includeMetadataChanges: true).listen(
          (s) => _log('SNAP $c size=${s.docs.length} fromCache=${s.metadata.isFromCache} pending=${s.metadata.hasPendingWrites}'),
          onError: (Object e) => _log('SNAP $c ERROR $e')));
    }
    for (final d in ['settings/contact', 'settings/features']) {
      _subs.add(db.doc(d).snapshots(includeMetadataChanges: true).listen(
          (s) => _log('DOC $d exists=${s.exists} fromCache=${s.metadata.isFromCache} '
              '${d == 'settings/contact' ? 'cats=${(s.data()?['categories'] as Map?)?.length}' : ''}'),
          onError: (Object e) => _log('DOC $d ERROR $e')));
    }
    Timer(const Duration(seconds: 25), () => _log('DONE (25 s)'));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              for (final l in _lines) Text(l, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 14)),
            ]),
          ),
        ),
      );
}
