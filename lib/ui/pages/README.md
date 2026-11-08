# pages

## Overview
The `pages` package implements all user-facing destination screens in the Church Portal. It delivers public pages for the church homepage, daily liturgical schedules, mass bookings, community activities, Christian education (Sunday school), medical clinics, community services, Katameros daily scripture readings, custom content pages, item details, contact forms, push notification settings, and the conversational Gemini AI assistant. Every page follows the church portal's Arabic-first RTL design, adheres to strict feature toggling (Golden Rule 6), respects sample data indicators (Golden Rule 1), and anchors temporal scheduling to Cairo wall-clock time (`CairoTime`).

## Interface
- `about_page.dart`:
  - `AboutPage`: Screen presenting the church history, church founders, ordination milestones, and parish leadership.
  - `PriestCard`: Card displaying priest profile, ordination anniversary, and contact details.
  - `SaintCard`: Card presenting church patron saints (Maximus, Domadius, Anba Moussa the Black).
- `activities_page.dart`:
  - `ActivitiesPage`: Directory screen listing spiritual activities, scouts, choral groups, and fellowship meetings.
- `assistant_page.dart`:
  - `assistantModelProvider`: Riverpod provider supplying the conversational AI backend (`FirebaseAssistantModel`).
  - `assistantUsageStoreProvider`: Riverpod FutureProvider managing local client request usage quotas and rate limits (`PrefsUsageStore`).
  - `AssistantPage`: Conversational AI assistant interface for asking natural-language questions about church services, doctrine, and schedules.
- `category_page.dart`:
  - `categoryIcon(String key)`: Returns the appropriate Material icon for an admin-configured category icon identifier.
  - `openLink(BuildContext context, String link)`: Dispatches internal application routes via GoRouter or opens external links in the system browser.
  - `CategoryPage`: Dynamic collection browser rendering items under an admin-defined category slug (`/section/<slug>`).
  - `ContentUnavailable`: Empty-state widget presented when a requested category or item is unpublished or disabled.
  - `EntryCard`: Standardized card rendering a collection item with image, schedule, and metadata.
- `clinics_page.dart`:
  - `ClinicsPage`: Specialized directory screen listing church medical clinics, physician specialties, and consultation schedules.
  - `ClinicCard`: Card widget detailing clinic opening hours, doctor names, and booking phone numbers.
- `contact_page.dart`:
  - `ContactPage`: Parish contact directory with physical address, Google Maps embed, phone directory, and public feedback form.
  - `ContactForm`: Interactive form enabling visitors to send inquiries or prayer requests to church administrators.
- `custom_page.dart`:
  - `CustomPageView`: Dynamic page renderer for arbitrary admin-authored pages (`/page/<slug>`).
  - `PageBlockView`: Modular block renderer for paragraphs, images, cards, and interactive call-to-actions.
  - `DonationInfoCard`: Specialized informational card providing church donation guidelines and bank transfer numbers.
- `education_page.dart`:
  - `stageOrder`: Ordered list of Sunday School educational stages.
  - `stageLabels`: Localized labels for education stages.
  - `EducationPage`: Sunday School and servant preparation directory structured by age groups and academic stages.
- `home_page.dart`:
  - `HomePage`: Central landing page featuring ambient hero visual stage, today's schedule strip, patron saint teasers, and quick service cards.
  - `PhoneRow`: Quick contact bar for urgent parish inquiries and office lines.
  - `HaloText`: Stylized typography widget with subtle golden ambient glow.
  - `HeroVerse`: Dynamic liturgical scripture banner displaying the daily or seasonal verse.
- `item_detail_page.dart`:
  - `ItemDetailPage`: Generalized detail viewer displaying full descriptions, image galleries, and contact buttons for any collection item (`/item/<id>`).
- `mass_schedule_page.dart`:
  - `MassSchedulePage`: Liturgical calendar screen showing daily and weekly Eucharistic liturgies, midnight praises, and altar designations.
- `notifications_page.dart`:
  - `notificationsPageStrings`: Localized string registry for notification preference UI strings.
  - `NotificationsPage`: User settings screen for toggling local mass alerts and push notifications.
- `notification_health_page.dart`:
  - `NotificationHealthPage`: Self-diagnostic utility inspecting device alarm permissions, battery optimization settings, and notification channels.
- `public_services_page.dart`:
  - `PublicServicesPage`: Directory screen listing community facilities including daycare, libraries, halls, and senior care.
- `readings_page.dart`:
  - `ReadingsPage`: Daily Katameros lectionary scripture readings screen computed for the current liturgical date.
- Subdirectories: None

## Invariants
- `[category_page.dart:CategoryPage]`: Disabled, deleted, or unverified category slugs must mark document route metadata with `indexable: false` and render `ContentUnavailable`.
- `[assistant_page.dart:AssistantPage]`: AI prompts must be checked against rate limit quotas in `assistantUsageStoreProvider` before dispatch to Firebase Gemini.
- `[contact_page.dart:ContactForm]`: Inbound contact messages must be throttled by client-side anti-spam cooldown (`ContactRateLimiter`).
- `[home_page.dart:HomePage]`: Every public section must be wrapped in feature checks observing `sectionsProvider`; disabled sections must not render or navigate (Golden Rule 6).
- `[mass_schedule_page.dart:MassSchedulePage]`, `[readings_page.dart:ReadingsPage]`: All dates, times, and day-of-week selections must route through `CairoTime` (Africa/Cairo timezone, ISO weekdays 1–7).
- `[about_page.dart:AboutPage]`, `[clinics_page.dart:ClinicsPage]`: Records marked `sample: true` must visually indicate unconfirmed status and must not invent facts (Golden Rule 1).

## Side Effects
- `[contact_page.dart:ContactForm]`: Writes submitted user messages into Cloud Firestore `messages` collection.
- `[assistant_page.dart:AssistantPage]`: Invokes external Firebase AI / Gemini API endpoints and persists prompt count into local storage (`PrefsUsageStore`).
- `[category_page.dart:openLink]`: Triggers browser URL launches (`url_launcher`), native dialer intents (`tel:`), or GoRouter navigation.
- `[notifications_page.dart:NotificationsPage]`: Mutates local notification subscription preferences in `SharedPreferences`.
- `[notification_health_page.dart:NotificationHealthPage]`: Queries device hardware/OS permissions and opens native application settings.

## Verification
- Run: `flutter test`
