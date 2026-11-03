// Sentry error tracking (ADR-034): off without a DSN, privacy scrubbing,
// the admin switch, and the assistant / content capture hooks.
import 'dart:async';
import 'dart:convert';

import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/error_reporting.dart';
import 'package:church_portal/domain/assistant_conversation.dart';
import 'package:church_portal/domain/assistant_settings.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/error_privacy.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/ui/admin/features_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

const _question = 'My name is Mina, call me on 01234567890 about my daughter Marina';
const _contactText = 'Please pray for my sick father, write to mina.private@example.com';

class _RecordingTransport implements Transport {
  final sent = <String>[];
  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    for (final item in envelope.items) {
      sent.add(utf8.decode(await item.dataFactory()));
    }
    return SentryId.newId();
  }
}

class _Model implements AssistantModel {
  _Model(this.error);
  final Object? error;
  int calls = 0;
  @override
  Future<void> warmUp() async {}
  @override
  Future<String?> generate({
    required String model,
    required String instruction,
    required List<AssistantTurn> history,
    required String prompt,
  }) async {
    calls++;
    if (error != null) throw error!;
    return 'ok';
  }
}

SentryEvent _piiEvent() => SentryEvent(
      user: SentryUser(id: 'uid-1', email: 'visitor@example.com', ipAddress: '41.33.1.2'),
      serverName: 'host',
      request: SentryRequest(
        url: 'https://maximos-domadios-church.web.app/contact?lang=en&q=$_contactText',
        method: 'GET',
        cookies: 'session=abc',
        headers: {'User-Agent': 'Mozilla/5.0', 'Cookie': 'session=abc', 'X-Forwarded-For': '41.33.1.2'},
        data: {'message': _contactText},
      ),
      // ignore: deprecated_member_use
      extra: {'question': _question},
      tags: {'route': '/ask?q=hello', 'section': 'assistant', 'email': 'visitor@example.com'},
      message: SentryMessage('failed for visitor@example.com, phone +20 123 456 7890'),
      exceptions: [SentryException(type: 'StateError', value: 'bad state for 01234567890 / a@b.co')],
      breadcrumbs: [
        Breadcrumb(category: 'ui.click', message: 'tap on send', data: {'label': _question}),
        Breadcrumb.http(url: Uri.parse('https://firestore.googleapis.com/v1/x?key=SECRET&q=1'), method: 'GET'),
        Breadcrumb(category: 'navigation', data: {'from': '/', 'to': '/ask?q=prayer', 'text': _question}),
        Breadcrumb(message: 'Assistant error: user mina@example.com 01011122233', category: 'console'),
      ],
      contexts: Contexts(device: SentryDevice(name: 'phone'))..['form'] = {'message': _contactText},
    );

void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('DSN / environment / release resolution', () {
    test('no DSN in debug builds and tests without the define: reporting off', () {
      expect(resolveSentryDsn(hasDefine: false, define: '', release: false, fallback: 'https://k@o1.ingest.de.sentry.io/1'),
          isNull);
    });

    test('an empty SENTRY_DSN define switches reporting off, even in release builds', () {
      expect(resolveSentryDsn(hasDefine: true, define: ' ', release: true, fallback: 'https://k@o1.ingest.de.sentry.io/1'),
          isNull);
    });

    test('release builds fall back to the public project DSN; a define wins', () {
      expect(resolveSentryDsn(hasDefine: false, define: '', release: true, fallback: 'https://k@o1.ingest.de.sentry.io/1'),
          'https://k@o1.ingest.de.sentry.io/1');
      expect(resolveSentryDsn(hasDefine: true, define: 'https://x@o2.ingest.de.sentry.io/2', release: true, fallback: 'f'),
          'https://x@o2.ingest.de.sentry.io/2');
      expect(resolveSentryDsn(hasDefine: false, define: '', release: true, fallback: ''), isNull);
    });

    test('environment: define, else production (release) / debug', () {
      expect(resolveSentryEnvironment(define: 'preview', release: true), 'preview');
      expect(resolveSentryEnvironment(define: '', release: true), 'production');
      expect(resolveSentryEnvironment(define: '', release: false), 'debug');
    });

    test('release: version + short git SHA', () {
      expect(buildSentryRelease('1.0.0+1', '93db6c7aa1b2c3'), 'church-portal@1.0.0+1+93db6c7');
      expect(buildSentryRelease('', 'abc'), 'church-portal@0.0.0+abc');
      expect(buildSentryRelease('1.0.0+1', ''), isNull);
    });
  });

  group('without a DSN', () {
    tearDown(() => ErrorReporting.debugSink = null);

    test('the app still runs, Sentry stays off and captures are dropped', () async {
      var ran = false;
      await ErrorReporting.run(() => ran = true, dsn: '');
      expect(ran, isTrue);
      expect(ErrorReporting.active, isFalse);
      expect(Sentry.isEnabled, isFalse);
      // Never throws and never reaches Sentry.
      ErrorReporting.capture(StateError('x'), StackTrace.current, section: 'content:alerts');
      expect(await ErrorReporting.sendTestEvent(), isFalse);
    });
  });

  group('privacy scrubbing (beforeSend)', () {
    test('no user, IP, cookies, request body, extra, query strings or contact / question text', () {
      final e = scrubEvent(_piiEvent());
      expect(e.user, isNull);
      expect(e.serverName, isNull);
      expect(e.request!.url, 'https://maximos-domadios-church.web.app/contact');
      expect(e.request!.cookies, isNull);
      expect(e.request!.data, isNull);
      expect(e.request!.queryString, isNull);
      expect(e.request!.headers, {'User-Agent': 'Mozilla/5.0'});
      // ignore: deprecated_member_use
      expect(e.extra, isNull);
      expect(e.tags, {'route': '/ask', 'section': 'assistant'});
      expect(e.message!.formatted, isNot(contains('visitor@example.com')));
      expect(e.message!.formatted, isNot(contains('456 7890')));
      expect(e.exceptions!.single.value, 'bad state for [number] / [email]');
      expect(e.contexts.containsKey('form'), isFalse);
      expect(e.contexts.device, isNotNull);

      final crumbs = e.breadcrumbs!;
      expect(crumbs.any((b) => b.category == 'ui.click'), isFalse, reason: 'taps can carry labels / text');
      final http = crumbs.firstWhere((b) => b.category == 'http');
      expect(http.data!['url'], 'https://firestore.googleapis.com/v1/x');
      final nav = crumbs.firstWhere((b) => b.category == 'navigation');
      expect(nav.data, {'from': '/', 'to': '/ask'});
      final log = crumbs.firstWhere((b) => b.category == 'console');
      expect(log.message, 'Assistant error: user [email] [number]');

      final json = jsonEncode(e.toJson());
      for (final secret in ['Mina', 'mina.private', 'visitor@example.com', '41.33.1.2', '01234567890', 'SECRET', 'pray']) {
        expect(json, isNot(contains(secret)), reason: secret);
      }
    });

    test('scrubText keeps times / codes but removes e-mails, phones (incl. Arabic digits) and URL queries', () {
      expect(scrubText('Liturgy at 07:00, HTTP 404, 3 retries'), 'Liturgy at 07:00, HTTP 404, 3 retries');
      expect(scrubText('call ٠١٢٣٤٥٦٧٨٩٠ or 012-345-6789'), 'call [number] or [number]');
      expect(scrubText('see https://x.web.app/ask?q=secret#frag now'), 'see https://x.web.app/ask now');
      expect(stripQuery('/section/youth?lang=en#top'), '/section/youth');
    });

    test('redact removes the visitor question from an error message', () {
      final f = AssistantFailure.from(Exception('Bad request for prompt "$_question"'), [_question]);
      expect(f.toString(), isNot(contains('Marina')));
      expect(f.toString(), contains('[redacted]'));
      expect(f.type, '_Exception');
    });
  });

  group('admin switch (settings/features.errorReporting)', () {
    late ErrorReportingGate gate;
    setUp(() {
      gate = ErrorReporting.gate..reset();
    });
    tearDown(() => ErrorReporting.gate.reset());

    test('defaults on; FeatureSettings parses, writes and copies it', () {
      expect(FeatureSettings.defaults.errorReporting, isTrue);
      expect(FeatureSettings.fromMap({'theme': 'navy'}).errorReporting, isTrue);
      expect(FeatureSettings.fromMap({'errorReporting': false}).errorReporting, isFalse);
      expect(FeatureSettings.fromMap({'errorReporting': 'no'}).errorReporting, isTrue, reason: 'tolerant fromMap');
      expect(FeatureSettings.defaults.copyWith(errorReporting: false).toMap()['errorReporting'], isFalse);
    });

    test('save writes: omitted while default and unstored, written once off or stored', () {
      final on = FeatureSettings.defaults;
      expect(featuresSaveWrites(on, null).first.containsKey('errorReporting'), isFalse);
      expect(featuresSaveWrites(on.copyWith(errorReporting: false), null).first['errorReporting'], isFalse);
      expect(featuresSaveWrites(on, {'errorReporting': false}).first['errorReporting'], isTrue);
    });

    test('switch off → beforeSend drops every event', () async {
      gate.update(false);
      expect(await ErrorReporting.beforeSend(_piiEvent(), Hint()), isNull);
      gate.update(true);
      expect(await ErrorReporting.beforeSend(_piiEvent(), Hint()), isNotNull);
    });

    test('events raised before the switch is known wait for it', () async {
      final pending = ErrorReporting.beforeSend(_piiEvent(), Hint());
      var done = false;
      unawaited(pending.then((_) => done = true));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(done, isFalse);
      gate.update(false);
      expect(await pending, isNull);
    });

    test('unknown for too long (offline) → the default (on) applies', () async {
      final g = ErrorReportingGate(patience: const Duration(milliseconds: 10));
      expect(await g.allowed(), isTrue);
    });

    test('with Sentry running: switch off → nothing reaches the transport; on → only scrubbed data', () async {
      final transport = _RecordingTransport();
      await Sentry.init((o) {
        o.dsn = 'https://public@o1.ingest.de.sentry.io/1';
        o.transport = transport;
        o.sendDefaultPii = false;
        o.sendClientReports = false;
        o.beforeSend = ErrorReporting.beforeSend;
        o.beforeBreadcrumb = (b, _) => scrubBreadcrumb(b);
      });
      addTearDown(Sentry.close);

      gate.update(false);
      await Sentry.captureException(StateError('while off'));
      expect(transport.sent, isEmpty);

      gate.update(true);
      Sentry.addBreadcrumb(Breadcrumb(category: 'ui.click', data: {'label': _question}));
      await Sentry.captureException(StateError('failed for mina@example.com'), withScope: (s) {
        s.setUser(SentryUser(id: 'u1', email: 'mina@example.com'));
        s.setTag('section', 'contact');
        s.setTag('email', 'mina@example.com');
      });
      expect(transport.sent, hasLength(1));
      final body = transport.sent.single;
      expect(body, contains('"section":"contact"'));
      for (final secret in ['mina@example.com', '"u1"', 'Marina', 'ui.click']) {
        expect(body, isNot(contains(secret)), reason: secret);
      }
    });

    testWidgets('the admin switch and the owner-only test button', (tester) async {
      tester.view.physicalSize = const Size(1200, 9000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      FeatureSettings? saved;
      var tested = 0;
      Widget app({Future<bool> Function()? onTest}) => MaterialApp(
            locale: const Locale('en'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(
              body: FeaturesEditor(
                  initial: FeatureSettings.defaults, onSave: (f) async => saved = f, onSendTestError: onTest),
            ),
          );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('features-sendTestError')), findsNothing, reason: 'editors: no test button');
      final sw = find.byKey(const ValueKey('features-errorReporting'));
      await tester.ensureVisible(sw);
      await tester.tap(sw);
      await tester.pump();
      await tester.tap(find.byKey(const Key('features-save')));
      await tester.pumpAndSettle();
      expect(saved!.errorReporting, isFalse);

      await tester.pumpWidget(app(onTest: () async {
        tested++;
        return true;
      }));
      await tester.pumpAndSettle();
      final btn = find.byKey(const ValueKey('features-sendTestError'));
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pumpAndSettle();
      expect(tested, 1);
      expect(find.text('A test error was sent to Sentry.'), findsOneWidget);
    });
  });

  group('capture hooks', () {
    tearDown(() => ErrorReporting.debugSink = null);

    test('assistant: a real failure is reported once, without the question', () async {
      final reported = <AssistantFailure>[];
      final c = AssistantConversation(_Model(Exception('Server error 500 while answering "$_question"')),
          defaultModel: 'd', retryDelay: Duration.zero, onError: (f, _) => reported.add(f));
      final r = await c.ask(_question,
          settings: AssistantSettings.defaults, instruction: 'I', historyKey: 'k', now: DateTime(2026, 11, 3, 12));
      expect(r.outcome, AssistantOutcome.error);
      expect(reported, hasLength(1));
      expect(reported.single.toString(), isNot(contains('Marina')));
      expect(reported.single.toString(), isNot(contains('01234567890')));
      expect(reported.single.toString(), contains('500'));
    });

    test('assistant: quota / rate-limit / safety rejections are not reported', () async {
      for (final e in [
        Exception('429 Too Many Requests: quota exceeded'),
        Exception('RESOURCE_EXHAUSTED'),
        Exception('Response blocked due to SAFETY'),
      ]) {
        final reported = <AssistantFailure>[];
        final c = AssistantConversation(_Model(e),
            defaultModel: 'd', retryDelay: Duration.zero, onError: (f, _) => reported.add(f));
        await c.ask('When is the liturgy?',
            settings: AssistantSettings.defaults, instruction: 'I', historyKey: 'k', now: DateTime(2026, 11, 3, 12));
        expect(reported, isEmpty, reason: '$e');
        expect(isUserFacingAssistantError(e), isTrue);
      }
    });

    test('content: a failing Firestore stream is reported with its section, then serves the seed', () async {
      final seen = <(Object, Map<String, String>)>[];
      ErrorReporting.debugSink = (e, st, tags) => seen.add((e, tags));
      final out = await guardSeeded<List<int>>(
        gate: SeedGate(() async => true),
        live: () => Stream<List<int>>.error(StateError('permission-denied')),
        fallback: const [1],
        onSeed: (_) {},
        label: 'liturgies',
      ).toList();
      expect(out, [
        [1]
      ]);
      expect(seen, hasLength(1));
      expect(seen.single.$2['section'], 'content:liturgies');
    });

    test('capture tags the section and the current route (path only)', () {
      final seen = <Map<String, String>>[];
      ErrorReporting.debugSink = (e, st, tags) => seen.add(tags);
      ErrorReporting.route = '/mass-schedule?lang=en';
      ErrorReporting.capture(StateError('permission'), StackTrace.current, section: 'content:liturgies');
      expect(seen.single, {'section': 'content:liturgies', 'route': '/mass-schedule'});
      ErrorReporting.route = null;
    });
  });
}
