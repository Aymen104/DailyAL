#!/usr/bin/env python3
"""Re-pin the bundled AnimeX next-broadcast snapshot against AniList.

`assets/animex_meta.json` freezes ONE upcoming broadcast per airing title at
build time, because MAL's API exposes no schedule at all -- only a weekly
`broadcast` string like "Sundays at 17:00". A frozen broadcast is correct only
on the day it was scraped: the countdown code projects the weekly slot forward,
but a delayed airing, a split cour or a finished run makes that projection
invent both the date and the episode number.

This tool asks AniList for the same field today and rewrites only the three keys
that describe the schedule:

    na  next airing time, epoch seconds (UTC)
    ne  the episode number that airs at `na`
    st  airing status (RELEASING / FINISHED / NOT_YET_RELEASED / CANCELLED)

Every other key -- banner, backdrop, dominant colour, popularity, score,
AniList id -- is carried through byte for byte, so the diff of the asset is
only the schedule. A title AniList no longer schedules (finished, cancelled,
hiatus) has `na`/`ne` removed, which is what makes the app fall back to MAL's
vague-but-true weekly string instead of counting down to an episode that aired
weeks ago.

Selection matches the app's own refresh rule (`AnimeXAiringLive.selectIds`):
titles that carry an anchor, plus everything currently RELEASING.

Usage:
    python tool/sync_animex_airing.py            # report only, no writes
    python tool/sync_animex_airing.py --write     # rewrite the asset
"""

from __future__ import annotations

import argparse
import datetime as _dt
import json
import os
import sys
import time
import urllib.error
import urllib.request

ASSET = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                     "assets", "animex_meta.json")
ENDPOINT = "https://graphql.anilist.co"
CHUNK = 50
QUERY = (
    "query($ids:[Int]){Page(page:1,perPage:50){media(type:ANIME,idMal_in:$ids){"
    "idMal status episodes nextAiringEpisode{airingAt episode}}}}"
)
SCHEDULED_STATUSES = ("RELEASING",)


def post(body: dict, attempts: int = 4) -> dict:
    payload = json.dumps(body).encode("utf-8")
    last = None
    for n in range(attempts):
        req = urllib.request.Request(
            ENDPOINT,
            data=payload,
            headers={
                "Content-Type": "application/json",
                "Accept": "application/json",
                # AniList's edge answers 403 to urllib's default UA.
                "User-Agent": "DailyAL-animex-sync/1.0",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=45) as r:
                return json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            last = e
            # AniList answers 429 when the minute budget is spent; honour Retry-After.
            wait = int(e.headers.get("Retry-After") or (2 * (n + 1)))
            if e.code in (429, 500, 502, 503, 504) and n + 1 < attempts:
                print("  http %s, retrying in %ss" % (e.code, wait), file=sys.stderr)
                time.sleep(min(wait, 30))
                continue
            raise
        except Exception as e:  # noqa: BLE001 - network shape varies
            last = e
            if n + 1 < attempts:
                time.sleep(2 * (n + 1))
                continue
            raise
    raise RuntimeError("anilist request failed: %s" % last)


def select_ids(asset: dict) -> list[int]:
    out = []
    for key, row in asset.items():
        if row.get("na") is not None or row.get("st") in SCHEDULED_STATUSES:
            try:
                out.append(int(key))
            except (TypeError, ValueError):
                continue
    return sorted(out)


def fetch_live(ids: list[int]) -> dict:
    live = {}
    for start in range(0, len(ids), CHUNK):
        chunk = ids[start:start + CHUNK]
        data = post({"query": QUERY, "variables": {"ids": chunk}})
        errors = data.get("errors")
        if errors:
            raise RuntimeError("anilist error: %s" % errors)
        for media in data["data"]["Page"]["media"]:
            mal = media.get("idMal")
            if mal:
                live[int(mal)] = media
        print("  fetched %d/%d" % (min(start + CHUNK, len(ids)), len(ids)))
    return live


def stamp(epoch) -> str:
    if not epoch:
        return "-"
    return _dt.datetime.fromtimestamp(int(epoch), _dt.timezone.utc).strftime(
        "%Y-%m-%d %H:%M")


def apply(asset: dict, live: dict) -> dict:
    """Rewrites na/ne/st in place. Returns a summary of what moved."""
    stats = {"dated": 0, "moved": 0, "cleared": 0, "status": 0, "missing": 0}
    changes = []
    for mal, media in live.items():
        row = asset.get(str(mal))
        if row is None:
            stats["missing"] += 1
            continue
        new_status = media.get("status")
        if new_status and row.get("st") != new_status:
            stats["status"] += 1
            row["st"] = new_status
        next_ep = media.get("nextAiringEpisode")
        old_na, old_ne = row.get("na"), row.get("ne")
        if next_ep and next_ep.get("airingAt"):
            na, ne = int(next_ep["airingAt"]), next_ep.get("episode")
            if old_na != na or old_ne != ne:
                stats["moved"] += 1 if old_na is not None else 0
                stats["dated"] += 1 if old_na is None else 0
                changes.append((mal, old_na, old_ne, na, ne))
            row["na"] = na
            if ne is not None:
                row["ne"] = int(ne)
        elif old_na is not None:
            # AniList schedules nothing for this title any more. Keeping the old
            # anchor is exactly the bug this tool exists to remove.
            stats["cleared"] += 1
            changes.append((mal, old_na, old_ne, None, None))
            row.pop("na", None)
            row.pop("ne", None)
    return {"stats": stats, "changes": changes}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--write", action="store_true",
                    help="rewrite assets/animex_meta.json (default is report only)")
    ap.add_argument("--limit", type=int, default=0,
                    help="only report the first N changes")
    args = ap.parse_args()

    with open(ASSET, encoding="utf-8") as f:
        asset = json.load(f)
    ids = select_ids(asset)
    print("asset rows: %d | schedule-relevant ids: %d" % (len(asset), len(ids)))

    live = fetch_live(ids)
    print("live rows: %d" % len(live))

    result = apply(asset, live)
    s = result["stats"]
    print("dated new: %d | moved: %d | cleared: %d | status changed: %d | not in asset: %d"
          % (s["dated"], s["moved"], s["cleared"], s["status"], s["missing"]))

    shown = result["changes"] if args.limit <= 0 else result["changes"][:args.limit]
    for mal, old_na, old_ne, na, ne in shown:
        print("  %-7s %s EP%s  ->  %s EP%s" % (
            mal, stamp(old_na), old_ne, stamp(na), ne))

    if not args.write:
        print("dry run - pass --write to update the asset")
        return 0

    text = json.dumps(asset, ensure_ascii=False, separators=(",", ":"))
    tmp = ASSET + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="") as f:
        f.write(text)
    if os.path.getsize(tmp) < 1000000:
        os.remove(tmp)
        print("refusing to install a suspiciously small asset", file=sys.stderr)
        return 1
    os.replace(tmp, ASSET)
    print("wrote %s (%d bytes)" % (ASSET, os.path.getsize(ASSET)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
