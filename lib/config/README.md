# Config Component Package

## Overview
The `lib/config` package centralizes build-time configurations, environment definitions (`--dart-define`), and operational constants across web and native targets. It provides immutable, compile-time defaults for telemetry (Sentry), App Check security (reCAPTCHA Enterprise), origin resolution, backend media selection, and Firebase AI Logic models without mutating runtime state.

## Interface
- [`AppConfig`](file:///c:/Users/Kerollos/church-portal/lib/config/app_config.dart#L10-L84): Static utility class hosting build-environment bindings.
  - [`AppConfig.geminiModel`](file:///c:/Users/Kerollos/church-portal/lib/config/app_config.dart#L20): Default Gemini model fallback (`GEMINI_MODEL`, defaults to `'gemini-3.1-flash-lite'`).
  - [`AppConfig.recaptchaSiteKey`](file:///c:/Users/Kerollos/church-portal/lib/config/app_config.dart#L28-L29): Web reCAPTCHA Enterprise site key (`RECAPTCHA_SITE_KEY`).
  - [`AppConfig.appCheckDebugToken`](file:///c:/Users/Kerollos/church-portal/lib/config/app_config.dart#L35): Optional App Check debug token (`APPCHECK_DEBUG_TOKEN`).
  - [`AppConfig.forceAppCheckDebug`](file:///c:/Users/Kerollos/church-portal/lib/config/app_config.dart#L36): Debug provider override flag (`APPCHECK_DEBUG`).
  - [`AppConfig.hasRecaptchaKey`](file:///c:/Users/Kerollos/church-portal/lib/config/app_config.dart#L38): Boolean property verifying presence of a configured reCAPTCHA key.
  - [`AppConfig.isUsableSiteKey`](file:///c:/Users/Kerollos/church-portal/lib/config/app_config.dart#L41-L44): Helper verifying that a site key is non-empty and does not contain `'PLACEHOLDER'`.
  - [`AppConfig.siteOriginDefine`](file:///c:/Users/Kerollos/church-portal/lib/config/app_config.dart#L49-L50): Build-time origin URL (`SITE_ORIGIN`, defaults to `'https://maximos-domadios-church.web.app'`).
  - [`AppConfig.dataOrigin`](file:///c:/Users/Kerollos/church-portal/lib/config/app_config.dart#L54): Dynamic origin for static asset fetches (`Uri.base.origin` on web, `siteOriginDefine` on Android).
  - [`AppConfig.mediaBackend`](file:///c:/Users/Kerollos/church-portal/lib/config/app_config.dart#L59): Media repository target storage engine (`'firestore'` or `'storage'`).
  - [`AppConfig.sentryDefaultDsn`](file:///c:/Users/Kerollos/church-portal/lib/config/app_config.dart#L65-L66): Hardcoded fallback Sentry ingest DSN.
  - [`AppConfig.sentryDsn`](file:///c:/Users/Kerollos/church-portal/lib/config/app_config.dart#L69-L71): Resolved Sentry DSN (honors `SENTRY_DSN` define; defaults to `sentryDefaultDsn` in release mode, null in debug/profile).
  - [`AppConfig.sentryEnvironment`](file:///c:/Users/Kerollos/church-portal/lib/config/app_config.dart#L74): Sentry runtime environment name (`'production'`, `'preview'`, or `'debug'`).
  - [`AppConfig.sentryRelease`](file:///c:/Users/Kerollos/church-portal/lib/config/app_config.dart#L80): Sentry release identifier constructed from `APP_VERSION` and `GIT_SHA`.
  - [`AppConfig.adminPath`](file:///c:/Users/Kerollos/church-portal/lib/config/app_config.dart#L83): Hidden administrative route URL path (`'/admin'`).

## Invariants
- [`app_config.dart:AppConfig._`](file:///c:/Users/Kerollos/church-portal/lib/config/app_config.dart#L11): Instantiation is disabled via private constructor; all state and accessors must remain static.
- [`app_config.dart:AppConfig.sentryDsn`](file:///c:/Users/Kerollos/church-portal/lib/config/app_config.dart#L69-L71): In the absence of an explicit `SENTRY_DSN` define, telemetry is disabled (`null`) in debug and profile modes to prevent pollution of production metrics.
- [`app_config.dart:AppConfig.dataOrigin`](file:///c:/Users/Kerollos/church-portal/lib/config/app_config.dart#L54): On web platforms (`kIsWeb`), `dataOrigin` must always mirror `Uri.base.origin` so preview channels, staging instances, and local dev servers load assets from their own host.
- [`app_config.dart:AppConfig.isUsableSiteKey`](file:///c:/Users/Kerollos/church-portal/lib/config/app_config.dart#L41-L44): Any key string matching empty or starting with `'PLACEHOLDER'` is rejected as unusable.

## Side Effects
- Zero side effects. All symbols evaluate pure constants or static environment getters.

## Verification
- Run: `flutter test`
