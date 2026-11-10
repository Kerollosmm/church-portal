import 'dart:math';
import 'package:church_portal/domain/today.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DayEvent persistent ID & NFC normalization (ADR-059)', () {
    test('nfcNormalizeArabic canonically composes decomposed Arabic sequences', () {
      // \u0627\u0653 -> \u0622 (Alif with Madda above)
      expect(nfcNormalizeArabic('\u0627\u0653'), '\u0622');

      // \u0627\u0654 -> \u0623 (Alif with Hamza above)
      expect(nfcNormalizeArabic('\u0627\u0654'), '\u0623');

      // \u0648\u0654 -> \u0624 (Waw with Hamza above)
      expect(nfcNormalizeArabic('\u0648\u0654'), '\u0624');

      // \u0627\u0655 -> \u0625 (Alif with Hamza below)
      expect(nfcNormalizeArabic('\u0627\u0655'), '\u0625');

      // \u064A\u0654 -> \u0626 (Yeh with Hamza above)
      expect(nfcNormalizeArabic('\u064A\u0654'), '\u0626');

      // \u0647\u0654 -> \u06C0 (Heh with Hamza above)
      expect(nfcNormalizeArabic('\u0647\u0654'), '\u06C0');

      // Already composed string remains unchanged
      const composed = 'كنيسة القديسين مكسيموس ودوماديوس والأنبا موسى الأسود';
      expect(nfcNormalizeArabic(composed), composed);
    });

    test('nfcNormalizeArabic sorts contiguous harakat by Canonical Combining Class (CCC)', () {
      // Fatha (\u064E, CCC 27) and Shadda (\u0651, CCC 33)
      // Regardless of input order, Canonical Combining Class sorts \u0651 (33) after \u064E (27)?
      // Actually Shadda is 33, Fatha is 27. So Fatha then Shadda: 27 <= 33.
      // If entered as Shadda (33) then Fatha (27), stable sort puts Fatha (27) before Shadda (33).
      final s1 = nfcNormalizeArabic('\u0645\u0651\u064E'); // Meem + Shadda + Fatha
      final s2 = nfcNormalizeArabic('\u0645\u064E\u0651'); // Meem + Fatha + Shadda
      expect(s1, equals(s2));
    });

    test('computeHashId produces deterministic 10-char lowercase hex SHA-1 prefix matching JS NFC', () {
      final hash1 = DayEvent.computeHashId('2026-11-05', '18:30', 'الليلة الرابعة');
      final hash2 = DayEvent.computeHashId('2026-11-05', '18:30', 'الليلة الرابعة');
      expect(hash1, equals(hash2));
      expect(hash1, matches(RegExp(r'^[0-9a-f]{10}$')));

      // Trimming whitespace does not change hash
      final hashTrimmed = DayEvent.computeHashId('  2026-11-05  ', '  18:30  ', '  الليلة الرابعة  ');
      expect(hashTrimmed, equals(hash1));
    });

    test('generateRandomId returns 8-character [a-z0-9]{8} string', () {
      final rng = Random(42);
      final id1 = DayEvent.generateRandomId(rng);
      final id2 = DayEvent.generateRandomId(rng);

      expect(id1.length, 8);
      expect(id1, matches(RegExp(r'^[a-z0-9]{8}$')));
      expect(id2.length, 8);
      expect(id2, matches(RegExp(r'^[a-z0-9]{8}$')));
      expect(id1, isNot(equals(id2)));
    });

    test('DayEvent.fromStored parses 17th id field when present and valid', () {
      // 17 fields: last field is random 8-char id 'abc12345'
      const raw17 = '2026-11-05\u001f\u001f18:30\u001f21:30\u001fنهضة\u001fRevival\u001fابونا\u001fFr\u001fموضوع\u001fTopic\u001fملاحظة\u001fNote\u001f/contact\u001fhttps://drive.google.com/pdf\u001fبرنامج\u001fProgram\u001fabc12345';
      final event = DayEvent.fromStored(raw17)!;

      expect(event.id, 'abc12345');
      expect(event.titleAr, 'نهضة');
      expect(event.start, '18:30');
    });

    test('DayEvent.fromStored falls back to 10-char SHA-1 prefix on legacy 13 or 16-field rows', () {
      // 16 fields (no 17th id)
      const raw16 = '2026-11-05\u001f\u001f18:30\u001f21:30\u001fالليلة الرابعة\u001f\u001f\u001f\u001f\u001f\u001f\u001f\u001f\u001f\u001f\u001f';
      final event = DayEvent.fromStored(raw16)!;

      final expectedHash = DayEvent.computeHashId('2026-11-05', '18:30', 'الليلة الرابعة');
      expect(event.id, equals(expectedHash));
      expect(event.id.length, 10);
      expect(event.id, matches(RegExp(r'^[0-9a-f]{10}$')));
    });

    test('DayEvent.fromStored replaces invalid 17th id with computeHashId fallback', () {
      // 17th field with invalid characters (uppercase or symbols)
      const rawBadId = '2026-11-05\u001f\u001f18:30\u001f21:30\u001fنهضة\u001f\u001f\u001f\u001f\u001f\u001f\u001f\u001f\u001f\u001f\u001f\u001fBAD_ID!';
      final event = DayEvent.fromStored(rawBadId)!;

      final expectedHash = DayEvent.computeHashId('2026-11-05', '18:30', 'نهضة');
      expect(event.id, equals(expectedHash));
    });
  });
}
