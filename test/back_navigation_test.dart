import 'package:church_portal/core/back_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decideBackAction', () {
    test('native apps always go', () {
      expect(
        decideBackAction(
          isWeb: false,
          previous: '/church-education',
          target: '/church-education',
        ),
        BackAction.go,
      );
    });

    test('web: coming from the target pops browser history', () {
      expect(
        decideBackAction(
          isWeb: true,
          previous: '/church-education',
          target: '/church-education',
        ),
        BackAction.historyBack,
      );
      expect(
        decideBackAction(
          isWeb: true,
          previous: '/church-education/',
          target: '/church-education',
        ),
        BackAction.historyBack,
      );
    });

    test('web: any other origin replaces the current entry', () {
      expect(
        decideBackAction(
          isWeb: true,
          previous: null,
          target: '/church-education',
        ),
        BackAction.replace,
      );
      expect(
        decideBackAction(
          isWeb: true,
          previous: '/search',
          target: '/church-education',
        ),
        BackAction.replace,
      );
    });
  });
}
