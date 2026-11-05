// ADR-046: fixes for the live user test of 5 Nov 2026
// (work/live-findings/rca.md).
//   1. The top-event card waits for the stored settings/features, never the
//      bundled seed copy (cold-load flicker).
//   2. index.html sets the English <title> / lang before Flutter boots.
//   3. index.html drops the App Check provider FlutterFire saved after /ask,
//      so reCAPTCHA loads on /ask only (ADR-037 lazy activation).
//   4. The /about accent reads «كنيستنا» / "Our church".
//   5. No «بيانات تجريبية» badge or "times pending" note in the public UI
//      (the `sample` field stays in the data and the admin).
//   6. fetch_synaxarium.js computes the Coptic date when Katameros sends null.
//   7. The pope-visit milestone images are Hosting assets (no Storage).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:church_portal/core/l10n.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/coptic_calendar.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/domain/today.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/widgets/cards.dart';
import 'package:church_portal/ui/widgets/today_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:timezone/timezone.dart' as tz;

tz.TZDateTime cairo(int y, int m, int d, [int h = 0, int min = 0]) => CairoTime.at(y, m, d, h * 60 + min);

/// Passes `is FirestoreRepository` with a controllable features stream.
class _Fs implements FirestoreRepository {
  _Fs(this.seed, this._features);
  @override
  final SeedData seed;
  final Stream<FeatureSettings> _features;
  @override
  Stream<FeatureSettings> features() => _features;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repo extends SeedRepository {
  _Repo(super.seed, this._lits);
  final List<Liturgy> _lits;
  @override
  Stream<List<Liturgy>> liturgies() => Stream.value(_lits);
  @override
  Stream<List<Season>> seasons() => Stream.value(const []);
}

Map<String, dynamic> _seedRaw() =>
    jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>;

/// A church event today (dayEvents row) so the top event has something to show.
const _eventToday = <String, dynamic>{
  'dayEvents': ['2026-11-05\u001f\u001f18:30\u001f21:30\u001fالليلة الرابعة\u001f\u001f\u001f\u001f\u001f\u001f\u001f\u001f\u001f\u001f\u001f'],
};

/// Runs `node` when it is on PATH (GitHub runners have it); null otherwise.
String? _node(List<String> args) {
  try {
    final r = Process.runSync('node', args);
    if (r.exitCode != 0) throw StateError('node failed: ${r.stderr}');
    return (r.stdout as String).trim();
  } on ProcessException {
    return null;
  }
}

void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('1. top event waits for the stored features (no seed flash)', () {
    const seedCopy = FeatureSettings.defaults;
    final stored = FeatureSettings.fromMap(const {'topEvent': false});

    test('the rule: seed copy and loading are not live; a stored doc or an error is', () {
      expect(featuresLive(const AsyncValue<FeatureSettings>.loading(), seedCopy: seedCopy), isFalse);
      expect(featuresLive(const AsyncValue.data(seedCopy), seedCopy: seedCopy), isFalse);
      expect(featuresLive(AsyncValue.data(stored), seedCopy: seedCopy), isTrue);
      expect(featuresLive(AsyncValue<FeatureSettings>.error('x', StackTrace.empty), seedCopy: seedCopy), isTrue);
      // A stored doc that reads like the seed still counts: only the bundled copy is skipped.
      expect(featuresLive(AsyncValue.data(FeatureSettings.fromMap(const {'topEvent': true})), seedCopy: seedCopy), isTrue);
    });

    test('the bundled copy is one object, so the identical test can match it', () {
      final seed = SeedData(_seedRaw());
      expect(identical(seed.features, seed.features), isTrue);
      expect(identical(seed.settings, seed.settings), isTrue);
      expect(featuresLive(AsyncValue.data(seed.features), seedCopy: seed.features), isFalse);
      // The stored doc's snapshot is parsed anew: never identical to the seed copy.
      final stored = FeatureSettings.fromMap(_seedRaw()['settings']['features'] as Map<String, dynamic>);
      expect(featuresLive(AsyncValue.data(stored), seedCopy: seed.features), isTrue);
      // A seed without features (or one that failed to load) is still its own object, so an
      // empty stored doc (parsed to the shared defaults) is not taken for it.
      final empty = SeedData(const {});
      expect(identical(empty.features, FeatureSettings.defaults), isFalse);
      expect(featuresLive(const AsyncValue.data(FeatureSettings.defaults), seedCopy: empty.features), isTrue);
    });

    test('off Firestore (seed mode) the seed is the content, so it is live at once', () {
      final c = ProviderContainer(overrides: [repositoryProvider.overrideWithValue(_Repo(SeedData(_seedRaw()), const []))]);
      addTearDown(c.dispose);
      expect(c.read(featuresLiveProvider), isTrue);
    });

    testWidgets('on Firestore: the seed copy waits, the stored doc goes at once, the seed is accepted after the patience',
        (tester) async {
      final seed = SeedData(_seedRaw());
      final ctl = StreamController<FeatureSettings>();
      addTearDown(ctl.close);
      final c = ProviderContainer(overrides: [repositoryProvider.overrideWithValue(_Fs(seed, ctl.stream))]);
      final seen = <bool>[];
      c.listen<bool>(featuresLiveProvider, (_, v) => seen.add(v), fireImmediately: true);
      ctl.add(seed.features); // the bundled copy (slow cold load / offline)
      await tester.pump();
      expect(c.read(featuresLiveProvider), isFalse);
      await tester.pump(featuresSeedPatience - const Duration(seconds: 1));
      expect(c.read(featuresLiveProvider), isFalse, reason: 'still within the patience');
      await tester.pump(const Duration(seconds: 2));
      expect(c.read(featuresLiveProvider), isTrue, reason: 'offline / failed stream: the defaults come back');
      expect(seen, [false, true]);
      c.dispose(); // before the binding checks for pending timers
    });

    testWidgets('on Firestore: a stored doc right after the seed copy is live with no wait', (tester) async {
      final seed = SeedData(_seedRaw());
      final ctl = StreamController<FeatureSettings>();
      addTearDown(ctl.close);
      final c = ProviderContainer(overrides: [repositoryProvider.overrideWithValue(_Fs(seed, ctl.stream))]);
      c.listen<bool>(featuresLiveProvider, (_, _) {}, fireImmediately: true);
      ctl.add(seed.features);
      await tester.pump();
      expect(c.read(featuresLiveProvider), isFalse);
      ctl.add(FeatureSettings.fromMap(const {'topEvent': false}));
      await tester.pump();
      expect(c.read(featuresLiveProvider), isTrue);
      c.dispose(); // cancels the patience timer before the binding checks for pending timers
    });

    ProviderContainer container({required bool live}) {
      final c = ProviderContainer(overrides: [
        repositoryProvider.overrideWithValue(_Repo(SeedData(_seedRaw()), const [])),
        nowProvider.overrideWith((ref) => Stream.value(cairo(2026, 11, 5, 12))),
        featuresProvider.overrideWithValue(FeatureSettings.fromMap(_eventToday)),
        featuresLiveProvider.overrideWithValue(live),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    Future<TopEvent?> topEvent(ProviderContainer c) async {
      c.listen(nowProvider, (_, _) {});
      c.listen(topEventProvider, (_, _) {});
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      return c.read(topEventProvider);
    }

    test('until the stored doc arrives there is no top event, then the event shows', () async {
      expect(await topEvent(container(live: false)), isNull);
      expect((await topEvent(container(live: true)))?.titleAr, 'الليلة الرابعة');
    });

    testWidgets('TopEventCard renders nothing on the seed copy', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(_Repo(SeedData(_seedRaw()), const [])),
          nowProvider.overrideWith((ref) => Stream.value(cairo(2026, 11, 5, 12))),
          featuresProvider.overrideWithValue(FeatureSettings.fromMap(_eventToday)),
          featuresLiveProvider.overrideWithValue(false),
        ],
        child: const MaterialApp(locale: Locale('ar'), home: Scaffold(body: TopEventCard())),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('topEventTitle')), findsNothing);
    });

    test('no new listener: the gate reads featuresStreamProvider only', () {
      final src = File('lib/state/providers.dart').readAsStringSync();
      final body = src.substring(src.indexOf('final featuresLiveProvider'), src.indexOf('@visibleForTesting\nbool featuresLive'));
      expect(body, contains('featuresStreamProvider'));
      expect(body, isNot(contains('StreamProvider<')));
    });
  });

  group('2 + 3. index.html boot script', () {
    final html = File('web/index.html').readAsStringSync();
    final start = html.indexOf('<script id="boot-prefs">');
    final script = html.substring(start + '<script id="boot-prefs">'.length, html.indexOf('</script>', start));

    test('runs after <title> and before Flutter boots', () {
      expect(start, greaterThan(html.indexOf('</title>')));
      expect(start, lessThan(html.indexOf('</head>')));
      expect(start, lessThan(html.indexOf('flutter_bootstrap.js')));
      expect(script, contains("'church_portal_lang'"));
      expect(script, contains("'FlutterFire-'"));
      expect(script, contains("'-recaptcha'"));
    });

    test('the English title is the app name', () {
      expect(script, contains("'St. Maximus & Domadius and St. Moses the Black Church'"));
      final l10n = File('lib/core/l10n.dart').readAsStringSync();
      expect(l10n, contains("'St. Maximus & Domadius and St. Moses the Black Church'"));
    });

    // Runs the real script against a fake page (when node is available).
    Map<String, dynamic>? run(String search, Map<String, String> local, [Map<String, String> session = const {}]) {
      final harness = '''
function store(init){var d=Object.assign({},init);return{get length(){return Object.keys(d).length},key:function(i){return Object.keys(d)[i]||null},getItem:function(k){return k in d?d[k]:null},removeItem:function(k){delete d[k]},_d:d};}
var localStorage=store(${jsonEncode(local)}), sessionStorage=store(${jsonEncode(session)});
var location={search:${jsonEncode(search)}};
var document={title:'عربي',documentElement:{lang:'ar'}};
$script
console.log(JSON.stringify({title:document.title,lang:document.documentElement.lang,local:Object.keys(localStorage._d),session:Object.keys(sessionStorage._d)}));
''';
      final out = _node(['-e', harness]);
      return out == null ? null : jsonDecode(out) as Map<String, dynamic>;
    }

    test('language: ?lang= wins, then the saved choice, else Arabic', () {
      final en = run('?lang=en', {});
      if (en == null) return markTestSkipped('node not on PATH');
      expect(en['lang'], 'en');
      expect(en['title'], 'St. Maximus & Domadius and St. Moses the Black Church');
      expect(run('', {'church_portal_lang': 'en'})!['lang'], 'en');
      expect(run('?lang=ar', {'church_portal_lang': 'en'})!['lang'], 'ar');
      expect(run('?lang=ar', {'church_portal_lang': 'en'})!['title'], 'عربي');
      expect(run('', {})!['lang'], 'ar');
      expect(run('?lang=xx', {})!['lang'], 'ar');
      // Duplicate keys: the last one wins, as in Dart's Uri.queryParameters.
      expect(run('?lang=en&lang=ar', {})!['lang'], 'ar');
      expect(run('?lang=ar&lang=en', {})!['lang'], 'en');
      expect(Uri.parse('/?lang=en&lang=ar').queryParameters['lang'], 'ar');
    });

    test('App Check: the saved reCAPTCHA provider is dropped, other keys stay', () {
      final r = run('', {
        'FlutterFire-[DEFAULT]-recaptchaType': 'enterprise',
        'FlutterFire-[DEFAULT]-recaptchaSiteKey': 'k',
        'church_portal_lang': 'ar',
        'ask_quota': '3',
      }, {
        'FlutterFire-[DEFAULT]-recaptchaType': 'enterprise',
        'other': '1',
      });
      if (r == null) return markTestSkipped('node not on PATH');
      expect(r['local'], unorderedEquals(['church_portal_lang', 'ask_quota']));
      expect(r['session'], ['other']);
    });

    test('the assistant still activates App Check itself (ADR-037)', () {
      expect(File('lib/data/assistant_model.dart').readAsStringSync(), contains('ensureAppCheckActivated'));
    });
  });

  group('4. /about accent', () {
    testWidgets('reads «كنيستنا» / "Our church", never «تعرّف على» before «عن الكنيسة»', (tester) async {
      final seen = <String>[];
      for (final l in const [Locale('ar'), Locale('en')]) {
        await tester.pumpWidget(MaterialApp(
            locale: l,
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Builder(builder: (c) {
              seen.add(c.tr('accent_about'));
              return const SizedBox();
            })));
      }
      expect(seen, ['كنيستنا', 'Our church']);
    });
  });

  group('5. no sample marks in the public UI', () {
    final sampleNight = Liturgy(
        id: 's',
        type: 'mass',
        nameAr: 'قداس تجريبي',
        nameEn: 'Sample mass',
        weekday: DateTime.thursday,
        start: '18:30',
        end: '20:00',
        sample: true);

    Future<void> pump(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(_Repo(SeedData(_seedRaw()), [sampleNight])),
          nowProvider.overrideWith((ref) => Stream.value(cairo(2026, 11, 5, 12))),
        ],
        child: MaterialApp(
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(body: SingleChildScrollView(child: child))),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('liturgy card and next-service card: no badge, no «times pending» note', (tester) async {
      await pump(tester, Column(children: [LiturgyCard(liturgy: sampleNight), const NextMassCard()]));
      expect(find.text('قداس تجريبي'), findsWidgets);
      expect(find.textContaining('بيانات تجريبية'), findsNothing);
      expect(find.textContaining('مواعيد تقريبية'), findsNothing);
    });

    test('the badge / banner widgets and their strings are gone; the sample field stays in the model', () {
      final ui = Directory('lib/ui')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && !f.path.contains('${Platform.pathSeparator}admin${Platform.pathSeparator}'));
      for (final f in ui) {
        final s = f.readAsStringSync();
        for (final banned in ['SampleBadge', 'PendingConfirmationNote', "'timesPending'", "'sampleData'"]) {
          expect(s.contains(banned), isFalse, reason: '${f.path} still uses $banned');
        }
      }
      expect(sampleNight.sample, isTrue);
      expect(Liturgy.fromMap('x', const {'sample': true}).sample, isTrue);
    });
  });

  group('6. fetch_synaxarium.js Coptic date fallback', () {
    test('matches CopticDate.fromGregorian for two years of days (incl. 8 Nov 2026 and Nasie)', () {
      final from = DateTime.utc(2026, 1, 1);
      final days = [for (var i = 0; i < 731; i++) from.add(Duration(days: i))];
      final iso = days.map((d) => d.toIso8601String().substring(0, 10)).toList();
      final out = _node([
        '-e',
        "const f=require('./tool/fetch_synaxarium.js');"
            "console.log(JSON.stringify(${jsonEncode(iso)}.map(s=>f.copticDateOf(new Date(s+'T00:00:00Z')))))",
      ]);
      if (out == null) return markTestSkipped('node not on PATH');
      final js = (jsonDecode(out) as List).cast<String>();
      for (var i = 0; i < days.length; i++) {
        final c = CopticDate.fromGregorian(days[i]);
        expect(js[i], '${c.day}/${c.month}/${c.year}', reason: iso[i]);
      }
      expect(js[iso.indexOf('2026-11-08')], '29/2/1743');
    });

    test('a null copticDate falls back to the local computation', () {
      final s = File('tool/fetch_synaxarium.js').readAsStringSync();
      expect(s, contains('clean(d.copticDate) || copticDateOf(date)'));
    });
  });

  group('7. pope-visit images are Hosting assets', () {
    test('four optimized WebP files under web/media/milestones (no Storage)', () {
      for (final n in ['9712', '9703', '9744', '9780']) {
        final f = File('web/media/milestones/pope-visit-$n.webp');
        expect(f.existsSync(), isTrue, reason: f.path);
        final b = f.readAsBytesSync();
        expect(String.fromCharCodes(b.sublist(8, 12)), 'WEBP', reason: f.path);
        expect(b.length, lessThan(300 * 1024), reason: f.path);
      }
    });
  });
}
