# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""What SLAB Steward has actually put into OpenStreetMap.

Three numbers, per docs/specs/analytics.md §5: how many changesets carry the
campaign hashtag, how many distinct people made them, and how many trail edits
they add up to. Deliberately *not* distinct trails — that would need one
`/changeset/{id}/download` per changeset against a courtesy-limited public API,
for a figure less useful than the edit count when the question is "how much is
this being used".

Read the numbers in `impact.ipynb` next door, which imports this module rather
than restating it — there is one implementation, and the notebook is a view onto
it. This file also stands alone:

    uv run tool/impact/impact.py
    uv run tool/impact/impact.py --json      # for a dashboard to consume

    cd tool/impact && uv run --with jupyter jupyter lab    # the notebook

No dependencies and no project files: `uv` fetches its own interpreter, so this
adds no global Python install to a repo that is otherwise entirely Dart.

Why OSMCha rather than the OSM API: `changesets.json` accepts a `hashtag`
parameter and silently ignores it, returning everything. There is no way to ask
OpenStreetMap itself "every changeset with this hashtag, across all users".

Two things about OSMCha's own API, both found the hard way and both load-bearing:

1. **Its `hashtags` filter is silently ignored too** — the identical failure
   mode. Verified 2026-08-30: `hashtags=slabsteward`, `hashtags=%23slabsteward`
   and `hashtags=zzznonexistentzzz` all return the same unfiltered count. The
   filter that *works* is `editor`, matching the `created_by` tag Steward
   stamps on every changeset. The hashtag is then re-checked here, client-side.
2. **The query cost scales with the date window, steeply.** Measured 2026-08-30:
   a floor of 2026-08-29 answers in 0.4s, 2026-08-25 in 9s, and 2026-01-01 or no
   floor at all both hang past 150s. `--since` is therefore mandatory rather than
   an optimisation, and defaults to the day Steward went live. Widening it will
   get slow long before it gets useful.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

VAULT = Path(__file__).resolve().parents[2] / "secrets" / "vault.env"
OSMCHA = "https://osmcha.org/api/v1/changesets/"
PAGE_SIZE = 100

# The `created_by` value Steward stamps on every changeset, minus the version
# suffix — OSMCha's `editor` filter matches on substring, so this catches
# `SLAB Steward/0.1.0` and every version after it.
EDITOR = "SLAB Steward"

# The day `osmEnvironment` was flipped to `OsmEnvironment.live`. Nothing Steward
# did before this reached OpenStreetMap, so there is nothing earlier to count,
# and asking for it only makes OSMCha scan further for no reason.
WENT_LIVE = "2026-08-29"

# A page count that would mean something has gone wrong — a runaway loop
# against someone else's server is the one failure worth refusing outright.
MAX_PAGES = 200


def vault_get(key: str) -> str | None:
    """Reads one `KEY: value` line, tolerating `KEY=value`, quotes and spaces.

    Same shape as `tool/run.sh`'s reader, and the same file: one gitignored
    place for the project's per-deployment ids, not a second one because a
    second language showed up.
    """
    if not VAULT.exists():
        return None
    pattern = re.compile(rf"^\s*{re.escape(key)}\s*[:=]\s*[\"']?([^\"'\s]+)")
    for line in VAULT.read_text().splitlines():
        if match := pattern.match(line):
            return match.group(1)
    return None


def fetch_changesets(token: str, since: str) -> list[dict]:
    """Every Steward changeset OSMCha holds since `since`, page by page."""
    features: list[dict] = []
    for page in range(1, MAX_PAGES + 1):
        query = urllib.parse.urlencode(
            {
                "editor": EDITOR,
                "date__gte": since,
                "page_size": PAGE_SIZE,
                "page": page,
            }
        )
        request = urllib.request.Request(
            f"{OSMCHA}?{query}",
            # OSMCha wants "Token", not "Bearer" — a Bearer header reads to it
            # as no credentials at all.
            headers={"Authorization": f"Token {token}"},
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                body = json.load(response)
        except urllib.error.HTTPError as error:
            if error.code == 401:
                sys.exit(
                    "OSMCha rejected the token.\n"
                    f"Check OSMCHA_API_KEY in {VAULT} — sign in at "
                    "https://osmcha.org with your OSM account and copy the "
                    "API token from your profile page."
                )
            sys.exit(f"OSMCha returned {error.code}: {error.reason}")

        batch = body.get("features", [])
        features.extend(batch)
        if not body.get("next") or not batch:
            break
    return features


def carries_hashtag(properties: dict, hashtag: str) -> bool:
    """Whether one changeset really is a campaign changeset.

    OSMCha's `editor` filter is a substring match, so this is what stops a
    future tool called "SLAB Stewardship" from being counted as Steward. Checks
    the `hashtags` metadata *and* the comment, exactly as `OsmApi
    ._carriesHashtag` does on the Dart side — `SubmissionGate.ensureHashtag`
    guarantees the comment carries it either way.
    """
    wanted = hashtag.lower().lstrip("#")
    metadata = properties.get("metadata") or {}
    tagged = metadata.get("hashtags")
    if isinstance(tagged, str):
        if any(entry.strip().lower().lstrip("#") == wanted for entry in tagged.split(";")):
            return True
    comment = properties.get("comment")
    if isinstance(comment, str):
        return re.search(rf"#{re.escape(wanted)}\b", comment, re.IGNORECASE) is not None
    return False


def edit_count(properties: dict) -> int:
    """How many elements one changeset touched.

    OSMCha reports a create/modify/delete breakdown rather than a total, so this
    sums it. Steward is metadata-only and never creates or deletes, so in
    practice this is the modify count — and if `create` or `delete` is ever
    non-zero for a Steward changeset, something is very wrong.
    """
    if isinstance(total := properties.get("changes_count"), int):
        return total
    return sum(
        value
        for key in ("create", "modify", "delete")
        if isinstance(value := properties.get(key), int)
    )


def summarise(features: list[dict], hashtag: str) -> dict:
    contributors = {
        uid
        for feature in features
        if (uid := feature.get("properties", {}).get("uid")) is not None
    }
    dates = sorted(
        date
        for feature in features
        if (date := feature.get("properties", {}).get("date"))
    )
    return {
        "hashtag": hashtag,
        "changesets": len(features),
        "contributors": len(contributors),
        "trail_edits": sum(
            edit_count(feature.get("properties", {})) for feature in features
        ),
        "first_edit": dates[0] if dates else None,
        "last_edit": dates[-1] if dates else None,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hashtag", default="slabsteward")
    parser.add_argument(
        "--since",
        default=WENT_LIVE,
        metavar="YYYY-MM-DD",
        help=f"date floor for the OSMCha query (default {WENT_LIVE}, the day "
        "Steward went live). Not optional in practice — an unbounded query "
        "never returns.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="emit the summary as JSON rather than prose",
    )
    parser.add_argument(
        "--debug-properties",
        action="store_true",
        help="print the property keys of the first changeset and stop — for "
        "when OSMCha's response shape has moved",
    )
    args = parser.parse_args()

    token = vault_get("OSMCHA_API_KEY")
    if not token:
        sys.exit(
            f"OSMCHA_API_KEY is missing or empty in {VAULT}.\n"
            "Sign in at https://osmcha.org with your OSM account and copy the "
            "API token from your profile page."
        )

    features = fetch_changesets(token, args.since)
    features = [
        feature
        for feature in features
        if carries_hashtag(feature.get("properties", {}), args.hashtag)
    ]

    if args.debug_properties:
        if not features:
            sys.exit("No changesets came back, so there is nothing to inspect.")
        print(sorted(features[0].get("properties", {})))
        return

    summary = summarise(features, args.hashtag)
    summary["since"] = args.since

    if args.json:
        print(json.dumps(summary, indent=2))
        return

    if not summary["changesets"]:
        print(f"No changesets tagged #{args.hashtag} yet.")
        return

    print(f"SLAB Steward — #{args.hashtag}")
    print(f"  changesets   {summary['changesets']}")
    print(f"  contributors {summary['contributors']}")
    # Named "trail edits" rather than "trails", on purpose: a trail rated today
    # and given a surface next week counts twice.
    print(f"  trail edits  {summary['trail_edits']}")
    print(f"  first edit   {summary['first_edit']}")
    print(f"  last edit    {summary['last_edit']}")
    print(f"  since        {summary['since']}")


if __name__ == "__main__":
    main()
