import 'dart:io';

import 'package:church_portal/main.dart' show ensureWebSemantics;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ensureWebSemantics enables semantics on web and no-ops off web', (tester) async {
    expect(ensureWebSemantics(isWeb: false), isNull);
    final handle = ensureWebSemantics(isWeb: true);
    expect(handle, isNotNull);
    try {
      expect(SemanticsBinding.instance.semanticsEnabled, isTrue);
    } finally {
      handle!.dispose();
    }
  });

  test('_start calls ensureWebSemantics immediately after WidgetsFlutterBinding.ensureInitialized', () {
    final source = File('lib/main.dart').readAsStringSync();
    final startIdx = source.indexOf('Future<void> _start()');
    expect(startIdx, greaterThanOrEqualTo(0));
    final body = source.substring(startIdx);
    final initIdx = body.indexOf('WidgetsFlutterBinding.ensureInitialized();');
    final semIdx = body.indexOf('ensureWebSemantics();');
    expect(initIdx, greaterThan(0));
    expect(semIdx, greaterThan(initIdx));
    expect(body.substring(initIdx, semIdx), isNot(contains('runApp(')));
  });
}
