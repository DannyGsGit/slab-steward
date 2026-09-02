# Product Analytics — SLAB Steward

**Scope:** how many people arrive, how far down the funnel they get, and what Steward has actually put into OpenStreetMap.
**Audience:** implementation reference for instrumentation and for the impact-metrics job.
**Date:** August 2026

---

## 0. The answers, up front

**1. Can a drop-in analytics snippet answer any of this?**
**No.** Flutter web renders to a canvas — there is no DOM for a script to read. Autocapture (PostHog autocapture, GA4 enhanced measurement, Plausible's link tracking) sees one pageview and zero interactions, permanently. Session replay is the same story: rrweb records DOM, so it would record a blank rectangle. **Every event is fired explicitly from Dart.** That is roughly a dozen call sites, and it means the event schema matters far more than the vendor.

**2. One system or two?**
**Two, and they must not be conflated.** Funnel behaviour comes from the client. Changeset and trail counts come from OpenStreetMap itself. Ad blockers eat a real share of client events and Steward's audience is unusually technical — client events cannot be trusted to count contributions. OSM's own record is authoritative, retroactive to launch, and doesn't depend on any tracking having been installed at the time.

**3. Which client tool?**
**PostHog Cloud, free tier.** 1M events/month, which Steward will not approach. The whole question here is a funnel; PostHog answers it on one screen where GA4 Explorations do not. GA4 via `firebase_analytics` is free forever and adds no vendor — the tradeoff is a worse funnel UI and a cookie-consent banner.

**4. Is dwell time in scope?**
**No — deliberately deferred.** A canvas app fires few events, and PostHog derives session duration from first-to-last event timestamp, so any number it reports would be a large undercount. Getting a real figure needs a visibility-gated heartbeat. Funnel progression first; revisit dwell once the funnel is telling us something.

---

## 1. The funnel

The question this whole document exists to answer:

```
app_opened → trail_selected → edit_staged → auth_completed → submit_opened → submit_succeeded
```

Each step is one event. Everything else in the schema exists to explain a drop between
two of them. Building this funnel, and the three views that diagnose it, is
[analytics-dashboard.md](analytics-dashboard.md) — all of it PostHog UI work, none of
it code.

---

## 2. Event schema

| Event | Call site | Properties |
|---|---|---|
| `app_opened` | `main.dart`, *after* the OAuth-popup early return | — |
| `trail_selected` | `setSelected` / `selectFromTile`, `steward_state.dart` | `bulk` (bool), `count` |
| `edit_staged` | `_applyAcross`, `steward_state.dart` | `attribute`, `trail_count` |
| `auth_started` | `signIn`, `osm_auth.dart` | — |
| `auth_completed` | `signIn`, `osm_auth.dart` | — |
| `auth_cancelled` | `signIn`, `osm_auth.dart` | — |
| `auth_failed` | `signIn`, `osm_auth.dart` | `reason` (exception *type*, never its message) |
| `submit_opened` | review screen, `staged_changes.dart` | `trail_count` |
| `gate_failed` | `SubmissionGate.run` returning false | **`check`** (`comment` \| `fetch` \| `conflicts`) |
| `submit_succeeded` | after `SubmissionGate.submit` | `trail_count`, `changeset_id` |

`auth_cancelled` was added during implementation and is deliberately not an
`auth_failed`: both UI layers already treat a closed popup as a non-error, and
merging the two would build a wall of "failures" out of people who simply changed
their mind. All four auth events are emitted from `OsmAuthState.signIn` rather than
from the two widgets that call it, so neither can drift from the other.

**`gate_failed` is the highest-value event in the list.** The gate rejects on comment quality, unreadable ways, and conflicts (`submission_gate.dart`). Which of those three is where riders give up is a product decision available from no other source — not from OSM, and not from any funnel step count.

### Two things to get right

Two call sites are worth naming, because the obvious place was the wrong one in both
cases. `app_opened` fires *after* `tryHandleOAuthCallback` returns false — the OAuth
popup is a second load of the same app, and counting it would add a phantom
`app_opened` for every rider who signed in, inflating the top of the funnel with
exactly the people who got furthest down it. And `edit_staged` fires from
`_applyAcross`, the single point every staging path funnels through, so one rider
*act* is one event carrying how many trails it covered — instrumenting `stageEdit`
would have emitted a hundred events for one bulk apply.

**Super-property `writes_to_osm`**, from `osmEnvironment.writesToOsm`. It records what
a build would actually do with a submission, which is a thing worth having on every
event permanently. Note it does *not* currently separate development from production
traffic — `osmEnvironment` is `live`, so it is `true` on a laptop exactly as it is on
`slab-steward.web.app`. Excluding your own traffic is `$host`'s job; see
[analytics-dashboard.md](analytics-dashboard.md) §0.2.

**`identify()` on the OSM user id** once auth completes. This links the anonymous session to the contributor, which is what makes return rate answerable.

---

## 3. Client configuration

Three settings carry their weight on canvas:

| Setting | Value | Why |
|---|---|---|
| `autocapture` | `false` | Nothing to capture — no DOM |
| `capture_pageview` | `false` | One pageview per session, forever; `app_opened` is the real signal |
| `disable_session_recording` | `true` | Would record a blank rectangle |
| `person_profiles` | `'identified_only'` | Profiles only for riders who signed in to OSM |

No autocapture plus no replay plus profiles only for signed-in riders is a
defensible posture for an OSM-facing tool, and needs a short privacy note rather
than a consent banner.

**Region: US** (`POSTHOG_API_HOST: https://us.i.posthog.com`). Worth recording
because it is the one setting that cannot be changed later without standing up a new
project. EU residency would have been the stronger posture for a tool with European
visitors — OSM's community is heavily European — since it keeps their data out of a
US transfer entirely. The mitigations above do most of the work regardless: no
autocapture means no incidental capture of anything not deliberately sent, and the
event schema in §2 carries no personal data beyond an OSM user id that is already
public. Revisit only if the privacy note turns out to need a transfer story.

**Ad blockers** will cost some share of events. Accept it for now — the funnel is about ratios between steps, and blocking hits every step roughly equally. A reverse proxy would need a Cloud Function, since Firebase Hosting rewrites can only target Hosting paths, Functions, or Cloud Run.

---

## 4. Code shape

The conditional-import pattern already used for `oauth_storage.dart`, `oauth_popup.dart` and `oauth_callback.dart`:

```
lib/src/analytics/analytics.dart        ← the facade every caller imports
lib/src/analytics/analytics_web.dart    ← package:web interop to the posthog global
lib/src/analytics/analytics_stub.dart   ← no-op, for tests and any future native build
```

**`web/index.html` is untouched** — no snippet, no `<script>`, no key. This is a
deliberate change from the earlier draft of this section, which had the library
loaded from the HTML. `analytics_web.dart` injects the `<script>` itself, pointing at
`{apiHost}/static/array.js`, and then calls `posthog.init()`. Three things fall out
of that: the region stays single-sourced from the vault instead of being half in HTML
and half in a define, a third-party script stays off the critical path to first paint,
and there is no load-order race between an `async` bootstrap and a global the Dart
code expects to already exist. Events captured before the library lands are queued and
flushed on load, which matters because `app_opened` fires before any round trip could
have finished.

The key and host come from `secrets/vault.env` via `--dart-define`, exactly as
`osmClientId` does (`tool/run.sh`). Both are public — they ship to every browser and
are readable in devtools — but they are per-deployment ids, and the project already
has one place for those.

**The facade must no-op on an empty key**, mirroring how `osmClientId` is documented
as "empty when it wasn't passed". That is what keeps `flutter test` and a bare
`flutter run` from crashing or, worse, quietly writing test traffic into the funnel.

The stub keeps tests and a future `flutter create --platforms=ios,android` from
caring that analytics exists at all.

---

## 5. Impact metrics — changesets and trail edits

Steward already tags its changesets for exactly this (`submission_gate.dart`):

```
created_by = SLAB Steward/{version}
hashtags   = #slabsteward
host       = https://slab-steward.web.app
```

### The OSM API cannot query these

**`GET /api/0.6/changesets.json` silently ignores an unrecognised `hashtag` parameter** — it does not error, it returns everything. Verified August 2026:

```
?user=3278183&closed=true                           → 100 changesets
?user=3278183&closed=true&hashtag=zzznonexistentzzz → 100 changesets
```

Two consequences.

**A live bug in the stats pane.** `OsmApi.fetchChangesets` filters on `user` and `closed` only, so riders are shown their *entire OSM history* rather than their Steward work — precisely what the method's own doc comment says it exists to avoid. Fix: filter client-side on the returned `tags.hashtags`. Caveat: the 100-changeset page then becomes a pre-filter, so a prolific mapper could page past all their Steward edits.

**Aggregate counts need an external index.** Use the **OSMCha API**
(`osmcha.org/api/v1/changesets/`). Requires a token — free, obtained by signing in
with an OSM account; it 401s without one.

Two things about that API, both found while building `tool/impact/impact.py` and
both load-bearing:

**OSMCha's `hashtags` filter is silently ignored as well** — the identical failure
mode to OSM's, in the second tool reached for to work around the first. Verified
2026-08-30, all three returning the same unfiltered count:

```
?date__gte=2026-08-29                              → 108506
?date__gte=2026-08-29&hashtags=slabsteward         → 108506
?date__gte=2026-08-29&hashtags=zzznonexistentzzz   → 108506
?date__gte=2026-08-29&editor=SLAB%20Steward        →      4
```

The filter that works is **`editor`**, matching the `created_by` tag Steward stamps
on every changeset. Since that is a substring match, the script re-checks the
hashtag client-side — the same belt-and-braces `OsmApi._carriesHashtag` applies on
the Dart side, and what would otherwise let a future "SLAB Stewardship" be counted
as Steward.

**The query cost scales with the date window, steeply.** Measured the same day:

| Date floor | Response |
|---|---|
| `2026-08-29` | 0.4s |
| `2026-08-25` | 9s |
| `2026-01-01` | hangs past 150s |
| none | hangs past 150s |

So a floor is mandatory rather than an optimisation. The script defaults to
2026-08-29 — the day `osmEnvironment` was flipped to `live`, and therefore the
first day any Steward edit could have reached OpenStreetMap. Widening it will get
slow long before it gets useful, which is worth knowing before assuming a hung
script is a broken one.

### Trail edits come from the listing itself — do not download changesets

The edit count is already in the listing response, so summing it costs nothing
beyond the call that was made anyway. **Use it.**

One correction to an earlier draft of this section: OSMCha does *not* return a
`changes_count` field. It returns the breakdown — `create`, `modify`, `delete` —
and the script sums those. For Steward that sum is the `modify` count alone, since
it is metadata-only and never creates or deletes; a non-zero `create` or `delete`
on a Steward changeset would mean something had gone badly wrong.

The precise meaning matters, so the dashboard doesn't overclaim. Steward writes
one `<modify>` element per trail (`osm_change_xml.dart`), so a changeset's edit
count is *the number of trails written in that changeset*. Summed across
changesets it is **trail edits, not distinct trails** — a trail rated today and
given a surface next week counts twice.

Distinct trails would need `GET /api/0.6/changeset/{id}/download` per changeset to
collect way ids. That is one API call per changeset, growing without bound as
Steward gets used, against a courtesy-limited public API — for a number that is
strictly less useful than the edit count when the goal is measuring activity.
**Not worth it.** Revisit only if the distinct figure is ever asked for by name.

| Metric | Source |
|---|---|
| Total changesets | OSMCha, `editor=SLAB Steward`, hashtag re-checked client-side |
| Distinct contributors | OSMCha, distinct `uid` |
| Trail edits | OSMCha, sum of `create + modify + delete` |

As of 2026-08-30, the first day Steward could write to OpenStreetMap at all, that
comes to **4 changesets, 1 contributor, 170 trail edits**.

### Where these numbers are displayed

**Audience 1 — the operator, asking "how is Steward doing?"** Ad hoc, exploratory,
changes shape every time it's asked. **A notebook in `tool/impact/`, run on demand.**
No job, no server, no deploy, and the OSMCha token never leaves the machine. This is
what to build first, and quite possibly the only thing ever built.



### Python in a Dart repo — managed by `uv`

Two files in `tool/impact/`, one implementation between them:

```
tool/impact/impact.py      ← the logic, plus a CLI
tool/impact/impact.ipynb   ← the notebook people actually read
```

The notebook **imports** `impact.py` rather than restating it. A notebook that
reimplements its own script drifts from it, and then one question has two answers
that disagree — the failure mode is silent and the discovery is always late.

```sh
cd tool/impact && uv run --with jupyter jupyter lab   # read the numbers
uv run tool/impact/impact.py                          # same numbers, no browser
uv run tool/impact/impact.py --json                   # for a dashboard to consume
```

`impact.py` has **no dependencies at all** — PEP 723 metadata, stdlib only — so the
CLI needs nothing but `uv`. The notebook adds Jupyter and nothing else: the tables
are plain HTML through `IPython.display`, deliberately, to keep pandas and
matplotlib out of a repo that is otherwise entirely Dart.

`uv` fetches its own interpreter, so this adds **no** global Python install, no
`pip`, no `activate` ritual, and no system-Python version to keep in step — which is
the thing worth caring about when the second language in a repo gets used a few times
a month and is cold every time. `__pycache__/` and `tool/impact/.venv/` are
gitignored.

The notebook is committed **with its outputs**, so opening the file shows the current
numbers without running anything. They are a snapshot, dated by the `last edit` row
they contain.

It ships nothing to the browser and is not part of any build.

---

## 6. Implementation checklist

- [x] PostHog project; library loaded by `analytics_web.dart` from the vault's host,
      key and host via `--dart-define`; autocapture, pageview and replay off
- [x] `analytics.dart` / `analytics_web.dart` / `analytics_stub.dart` facade
- [x] `writes_to_osm` super-property from `osmEnvironment`
- [x] The ten events of §2, `gate_failed` carrying its `check` id
- [x] `identify()` on OSM user id at `auth_completed`, and on a restored session
- [ ] Funnel saved in PostHog over the six steps of §1 — build it from
      [analytics-dashboard.md](analytics-dashboard.md), which is entirely UI work
- [x] **Separately:** fix `fetchChangesets` to filter on `tags.hashtags`
- [x] `uv`-managed `tool/impact/impact.py` + `impact.ipynb` per §5 — filters on
      `editor`, sums the OSMCha edit breakdown, no changeset downloads
- [x] A real OSMCha token in `secrets/vault.env` as `OSMCHA_API_KEY`
- [ ] *Deferred:* nightly `impact.json` job, only if a public figure lands in the app
- [x] Short privacy note in the app — foot of the Account pane
