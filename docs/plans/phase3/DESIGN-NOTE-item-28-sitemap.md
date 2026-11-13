# مذكرة تصميم — البند 28: خريطة الموقع من غير نشر (Design note — item 28: sitemap without a deploy)

> Written 13 November 2026 for the owner's decision D3 ([README.md](README.md) §١٠): design note first, on the
> existing Cloudflare Worker + Firestore REST API reached from Firebase Hosting; if it is more than a small
> addition, defer and keep the deploy-time sitemap.

## الخلاصة (Outcome)

**Deferred.** The Worker route is more than a small addition, for the two reasons in §٣. The sitemap stays
generated at deploy time, as today. A smaller route that reuses the existing generator is described in §٥ in
case the item is reopened; it is not approved and not scheduled.

## ١. الوضع الحالي (What exists today — checked in the code)

- `.github/workflows/deploy.yml` runs `tool/build_sitemap.sh` on every deploy (ADR-038).
- `tool/export_public_content.js` reads the public collections read-only with the deploy key.
- `tool/gen_sitemap.dart` turns the export into `sitemap.xml` using `lib/domain/sitemap.dart`, so the sitemap lists
  exactly the URLs the app itself treats as indexable: section switches (`FeatureSettings.routeEnabled`), public
  categories and pages (`publicCategories`, `publicPages`), and item detail pages (`detailItemOpens`).
- Any failure keeps the static `web/sitemap.xml`. `web/robots.txt` points to
  `https://maximos-domadios-church.web.app/sitemap.xml`.
- The Cloudflare Worker (`wrangler.toml`, `tool/cf_push_worker.js`, Workers Free) already has a `fetch` handler
  (`POST /assistant`), four cron triggers, a KV namespace (`PUSH_KV`) and a Firestore REST client
  (`tool/firestore_rest.js`, including `listCollection`).
- `tool/publish_hosting_file.js` can replace one file on the live Hosting site without rebuilding the app
  (ADR-040); the Android workflow uses it for the APK files.

So a new page already reaches the sitemap, but only at the next deploy.

## ٢. المسار المطلوب (The requested route)

`GET /sitemap.xml` on the site → Firebase Hosting → the Worker → Firestore REST → XML built on the fly, cached
in KV for about an hour.

## ٣. ليه ده أكبر من إضافة صغيرة (Why it is more than a small addition)

1. **The indexing rules would exist twice.** They are Dart (`lib/domain/sitemap.dart`, plus the `fromMap` models,
   `features.dart`, `custom_content.dart` and `item_detail.dart` it calls). The Worker is JavaScript and cannot
   run them. A Worker sitemap needs a JavaScript copy of those rules, and every later change to visibility
   (a new switch, a new section kind) must then be made in two languages. If the copies drift, the sitemap
   lists hidden pages or misses visible ones — the exact failure ADR-038 was written to prevent. Keeping them
   equal needs a shared fixture test on both sides. This alone is size M–L, not S.
2. **Hosting cannot proxy to the Worker.** Firebase Hosting rewrites serve a static file, a Cloud Function or a
   Cloud Run service; they do not forward to an outside origin, and Functions / Cloud Run are outside the Spark
   decision. What Hosting can do is a **redirect** from `/sitemap.xml` to the Worker's address, or `robots.txt`
   can name the Worker's sitemap directly. Either way the sitemap is then served from another host, which
   changes how search engines are told about it and must be re-checked in Search Console. (This limit is from
   the Firebase Hosting documentation and was not re-tested here; confirm it first if the item is reopened.)

Smaller costs on top: a new public `GET` route on a Worker that today only accepts `POST /assistant`; about ten
Firestore list calls per rebuild (inside Workers Free and Spark limits when cached hourly); and a fallback for
when Firestore is unreachable, which the deploy script has and the Worker would need again.

## ٤. القرار حسب قاعدة المالك (Decision under the owner's rule)

More than a small addition → **defer item 28; keep deploy-time generation.** No code, no change to
`firebase.json`, `robots.txt` or the Worker. Item 28 is marked deferred in [STATUS.md](STATUS.md).

What this means in practice: a page or section added from the panel is public at once and is linked from the
site's own menu; it enters `sitemap.xml` at the next deploy to `main`.

## ٥. لو اتفتح تاني: مسار أصغر (If reopened: a smaller route — not approved)

Keep the one Dart generator and only run it more often:

- a scheduled GitHub Actions job (for example every 6 hours, plus a manual button) that runs
  `tool/build_sitemap.sh` on a copy of the static sitemap and publishes the result to `/sitemap.xml` with
  `tool/publish_hosting_file.js`;
- same rules, same validation, same fallback, same URL, no second copy of the logic, no change for search
  engines; Spark only, no new server.

Limits: the update is within hours, not instant; it needs a Flutter / Dart setup step in the job; each run is a
Hosting release (the release history grows). Estimated size S–M. Acceptance if built: a newly visible page
appears in the live `sitemap.xml` after the next scheduled run without a deploy, and a hidden page does not.
