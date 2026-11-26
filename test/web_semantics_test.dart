import 'package:church_portal/main.dart' show ensureWebSemantics;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ensureWebSemantics enables semantics on web and no-ops off web', (tester) async {
    expect(ensureWebSemantics(isWeb: false), isNull);
    final handle = ensureWebSemantics(isWeb: true);
    expect(handle, isNotNull);
    expect(SemanticsBinding.instance.semanticsEnabled, isTrue);
    handle!.dispose();
  });
}
