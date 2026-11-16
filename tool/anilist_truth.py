"""Ground truth for the schedule: what AniList actually says right now.

Mirrors the app's own query (lib/animex/animex_live.dart _query) so the numbers
are directly comparable with what the device renders.
"""
import datetime
import json
import sys
import urllib.request

QUERY = (
    'query($ids:[Int]){Page(page:1,perPage:50){'
    'media(type:ANIME,idMal_in:$ids){'
    'idMal status episodes title{romaji english} nextAiringEpisode{airingAt episode}'
    '}}}'
)
# Default ids are the two the schedule bug was proved on. Extra ids may be passed
# as argv so a device dump can be reconciled title by title.
ids = [int(a) for a in sys.argv[1:]] or [64084, 61999]

body = json.dumps({"query": QUERY, "variables": {"ids": ids}}).encode()
# AniList fronted by Cloudflare answers 403 to Python's default UA but accepts
# the UA the app itself sends (dart:io), so this mirrors the real client instead
# of proving something the app can never reproduce.
req = urllib.request.Request(
    "https://graphql.anilist.co",
    data=body,
    headers={
        "Content-Type": "application/json",
        "Accept": "application/json",
        "User-Agent": "Dart/3.13 (dart:io)",
    },
)
payload = json.load(urllib.request.urlopen(req, timeout=30))

now = datetime.datetime.now(datetime.timezone.utc)
rows = []
for media in payload["data"]["Page"]["media"]:
    nxt = media["nextAiringEpisode"]
    if not nxt:
        title = (media.get("title") or {}).get("romaji") or "?"
        print(f"{media['idMal']:>7} {media['status']:<12} {title[:40]:<40} no next episode")
        continue
    at = datetime.datetime.fromtimestamp(nxt["airingAt"], datetime.timezone.utc)
    secs = int((at - now).total_seconds())
    hours, rem = divmod(secs, 3600)
    days, hours = divmod(hours, 24)
    label = f"Ep {nxt['episode']} in {days}d-{hours:02d}h-{rem // 60:02d}m"
    rows.append(
        {
            "malId": media["idMal"],
            "status": media["status"],
            "title": (media.get("title") or {}).get("romaji"),
            "episode": nxt["episode"],
            "airingAt": at.isoformat(),
            "epoch": nxt["airingAt"],
            "label": label,
        }
    )
    title = (media.get("title") or {}).get("romaji") or "?"
    print(f"{media['idMal']:>7} {media['status']:<12} {label:<26} {title[:38]}")

print("now", now.strftime("%Y-%m-%d %H:%M:%S UTC"))
out = sys.argv[0].replace(".py", "-out.json")
with open(out, "w", encoding="utf-8") as fh:
    json.dump({"now": now.isoformat(), "rows": rows}, fh, indent=2)
print("wrote", out)
