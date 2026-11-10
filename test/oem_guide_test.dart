import 'package:flutter_test/flutter_test.dart';
import 'package:church_portal/domain/oem_guide.dart';

void main() {
  group('OEM Brand Detection', () {
    test('detects Xiaomi variants', () {
      expect(detectOemBrand('Xiaomi'), OemBrand.xiaomi);
      expect(detectOemBrand('Redmi'), OemBrand.xiaomi);
      expect(detectOemBrand('POCO', 'POCO X3'), OemBrand.xiaomi);
      expect(detectOemBrand('Blackshark'), OemBrand.xiaomi);
    });

    test('detects Oppo and sister brands', () {
      expect(detectOemBrand('OPPO', 'CPH2235'), OemBrand.oppo);
      expect(detectOemBrand('Realme'), OemBrand.oppo);
      expect(detectOemBrand('OnePlus'), OemBrand.oppo);
    });

    test('detects Vivo variants', () {
      expect(detectOemBrand('vivo'), OemBrand.vivo);
      expect(detectOemBrand('iQOO'), OemBrand.vivo);
    });

    test('detects Huawei and Honor', () {
      expect(detectOemBrand('HUAWEI'), OemBrand.huawei);
      expect(detectOemBrand('HONOR'), OemBrand.huawei);
    });

    test('detects Samsung', () {
      expect(detectOemBrand('samsung', 'SM-G998B'), OemBrand.samsung);
    });

    test('falls back to other for unknown manufacturers', () {
      expect(detectOemBrand('Google', 'Pixel 8'), OemBrand.other);
      expect(detectOemBrand('Motorola'), OemBrand.other);
    });
  });

  group('OEM Steps and Intent Try-Lists', () {
    test('returns dedicated steps for each brand', () {
      for (final brand in OemBrand.values) {
        final steps = oemStepsForBrand(brand);
        expect(steps, isNotEmpty);
        for (final s in steps) {
          expect(s.title(true), isNotEmpty);
          expect(s.title(false), isNotEmpty);
          expect(s.body(true), isNotEmpty);
          expect(s.body(false), isNotEmpty);
        }
      }
    });

    test('intent try-lists exist for action keys', () {
      expect(oemIntentTryLists['autostart_xiaomi'], isNotEmpty);
      expect(oemIntentTryLists['autostart_oppo'], isNotEmpty);
      expect(oemIntentTryLists['battery_samsung'], isNotEmpty);
    });
  });
}
