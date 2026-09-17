# Shelf — Visual Design Tokens

Extracted read-only from the iOS app (`ShelfV2/Shelf/`) on 2026-06-21 to help a web landing page match the app's look. No code was changed. File:line references point at the source of truth.

Colors are defined as **inline hex literals** via two `Color` initializers in [`Views/Shared/ColorHex.swift`](ShelfV2/Shelf/Views/Shared/ColorHex.swift) — `Color(hex: 0xRRGGBB)` and `Color(hexString: "RRGGBB")`. There are **no** `.colorset` assets and **no** central theme/palette file; the values below are the literals actually used across the views.

---

## 1. Color palette

### Theme / neutrals
| Hex | Role | Where |
|---|---|---|
| `#FAF6F0` | **Cream** — app background wash, the signature surface | WelcomeView |
| `#1A1A1A` | **Near-black** — primary button / CTA / "Save" fill | WelcomeView CTA, BookDetailView |
| `#444444` | Dark gray — secondary text & pill labels | BookDetailView, ListDetailView |
| `#DDDDDD` | Hairline gray — 0.5px borders/strokes | BookDetailView, ListDetailView |
| `#FFFFFF` | White — text on dark/gradient surfaces | buttons, list cards |

### Accents (gesture / CTA semantics)
| Hex | Role |
|---|---|
| `#4D3388` | Purple — "✦ Because you loved …" attribution |
| `#D04763` | Pink — "loved it" affirmative CTA |
| `#3B6D11` | Green — "read it" / positive check |
| `#A32D2D` | Red — "pass" / dismiss |

### Award badge
| Hex | Role |
|---|---|
| `#FAEEDA` | Amber-cream badge background |
| `#633806` | Brown badge text |

(from `BookCardView.amberBackground` / `amberText`)

### Toast accents ([`Views/Shared/ToastView.swift`](ShelfV2/Shelf/Views/Shared/ToastView.swift))
| Hex | Name | Trigger |
|---|---|---|
| `#FAC775` | gold | saved to shelf, first generation |
| `#9FE1CB` | mint | marked read, daily refresh |
| `#CECBF6` | lavender | passed |
| `#F4C0D1` | pink | removed from shelf/taste |

### Gradient cards (Discover list cards)
List cards render a 2-stop linear gradient (top-leading → bottom-trailing) from backend-supplied `colorStart`/`colorEnd`. The iOS **default fallback** is `#534AB7 → #7F77DD` ([APIModels.swift:243](ShelfV2/Shelf/Models/APIModels.swift)). The curated gradients (from `backend/data/lists/_index.json`):

| List | Start → End |
|---|---|
| Loved by Readers | `#B23A48 → #E86A6A` (rose) |
| Oprah's Book Club | `#534AB7 → #7F77DD` (purple) |
| Reese's Book Club | `#993C1D → #D85A30` (coral) |
| Obama's Favorites | `#1A4A7A → #2E7BC4` (blue) |
| NYT Notable 2024 | `#1A1A1A → #444444` (charcoal) |
| Booker Winners | `#5C3317 → #A0622A` (brown) |
| Pulitzer Fiction | `#1B4332 → #2D6A4F` (green) |
| Goodreads Choice | `#5C4033 → #F4A261` (tan→amber) |

Also used as For-You shortcut-card gradients: purple `#534AB7→#7F77DD` and coral `#D67C5C→#F2B69A` (EmptyForYouView).

### Paste-ready CSS
```css
:root {
  /* theme / neutrals */
  --cream:        #FAF6F0;  /* page background */
  --ink:          #1A1A1A;  /* primary button / CTA */
  --gray-text:    #444444;
  --hairline:     #DDDDDD;

  /* accents */
  --purple:       #4D3388;
  --pink:         #D04763;
  --green:        #3B6D11;
  --red:          #A32D2D;

  /* award badge */
  --badge-bg:     #FAEEDA;
  --badge-text:   #633806;

  /* toasts */
  --gold:         #FAC775;
  --mint:         #9FE1CB;
  --lavender:     #CECBF6;
  --soft-pink:    #F4C0D1;

  /* signature gradient (community list) */
  --grad-rose:    linear-gradient(135deg, #B23A48, #E86A6A);
  --grad-purple:  linear-gradient(135deg, #534AB7, #7F77DD);
  --grad-coral:   linear-gradient(135deg, #993C1D, #D85A30);
}
```

---

## 2. Typography

**System font only — San Francisco.** No custom fonts, no serif, no rounded design anywhere in the app (verified: zero `.custom(`, `.serif`, or `fontDesign` usages). Apple text styles drive the scale; a few fixed sizes are used for icons and micro-labels.

Text styles in use (by frequency): `subheadline`, `caption`, `headline`, `title3`, `title2`, `body`, `caption2`, `footnote`.
Fixed sizes: `56`, `44`, `32` (large symbols/emoji & big numerals), `14 semibold`, `13 medium`, `12 semibold`, `9 medium` (pill micro-labels).
Weights: regular, medium, semibold, bold.

Note: the current `WelcomeView` has **no text wordmark** — the brand is carried by the cover wall + CTA, not a logotype.

**Web equivalent type scale** (maps SF text styles to px / weight):
```css
:root {
  --font-sans: -apple-system, BlinkMacSystemFont, "SF Pro Text",
               "Inter", system-ui, "Segoe UI", Roboto, sans-serif;
}
/* title2 ≈ 22/700 · title3 ≈ 20/700 · headline ≈ 17/600 ·
   body ≈ 17/400 · subheadline ≈ 15/400 · footnote ≈ 13/400 ·
   caption ≈ 12/400 · caption2 ≈ 11/400 */
```

---

## 3. Splash / welcome screen (the signature look)

[`WelcomeView.swift`](ShelfV2/Shelf/Views/Onboarding/WelcomeView.swift) + [`SplashCoverScrollView.swift`](ShelfV2/Shelf/Views/Splash/SplashCoverScrollView.swift):

- **Background:** solid cream `#FAF6F0`, full-bleed.
- **Drifting cover wall** (ambient): **2 columns** of book covers scrolling **vertically, upward**, infinite loop.
  - cover size **130 × 190** px, **corner radius 6**, gap **12** px between covers
  - speed **8 px/sec** (very slow), linear, seamless wrap (content doubled, modulo loop height)
  - the two columns are offset (odd/even covers split) so rows stagger
  - whole wall held at **opacity 0.55** so it reads as background
  - 20 bundled covers (`Assets.xcassets/SplashCovers/SplashCover00–19`)
- **Bottom fade:** a linear gradient `cream(0) → cream → cream`, **260px tall**, pinned to the bottom, fading the covers into the CTA area.
- **CTA button:** full-width, fill `#1A1A1A`, white text, `headline` weight, corner radius **14**, vertical padding **16**, horizontal inset **24**, bottom inset **48**. No headline copy — just the button.

To reproduce on web: cream page, two CSS columns of book covers with a slow `@keyframes` vertical translate (~8px/s) at 55% opacity, a bottom `linear-gradient` cream fade, and a black pill button.

---

## 4. Book cover component

Canonical cover = [`BookCoverView.swift`](ShelfV2/Shelf/Views/Shared/BookCoverView.swift). Every cover funnels through it.

- **Aspect ratio: 2:3** (height = width × 1.5)
- **Corner radius: 4**
- Two modes: fixed `width × width*1.5`, or flexible `aspectRatio(2/3, .fit)` filling the container
- Placeholder: SF Symbol `book.closed` (tertiary label) on a `secondarySystemFill` rectangle
- Cover-art container fill while loading: `secondarySystemFill`

Common cover widths in use: **36** (search rows), **60** (similar-books seed header), **hero/PDP cover** = `min(screenWidth × 0.45, 180)` — i.e. caps at **180px** wide (270 tall).

Splash covers are larger and slightly less tall than 2:3 (130 × 190 ≈ 1.46) with radius 6.

---

## 5. Shape & spacing tokens

| Token | Value | Use |
|---|---|---|
| radius — cover | `4` | book covers |
| radius — splash cover | `6` | covers in the wall |
| radius — input/small pill | `10` | search box |
| radius — button/card | `14` | CTAs, pills, Discover list cards |
| radius — modal | `22` | centered overlays/sheets |
| border | `0.5px` `#DDDDDD` | hairlines |
| list card | min-height `110`, padding `16`, white text on gradient | Discover cards |
| common spacing | `12 / 16 / 24` | gaps & padding |

---

## Signature look, in one line
Cream (`#FAF6F0`) canvas · slow-drifting 2-up book-cover wall at ~55% opacity fading into a bottom cream gradient · a single near-black (`#1A1A1A`) rounded CTA · system sans typography · 2:3 covers with soft 4–6px corners · gradient list cards. Match those and the web page will read as the same product.
