# PostHog Dashboard Setup — SLAB Steward

**Scope:** turning the events of [analytics.md](analytics.md) §2 into the four views worth looking at.
**Audience:** whoever is sitting in front of PostHog with the project already created.
**Date:** August 2026

Everything here is done in PostHog's UI, not in code. PostHog moves its labels
around; the concepts below don't, so where a name has drifted, search for the
noun rather than the path.

---

## 0. Before building anything

**1. Confirm events are actually arriving — do this before anything else.**
Run the app (`tool/run.sh`, or open the deployed build), click a trail, and then
look for `app_opened` in the project's activity / live-events view. Nothing else
in this document can be set up until PostHog has seen at least one event: every
filter and breakdown below is chosen from a list built out of what has already
been ingested.

If nothing arrives, the problem is upstream of this document — check the build
was made through `tool/run.sh` (which passes `POSTHOG_API_KEY`), and that an ad
blocker isn't eating the request in the browser you're testing from. Open one of
the received events and read its property list; that is also the fastest way to
confirm `$host` and `writes_to_osm` are both present.

**2. Set the internal-traffic filter — but only after step 1 passes.** This is
the one setup step that silently ruins everything downstream if skipped, and it
is far more annoying to retrofit across a dozen saved insights than to do once
now. It cannot be done first, though: PostHog's filter box is a *picker* over
properties it has already ingested, so until at least one event has arrived
there is nothing to pick and the box reports "no results" for everything.

Project settings → the "internal and test users" filter → Add filter → type
**just the property name** (`$host`), choose it from the list, *then* set the
operator and value:

```
$host   does not equal   slab-steward.web.app
```

**Not `writes_to_osm`.** That property was the original plan and is now the
wrong discriminator: `osmEnvironment` is `OsmEnvironment.live`, so
`writes_to_osm` is `true` in local development exactly as it is in production.
It separates nothing. It is still worth sending — it records what a build would
actually do, and it would discriminate again if a dry-run build ever ships — but
it cannot carry this filter.

`$host` can, because posthog-js attaches it to *every* event regardless of the
pageview and autocapture settings this project turns off. Local runs report
`127.0.0.1`; the deployed app reports `slab-steward.web.app`.

Without this rule, your own clicking sits inside the same funnel as real riders
— and since you exercise the submit path far more thoroughly than any rider ever
will, it doesn't just add noise, it *biases the conversion rate upward*. Each
insight then has a toggle to respect the filter; leave it on everywhere except
when you are deliberately debugging your own traffic.

**The stronger alternative**, if you would rather development traffic never
leave the machine at all: gate `initAnalytics` on `kReleaseMode` in
`lib/main.dart`. That trades away the ability to exercise the instrumentation
against the real project — which is exactly what step 1 above is for — so it is
a deliberate choice rather than an obvious improvement.

**3. Know what you cannot ask.** Skip to §5 before wondering where the
pageviews went.

---

## 1. The funnel — the reason any of this exists

New insight → **Funnel**. Six steps, in order:

| # | Event |
|---|---|
| 1 | `app_opened` |
| 2 | `trail_selected` |
| 3 | `edit_staged` |
| 4 | `auth_completed` |
| 5 | `submit_opened` |
| 6 | `submit_succeeded` |

Settings that matter:

- **Conversion window: 7 days.** The default (14) is too generous and 1 hour is
  too mean. Steward's shape of use is "go for a ride, come back and rate what
  you rode" — a rider who opens the map on Tuesday and submits on Saturday is
  one converted rider, not a bounce plus a mystery.
- **Order: sequential**, not "any order". The steps are causally ordered and
  a rider cannot submit before staging.
- **Step 4 is where to expect the cliff.** Signing in to OpenStreetMap is the
  single largest ask in the product — an OAuth popup, an external account, a
  consent screen. Treat a large drop there as expected and measure whether it
  *moves*, rather than as a bug to fix on sight.

Save it as **Steward funnel**. This is the number that answers "is the tool
working", and it is the one insight to look at first every time.

### The variant worth having

Duplicate it and add a breakdown by **`bulk`** on step 2 (`trail_selected`).
Whether people who select in bulk convert differently from people clicking one
trail at a time tells you which editing mode to invest in — and the two modes
were a substantial design bet (see the README on multi-select).

---

## 2. Where the compliance gate loses people

New insight → **Trends**. Event `gate_failed`, breakdown by property **`check`**.

Three series come out: `comment`, `fetch`, `conflicts`. This is the highest-value
view in the whole project, because it is the only place the information exists
at all — OpenStreetMap records what succeeded, never what a rider abandoned.

How to read each:

| Series | What it means | What to do about it |
|---|---|---|
| `comment` | The changeset comment failed the quality bar in `submission_gate.dart` | A steady high count means the bar's *guidance* is failing, not the rider — they're trying and being rejected. Rewrite the helper text before lowering the bar |
| `conflicts` | Someone else edited the trail between staging and submit | Expect a low rate. A rising one means riders are leaving edits staged for too long, which is a product-shape signal |
| `fetch` | A way couldn't be re-read from the OSM API | Should be near zero. Anything else is an OSM availability problem, not a rider problem |

Pair it with a second Trends insight showing `gate_failed` as a **ratio of
`submit_opened`** — the absolute count rises with traffic, and the rate is what
actually tells you whether the gate got better or worse.

---

## 3. Sign-in outcomes

New insight → **Trends**, four series on one chart: `auth_started`,
`auth_completed`, `auth_cancelled`, `auth_failed`.

The distinction between the last two is the point, and it's why
`auth_cancelled` exists as its own event (analytics.md §2):

- **`auth_cancelled` is people, `auth_failed` is software.** Someone closing the
  OSM popup is making a decision — usually "I don't want to make an account for
  this yet". That's product feedback. An exception thrown mid-exchange is a bug.
- A rise in `auth_cancelled` says the *ask* is landing badly — wrong moment,
  unclear why it's needed.
- Any `auth_failed` at all deserves investigation. Break it down by **`reason`**
  (the exception type — never the message, by design) to see which.

---

## 4. How riders actually edit

Two small Trends insights, useful for product decisions rather than health:

- **`edit_staged`, breakdown by `attribute`.** Difficulty versus e-bike access.
  Which vocabulary riders reach for tells you which one to deepen.
- **`trail_selected`, breakdown by `bulk`**, and `edit_staged` with `trail_count`
  as an average. Steward invested heavily in bulk editing; this says whether it
  was worth it.

And one **Retention** insight, on `submit_succeeded` returning to
`submit_succeeded`. Only identified riders appear (person profiles are
`identified_only`), which is exactly right here — the question is whether a
*contributor* comes back, and everyone who has submitted is signed in by
definition.

---

## 5. What this project cannot answer, and why

Do not build these. Each looks available in the PostHog UI and each is empty or
misleading here.

| Don't build | Why it's broken |
|---|---|
| Anything on the **Web Analytics** tab | It runs on `$pageview` / `$pageleave` plus autocapture, all three disabled. Flutter web draws to a canvas; there is no DOM to observe |
| **Session duration** or time-on-page | Derived from first-to-last event timestamp. A canvas app fires few events, so any figure would be a large undercount. Deliberately deferred — analytics.md §0.4 |
| **Pageviews** or entry/exit pages | One page load per session, forever. `app_opened` is the real signal |
| **Session replay** | rrweb records DOM. It would record a blank rectangle |
| **Autocapture / heatmaps** | Nothing to capture |

**And one caveat that applies to every number above:** ad blockers eat a share
of events, and Steward's audience is unusually technical. Treat absolute counts
as **floors**, not totals. Ratios between funnel steps are the trustworthy part,
since blocking hits every step roughly equally.

For anything about what Steward has actually put into OpenStreetMap — changesets,
contributors, trail edits — do not use PostHog at all. That is
`tool/impact/impact.py`, and analytics.md §5 explains why the two must never be
conflated.

---

## 6. Assembling the dashboard

New dashboard, **Steward**, in this order — health first, diagnosis second,
curiosity last:

1. Steward funnel (§1)
2. `gate_failed` by check (§2)
3. Sign-in outcomes (§3)
4. Editing shape and retention (§4)

Set the default date range to **30 days**. Steward's traffic is low enough that
a 7-day window is mostly noise, and long enough windows hide a regression inside
an accumulating total.

Optional, once there is a baseline to compare against: an alert on
`submit_succeeded` falling to zero over 7 days. That is the one condition that
means the tool is broken rather than quiet — and it's the failure mode a
dashboard nobody opened would otherwise hide.
