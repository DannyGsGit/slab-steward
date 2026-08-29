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
- Travel-mode filter (all / mountain biking / hiking), and a multi-select
  highlight menu of stackable completeness lenses
- Click a trail to select it — geometry and authoritative tags are read live
  from the OSM API, and the panel shows difficulty, e-bike access and surface
  through SLAB's guided vocabulary rather than raw tag keys
- Multi-select: ctrl-click (Windows/Linux) or cmd-click (macOS) builds a working
  set of trails, and the panel becomes a bulk editor that applies one rating
  and/or one e-bike permission across all of them
- A trail list for the current viewport, filtered by the same completeness
  questions the lenses ask. Rows can be edited in place one at a time, or ticked
  — including "select all" over a filter — to feed the same bulk editor
- Guided editing of difficulty and e-bike access: every editable field is a
  live picker whose options carry their meaning — e-bike access is allowed or
  not allowed, and each says what it claims, since the key is about e-bikes
  alone. A trail already answering with a value Steward can't offer
  (`designated`, `permissive`) is read-only rather than overwritten, singly and
  in bulk. Choosing a value stages the change — no edit mode to enter
  and no check to press after — and an undo beside the field walks it back.
  Staged edits accumulate across trails behind a counted badge on the map, and
  the review sheet shows them grouped by trail — plain-language before/after
  plus the actual tag diff — with a mandatory changeset comment before submit

Editing is gated on authoritative tags: the picker stays disabled until the OSM
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

- OSM sign-in via OAuth 2.0 + PKCE, and a real submit: the review sheet opens
  a changeset under the rider's own account, uploads the tag diff atomically,
  closes it, and links the result. **This build is a dry run — it does
  everything but send the changeset** — see "OSM API environment" below before
  changing that

Not built yet: surface and sanction editing, Commons, the keyring. Lasso
selection is deliberately deferred (product description §4).

One thing worth checking in a real browser rather than in `flutter test`: the
additive modifier is read from `HardwareKeyboard` at pointer-down time, and the
map is an `HtmlElementView`. Flutter's engine listens for keys at the window, so
keys pressed over the map canvas do reach it — but that's the one part of this
feature a widget test can't exercise.

## Running and deploying

Three scenarios. All build through [tool/run.sh](tool/run.sh), which supplies
the OSM client id from `secrets/vault.env` — a bare `flutter` command compiles
in no id, and sign-in fails with "No OSM client id".

| | Serves at | `osmEnvironment` | Writes reach |
|---|---|---|---|
| **1** Local | `127.0.0.1:5000` | `dryRun` | nothing — the changeset isn't sent |
| **2** Firebase, dry run | `slab-steward.web.app` | `dryRun` | nothing — the changeset isn't sent |
| **3** Firebase, live | `slab-steward.web.app` | `live` | **the real map, immediately** |

`osmEnvironment` is a one-line constant in
[lib/src/osm/osm_environment.dart](lib/src/osm/osm_environment.dart); edit it,
then build. All three use the same hosts, the same OAuth app and the same real
trail data — the only difference is whether the last three API calls happen.

### Prerequisite: one OAuth app, both origins

Sign-in now goes to `www.openstreetmap.org` in **every** configuration,
including local. So the production OAuth app has to list both origins:

```
https://slab-steward.web.app/
http://127.0.0.1:5000/
```

Add them at
<https://www.openstreetmap.org/oauth2/applications> before the first run — a
missing redirect URI fails at the OSM authorize screen, not in Steward, so the
error arrives as OSM's own "The requested redirect uri is malformed or doesn't
match" rather than anything this app can explain. Registration details are
under "Registering the OAuth app" below.

`secrets/vault.env` already has the `OSM_OAUTH_CLIENT_ID` this needs. Its
`OSM_OAUTH_DEV_*` and `OSM_DEV_ACCESS_TOKEN` entries are now dead — nothing
reads them, and the sandbox app they belong to can be deleted.

### 1. Local, dry run

```sh
tool/run.sh
```

Pins `127.0.0.1:5000` because OSM rejects `localhost` outright and Flutter
otherwise picks a random port — neither matches a registered redirect URI.

Every trail the map draws is clickable and editable, because reads go to the
same OSM the tiles were cut from. Take an edit all the way through the review
sheet: the gate re-reads each way, checks for conflicts, builds the upload,
and stops one call short of sending it. The last checklist row says so, and no
changeset link appears — that's the whole difference.

Worth confirming while you're there, since these are what the dry run is
actually able to prove: a trail you click resolves its authoritative tags, a
staged edit survives to the review sheet, a bad comment is rejected by the
gate, and submitting empties staging and leaves the trail drawn in its edited
colour rather than snapping back.

### 2. Firebase, dry run

```sh
tool/run.sh build web
firebase deploy --only hosting
```

Live at <https://slab-steward.web.app>. Same build as 1, so if sign-in worked
locally the only thing that can newly fail here is the `web.app` redirect URI.

### 3. Firebase, live

Same two commands as 2, but **every edit is live and permanent the moment it
uploads**. Before the first one:

- [ ] `osmEnvironment` flipped to `OsmEnvironment.live`
- [ ] The dry run exercised end to end at `slab-steward.web.app`, since that
      leaves only the upload itself untested
- [ ] `Organised Editing/Activities/SLAB Steward` wiki page live
- [ ] Two-week community notice posted — forum, OSM US Slack `#trails`,
      regional channel

The last two are obligations, not suggestions:
[docs/slab-steward-osm-changeset-spec.md](docs/slab-steward-osm-changeset-spec.md)
§9-10.

### Other commands

```sh
flutter test
flutter analyze
flutter run -d chrome    # fine for map/editor work; sign-in won't work
```

---

## OSM API environment

**There is one OpenStreetMap.** Both configurations talk to the production
hosts, under the production OAuth app, against the same real trails. What the
constant decides is whether a submission commits:

```dart
const osmEnvironment = OsmEnvironment.dryRun;  // ← the switch
```

| | `dryRun` (current) | `live` |
|---|---|---|
| API | `api.openstreetmap.org` | `api.openstreetmap.org` |
| Website (OAuth, permalinks) | `www.openstreetmap.org` | `www.openstreetmap.org` |
| Sign-in, reads, the pre-submit gate | real | real |
| Changeset create / upload / close | **skipped** | sent — **live and permanent** |

`dryRun` runs the whole flow and stops at the point of no return. The gate
re-reads every staged way from live OSM, checks it for conflicting edits, and
builds the `osmChange` document; then the three write calls simply aren't
made. The submit checklist says so, no changeset permalink is offered, and
everything downstream — staging clearing, the map recolouring — behaves as it
would after a real submission, because those are the parts worth exercising.

**Why not a sandbox.** Steward used to point a whole configuration at
`master.apis.dev.openstreetmap.org`. That is a *separate database*, not a
mirror: it holds none of the trails the tileset draws, so every click 404'd
until a seeder had copied a park into it, and even then only the seeded ones
worked. What you were testing was never the thing that would ship. Reading
production and writing the sandbox isn't a middle ground either — the write
references way ids the sandbox has never heard of. Doing the real reads and
declining the write is a far closer rehearsal, and the only thing it can't
exercise is the API's response to an upload.

Two things about the hosts that are easy to get wrong:

**The API host and the website host are different.** OAuth's
`/oauth2/authorize` and `/oauth2/token`, and the human-facing `/way/{id}` and
`/changeset/{id}` permalinks, are all served by the *website*, not by
`api.openstreetmap.org`. Hence `osmApiHost` and `osmWebHost` rather than one
base URL.

**A dry run still needs sign-in, and a real token.** It reads
`/api/0.6/user/details` and every staged way under the rider's own OAuth
token, exactly as a live build does. It just never spends that token on a
write.

### Registering the OAuth app

Steward is a **public** client — a browser app with nowhere to keep a secret —
so it uses Authorization Code with PKCE. Register at
`https://www.openstreetmap.org/oauth2/applications/new`:

- **Redirect URIs** — one per line. OSM requires `https://`, with
  `http://127.0.0.1` as the sole exception (**not** `localhost`):
  ```
  https://slab-steward.web.app/
  http://127.0.0.1:5000/
  ```
- **Confidential application? — leave UNCHECKED.** Checking it makes OSM
  expect a client secret in the token exchange, which a single-page app can't
  supply and this flow never sends.
- **Permissions** — exactly three:

  | Checkbox | Scope | Why |
  |---|---|---|
  | Read user preferences | `read_prefs` | resolve the rider's display name |
  | Modify the map | `write_api` | create and upload changesets (includes changeset comments) |
  | Modify notes | `write_notes` | requested now so the planned note-leaving feature won't need a second consent screen |

  "Sign in using OpenStreetMap" (`openid`) is not needed — identity comes from
  `/api/0.6/user/details`.

### The client id, and why there is no client secret

One id, for one app, in the gitignored `secrets/vault.env`:

```
OSM_OAUTH_CLIENT_ID: <the app's client id>
```

[tool/run.sh](tool/run.sh) reads it and passes it as
`--dart-define=OSM_CLIENT_ID=…`. Both configurations use it; a dry run signs
in for real.

**A client id is not a secret.** In Authorization Code + PKCE it travels in the
authorize URL in plain sight; it identifies the app, it doesn't authenticate
it. It's kept out of source only so the repo doesn't name a specific
registration.

**A client secret can't be used here at all, and none is passed.** Steward is a
*public* client — a browser app with nowhere to keep one. Anything handed to
the web build is readable in devtools, so a "stored" secret would be a
published one; no credential store changes that, because the browser still has
to fetch it to use it. Remote Config is client-readable by design, Firestore
needs Firebase auth that is itself minted from OSM sign-in, and Secret Manager
is server-only. PKCE's `code_verifier` is what replaces the secret: generated
fresh per sign-in, never transmitted until the token exchange, useless to
anyone who intercepts the redirect.

If `secrets/vault.env` holds `*_CLIENT_SECRET` entries, they're vestigial —
nothing reads them, and their presence means the OSM app may have been
registered as *confidential*, which is the wrong type here (see the
"Confidential application?" note above). Re-register as public and revoke them,
or accept that sign-in will fail against a confidential registration. Making
them usable would mean routing the token exchange through a Cloud Function so
the secret stays server-side — real added infrastructure, and against the
product description's "no client secret required" (§7, §9).

Sign-in runs in a popup. The popup lands back on Steward's own origin with
`?code=...`, and [lib/main.dart](lib/main.dart) short-circuits that page load —
`tryHandleOAuthCallback()` posts the code to the opener and closes the popup
instead of booting the whole app inside it. There's no separate callback page
because [firebase.json](firebase.json) rewrites every path to `index.html`
anyway, so a standalone one would never be served. The access token is kept in
`localStorage`, so a reload doesn't force a re-login.

## Web quirks worth knowing about

`web/index.html` loads MapLibre GL JS from unpkg — the Flutter plugin's web
implementation binds to that global rather than bundling its own copy.

**Clicks reach the map even through panels on top of it.** The map is an
`HtmlElementView`, and MapLibre
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

## Firebase Hosting wiring

Project `gen-lang-client-0486805387` (display name `slab-steward`), serving the
site `slab-steward` — [firebase.json](firebase.json) targets it by the
`slab-steward` hosting target set in `.firebaserc`. Deploy commands are under
"Running and deploying" above.

`.firebaserc` isn't gitignored, so a fresh checkout has the project/target
wiring already; it only needs `firebase login` and, if `firebase target:list`
comes up empty, the `firebase target:apply` below.

**Why a second site.** The project's underlying id is what Firebase's *default*
hosting site is named after, so a naive `firebase deploy` lands on
`https://gen-lang-client-0486805387.web.app`. `slab-steward.web.app` is a
second site under the same project:

```sh
firebase hosting:sites:create slab-steward
firebase target:apply hosting slab-steward slab-steward
```

A custom domain (e.g. `slabsteward.org`) can be layered on later via Hosting →
Add custom domain — no change to this wiring needed, though it would need
adding to the OAuth apps' redirect URIs.

## Data sources

Everything is fetched directly from the browser; there is no backend yet.

| What | Where | Notes |
|---|---|---|
| Basemap style | `opentrailmap.us/style.json` | OpenTrailMap's published MapLibre stylesheet |
| Trail geometry & tags | `tiles.openstreetmap.us/vector/trails.json` | OSM US's trails tileset. Carries `mtb:scale:imba`, `surface`, `informal`, `OSM_ID`, `OSM_VERSION` — the whole discovery surface, no Overpass needed |
| Authoritative tags & geometry | `api.openstreetmap.org/api/0.6/way/{id}/full.json` | Fetched on selection. Tiles lag OSM by days, and a changeset built on a stale version clobbers someone else's edit. What comes back also feeds [TrailOverrides](lib/src/model/trail_overrides.dart) — see "Trails the tiles are wrong about" |
| Sign-in, changeset writes | `www.openstreetmap.org/oauth2/*`, `api.openstreetmap.org/api/0.6/changeset/*` | Under the rider's own OAuth token. The changeset calls are the one thing `osmEnvironment = dryRun` skips — see "OSM API environment" |

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
| Teal `#007f79` | Every selected lens' attribute is present |
| Purple `#c100cc` | One of them is missing — what a steward is here to fix |

Three deliberate departures, each commented at its call site:

1. **Disallowed trails stay visible** when a travel mode is picked, rendered
   pale rather than hidden. OpenTrailMap hides them; a steward still has to be
   able to click a trail in order to fix its tags, and a hidden trail can't be
   clicked.
2. **Lenses stack, all-of.** OpenTrailMap's attribute lenses each ask about
   one key, one at a time. Steward's highlight picker is a multi-select: a
   trail is teal only when it answers *every* ticked lens, so ticking
   difficulty, surface and e-bike access together is the completeness
   indicator the product description §2 describes.
3. **Selection is drawn from its own GeoJSON source**, not as a feature-state
   highlight. The Flutter MapLibre binding has no `setFeatureState`.
4. **The filters can read from somewhere other than the tile** — see below.

Waterways and oneway arrows are dropped — v1 edits neither.

### Trails the tiles are wrong about

The lens colours are decided by MapLibre expressions over vector tile
properties, and that tileset is a periodic planet build — its TileJSON
routinely reports a timestamp several days old. Left alone, this means a trail
you just rated keeps drawing as unrated, and the moment the changeset closes it
also loses its blue staged glow: the work looks undone exactly when it lands.
Trails somebody *else* has already fixed keep being advertised as work, too.

[TrailOverrides](lib/src/model/trail_overrides.dart) is the reconciliation. It
holds tags Steward knows to be newer than the tiles, from two sources:

1. **What we submitted** — folded in by `StewardState.applySubmitted` as the
   staging area empties.
2. **What we read** — every authoritative read on click, which carries whatever
   anyone else has changed since the tiles were cut. Only cached when it
   actually contradicts the tile on a rendered key, or every first click would
   restyle the map for nothing.

The map applies it by *substituting tags*, not verdicts:
`TagSource.overriding` rewrites the `['get', k]` / `['has', k]` primitives the
conventions are built from, so an overridden trail's id resolves to Steward's
tags and every other feature falls through to its tile. That keeps
`otm_conventions.dart` the single definition of what "specified" and "allowed"
mean — the same expressions simply run against better data — and it needs no
geometry, so the tile's own line is what recolours.

Three things about it are easy to get wrong, and each has a test:

- **A tag the override lacks reads as absent**, never as whatever the tile
  still says, or a deleted tag could never be represented.
- **The cache is keyed by the id the style expressions match on** — the OSM way
  id the tile feature carries. Key it any other way and the filters match
  nothing at all.
- **Entries expire against the tileset's own build timestamp**, so an override
  stops being consulted once the tiles carry it.

The cache is persisted (browser local storage), because the complaint it
answers is "I submitted it, refreshed, and it's still magenta".

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
      lens.dart              travel modes, and the lenses a selection is made of
      trail.dart             a trail, tile-provisional or OSM-authoritative
      staged_edit.dart       one pending attribute change, with its tag diff
    osm/
      osm_environment.dart   the OSM hosts, and whether writes commit — the switch
      osm_api.dart           OSM API v0.6 client: way reads + changeset writes
      osm_change_xml.dart    changeset-create and osmChange upload bodies
      osm_auth.dart          OAuth 2.0 + PKCE sign-in state and token storage
      pkce.dart              code verifier / challenge / state generation
      oauth_popup.dart       opens the authorize popup, awaits its result
      oauth_callback.dart    the popup side: hands the code back and closes
      oauth_storage.dart     where the token lives between page loads
      submission_gate.dart   pre-submit checks, then the actual write
    state/
      steward_state.dart     ChangeNotifier: mode, lenses, the working set,
                             the in-view list, and staging
    ui/
      fields.dart            labelled rows, status badges, difficulty picker
      map_controls.dart      travel mode picker and the multi-select lens menu
      legend.dart            what the colours mean
      trail_panel.dart       one selected trail, and its guided editor
      selection_panel.dart   several selected trails, and the bulk editor
      trail_list_panel.dart  every trail in the viewport, as a working list
      staged_changes.dart    staged-changes badge and review sheet
      account_button.dart    OSM sign-in / who you're writing as
    steward_app.dart
```

## Next

1. Validate the write path end to end as a dry run — the `osmChange` document
   is built in full, so it can be read before it's ever sent — then everything
   in "3. Firebase, live" above. The OEG wiki page and the two-week community
   notice are the long poles, not the code.
2. The changeset tags the spec §6 calls required but no UI collects yet:
   `source` (provenance), and the `slab:*` namespace beyond what's derivable.
   Needs a provenance question in the submit flow, not just a constant.
3. The token-lifetime question the product description §11 flags as
   unresolved. Right now a dead token surfaces as a 401 on the next write and
   signs the rider out; that's honest but not graceful.
4. Surface, then sanction status, through the same staging flow — adding one
   is a `TrailAttribute` value, a `StagedEdit` factory that diffs it, a row in
   the panel, and a `StewardState.apply*` batch method for the bulk editor.
