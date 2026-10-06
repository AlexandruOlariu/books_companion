# Design system

Visual language of the POC: warm paper, dark ink, a bookcase for the home screen, and restrained decoration. Code lives in `lib/core/theme/app_theme.dart`, `lib/core/widgets/`, and `lib/features/library/presentation/{shelf,keepsakes}.dart`. Screenshots are in `docs/screenshots/`.

## Colour tokens (`RoomColors`)

| Token | Value | Use |
| --- | --- | --- |
| paper | `#F7F3EB` | page background |
| surface | `#FFFCF6` | cards, inputs, navigation |
| ink | `#242B28` | primary text |
| muted | `#5E655F` | secondary text |
| forest | `#28564B` | primary accent, buttons, calendar activity |
| terra | `#B66750` | decorative accent, pin edge, finish ring (sparingly) |
| line | `#DDD9CF` | hairlines |
| shelfBack / shelfBackDeep | `#EADFCB` / `#D9CBB1` | bookcase back panel |
| woodLight / wood / woodDark | `#CDA97C` / `#B08659` / `#86623F` | planks and frame |

Cover colours never change navigation or control colours. One light theme only; a dark theme would need separately validated colours.

## Typography

Literata (serif) for editorial headings and book titles; DM Sans for body and controls. Body text is 16 logical px and honours the system text scale. Headings: headline large 34, medium 28, title large 22, all in Literata with slight negative tracking. Section labels use an uppercase "eyebrow" (11 px, letter-spaced).

## Spacing, shape, targets

Base scale 4, 8, 12, 16, 24, 32. Page gutters 24 (shelf 16). Moderate radii (12 for inputs and buttons, 16 for cards). Minimum tap target 48 x 48 with no overlapping hit areas; filled buttons are 52 high. Shadows are soft and local to books and floating surfaces.

## Components (`lib/core/widgets`)

- **`BookCover`**: draws a cover or a spine of a given size.
  - Cover: a real image with aspect-preserving fit (never cropped), a spine-edge gradient on the left, a narrow page block on the right, a contact shadow; a gold bookmark ribbon when the book is being read.
  - Generated cover (no artwork): palette colour, a small rule, the title in Literata, the author in small caps.
  - Spine: a horizontal gradient for roundness, gilt bands near head and tail, the title rotated, never an untappable sliver.
  - Cover images are decoded at display size.
- **Palette and hash:** `bookPalette` has 14 muted colours. `bookSeed(title)` is an FNV-1a hash so neighbouring titles differ; use different bit slices for different decisions (colour uses the whole value modulo 14, heights use shifted bits) because correlated moduli make colours cluster. A simple character sum was replaced because it made every spine purple, green, or brown.
- **`EmptyRoom`**, **`Eyebrow`**, **`FormSheet`** (modal sheet that keeps Save above the keyboard), **`notifyUser`** (snackbar), **`confirmDiscard`**, **`readableError`**.

## The bookshelf

The signature element of the Library tab. Inspired by a physical bookcase rather than a grid of cards.

- **Structure:** each shelf row is a compartment: a back panel in `shelfBack` shaded darker at the top, wooden side frames, and a wooden plank with a light top edge. The first row has a top beam. Rows touch so they read as one bookcase.
- **Books:** packed left to right by real width. A book is a spine 48 to 68 wide (grows with page count) and 138 to 177 tall, or face-out (96 wide, 144 to 157 tall) when it is being read (bookmark ribbon) or, for roughly one in seven others, by hash. Face-out books show the real cover.
- **Selection:** tapping lifts the book 10 px (about 200 ms, instant under reduced motion) and shows it in the panel above; positions do not shuffle.
- **Rows are lazy** (a sliver list) so 500 books stay cheap. Row packing is O(n) per layout.
- **Width:** the usable width is the screen width minus gutters and frame; the packing is recomputed for the layout width.

## Keepsakes

Painted with `CustomPainter`, no assets. Names, thresholds, and sizes:

| Keepsake | Finished books | Size |
| --- | --- | --- |
| Brass bookend | 1 | 30 x 76 |
| Potted plant | 3 | 64 x 96 |
| Tea mug | 5 | 54 x 48 |
| Candle | 8 | 40 x 70 |
| Globe | 12 | 72 x 100 |
| Hourglass | 18 | 44 x 76 |
| Reading cat | 25 | 66 x 74 |

They stand on the plank among the books, evenly spread and never adjacent. Every keepsake is a tappable target with a semantic label. Colours stay in the app palette; the mug is teal with a cream band so it does not vanish against the cream panel.

## Journal visuals

- **Month tiles:** a three-column grid of rounded tiles (surface fill, hairline border). The month is an uppercase eyebrow; the count sits at the right in Literata; below, a fan of up to three overlapping covers. Empty months are transparent with a faint border and a faded label, so the year reads as twelve slots with a few filled.
- **Year rows:** a card with the year in Literata, the book count, and a fan of up to five covers.
- **Cover fans** adapt to the space they get and show "+N" for the rest; a fixed fan overflowed narrow tiles at 360 px.
- **The "Sometime in <year>" tile** is wide and grows with its text so large type is not clipped.
- **Days calendar:** a filled forest cell means a logged session; a small terracotta dot means a finish. Colour and dot are never mixed up, because only sessions are activity.

## Motion and feedback

Short, purposeful: a 200 ms lift on selection. Saving is never blocked by animation. Reduced motion removes the lift. No looping animation. Confirmations are snackbars; page updates offer Undo; a snackbar is dismissed before the next sheet opens so it never covers Save.

## Accessibility rules the design depends on

- Visible text labels on all core actions; no feature needs a gesture.
- Large text: the list view is used automatically and content reflows; layouts are tested at 360 px wide with 200% text.
- Screen readers get title, author, status and actions for books; decorative edges and shadows are excluded; keepsakes announce how they were earned.
- Dirty-form dismissal asks first; typed input survives validation errors.

## Layout lessons learned (worth keeping if the app is rebuilt)

- Test at phone size (360 x 800 logical), not the default 800 x 600 test surface. Several problems only appeared there: a status chip pushed off-screen by a horizontal scroll (now wrapping chips), a fixed 136 px selection panel overflowing by 6 px, and empty-state buttons hidden behind the floating button.
- The shelf starts below the header, so on a short phone the first row is partly below the fold; tests must scroll like a reader does.
- Do not use `Eyebrow` text in tests literally: it uppercases its text.
