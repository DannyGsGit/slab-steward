# SLAB Steward

An OSM metadata editor for laypeople — find a trail you know, set its difficulty
and surface, submit under your own OpenStreetMap account.

Full scope in [docs/product/SLAB_Steward_Product_Description_v1.md](docs/product/SLAB_Steward_Product_Description_v1.md).

## Status

Flutter app, **web only** for now — mobile is deliberately deferred, so
`flutter create` was run with `--platforms=web` and the other platform folders
don't exist yet. Adding them later is `flutter create --platforms=ios,android .`;
nothing in `lib/` is web-specific.

What works today:

- Map of OSM trails, styled to OpenTrailMap's conventions (see below)
- Travel-mode filter (all / mountain biking / hiking) and completeness lenses
- Click a trail to select it — geometry and authoritative tags are read live
  from the OSM API, and the panel shows difficulty and surface through SLAB's
  guided vocabulary rather than raw tag keys
- Multi-select: ctrl-click (Windows/Linux) or cmd-click (macOS) builds a working
  set of trails, and the panel becomes a bulk editor that applies one rating
  across all of them
- A trail list for the current viewport, filtered by the same completeness
  questions the lenses ask. Rows can be edited in place one at a time, or ticked
  — including "select all" over a filter — to feed the same bulk editor
- Guided difficulty editing: a pencil on the difficulty row opens a picker,
  a check stages the change and an X discards it. Staged edits accumulate
  across trails behind a counted badge on the map, and the review sheet shows
  them grouped by trail — plain-language before/after plus the actual tag diff
  — with a mandatory changeset comment before submit

Editing is gated on authoritative tags: the pencil stays disabled until the OSM
API has answered, because a changeset composed against tile data is built on a
version that may already be stale. That gate holds in bulk too — a batch resolves
every trail in the working set against the OSM API before it stages anything, a
few reads at a time, and reports what it skipped.

**Where a batch does and doesn't read OSM.** Picking trails one at a time — a
click, a modified click, a single checkbox — reads that trail immediately, so
the panel has something to show and the map has geometry to highlight. "Select
all" deliberately reads nothing: it's one click that can name a hundred trails,
and a hundred OSM API calls is not a reasonable answer to it. Those reads happen
at the point there's actually an edit to compose.

A batch produces **one staged edit per trail**, never one opaque batch entry —
the review sheet lists, explains and prunes each one on its own.

Not built yet: OSM OAuth sign-in, so **submit is a no-op** — it clears the
staged list and says plainly that nothing reached OpenStreetMap. Also pending:
surface and sanction editing, Commons, the keyring. Lasso selection is
deliberately deferred (product description §4).

One thing worth checking in a real browser rather than in `flutter test`: the
additive modifier is read from `HardwareKeyboard` at pointer-down time, and the
map is an `HtmlElementView`. Flutter's engine listens for keys at the window, so
keys pressed over the map canvas do reach it — but that's the one part of this
feature a widget test can't exercise.

## Running it

```sh
flutter run -d chrome
```

`web/index.html` loads MapLibre GL JS from unpkg — the Flutter plugin's web
implementation binds to that global rather than bundling its own copy.

**Web quirk worth knowing about:** the map is an `HtmlElementView`, and MapLibre
GL JS listens for clicks on that DOM element itself. The browser delivers those
clicks even when a Flutter panel, dropdown or dialog is painted on top, so
without a guard every tap on the trail panel *also* reads as a tap on empty map
and clears the selection out from under the editor.
[steward_map_view.dart](lib/src/map/steward_map_view.dart) therefore only honours
a map click whose press Flutter routed to the map itself — and reads the
multi-select modifier off that same press, because MapLibre reports the click
afterwards, by which point the key may already be up.

**Why cmd and not ctrl on macOS:** ctrl-click *is* a right-click there. It
arrives as `contextmenu`, never as a click, so the additive modifier has to be
cmd. [fields.dart](lib/src/ui/fields.dart) picks the label off the platform for
the same reason.

```sh
flutter test
flutter analyze
```

## Deploying

Hosted on Firebase Hosting, project `gen-lang-client-0486805387` (display name
`slab-steward`), under the site `slab-steward` — [firebase.json](firebase.json)
targets it by the `slab-steward` hosting target set in `.firebaserc`.

```sh
flutter build web
firebase deploy --only hosting
```

Live at **https://slab-steward.web.app**.

`.firebaserc` isn't gitignored, so a fresh checkout has the project/target
wiring already; it only needs `firebase login` and, if `firebase target:list`
comes up empty, the same `firebase target:apply` in "Friendlier URL" below.

## Friendlier URL

The project's underlying ID (`gen-lang-client-0486805387`) is what Firebase's
*default* hosting site is named after, which is why a naive `firebase deploy`
lands on `https://gen-lang-client-0486805387.web.app`. `slab-steward.web.app`
is a second Hosting site added under the same project:

```sh
firebase hosting:sites:create slab-steward
firebase target:apply hosting slab-steward slab-steward
```

`firebase.json`'s `hosting.target` then routes deploys to it instead of the
default site. A custom domain (e.g. `slabsteward.org`) can be layered on top
later via Hosting → Add custom domain in the Firebase console — no change to
this wiring needed.

## Data sources

Everything is fetched directly from the browser; there is no backend yet.

| What | Where | Notes |
|---|---|---|
| Basemap style | `opentrailmap.us/style.json` | OpenTrailMap's published MapLibre stylesheet |
| Trail geometry & tags | `tiles.openstreetmap.us/vector/trails.json` | OSM US's trails tileset. Carries `mtb:scale:imba`, `surface`, `informal`, `OSM_ID`, `OSM_VERSION` — the whole discovery surface, no Overpass needed |
| Authoritative tags & geometry | `api.openstreetmap.org/api/0.6/way/{id}/full.json` | Fetched on selection. Tiles can lag OSM by hours, and a changeset built on a stale version clobbers someone else's edit |

**Worth resolving before this is public:** Steward hotlinks OSM US's tile
infrastructure. That's fine for development, and the endpoints are openly
reachable, but shipping a product on someone else's tile server without asking
is not. Either confirm acceptable use with OSM US or stand up the PMTiles-on-R2
pipeline the product description already plans (§7).

## Trail rendering conventions

Ported from [osmus/OpenTrailMap](https://github.com/osmus/OpenTrailMap) rather
than invented, so a rider who knows that map reads this one the same way. The
port lives in [lib/src/map/otm_conventions.dart](lib/src/map/otm_conventions.dart)
(palette and access expressions, from `style/constants.js` and
`js/accessExpressions.js`) and
[lib/src/map/steward_style.dart](lib/src/map/steward_style.dart) (layer set and
filter composition, from `js/styleGenerator.js`).

| Rendering | Means |
|---|---|
| Solid line | Official trail |
| Dashed line | `informal=yes` |
| Pale tan + no-entry symbols | The selected travel mode isn't allowed here |
| Teal `#007f79` | The lens' attribute is present |
| Purple `#c100cc` | The lens' attribute is missing — what a steward is here to fix |

Three deliberate departures, each commented at its call site:

1. **Disallowed trails stay visible** when a travel mode is picked, rendered
   pale rather than hidden. OpenTrailMap hides them; a steward still has to be
   able to click a trail in order to fix its tags, and a hidden trail can't be
   clicked.
2. **A composite "missing either" lens.** OpenTrailMap's attribute lenses each
   ask about one key and are all any-of. The completeness lens asks for
   difficulty *and* surface together, which is the completeness indicator the
   product description §2 describes.
3. **Selection is drawn from its own GeoJSON source**, not as a feature-state
   highlight. The Flutter MapLibre binding has no `setFeatureState`.

Waterways and oneway arrows are dropped — v1 edits neither.

## Layout

```
lib/
  main.dart
  src/
    map/
      otm_conventions.dart   OpenTrailMap palette + access expressions
      steward_style.dart     style document assembly
      steward_map_view.dart  the map widget; click → selection
    model/
      difficulty.dart        SLAB scale ↔ mtb:scale:imba, and the signage glyphs
      surface.dart           SLAB picker ↔ surface=*
      lens.dart              travel modes and completeness lenses
      trail.dart             a trail, tile-provisional or OSM-authoritative
      staged_edit.dart       one pending attribute change, with its tag diff
    osm/
      osm_api.dart           OSM API v0.6 client (read-only so far)
    state/
      steward_state.dart     ChangeNotifier: mode, lens, the working set,
                             the in-view list, and staging
    ui/
      fields.dart            labelled rows, status badges, difficulty picker
      map_controls.dart      travel mode and lens pickers
      legend.dart            what the colours mean
      trail_panel.dart       one selected trail, and its guided editor
      selection_panel.dart   several selected trails, and the bulk editor
      trail_list_panel.dart  every trail in the viewport, as a working list
      staged_changes.dart    staged-changes badge and review sheet
    steward_app.dart
```

## Next

1. OSM OAuth 2.0 with PKCE, and the token-lifetime question the product
   description §11 flags as unresolved.
2. Wire submit to the API — open / upload / close, `#SLABSteward` hashtag on
   every changeset including single-trail edits, and re-check each staged
   edit's `baseVersion` before writing. The OEG wiki page before bulk edit
   ships.
3. Surface, then sanction status, through the same staging flow — adding one
   is a `TrailAttribute` value, a `StagedEdit` factory that diffs it, a row in
   the panel, and a `StewardState.apply*` batch method for the bulk editor.
