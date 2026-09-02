# Draft — OSM wiki page for SLAB Steward

Target page: `https://wiki.openstreetmap.org/wiki/Slab_Steward`

## Before publishing

Placeholders are marked `TODO` in the source. The ones that need a real answer:

- **`version` / `date`** — `pubspec.yaml` says `0.1.0+1`. Use whatever ships.
- **`screenshot` / `logo`** — need uploading to the wiki first
  (Special:Upload), under a free license, then referenced by filename.
- **Contact** — the page points complaints at "the contact above", meaning the
  `author` field (DannySlab). Fill in an OSM username whose messages you'll actually read.
  Not an OEG requirement any more, but the page makes a promise of
  reachability and should keep it.
- ~~**`coverage`**~~ — resolved: worldwide. Editing goes through the OSM API
  and OAuth, which are not geographically scoped, and the e-bike picker's
  jurisdiction table already covers multiple countries. The discovery map's
  tileset is presently OSM US's, which is a data-source limitation, not a
  scope claim — worth a footnote if it isn't obvious from context.

Two things in the source deliberately describe the app *as it will ship*, and
are not true of the working tree yet:

1. The page says edits go to the live API. `osmEnvironment` is still
   `dryRun` — the build does every read and check for real but never sends the
   changeset. Flip it to `live` before this page goes up, or the page is wrong
   the day it's published.
2. The page says the discovery tileset is served by SLAB. It is currently
   hotlinked from OSM US. Either get that blessed or stand up your own
   pipeline; describing someone else's infrastructure as a "data source" on a
   wiki page is how they find out.

## Companion page this one does not replace

- The row in **`Editors`** — the comparison table there is maintained by hand.
  Add a row once this page exists, with the same yes/no answers as the infobox.

## Scope claims worth checking against the code before you publish

- ~~Only difficulty is editable today.~~ Resolved: `TrailAttribute` has two
  values, `difficulty` (`mtb:scale:imba`) and `electricBicycle`
  (`electric_bicycle`). Surface and sanction status remain planned —
  `TrailAttribute` doesn't have a third value yet.
- No `check_date:*` is written. The product description §3.4 says it is, the
  changeset spec §8 recommends it, and the code does not — so the page doesn't
  claim it. Worth resolving in the code rather than in the page.
- ~~`created_by` is written as bare `SLAB Steward`, no version.~~ Resolved:
  `submission_gate.dart` now writes `SLAB Steward/{version}`, matching the
  `Name Version` convention the changeset spec §6 asks for.
- No `source` changeset tag yet (README "Next" §2). Listed as planned.

---

```wikitext
{{Languages}}
{{Software
| name           = SLAB Steward
| logo           = <!-- TODO: upload logo, e.g. SLAB_Steward_logo.svg -->
| screenshot     = <!-- TODO: upload screenshot, e.g. SLAB_Steward_screenshot.png -->
| author         = [[User:Danny Godbout|Danny Godbout]]
| license        = MIT
| platform       = web
| status         = active
| version        = 0.1.0
| date           = <!-- TODO: YYYY-MM-DD of the first production release -->
| languages      = EN
| coverage       = worldwide
| web            = https://slab-steward.web.app
| repo           = https://github.com/DannyGsGit/slab-steward
| code           = Dart
| framework      = Flutter
| description    = A guided browser editor for trail difficulty and e-bike access, aimed at riders and walkers who know the trail but not the tagging.
| genre          = editor
| map            = yes
| mapData        = vector
| datasource     = online
| findLocation   = no
| findNearbyPOI  = no
| addPOI         = no
| editPOI        = no
| addWay         = no
| editGeom       = no
| editTags       = Limited
| editRelations  = no
| viewNotes      = no
| createNotes    = no
| editNotes      = no
| editSource     = online
| offsetDBsupport = no
| uploadOSMData  = yes
}}

{{Communication channels
| issue tracker = https://github.com/DannyGsGit/slab-steward/issues
}}

'''SLAB Steward''' is a browser editor for one job: adding
{{Tag|mtb:scale:imba}} difficulty and {{Key|electric_bicycle}} access to
trails that are missing them.

The experience is intentionally simplified. Users pick the difficulty symbol 
as it would be shown on trailhead sign, Steward writes the correct tag.

Edits go through user's own OSM account via OAuth 2.0. No shared or bot accounts are used.

Try it at: [https://slab-steward.web.app slab-steward.web.app]
<div style="clear:left"> </div>

== What it edits ==

Metadata on existing trail ways, nothing else. Steward cannot draw a trail,
move a node, split a way, add a POI, or edit a relation. Sensitive tags
representing sanctioned status are also scoped out.

=== Difficulty ===

Writes {{Tag|mtb:scale:imba}} only, using the IMBA circle/square/diamond
signage scheme:

{| class="wikitable"
! Picker label !! Symbol !! Tag written
|-
| Beginner || purple circle || {{Tag|mtb:scale:imba|0}}
|-
| Easy || green circle || {{Tag|mtb:scale:imba|1}}
|-
| Medium || blue square || {{Tag|mtb:scale:imba|2}}
|-
| Difficult || black diamond || {{Tag|mtb:scale:imba|3}}
|-
| Expert || double black diamond || {{Tag|mtb:scale:imba|4}}
|-
| Pro Line || double orange diamond || {{Tag|mtb:scale:imba|4}}
|-
| Un-rated || gold ring || ''(no tag; absence is the un-rated state)''
|}

* '''{{Key|mtb:scale:imba}}, not {{Key|mtb:scale}}.''' Matches the signage
  riders actually read. {{Key|mtb:scale}} support in development for regions outside
  North America.

=== E-bike access ===

Writes {{Key|electric_bicycle}}, yes/no only:

{| class="wikitable"
! SLAB option !! What it claims !! OSM
|-
| Allowed || E-bikes may ride here, same as any other bike. || {{Tag|electric_bicycle|yes}}
|-
| Not allowed || E-bikes are shut out, regardless of regular bikes. || {{Tag|electric_bicycle|no}}
|}

Only yes/no. {{Tag|electric_bicycle|designated}} and
{{Tag|electric_bicycle|permissive}} are valid OSM values, but both require a
judgment call a rider can't make from a sign, so Steward doesn't offer them.

If a way already carries one of those values, Steward leaves it alone and the
picker becomes read-only.

=== Planned ===

{{Key|surface}}, {{Key|oneway}}, {{Key|smoothness}}, {{Key|width}}, {{Key|incline}}
are out of scope for now but may incrementally be added.

== How it works ==

# '''Discover.''' Map colors trails by whether the attribute you're working on
  is present or missing. Filter by travel mode and completeness.
# '''Select.''' Click a trail, ctrl/cmd-click to add more, ctrl/cmd-drag to
  box-select, or tick trails from a list.
# '''Edit.''' Pick a value per attribute. Nothing is sent yet — changes stage
  locally, with undo.
# '''Review.''' Every staged change, in plain language and as the literal tag
  diff. A real changeset comment is required before submit unlocks.
# '''Submit.''' A changeset is created, all changes validated against API pulls,
uploaded atomically, closed, and linked back to osm.org. All uploads tied to user's
OSM account.

=== Reads before every edit ===

Steward reads current tags and version from the OSM API before it lets you edit, rather
than rely on map tiles which lag the database by days. Editing against stale
tile data risks a version conflict or silently overwriting someone else's
edit. 

== Changesets ==

Every changeset carries:

{| class="wikitable"
! Tag !! Value
|-
| {{Key|created_by}} || <code>SLAB Steward/''version''</code>, e.g. <code>SLAB Steward/0.1.0</code>
|-
| {{Key|comment}} || written by the contributor, required, more than one word
|-
| {{Key|hashtags}} || <code>#slabsteward</code>
|-
| {{Key|host}} || <code>https://slab-steward.web.app</code>
|-
| {{Key|locale}} || the contributor's UI language, e.g. <code>en-US</code>
|-
| {{Key|review_requested}} || <code>yes</code>, only if the contributor asks for review
|}

<code>#slabsteward</code> is added automatically if missing, so the corpus of
Steward edits is queryable in [[OSMCha]].

The comment is never auto-generated. Steward requires the contributor to
write one, and rejects <code>update</code>, <code>fix</code>, or a full stop.

== Data sources ==

{| class="wikitable"
! What !! Source
|-
| Basemap style || [https://opentrailmap.us OpenTrailMap]'s published MapLibre stylesheet
|-
| Trail discovery layer || [https://tiles.openstreetmap.us OpenStreetMap US]'s vector tileset, used under its [https://tiles.openstreetmap.us/usage-policy/ usage policy]
|-
| Authoritative tags, geometry, version || OSM API v0.6, read fresh on every selection
|-
| Sign-in and writes || OAuth 2.0 with PKCE against openstreetmap.org, under the contributor's own account
|}

No external data is imported into OSM. Every value is hand picked.

== Rendering ==

Map styling follows [https://github.com/osmus/OpenTrailMap OpenTrailMap]'s
conventions rather than inventing new ones: solid lines for official trails,
dashed for {{Tag|informal|yes}}, faded with no-entry symbols where the
selected travel mode isn't allowed.

Line color is the trail's {{Tag|mtb:scale:imba}} rating, in the same signage
colors SLAB puts on a trailhead sign: green for {{Tag|mtb:scale:imba|0}} and
{{Tag|mtb:scale:imba|1}}, blue for {{Tag|mtb:scale:imba|2}}, black for
{{Tag|mtb:scale:imba|3}}, red for {{Tag|mtb:scale:imba|4}}, and magenta where
there is no rating at all.

Everything else is said with a glow: golden where a trail matches the
completeness rules the user has ticked — i.e. the golden trails are the to-do
list — teal where it is selected, and its own rating's color where an edit is
staged on it.

One departure: trails that disallow the selected travel mode stay visible,
drawn faded, instead of hidden, to remain clickable to fix their
tags.

Because the tileset lags the database, a trail you just edited would draw as
unrated until the next tile build. Steward keeps a local overlay of tags newer
than the tiles and restyles those trails until the tileset catches up.

== Limitations ==

* Existing trail ways only. No create, delete, split, reshape, or relation
  editing.
* Two attributes only today: difficulty and e-bike access.
* No [[Notes|OSM Notes]] support.
* Online only, no offline editing or local cache.
* Web only, mobile planned for later.
* English only.

For anything outside that, Steward links out to [[iD]] ways instead of
growing a general-purpose editing mode.

== See also ==

* [[Editors]] — comparison of OpenStreetMap editors
* [[MapComplete]] and [[Pic4Review]] — other browser-based, question-style tag editors
* [[StreetComplete]] — the mobile original of the pattern
* {{Key|mtb:scale:imba}}, {{Key|mtb:scale}}, {{Key|surface}}, {{Key|informal}},
  {{Key|electric_bicycle}}

[[Category:Editors]]
```
