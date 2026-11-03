# Design direction — "Golden hour" (Coptic identity for the Church Portal)

Branch: `design/coptic-identity` · Draft PR #15 · Updated: 3 Nov 2026 · Status: preview only (not for merge)
Decisions: ADR-022 (identity, revised) and ADR-023 (image display styles) in `docs/memory-bank/10-decisions-and-history.md`.

> Supersedes the first draft "Iconostasis" (flat plaster wall, Naskh/Marcellus, 4 px radii, oxblood `#7B2216`). The
> team preferred the parish's own posters, so the identity now follows them.

## 1. The idea in one line
The site looks like the parish's own **posters**: a church floating in **golden-hour clouds**, a heavy **maroon**
display title with a small **calligraphic accent word** above it, the subtitle on a **ribbon**, warm translucent
panels over the painting, and the patron saints standing in **gold halos** over the Nile at sunset.

## 2. Sources
- Parish posters (WhatsApp, Nov 2026): `work/design/poster_refs/` — maroon tabs and titles, Ruqaa accent words,
  gold halos, sepia story boxes.
- Painted art (Gemini drop, `work/design/gemini/`): hero church in clouds (16:9 and 9:16), Nile at sunset, gold-cloud
  texture, St Moses the Black and Sts Maximus & Domadius (4:5), a 6-second clouds loop. Built into
  `assets/art/*.webp` and `assets/video/hero_clouds.mp4` by `work/design/poster/make_assets.py`. The art is
  **decorative** (`ExcludeSemantics`) and never stands in for real church photos (golden rule #1).

## 3. Palette (`lib/core/theme.dart`, WCAG checked in `test/golden_hour_test.dart`)

| Token | Hex | Use |
|---|---|---|
| `burgundy` (primary preset) | `#6E1C1C` | poster maroon: titles, tabs, buttons |
| `script` | `#9A2A1E` | calligraphic accent word (7.0:1 on cream) |
| `gold` | `#C9963F` | halo rings, rules, glows — **never text** |
| `goldText` | `#7A5410` | gold text/icons on light (6.1:1 on cream) |
| `goldLight` | `#E7C27A` | gold text on maroon/dark |
| `amber` | `#E8B65C` | sun disc, light rays (decorative) |
| `cream` / `parchment` / `vellum` | `#FBF3E4` / `#F4E6CC` / `#FFF9EE` | page wash / sand chips / opaque panels |
| `panel` | `#FBF3E4` @ 88 % | translucent panels over the art (text checked against `panelOverDark`) |
| `ink` / `muted` | `#3A2416` / `#6A4A2E` | body / secondary text |

## 4. Type (bundled, SIL OFL, no runtime fetch)
- **Lalezar** (`AppFonts.display`) — heavy rounded poster titles, Arabic + Latin.
- **Aref Ruqaa** (`AppFonts.accent`) — the small accent word above titles («تعرّف على», «أهلاً بكم في») and verses.
- **IBM Plex Sans Arabic** (`AppFonts.body`) — body and UI.

## 5. Components
- **Hero:** the church in clouds (wide/tall art by aspect), slow drift + light rays, muted video loop (seconds 3–10 of the
  Gemini clip, crossfaded loop; portrait crop on phones; native `<video>` on web, `video_player` on Android/iOS). Admin switch `settings/features.heroMotion` (default on); visitors'
  reduced-motion and save-data always win.
- **Inner page header:** same painting with a cream scrim, accent word, maroon title, subtitle ribbon. Saint pages:
  the saint in a gold halo over the Nile.
- **Panels:** soft 20 px radius, warm shadow, hairline gold border; maroon title band on the next-liturgy card.
- **Patrons band:** both patron saints in halos with two lines of their life and a link.
- **Footer:** warm panels over the cloud art (not the dark night footer of the first draft).

## 6. Layout system (redesign pass 2, 3 Nov 2026)
- **Grid:** `ResponsiveGrid` — 1 column on phones (< 560 px of grid width), 2 on tablets (< 900), 3 on desktop;
  `maxColumns` caps it (saints 2). Content max width **1200 px** (`kMaxContentWidth`), centred.
- **Cards size to their content.** No `Expanded`/fixed heights reserving vertical space; rows in the grid keep each
  card's own height and start at the reading edge (right in Arabic).
- **Optional fields collapse with their gaps:** description/bio, feast pills, time (`TimeRangeText` renders nothing
  without a start), weekday, degree, contact buttons, image.
- **Spacing tokens:** `Space.xs 4 · s 8 · m 12 · l 16 · xl 24 · xxl 32`, `Space.grid 16`, `Space.card 16`.
- **Must hold at 320 px and at 200 % text** (`test/image_style_layout_test.dart`, `test/accessibility_test.dart`).

## 7. Image display styles (ADR-023)
Every optional item image is shown in one of three styles, chosen per section by the admin and overridable per item:

| Style | Look | Default for |
|---|---|---|
| `avatar` | round photo in a gold halo ring, leading the title row | priests & departed fathers, clinics (doctor) |
| `card` | large cover on top of the card, rounded 14 px, **whole picture visible** (contain over a blurred sepia copy) — portrait 4:5 for saints, 4:3 otherwise | saints, activities, milestones, meetings, notices, seasons, public services |
| `banner` | full card width, edge to edge, 16:7 | — (admin choice) |

No image (or images switched off) → the card is exactly as before (golden rule #9).

## 8. Board and screenshots
- Board: `work/design/poster/board/` (`gen.py` → HTML, `render.py` → `../png/*.png`, `overview.py` → `overview.png`).
- Card comparisons: `work/design/poster/png/cards/compare_*.png`.
- Deployed preview overview: `work/design/poster/png/preview_overview.png`.
