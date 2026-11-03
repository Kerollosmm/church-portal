# Design direction — "Iconostasis" (Coptic identity for the Church Portal)

Branch: `design/coptic-identity` · Date: 3 Nov 2026 · Status: preview only (not for merge)

## 1. The idea in one line
The site is built the way an Coptic **iconostasis** (حامل الأيقونات) is built: a calm plaster/parchment wall, **gold-leaf
arches** that hold the holy images, **horizontal tiers** (registers) that order everything, and a thin **interlace
border** that binds the parts. Colour comes from the pigments of *our* icons — Sts Maximus & Domadius and St Moses the
Black — not from a UI kit.

## 2. Source: what the actual icons are made of
Sampled (median-cut, 8 colours) from `work/real-data/photos/saints/*.jpg`:

| Icon | Dominant pigments |
|---|---|
| Maximus & Domadius (Mina Anton) | ochre gold `#A77333`, halo gold `#DBBE5E`, umber `#483226`, monastic black `#1A1310`, raw sienna `#8E5A32` |
| Macarius with Maximus & Domadius (Gerges Samir) | lime-white `#F2F3CB`, oxblood `#7C2B1B`, sienna `#AC6943`, warm grey `#C3B8A9` |
| Moses the Black (01) | cinnabar `#C2593E`, vermilion `#AD3934`, bone `#C9B59F`, charcoal `#343333` |
| Moses & Isidore | wall-plaster ochres `#C4A97C`, `#D3BB8C`, olive umber `#5F5C4B` |

These are **earth pigments on gold**: no purple, no teal, no saturated blue. Lapis is kept as a *rare* second accent
(the traditional colour of the Theotokos/Pantocrator mantle), never as a gradient.

## 3. Palette (tokens, WCAG checked)

| Token | Hex | Use | Contrast |
|---|---|---|---|
| `ink` (umber black) | `#1F1611` | body text | 15.4:1 on parchment, 17.4:1 on vellum |
| `umber` | `#5E4A3A` | secondary text, meta | 7.2:1 parchment · 8.1:1 vellum · 6.5:1 plaster |
| `parchment` | `#F5EEDF` | page ground | — |
| `vellum` | `#FFFCF5` | cards, header bar | — |
| `plaster` | `#ECE2CC` | bands, register strips | — |
| `hairline` | `#D9C8A4` | borders (decorative, 1.6:1 — never meaning-bearing alone) | — |
| `goldLeaf` | `#B8862B` | ornaments, rules, arch frames (decorative only on light) | 2.8:1 parchment ✗text · 5.6:1 on night ✓ |
| `goldInk` | `#7A5400` | gold *text/icons* on light | 5.9:1 parchment · 6.6:1 vellum |
| `halo` | `#E3C578` | gold text on dark grounds | 10.8:1 on night · 8.4:1 on oxblood-deep |
| `oxblood` (default primary) | `#7B2216` | primary buttons, titles, active nav | 8.7:1 parchment · white on it 10.1:1 |
| `oxbloodDeep` | `#561409` | pressed, dark bands | — |
| `cinnabar` | `#B0402A` | "today / now" accent, small badges | 5.0:1 parchment · 5.7:1 vellum |
| `lapis` | `#1F3B6E` | rare 2nd accent (links in long text, info) | 9.5:1 parchment · white on it 11.0:1 |
| `night` | `#1C140E` | hero + footer ground (candle-lit nave) | parchment on it 15.7:1 |

Admin theme presets keep working: `primary` is still the admin preset. The `burgundy` preset value moves from the
wine-red `#6B1426` to the icon oxblood `#7B2216` (same key, same label). Every other preset only swaps `primary`;
parchment, gold, ink and night stay.

## 4. Typography (all OFL 1.1, bundled locally, subset)

| Role | Arabic | English | Why |
|---|---|---|---|
| Display / headings | **Noto Naskh Arabic** Bold (static instance) | **Marcellus** (inscriptional Roman, Trajan-like) | Naskh is the hand of liturgical books (الخولاجي، الأجبية); Marcellus echoes Greek/Coptic uncial inscriptions on icons. |
| Verse / quotes | Noto Naskh Arabic Regular | Noto Naskh (Latin) Regular | Book-like. |
| Body / UI | **IBM Plex Sans Arabic** Regular + Bold | (same family's Latin) | Sober, tabular-friendly, very readable at 14–16 px; less "landing-page" than Cairo/Tajawal. |

Subset to Basic Latin + Latin-1 + Arabic (+ Supplement) + punctuation, hinting dropped: 5 files, **453 KB total**
(replacing the runtime Google Fonts fetch of Cairo, which also blocked first paint).
Licences: `work/design/fonts/*-OFL.txt` (copied into `assets/fonts/` in the app).

Scale (phone → desktop): Display 30→44 / H1 26→34 / H2 21→26 / H3 17→19 / Body 15→16 (line-height 1.7 Arabic) /
Small 13 / Kicker 12 tracking +0.5 (gold-ink). Headings never centred by default: Arabic reads from the start edge.

## 5. Shapes & ornaments (drawn, never emoji)
- **Arch frame** (`ArchFrame`): round-topped (semicircle) frame with a 2 px gold-leaf line + inner hairline, used for
  saint icons, priest photos and the hero image. The arch is the single signature shape.
- **Coptic cross** (existing `CopticCross` painter, refined: trefoil ends, hollow centre) as bullets for section
  titles, list markers, and the empty-image fallback.
- **Interlace band** (`InterlaceBand` painter): a running two-strand guilloche in gold-leaf, 10–14 px high, on the
  header's lower edge and the footer's top edge. Static (no animation).
- **Register rule**: section titles sit on a tier line — kicker + title, then a thin gold rule with a small cross
  medallion at the start.
- Cards: vellum, **4 px radius**, 1 px hairline, **no drop shadows**; listing cards carry a 3 px start-edge in
  primary (the IA standard's "accent edge"), hover = border to gold-leaf.
- Buttons: 4 px radius (stone-cut, not pill), 48 px min height. Primary = oxblood fill; secondary = umber outline;
  on dark grounds = gold-leaf fill with night text.
- Chips: 4 px radius, plaster fill; selected = oxblood with white text.

## 6. Motion
Only: 150 ms colour/border transitions on hover/focus, the existing skeleton pulse (static under reduced motion).
No parallax, no scroll-reveal, no animated gradients.

## 7. Layout & IA (taken from the team's UX standard, visual language our own)
- **Header**: vellum bar, seal + church short name in Naskh, grouped nav: الرئيسية · عن الكنيسة · خدمات الكنيسة ▾
  (القداسات، التربية الكنسية، الأنشطة، الخدمات العامة، العيادات) · اسأل الكنيسة · تواصل معنا, and one primary CTA
  «مواعيد القداسات». Interlace band under it.
- **Phone drawer**: seal + name header with ✕, two labelled groups (الكنيسة / خدمات الكنيسة) with an icon per row,
  48 dp rows, language toggle at the bottom.
- **Home order**: hero (name, locality, verse, CTAs «تعرّف على الكنيسة» + «مواعيد القداسات», patron icon in an arch) →
  admin blocks (next liturgy + phones first, i.e. the business tasks) → about/patrons teaser → story → services
  directory → map → footer.
- **Page header** (every inner page): plaster band, kicker = church short name, Naskh title, subtitle, arch outline
  watermark at the end edge, interlace band at the bottom. Admin title/subtitle overrides kept.
- **Footer**: night ground, interlace top, 3 columns ≥ 900 px (identity · contact · quick links), stacked on phone.

## 8. What we deliberately avoid (the "AI slop" list)
Purple/teal gradients · glassmorphism/blur · emoji as icons · rounded-xl white cards with soft shadows in uniform
grids · blob/mesh hero backgrounds · everything centred · gradient text · pill buttons everywhere · generic stock
church photos. Gradients in the old hero/page header are removed: flat pigment grounds only.

## 9. Business-readiness checklist
Next liturgy + phone numbers are on the first phone screen after the hero; "call" is one tap; times show Arabic and
Latin digits; every page has the same header anatomy; contrast ≥ 4.5:1 for all text tokens; 48 dp targets; works at
320 px and 200 % text.
