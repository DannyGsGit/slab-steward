# OSM Changeset Requirements — SLAB Steward

**Scope:** metadata-only tag edits to *existing* trail ways. No new geometry, no new trails, one attribute at a time.
**Audience:** implementation reference for the Steward write path.
**Date:** August 2026 · API v0.6

---

## 0. The four answers, up front

**1. Do you submit only the field you're editing?**
**No. There is no partial update in OSM.** The API has no `PATCH`. Every write must carry the **complete post-edit representation** of the element. The wiki is explicit: *"A full representation of the element as it should be after the update has to be provided. Any tags, way-node refs, and relation members that remain unchanged must be in the update as well."* Anything you omit is **deleted**. A one-field edit is therefore mechanically a read-modify-write: fetch the current element, mutate one key in memory, send the whole thing back.

**2. Does the full ordered node list have to be included?**
**Yes — all of it, in order.** Omitted `<nd ref>` entries are removed from the way, which destroys geometry. Since Steward never changes geometry, the rule is simple: **echo the `<nd>` block back exactly as received.** You do *not* need to send the node elements themselves — only their refs inside the way.

**3. How does Steward get attributed alongside the username?**
Via the **`created_by` changeset tag** (the canonical software-attribution channel that taginfo, OSMCha and planet analytics key off), plus **`hashtags=#slabsteward`** for campaign-level queryability, plus `host`. The **username stays the human's own OSM account** via OAuth 2.0 — never a shared Slab service account. That is both an Organised Editing requirement and your own P0 design constraint.

**4. Is there room for custom tags?**
**On the changeset: yes, essentially unlimited** — free-form keys, 255 chars each for key and value, no validation, no approval. iD already writes `ideditor:*`, `warnings:*`, `resolved:*`; Rapid writes `data_used`. A `slab:*` changeset namespace is safe and uncontroversial.
**On map elements: technically yes, socially constrained.** "Any tags you like" is real policy, but a vendor namespace on trail ways will read as pollution and attract attention. Use operator-scoped keys (`ref:wmbc=*`) and `check_date:<key>=*`, which are legitimate and already conventional. Put subjective data (flow, fun factor, regional difficulty calibration) in SLAB Commons, not OSM.

---

## 1. The write path

Five steps. Steward will run steps 2–5 per submission batch.

```
① OAuth 2.0 (PKCE) → user's own OSM account
② GET  /api/0.6/way/{id}                          ← fetch current full element + version
③ PUT  /api/0.6/changeset/create                  ← open changeset with tags
④ POST /api/0.6/changeset/{cs}/upload             ← osmChange diff (atomic)
⑤ PUT  /api/0.6/changeset/{cs}/close
```

**Auth.** OAuth 2.0 Authorization Code **with PKCE** — no client secret in the browser. Scopes needed:

| Scope | Why |
|---|---|
| `write_api` | modify the map (includes `write_changeset_comments`) |
| `read_prefs` | read the user's identity/display name |
| `openid` | optional — sign-in with OSM |

Redirect URIs must be `https://` (or `http://127.0.0.1`). Register a **separate OAuth app for the dev/staging environment against `api06.dev.openstreetmap.org`** — never test writes against the production database.

**Changes are live the moment the upload succeeds.** Closing the changeset is bookkeeping, not publication. There is no staging or pre-publish review inside OSM; any review gate Steward offers must happen before step ④.

---

## 2. Full representation — what this actually means for a one-field edit

### The rule

`PUT /api/0.6/way/{id}` (or the equivalent `<modify>` block in a diff upload) replaces the element wholesale. The payload must carry:

- `id` — matching the URL
- `version` — the **exact** current version in the database, or you get `409 Conflict`
- `changeset` — an open changeset owned by the authenticated user
- **every** `<nd ref>` in original order
- **every** `<tag>`, including the ~15 you aren't touching

Omit a tag and it's gone. Omit an `nd` and the geometry changes. There is no way to say "set `surface=dirt` and leave everything else alone."

### The consequence: fetch at submit time, not at form-open time

The single biggest correctness hazard in Steward is a **stale read**. If a user opens the "set difficulty" form at 10:00, goes to lunch, and submits at 11:30, and someone edited that way at 10:45, you will either get a 409 (good) or — if you cached the body and blindly reused a stale version number — you'd be attempting to resurrect deleted tags (bad).

**Implementation rule:**

> Never cache element bodies across the user-interaction boundary. Re-`GET` every element immediately before building the diff. The version number and the tag set must come from the same read.

Use `GET /api/0.6/ways?ways=1,2,3` (multi-fetch) to pull a batch in one round trip right before submitting.

### Worked example

A user sets `surface=ground` on a 40-node Galbraith way that already has 11 tags.

**Step ② — read:**
```xml
<osm version="0.6">
  <way id="123456789" version="7" changeset="98765432" timestamp="2025-04-11T18:22:03Z">
    <nd ref="1000000001"/>
    <nd ref="1000000002"/>
    <!-- ... 37 more, in order ... -->
    <nd ref="1000000040"/>
    <tag k="highway" v="path"/>
    <tag k="name" v="Evolution"/>
    <tag k="bicycle" v="designated"/>
    <tag k="foot" v="yes"/>
    <tag k="horse" v="no"/>
    <tag k="mtb:scale" v="2"/>
    <tag k="mtb:scale:imba" v="2"/>
    <tag k="oneway:bicycle" v="yes"/>
    <tag k="width" v="0.6"/>
    <tag k="operator" v="Whatcom Mountain Bike Coalition"/>
    <tag k="ref:wmbc" v="GAL-0142"/>
  </way>
</osm>
```

**Step ④ — upload.** Note the version echoed as `7`, the full `nd` list reproduced, all 11 original tags reproduced, one tag added, and a `check_date:surface` recording the verification:

```xml
<osmChange version="0.6" generator="Slab Steward 1.4.2">
  <modify>
    <way id="123456789" version="7" changeset="112233445">
      <nd ref="1000000001"/>
      <nd ref="1000000002"/>
      <!-- ... all 40, unchanged, in original order ... -->
      <nd ref="1000000040"/>
      <tag k="highway" v="path"/>
      <tag k="name" v="Evolution"/>
      <tag k="bicycle" v="designated"/>
      <tag k="foot" v="yes"/>
      <tag k="horse" v="no"/>
      <tag k="mtb:scale" v="2"/>
      <tag k="mtb:scale:imba" v="2"/>
      <tag k="oneway:bicycle" v="yes"/>
      <tag k="width" v="0.6"/>
      <tag k="operator" v="Whatcom Mountain Bike Coalition"/>
      <tag k="ref:wmbc" v="GAL-0142"/>
      <tag k="surface" v="ground"/>
      <tag k="check_date:surface" v="2026-08-23"/>
    </way>
  </modify>
</osmChange>
```

**Response:**
```xml
<diffResult version="0.6" generator="OpenStreetMap server">
  <way old_id="123456789" new_id="123456789" new_version="8"/>
</diffResult>
```

### Diff upload vs. per-element PUT

Use **`POST /api/0.6/changeset/{id}/upload`**, not individual PUTs.

| | Diff upload | Per-element PUT |
|---|---|---|
| Atomicity | **Guaranteed transaction** — all changes apply or none | Each element independent; partial failure leaves inconsistent state |
| Round trips | One per batch | One per element |
| Rate-limit pressure | Lower | Higher |
| Conflict reporting | Whole batch rejected on any 409 | Per-element |

The all-or-nothing property is what you want for a bulk attribute editor: a user selecting 40 trails and setting `surface` on all of them should not end up with 23 done and 17 not.

Each element inside the diff still needs its own `changeset` and `version` attributes.

---

## 3. Node lists in detail

**Ways.** The `<nd>` list *is* the geometry. It must be complete and ordered. Reversing it reverses the way (which flips the meaning of `oneway`, `incline`, `mtb:scale:uphill`). Since Steward is metadata-only:

- Treat the `nd` block as an **opaque blob** — copy it from the read response into the write payload without touching it.
- Never sort, dedupe, or "clean" it. Duplicate consecutive refs are unusual but legal in edge cases and are not yours to fix.
- **Ceiling: 2,000 nodes per way.** You won't hit it on a trail, but validate rather than assume when handling imported agency data.
- You do **not** send node elements. Only the refs. The nodes stay untouched and their versions are irrelevant to your write.
- `412 Precondition Failed` means a referenced node is missing or invisible — usually a stale read against a way that was edited concurrently.

**Relations.** Same rule for `<member>` entries, but Steward mostly won't be writing relations. Be aware that named trails are frequently modelled as `type=route` relations over multiple ways: a name change the user thinks is "one field on one trail" may actually live on a relation, and the constituent ways may carry their own names. Resolve which object owns the attribute *before* presenting the form, or you'll write the right value to the wrong object.

**Way splits are your real geometry problem.** Another mapper splits "Evolution" at a junction; way `123456789` keeps its ID but now covers half the trail, and a new way holds the rest. Nothing errors. Your next edit silently applies to half a trail. This is exactly what the `ref:wmbc=GAL-0142` anchor solves — split segments inherit tags, so the ref survives and re-matching is a lookup rather than a geometry problem.

---

## 4. Conflicts and errors

| Code | Meaning | Steward should |
|---|---|---|
| **409 Conflict** | Version mismatch, or changeset closed / not yours | Re-fetch. If the other edit **didn't touch your key**, auto-retry silently. If it **did**, stop and show the user both values. |
| **404 Not Found** | Element deleted, or version redacted | Element is gone — send to the re-match queue, don't retry |
| **412 Precondition Failed** | Referenced node/member missing or invisible | Stale read — re-fetch and rebuild the diff once, then escalate |
| **400 Bad Request** | Malformed XML, missing changeset id, out-of-bounds node | Bug in Steward. Log loudly, never retry blind. |
| **429 Too Many Requests** | Rate limited | Exponential backoff; surface a "queued" state, don't fail the user's edit |

**The auto-merge rule is worth building properly.** Because Steward writes exactly one attribute per edit, conflict resolution is unusually tractable: diff the old and new server states, and if the intersection with your changed key is empty, the merge is safe. This turns most 409s into invisible retries instead of user-facing errors, which matters a lot for a volunteer board member's confidence in the tool.

Cap retries at 2–3 and add jitter. A conflict loop against a busy area is how you get a DWG email.

---

## 5. Changeset composition

### Hard limits

| Limit | Value |
|---|---|
| Elements per changeset | **10,000** |
| Max open duration | **24 hours** |
| Idle auto-close | **1 hour** with no API activity |
| Tag key / value length | **255 UTF-8 codepoints each** (changeset tags included) |
| Nodes per way | 2,000 |
| Relation members | 32,000 |
| Server request timeout | 300 s |

**A closed changeset is immutable — including its comment.** You cannot fix a typo in a changeset comment after the fact. This makes the comment-generation step worth getting right, and worth showing the user before submit.

### Rate limits

Edits are rate-limited per user, and the configured values on osm.org are:

| Setting | Value |
|---|---|
| `min_changes_per_hour` | 100 |
| `initial_changes_per_hour` | 1,000 |
| `max_changes_per_hour` | 100,000 |
| `days_to_max_changes` | 7 |
| `max_changeset_comments_per_hour` | 60 |

The allowance ramps with account standing over roughly a week, and is reduced for accounts with active reports. **This matters more for Steward than for most tools**, because you will be onboarding brand-new OSM accounts — a trail director who signed up this morning has the lowest allowance in the system, and a first session that bulk-edits 300 trails is exactly the shape that trips it. Design the submit queue to absorb 429s gracefully and consider throttling first-week accounts below the limit rather than discovering it.

### Batching policy

Neither extreme works:

- **One changeset per field edit** → thousands of one-element changesets, unreadable history, community irritation.
- **One changeset per week** → an enormous bounding box, impossible to review, and an all-or-nothing revert target.

**Recommended:** one changeset per *user session, per region, per intent*. A trail director filling in missing `surface` values across Galbraith in one sitting = one changeset, ~50 ways, comment `Added surface for 47 trails at Galbraith Mountain from field survey #slabsteward`. Close it explicitly when the session ends rather than letting it idle out.

Keep changesets geographically tight. The bounding box is drawn from the two farthest-apart edited objects, so a session that touches Galbraith and Chuckanut produces a box covering everything in between — which clutters every reviewer's filter in Whatcom County and is a common source of unearned suspicion.

---

## 6. Changeset tags for Steward

### Required

| Tag | Value | Notes |
|---|---|---|
| `created_by` | `Slab Steward 1.4.2` | **The attribution channel.** Convention is `Name Version` or `Name/Version`. Bump on release. |
| `comment` | human-meaningful sentence | Must have a verb and an object. Generated by Steward, **editable by the user before submit.** |
| `hashtags` | `#slabsteward` | Semicolon-delimited if multiple. Also mirror in the comment text. |
| `source` | `survey` / `local knowledge` / `operator records` | Where the *value* came from — this is the provenance gate's output, not a formality. |

### Recommended

| Tag | Value |
|---|---|
| `host` | `https://steward.slab.app` |
| `locale` | user's UI language, e.g. `en-US` |
| `review_requested` | `yes` **only** when genuinely uncertain — not by default |

### Do *not* set

- **`bot=yes` / `mechanical=yes`** — these are human-confirmed edits under your P0 constraints, and mislabelling them invites reverts. (See §8 for where the line actually sits.)
- Auto-generated comment strings like `BBOX:... ADD:0 UPD:47 DEL:0` — explicitly called out as bad practice.

### Comment templates

Good comments name the action, the object, the place, and the source:

```
Set surface on 47 trails at Galbraith Mountain from WMBC field survey #slabsteward
Corrected mtb:scale:imba on Evolution to match new trailhead signage #slabsteward
Marked 12 social trails at Blanchard as informal=yes per DNR guidance #slabsteward
```

Avoid: `update`, `fix`, `.`, `Slab Steward edit`, and anything mentioning intent without content.

### Custom `slab:*` changeset tags — safe and recommended

Changeset tags are free-form and unvalidated. There is clear precedent for tool-specific namespaces. These give you queryable telemetry and audit trail without touching map data:

```
slab:region          = wmbc-galbraith
slab:org             = Whatcom Mountain Bike Coalition
slab:workflow        = bulk-attribute
slab:profile         = mtb-pnw-v1
slab:attribute       = surface
slab:provenance      = field-survey
slab:review_stage    = approved-by-region-admin
```

Two things this buys you cheaply: OSMCha filtering by `slab:region` when investigating a complaint, and a defensible audit record when an association asks "who changed that, and under what authority?"

Keep them short and don't put anything in them a mapper would consider surveillance — changesets are public forever.

---

## 7. Attribution — how Steward gets named

There are three channels, and only one of them is authoritative.

**1. `created_by` — the real one.** This is what shows in the changeset details on osm.org, what OSMCha displays, what planet-file analytics aggregate, and what people mean when they say "which editor made this edit." Set it on every changeset. Nothing else substitutes for it.

**2. `hashtags` — the campaign one.** `#slabsteward` makes the full corpus of Steward edits queryable in OSMCha and hashtag dashboards. This is how you'll produce "here is everything our tool has done in Whatcom County" for the OEG wiki page, for a grant report, and for the OSM US conversation. Add a per-association hashtag too if it helps them report to their board.

**3. The OAuth application — not a public attribution channel.** Registering "Slab Steward" as an OAuth app makes it appear in the user's authorized-applications list and is required for the write path, but the changeset record does **not** publicly expose which OAuth client produced it. Don't rely on it for credit; rely on `created_by`.

**And the username stays the human's.** Each association member authenticates with their own OSM account, and their edits accrue to their own edit history and standing. This is:

- what the Organised Editing Guidelines expect,
- what makes the edits defensible in a changeset discussion (a real person can answer),
- and a genuine benefit you can sell — the association's people build real OSM standing rather than hiding behind a vendor.

A shared `slab_steward_bot` account writing on everyone's behalf would be a fast route to a DWG block. Don't.

**One more OEG obligation:** participating contributors' OSM profile pages should link to the organised-editing activity wiki page. Steward should prompt for this at onboarding — it's a one-line profile edit and it heads off most "who is this account and why is it editing my area" questions.

---

## 8. Custom tags on map elements

### The principle

"Any tags you like" is real: **you may invent tags for verifiable, mappable features without approval.** No proposal is required, and proposals don't guarantee adoption anyway.

### The constraints that actually bind

- Don't ignore an existing convention because it's inconvenient.
- Don't redefine an existing key unilaterally.
- Don't tag for the renderer — misusing a tag to force a display outcome in AllTrails or Gaia is the single fastest way to lose community standing, and it is precisely the temptation your display-policy strategy creates. **Resist it.** Tag reality; work the rendering problem through the app developers and the Trails Working Group.
- Only map geographic reality. No subjective ratings, no hypothetical features, no private information.

### What's safe for Steward to write

| Pattern | Status | Use |
|---|---|---|
| `ref:<operator>` e.g. `ref:wmbc=GAL-0142` | **Conventional and legitimate** | Your stable anchor. An operator's own reference number is verifiable and useful, and it survives way splits. |
| `operator`, `operator:type` | Standard | Association ownership |
| `check_date=YYYY-MM-DD` | Standard | Whole-object re-verification |
| `check_date:<key>=YYYY-MM-DD` | Standard | **Best fit for Steward's model** — see below |
| `informal`, `access`, `access:conditional` | Standard | Sanction status |
| Lifecycle prefixes (`disused:`, `not:`) | Standard | Decayed or phantom trails |

**`check_date:<key>` deserves emphasis.** It records that *one attribute* was re-verified on a date, without implying the whole trail was surveyed. That is an exact structural match for a product where users edit single fields. Writing `check_date:surface=2026-08-23` alongside `surface=ground` gives you a per-attribute freshness signal that feeds your completeness scorecard directly, and it's honest in a way a bare `check_date` would not be.

### What's not safe

| Pattern | Why not |
|---|---|
| `slab:*` on ways/nodes | Vendor namespace on map objects reads as pollution. Fine on changesets, not on elements. |
| `slab:flow`, `fun_factor`, `slab:calibrated_difficulty` | Subjective — fails verifiability. → SLAB Commons. |
| Conditions, closures, work logs, galleries | Temporal or organisational, structurally excluded from OSM. → SLAB Commons. |
| Anything Steward needs but the ground doesn't have | If a mapper standing at the trailhead couldn't confirm it, it isn't OSM data. |

### If you genuinely need a new tag

The sequence, in order:

1. Check taginfo and the wiki — someone has probably tried already (`mtb:type` was proposed and never approved; `mtb:scale` is contested).
2. Use it in real edits, namespaced sensibly, lowercase with underscores, colons for namespacing.
3. Document it on the OSM wiki. This is where a vendor-built tool earns or loses credibility.
4. Raise it in the community forum **and** the OSM US Trails Working Group before doing it at scale.
5. Formal proposal only if it's broadly interesting or changes an existing key's meaning.

Given SLAB's position, steps 3 and 4 are not optional overhead — they're the difference between "the tool that helped standardise MTB tagging" and "the startup that sprayed proprietary keys across US trail data."

---

## Sources

- [API v0.6 — OpenStreetMap Wiki](https://wiki.openstreetmap.org/wiki/API_v0.6)
- [Changeset — OpenStreetMap Wiki](https://wiki.openstreetmap.org/wiki/Changeset)
- [Good changeset comments — OpenStreetMap Wiki](https://wiki.openstreetmap.org/wiki/Good_changeset_comments)
- [Organised Editing Guidelines — OSM Foundation](https://osmfoundation.org/wiki/Organised_Editing_Guidelines)
- [Organised Editing Guidelines — OpenStreetMap Wiki](https://wiki.openstreetmap.org/wiki/Organised_Editing_Guidelines)
- [Automated Edits code of conduct — OpenStreetMap Wiki](https://wiki.openstreetmap.org/wiki/Automated_Edits_code_of_conduct)
- [Any tags you like — OpenStreetMap Wiki](https://wiki.openstreetmap.org/wiki/Any_tags_you_like)
- [Tagging for the renderer — OpenStreetMap Wiki](https://wiki.openstreetmap.org/wiki/Tagging_for_the_renderer)
- [Key:check_date — OpenStreetMap Wiki](https://wiki.openstreetmap.org/wiki/Key:check_date)
- [OAuth — OpenStreetMap Wiki](https://wiki.openstreetmap.org/wiki/OAuth)
- [Error 429 — OpenStreetMap Wiki](https://wiki.openstreetmap.org/wiki/Error_429)
- [openstreetmap-website `config/settings.yml`](https://github.com/openstreetmap/openstreetmap-website/blob/master/config/settings.yml)
- [Report rate limit settings in capabilities API call — issue #4380](https://github.com/openstreetmap/openstreetmap-website/issues/4380)
- [osmlab/osm-api-js](https://github.com/osmlab/osm-api-js/blob/main/README.md)
