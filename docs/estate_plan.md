# Estate Plan

Working reference for the building/room layout. Not a finished design doc —
updated as we build. Ground truth for level design lives here; puzzle/
mechanic detail per room comes later, once the whole shell is blocked out
(see "Build order" below).

## Core mechanic (context for room design later)

Player carries a light that switches between Real (orange) and Otherside
(green) — same house, different layout/doors/items per world. Puzzles are
routes that use both worlds in sequence. Each room should teach one new
combination of already-known rules, not a one-off gimmick. Horror is
atmosphere/uncertainty-driven, no jump scares. See project memory
`crosslight-game-concept` for the full brief.

## Overall shape

Building is a **quadrangle** — front block (hall) + two side wings +
a rear block, enclosing a closed inner courtyard. Roughly square/
rectangular footprint. Diagram: https://claude.ai/code/artifact/b3f6d97b-e426-45fe-b606-568c18141b3a
(ground floor only; update this link if the artifact gets republished
under a new one instead of edited in place).

## Layout decision: hall doors

Grand hall has twin staircases (left/right) framing a central statue.
Doors off the hall go on the **sides**, flanking the staircases, leading
to the main day rooms — matches real manor layouts (public rooms open
directly off the entrance hall) and avoids competing with the statue
sightline.

The wall directly behind the statue (opposite the entrance) is **not** a
dead end — it's a door into the inner courtyard (see below). Revises the
earlier assumption that the space behind the statue was just a backdrop.

## Massing (height)

Whole building is **two storeys**, except the Hall, which is
**double-height** (no floor slab splitting it) — its "second floor" is
the gallery/balcony landing ringing the atrium, reached by the twin
staircases, which is already built. Every other room, including the
wings (Music room, Kitchen) and the rear block, is normal single-storey-
height with an actual second floor sitting on top of it — no other room
gets a glass roof or open-to-sky ceiling. Only the courtyard has no
floor above it, for the obvious reason (it's exterior, open to sky by
design).

## Inner courtyard

Enclosed courtyard at the center of the quadrangle, open to the sky.
Reached only through the door behind the hall's statue. Side wings
(drawing room/orangery on one side, dining room/kitchen on the other)
form its left/right walls; a rear block (not yet designed) closes it on
the far side. Deliberately the one space in the house with no roof —
should be a strong beat for world-switching (moon, weather, greenery all
visibly different between Real and Otherside).

## Ground floor

Doubles as the estate's grand/parade level — see "Parade level" decision
below. Quadrangle: hall (front) + two side wings + rear block, enclosing
the inner courtyard.

- Grand Hall — **built** (twin staircases, statue centerpiece, dome +
  chandelier overhead). Also serves as the "great hall" — no separate
  ballroom is planned (see Status log 2026-08-18).
- Left wing:
  - Drawing room / parlor (off hall, left) — **built** (base blockout +
    decor: sofa, rug, curtains, fireplace, wall shader). Also serves as
    the reception salon — no separate upstairs salon planned.
  - Music room (beyond drawing room, forms courtyard's left wall) — not
    started. Roll/clavichord, sheet music — a self-playing instrument on
    the Otherside is the intended beat; sheet music as a lore/puzzle
    prop. Replaces the earlier Orangery idea for this slot (see Second
    floor: the conservatory idea moved there instead, as a courtyard-
    facing planted balcony rather than a standalone room).
- Right wing:
  - Dining room (off hall, right) — **built** (base blockout, no decor
    yet). This is the everyday/family dining room (родинна їдальня, see
    [docs/design/story_and_level.md](design/story_and_level.md)) — the
    formal one is upstairs, see Second floor.
  - Kitchen + pantry/comora (beyond dining room, forms courtyard's right
    wall) — not started. Service space.
- Rear block (closes the quadrangle, opposite the hall, across the
  courtyard) — not started. Two clusters:
  - Near the kitchen side: steward's office (кабінет управителя, lore/
    notes source), servants' hall (людська), storage (комора/кладові —
    dark/tight, candidate for a feel-your-way puzzle beat). Servants'
    back stairs here, connecting to the 2nd floor service side,
    separate from the grand staircase.
  - Near the orangery side: Library, Study — quiet cluster, courtyard-
    facing windows.
  - Consider a second courtyard door here (in addition to the one
    behind the hall statue) for backtracking/shortcut routing.

## Second floor

Private/family level. No separate great hall or salon here — the ground-
floor Hall and Drawing room already cover that role (see Status log
2026-08-18).

- Gallery / balcony landing — **built** (top of grand staircase). Doubles
  as the portrait gallery (портретна галерея) — ancestral portraits along
  the balcony overlooking the hall. Priority spot for early Otherside
  hints about death/family.
- Courtyard-side planted balcony — replaces the earlier standalone
  Orangery idea. A narrow walkway runs the second floor's courtyard-
  facing perimeter, dressed with potted greenery, open to the sky over
  the courtyard below — gets the "glass conservatory" mood without a
  dedicated room. Extends the mini-balcony already built off the second
  floor (the one with the Otherside ghost-passable window) all the way
  around the courtyard side.
- Formal dining room (парадна їдальня) — ceremonial counterpart to the
  ground-floor everyday dining room, near the gallery.
- Master's study (кабінет господаря)
- Master bedroom + будуар
- 2–3 guest bedrooms
- Nursery (дитяча) — high atmosphere value, classic horror beat
- Bathroom

## Later-game escalation areas (build last)

- Basement/cellar — descent = stronger Otherside presence
- Mausoleum/crypt (exterior, rear grounds) — likely late-game or ending
  area

## Exterior

- Front gates → courtyard (gazon/gazon2, fountain out front) → entrance —
  **built**
- Rear garden / mausoleum — not started
- From [docs/design/story_and_level.md](design/story_and_level.md)'s
  outbuildings list, not yet placed: carriage house (каретний сарай),
  stable (стайня), pond (ставок), greenhouse (теплиця, now a fully
  separate freestanding garden structure — the interior Orangery idea
  was cut, see Second floor).

## Build order

1. Finish remaining ground-floor rooms (closest to existing hall, lowest
   rework risk)
2. Second floor rooms
3. Basement + exterior escalation areas last

Blockout pass only for all of the above — minimal geometry, no decor/
interior dressing — before going back for a detail pass across everything
at once. Rationale: pacing across the whole estate can't be judged from
2 finished rooms, and decorating early risks redoing work if a room needs
to move/resize during blockout.

## Status log

- 2026-08-06: doc created. Hall + front courtyard built. Deciding
  next-room order (side doors off hall, not center).
- 2026-08-06: settled on quadrangle shape — inner courtyard behind the
  hall statue, reached through a door directly opposite the entrance.
  Published a floor-plan diagram (ground floor) to visualize it.
- 2026-08-18: Drawing room and Dining room both built (Drawing room has
  decor, Dining room is base-only so far); neither has a door leading
  further into its wing yet. Reconciled this doc against
  [docs/design/story_and_level.md](design/story_and_level.md), whose
  ground-floor/second-floor split would have put the great hall and
  salon upstairs, separate from what's already built downstairs —
  decided **not** to duplicate them: the built Hall + Drawing room
  already are the parade level, second floor stays private/family-only.
  Assigned the lore doc's remaining ground-floor rooms (steward's
  office, servants' hall, storage, library, study) to the rear block
  that closes the quadrangle, and its remaining second-floor rooms
  (portrait gallery, formal dining, master's study) onto the already-
  built gallery/balcony landing and its neighbors. Next build step:
  door from Drawing room → next room and from Dining room → Kitchen, so
  both wings stop dead-ending.
- 2026-08-18 (later same day): settled the building's massing — whole
  estate is two storeys, except the Hall, which is double-height (its
  built gallery/balcony landing is the "second floor" there, no slab
  splits it). Every other room, wings included, is normal single-
  storey-height with a real second floor on top; only the courtyard has
  no floor above it. This killed the original Orangery-behind-the-
  drawing-room idea (a glass roof doesn't fit under a second floor).
  Replaced it two ways: the first-floor slot behind the Drawing room is
  now a **Music room** instead; the "glass conservatory" mood moved to
  the **second floor** as a planted balcony running the courtyard-
  facing perimeter (extending the mini-balcony + Otherside ghost-
  passable window already built there), rather than a dedicated room.
