# web

## Overview
The `web` component package provides the web application host shell, Progressive Web App (PWA) manifest and runtime environment, SEO and OpenGraph metadata configurations, first-frame liturgical splash screen lifecycles, and JavaScript platform bridges for the Flutter web deployment. It manages instant language determination before the Flutter framework initializes, keeps App Check reCAPTCHA loading strictly lazy (ADR-037), captures early PWA installation lifecycle prompts, polyfills non-standard line-breaking engines with standard `Intl.Segmenter` shims for Arabic and Latin typography, and provides background web push / service worker scaffolds (`push_client.js`, `firebase-messaging-sw.js`).

## Interface
- **HTML Shell & Bootstrap Scripts:**
  - `[web/index.html:#boot-prefs]`: Inline startup script running synchronously after `<title>`, determining initial language from `?lang=` or `localStorage.church_portal_lang`, clearing cached `FlutterFire-*-recaptcha` tokens to maintain lazy App Check activation (ADR-037), and capturing `beforeinstallprompt` / `appinstalled` events (ADR-057).
  - `[web/index.html:splashDone]`: Lifecycle callback fading out and removing the `#splash` liturgical loading screen when `app-content-ready` triggers or capped at 9 seconds after `flutter-first-frame`.
  - `[web/index.html:splashFailed]`: Failure fallback displaying an Arabic/English error state and reload anchor if the bootstrap script fails to load or Flutter does not render within 30 seconds.
  - `[web/index.html:Intl.v8BreakIterator Shim]`: Custom `Intl.v8BreakIterator` polyfill using `Intl.Segmenter` (grapheme granularity) and Unicode UAX #14 rules for Arabic and Latin text word/line breaking.
  - `[web/index.html:JSON-LD Schema]`: Structured schema.org `Church` metadata specifying verified coordinates, parish contact phone, social channels, and address.
- **Push Notification & Service Worker Bridges:**
  - `[web/push_client.js:window.__churchPortalPush]`: Push notification bridge object exposed on `window`:
    - `[web/push_client.js:isSupported]`: Evaluates browser compatibility (`Notification`, `serviceWorker`, `PushManager`).
    - `[web/push_client.js:permission]`: Reads current browser `Notification.permission` status.
    - `[web/push_client.js:requestPermission]`: Prompts user for browser notification permission via `Notification.requestPermission()`.
  - `[web/firebase-messaging-sw.js]`: Background Firebase Cloud Messaging service worker handling `install` (`skipWaiting`) and `activate` (`clients.claim`).
- **Configuration & Discovery:**
  - `[web/manifest.json]`: Web App Manifest configuring standalone PWA mode, background color (`#FBF3E4`), theme color (`#470812`), icons, and Arabic RTL orientation.
  - `[web/robots.txt]`: Crawler policy directing search indexing and declaring sitemap location.
  - `[web/sitemap.xml]`: Static fallback XML sitemap indexing all canonical parish portal routes.
  - `[web/llms.txt]`: Machine-readable architectural and functional documentation guide for LLM crawlers.
- **Subdirectories & Boundaries:**
  - `./art`: Visual saint iconography and artwork.
  - `./icons`: App icons, favicons, Apple touch icons, and maskable PWA icons.
  - `./install-guide`: [Android Sideload Guide](./install-guide/README.md) - Specifications and assets for sideload APK installation screenshots.
  - `./media`: Milestone historical photo galleries.

## Invariants
- `[web/index.html]`: Never set `dir="rtl"` on `<html>` or `<body>` in `index.html`. Flutter Web handles RTL rendering internally; placing `dir="rtl"` on DOM parents corrupts platform-view iframe coordinate calculations (e.g., Google Maps).
- `[web/index.html:#boot-prefs]`: App Check reCAPTCHA must remain strictly lazy (ADR-037). Persisted reCAPTCHA tokens in `localStorage` and `sessionStorage` are stripped on every boot to prevent eager initialization of the ~700 KiB reCAPTCHA Enterprise bundle on pages other than `/ask`.
- `[web/index.html:splashDone]`: The `#splash` loading element must remain visible over the application canvas until the real home / settings content is painted (`app-content-ready`), or at most 9 seconds after `flutter-first-frame`, preventing unpopulated default state flicker.
- `[web/firebase-messaging-sw.js]`: The service worker must never intercept page navigations or resource fetch events (`fetch` event listener is intentionally omitted).

## Side Effects
- Mutates DOM nodes: toggles visibility/removal of `#splash`, updates `document.title`, and updates `document.documentElement.lang`.
- Accesses web storage: reads and removes keys in `localStorage` and `sessionStorage`.
- Listens to global window events: `app-content-ready`, `flutter-first-frame`, `error`, `beforeinstallprompt`, `appinstalled`.
- Registers service worker and invokes browser `Notification` permissions.

## Verification
- Run: `flutter build web --release`
