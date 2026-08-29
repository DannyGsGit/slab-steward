# Draft — OSM wiki page for SLAB Steward

Target page: `https://wiki.openstreetmap.org/wiki/SLAB_Steward`

Everything below the rule is the page source, in wikitext, ready to paste into
the wiki's "edit source" box. It follows the shape the other editor pages use
(`{{Software}}` infobox + `{{Communication channels}}` + prose), modelled on
[MapComplete](https://wiki.openstreetmap.org/wiki/MapComplete) and
[Pic4Review](https://wiki.openstreetmap.org/wiki/Pic4Review) — the two closest
neighbours, both browser-based question-style tag editors that don't touch
geometry.

## Note on organised editing

Confirmed with OSM (August 2026) that SLAB Steward is **not** organised editing:
individuals editing on their own initiative, no coordination, no assignments, no
targets. The page says so explicitly rather than staying silent, because a tool
that makes bulk attribute edits easy attracts the question anyway, and answering
it up front is cheaper than answering it in a changeset thread later.

Two consequences outside this file, neither of them acted on yet:

- **`docs/slab-steward-osm-changeset-spec.md` §9-10 and the README's pre-flight
  checklist both still list the OEG activity page and the two-week community
  notice as blockers on the production flip.** They are not blockers any more.
  Worth correcting so the checklist stays trustworthy — a checklist with one
  known-stale item on it gets skimmed.
- **The [[Automated Edits code of conduct]] material in the page is unaffected.**
  That is a separate policy and it still applies: it is about whether objects are
  reviewed individually, not about whether the activity is coordinated. The bulk
  editor's per-object review, and the deliberate absence of lasso selection, are
  what keep Steward on the right side of it. Keep both.

## Before publishing

Placeholders are marked `TODO` in the source. The ones that need a real answer:

- **`license`** — there is no `LICENSE` file in the repo. Pick one, or drop the
  parameter. The infobox treats an empty license as unknown, which reads worse
  than proprietary.
- **`repo`** — `github.com/DannyGsGit/slab-steward` is currently private. Either
  make it public or remove the parameter; a dead link on the infobox is the
  first thing a reviewer clicks.
- **`version` / `date`** — `pubspec.yaml` says `0.1.0+1`. Use whatever ships.
- **`screenshot` / `logo`** — need uploading to the wiki first
  (Special:Upload), under a free license, then referenced by filename.
- **Contact** — the page points complaints at "the contact above", meaning the
  `author` field. Fill in an OSM username whose messages you'll actually read.
  Not an OEG requirement any more, but the page makes a promise of
  reachability and should keep it.
- **`coverage`** — written as United States, on the basis that the discovery
  layer is OSM US's trails tileset. Confirm before publishing.

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

- Only difficulty is editable today (`mtb:scale:imba`). Surface and sanction
  status are described as planned, because `TrailAttribute` has one value.
- No `check_date:*` is written. The product description §3.4 says it is, the
  changeset spec §8 recommends it, and the code does not — so the page doesn't
  claim it. Worth resolving in the code rather than in the page.
- `created_by` is written as bare `SLAB Steward`, no version. Convention is
  `Name Version`, and the changeset spec §6 asks for it. The page documents
  what the code does.
- No `source` changeset tag yet (README "Next" §2). Listed as planned.

---

```wikitext
{{Languages}}
{{Software
| name           = SLAB Steward
| logo           = <!-- TODO: upload logo, e.g. SLAB_Steward_logo.svg -->
| screenshot     = <!-- TODO: upload screenshot, e.g. SLAB_Steward_screenshot.png -->
| author         = [[User:TODO|TODO]]
| license        = <!-- TODO: no LICENSE file in the repository yet -->
| platform       = web
| status         = active
| version        = 0.1.0
| date           = <!-- TODO: YYYY-MM-DD of the first production release -->
| languages      = EN
| coverage       = United States
| web            = https://slab-steward.web.app
| repo           = https://github.com/DannyGsGit/slab-steward
| code           = Dart
| framework      = Flutter
| description    = A guided browser editor for trail difficulty, e-bike access and surface, aimed at riders and walkers who know the trail but not the tagging.
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

'''SLAB Steward''' is a browser-based [[editor|OpenStreetMap editor]] for a
single, narrow job: adding trail attributes that most trails in the United
States are missing, in particular {{Tag|mtb:scale:imba}} difficulty ratings.

It is aimed at people who know a trail well but do not know OpenStreetMap's
tagging — riders, hikers, trail crew, mountain bike association volunteers. The
editor never shows a tag key. A rider picks the difficulty symbol they saw on
the trailhead sign, and the app writes the corresponding tag. Everything else
about the trail — geometry, name, access, the fifteen tags nobody is touching —
is read from the API and echoed back unchanged.

Every edit is made under the contributor's own OSM account via OAuth 2.0. There
is no shared service account, and edits accrue to the person who made them.

Try it at [https://slab-steward.web.app slab-steward.web.app].
<div style="clear:left"> </div>

== What it edits ==

Deliberately very little. Steward is a metadata editor for ''existing'' trail
ways: it cannot draw a trail, move a node, split a way, add a POI, or edit a
relation, and it is not intended to grow those abilities.

=== Difficulty ===

Steward writes {{Tag|mtb:scale:imba}} and nothing else on the difficulty axis.
The picker is the IMBA circle/square/diamond signage scheme, because that is
what riders read off the sign:

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

Two choices here are worth stating plainly, because both are visible in the
resulting data:

* '''{{Key|mtb:scale:imba}} rather than {{Key|mtb:scale}}.''' The wiki scopes
  {{Key|mtb:scale:imba}} to purpose-built trails and recommends
  {{Key|mtb:scale}} elsewhere; that scope has been disputed on the tagging list
  for years, and in practice mappers use {{Key|mtb:scale:imba}} wherever a
  trail carries signposted IMBA-style ratings. Steward follows the practice,
  because it is the scale its users can actually read off a sign.
  {{Key|mtb:scale}} asks for percent grade and obstacle height in centimetres,
  which a layperson cannot self-assess, and a guess written confidently is
  worse than a blank.
* '''"Pro Line" writes 4, the same as Expert.''' The schema tops out at 4 and
  Steward does not invent a 5. The extra distinction is kept outside OSM. The
  UI says so at the point of choosing, rather than letting a rider believe OSM
  carries it.

'''Un-rated is not selectable.''' Choosing it would delete an existing rating,
which is a destructive edit dressed up as a dropdown entry. Clearing a bad
rating is not something Steward does yet.

=== E-bike access ===

Steward writes {{Key|electric_bicycle}}, through a two-option picker:

{| class="wikitable"
! SLAB option !! What it claims !! OSM
|-
| Allowed || E-bikes may ride here, the same as any other bike. || {{Tag|electric_bicycle|yes}}
|-
| Not allowed || E-bikes are shut out, whether or not regular bikes are. || {{Tag|electric_bicycle|no}}
|}

'''Yes and no, and nothing else.''' The key takes the full access vocabulary,
and {{Tag|electric_bicycle|designated}} and {{Tag|electric_bicycle|permissive}}
are correct on some trails — but neither is a reading a rider can take off a
sign without interpreting it. "Designated" means a trail built or signposted
''for'' e-bikes rather than merely open to them, and "permissive" is a claim
about a landowner's intent. A picker that offers a choice its user cannot
reliably make collects confident wrong answers, which is worse for the map than
a narrower question answered well.

Because {{Key|electric_bicycle}} is a sub-class of {{Key|bicycle}}, both
options are about e-bikes ''specifically'' — "allowed" is not a statement that
the trail allows bikes, and "not allowed" can be true on a trail that welcomes
them. Steward shows that sentence beside each option while the picker is open
and keeps the chosen one under it afterwards, rather than leaving a one-word
label to carry it.

E-bike access is one of the completeness questions: the lenses, the in-view
list filter and the completeness indicator all ask for it alongside difficulty
and surface. The picker's help text points at the trailhead sign or the land
manager's rules as the source, because the failure mode for an access key is
not a blank field, it is a confident guess about what riders are ''doing''.

'''A value Steward cannot offer is never overwritten by one it can.''' An
access key holds one value, so writing {{Tag|electric_bicycle|yes}} to a way
already tagged {{Tag|electric_bicycle|designated}} would ''replace'' the more
specific answer, not add to it — and in a forty-trail batch nobody would see it
go. So Steward does not write those ways at all: the picker is replaced by the
raw value, read-only, and a bulk apply skips them and says how many it skipped.
Correcting such a value is a job for an editor that can show the rider what
they are replacing. The same holds for {{Tag|electric_bicycle|permissive}},
{{Tag|electric_bicycle|destination}} and the rest of the vocabulary; all of
them still count as ''answered'' for completeness.

{{Key|speed_pedelec}} is out of scope: Steward's picker is about pedelecs, and
a rider reading a trailhead sign is not classifying vehicles by top speed.

'''Nothing is selectable that would delete the tag,''' for the same reason
un-rated is not selectable above.

=== Planned ===

{{Key|surface}} (through a similarly simplified picker mapping to standard
values) and sanction status ({{Tag|informal|yes}}) are designed but not yet
built. Sanction status will carry a mandatory written justification, because it
is the field most likely to be contentious on the ground.

{{Key|oneway}}, {{Key|smoothness}}, {{Key|width}} and {{Key|incline}} are out
of scope for now.

Subjective attributes — flow, fun, local difficulty calibration, trail
conditions, closures, photos — are '''not''' written to OSM at all. They fail
verifiability, and they belong in a separate store.

== How it works ==

# '''Discover.''' The map draws trails from a vector tileset, coloured by
  whether the attribute you are looking for is present or missing. Filters
  narrow the view by travel mode (all / mountain biking / hiking) and by
  completeness ("missing difficulty", "missing surface", "missing e-bike
  access", "missing any").
# '''Select.''' Click a trail, or ctrl-click (cmd-click on macOS) to build up a
  working set. A list of every trail in the current viewport can also be ticked
  through, including "select all" over a filter.
# '''Edit.''' A guided picker per attribute, always live: choosing a value
  stages it, and an undo beside the field walks it back. Changes are
  ''staged'', not sent — they accumulate behind a counter and nothing has
  reached OSM yet.
# '''Review.''' The review sheet lists every staged change grouped by trail,
  in plain language ("Difficulty: Not rated → Medium") '''and''' as the literal
  tag diff, so a mapper can check exactly what will be written. Individual
  changes can be dropped here. A meaningful changeset comment is required
  before the submit button enables.
# '''Submit.''' One changeset is opened under the contributor's own account,
  the diff is uploaded atomically, the changeset is closed, and the result
  links to osm.org.

=== Authoritative reads before every edit ===

Steward will not let you edit a trail whose current tags and version it has not
read from the API. The pickers stay disabled until the read completes, and a
bulk operation resolves every trail in the selection against the API — a few at
a time — before it stages anything, reporting whatever it skipped.

This is deliberate and it is the reason the tool is slower than it looks like it
should be. The vector tiles the map draws from are a periodic build and lag the
database by days; a changeset composed against tile data carries a stale version
number and either fails with a 409 or, worse, echoes back a tag set that another
mapper has already changed. Read-modify-write against the live API is the only
correct way to make a one-field edit, so Steward does that every time.

=== Bulk editing, and where it stops ===

Applying one value across a selection — a rating, an e-bike permission, or
both in one pass — produces '''one staged change per trail per attribute''',
never a single opaque batch entry. The review sheet lists, explains
and prunes each one individually, and the contributor sees every trail they are
about to change, by name, with its own before-and-after.

That is the line between a bulk editor and a
[[Automated Edits code of conduct|mechanical edit]], and Steward is built to sit
on the correct side of it: a human sees and confirms each object. Changesets are '''not''' tagged
{{Tag|bot|yes}} or {{Tag|mechanical|yes}}, because they are not.

Lasso and polygon selection are intentionally not implemented. "Set this value
on everything inside this shape" is the shape of edit that cannot be reviewed
per-object, and adding the gesture would quietly move the tool across that line.

== Changesets ==

Every changeset carries:

{| class="wikitable"
! Tag !! Value
|-
| {{Key|created_by}} || <code>SLAB Steward</code>
|-
| {{Key|comment}} || written by the contributor, required, must be more than one word
|-
| {{Key|hashtags}} || <code>#slabsteward</code>
|-
| {{Key|host}} || <code>https://slab-steward.web.app</code>
|-
| {{Key|locale}} || the contributor's UI language, e.g. <code>en-US</code>
|-
| {{Key|review_requested}} || <code>yes</code>, only when the contributor asks for review
|}

<code>#slabsteward</code> is appended to the comment automatically if the
contributor has not typed it, so the whole corpus of Steward edits is
queryable in [[OSMCha]] and the hashtag dashboards.

'''The comment is not generated.''' Steward requires the contributor to write
one and will not enable submit for <code>update</code>, <code>fix</code>, or a
full stop. Machine-generated summaries of the form
<code>BBOX:… ADD:0 UPD:47 DEL:0</code> are not produced. A changeset comment
cannot be edited after the changeset closes, which is why the review sheet
shows the exact text before it is sent.

A {{Key|source}} changeset tag recording where the value came from (survey,
local knowledge, operator records) is planned and not yet collected.

Changesets are kept to one session in one area. Because the bounding box is
drawn from the two farthest-apart objects in the changeset, a session that
wanders between trail networks produces a box covering everything in between,
which clutters every reviewer's filter in the region.

== Attribution, and why this is not organised editing ==

A tool that makes attribute edits easy, used by many accounts, invites the
question, so it is answered here directly: SLAB Steward is '''not''' a
coordinated editing activity, and is not registered under the
[[Organised Editing Guidelines]]. Nobody is directed to edit, no area or trail
is assigned, no participant is measured against a target, and there is no
campaign or deadline. People who know a trail use the tool on their own
initiative, on trails they choose, and stop when they feel like it.

Attribution follows from that:

* '''Edits are made under each contributor's own OSM account''', via OAuth 2.0.
  There is no shared service account and no bot account. Edits accrue to the
  person who made them, and a real person can answer a changeset comment.
* '''{{Key|created_by}} names the tool''' on every changeset. That is the
  authoritative software-attribution channel.
* '''<code>#slabsteward</code>''' in {{Key|hashtags}} makes the corpus of
  Steward edits queryable, so anyone can audit what the tool has done in their
  area without having to identify its users first.

If that ever changes — an association coordinating volunteers toward a target,
a funded campaign, a deadline — it becomes organised editing, and an activity
page under [[Organised Editing/Activities]] will be created before that work
starts, not after.

Questions or complaints about edits made with this tool are welcome on the
changeset itself, on this page's talk page, or at the contact above.

== Data sources ==

{| class="wikitable"
! What !! Source
|-
| Basemap style || [https://opentrailmap.us OpenTrailMap]'s published MapLibre stylesheet
|-
| Trail discovery layer || a vector tileset of OSM trail data <!-- TODO: name the host you actually ship with -->
|-
| Authoritative tags, geometry and version || the OSM API v0.6, read fresh on every selection
|-
| Sign-in and writes || OAuth 2.0 with PKCE against openstreetmap.org, under the contributor's own account
|}

No external or non-OSM data is imported into OSM by this tool. The only values
written are ones a human picked from a list.

== Rendering ==

The map's conventions are ported from
[https://github.com/osmus/OpenTrailMap OpenTrailMap] rather than invented, so
that anyone who reads that map reads this one the same way: solid lines for
official trails, dashed for {{Tag|informal|yes}}, pale tan with no-entry
symbols where the selected travel mode is not allowed.

On top of that, a completeness lens colours trails teal where the attribute
being worked on is present and magenta where it is missing — magenta is, in
effect, the to-do list.

One departure from OpenTrailMap is worth naming: trails that disallow the
selected travel mode stay '''visible''', drawn pale, rather than being hidden.
OpenTrailMap hides them; a steward still has to be able to click a trail in
order to fix its tags, and a hidden trail cannot be clicked.

Because the tileset lags the database, a trail whose rating you just submitted
would keep drawing as unrated until the next tile build. Steward keeps a local
record of tags it knows to be newer than the tiles — both what it submitted and
what it read from the API — and restyles those trails accordingly, expiring
each entry once the tileset's own build timestamp catches up.

== Limitations ==

* Existing trail ways only. It cannot create, delete, split or reshape
  anything, and it does not edit relations — including {{Tag|type|route}}
  relations, which is where a named trail's attributes sometimes actually live.
* One attribute (difficulty) today.
* No [[Notes|OSM Notes]] support.
* Online only; no offline editing and no local cache of the editable data.
* No imagery, no [[Imagery Offset Database|offset database]], no photo mapping.
* Web only. Nothing in it is web-specific, and mobile is a later port.
* English only.

For anything outside that envelope, Steward links out to [[iD]] and
[[JOSM]] rather than growing a general-purpose editing mode.

== See also ==

* [[Editors]] — comparison of OpenStreetMap editors
* [[MapComplete]] and [[Pic4Review]] — other browser-based, question-style tag editors
* [[StreetComplete]] — the mobile original of the pattern
* {{Key|mtb:scale:imba}}, {{Key|mtb:scale}}, {{Key|surface}}, {{Key|informal}},
  {{Key|electric_bicycle}}
* [[Organised Editing Guidelines]]
* [[Automated Edits code of conduct]]

[[Category:Editors]]
```
