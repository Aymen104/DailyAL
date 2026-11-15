# DailyAL release predictions: root cause, measured on device

User report: "the release date and episode is off in DailyAL" → "it should point
at ep 21 sometime in next week and the other series prediction release are off".

## What the device actually has

`adb -s emulator-5554 pull /data/data/io.github.jica98/shared_prefs/FlutterSharedPreferences.xml`
gives the app's own caches. The Tenrai (Jikan v4) schedule pages that
`_getScheduleForMalIdsFromTenrai` consumed are in there verbatim. For the title
in question:

```
mal_id  59741  "Tsuihou sareta Tensei Juukishi wa Game Chishiki de Musou suru"
episodes        26
status          Currently Airing
aired           Jul 3, 2026 to ?
broadcast       Fridays at 00:26 (JST)     <- the ONLY slot information Jikan gives
```

AniList, the same public endpoint the app already trusts for the airing label:

```
idMal 59741 / status RELEASING / episodes 26
startDate 2026-07-03, endDate 2026-12-25
nextAiringEpisode episode 21, airingAt 1795101960 = 2026-11-20 03:39 JST (Friday)
```

The app showed **"Ep 20 in 05d 01h 22m"** (emulator, old build) — one episode and
one week behind the truth.

## Why the prediction drifts

`DalApi._scheduleDataFromTenrai` (lib/api/dalapi.dart) has no schedule from MAL:
Jikan only reports a weekly weekday/time. So it derives both numbers:

* `weeks = whole weeks since the premiere slot` (Fridays 00:26 JST from 2026-07-03)
* `episode = 1 + weeks`
* `next = the next occurrence of that weekly slot`

19 weeks after 2026-07-03 is 2026-11-13, so it says "the next episode is 20, airing
next Friday". The real run skipped one week (ep 20 aired 2026-11-13), so the
derivation is permanently offset by one and keeps counting down to an episode
that already aired. Every title that ever skipped a week, moved its slot, or
premiered mid-week is off in the same way — which is exactly "the other series
prediction release are off".

A second, independent defect found in the same cache: Jikan page 3 of
`/schedules` was fetched as an error page and **that non-JSON body was cached**
(keys `flutter.https://api.tenrai.org/v1/schedules?sfw=false&page=3` and
`...&fromCache=true`), so one page of titles silently has no prediction at all
until the cache expires. Fixed in `_getScheduleForMalIdsFromTenrai`: a page that
comes back null is now retried once before its titles are dropped (`worker()`).

## The fix

1. **`AnimeXAiringLive.reconcileSchedules(base)`** (lib/animex/animex_live.dart)
   re-spells the projected map with AniList's reading, keyed by MAL id:
   live upcoming episode → that timestamp + episode number; live "nothing
   scheduled" → the row is dropped (the run is over, do not count down to the
   episode that just aired); no live reading → the projection is kept.
2. **`DalApi.scheduleForMalIdsSync`** and **`scheduleForMalIds`** reconcile at
   read time, and `DalApi.reapplyAiringToSchedules()` is registered on
   `AnimeXService.onOverlayChanged` so a fetch that lands *after* a screen has
   already read the map re-derives it and pokes `scheduleVersion`, which the two
   one-time readers (the detail page banner, the calendar editor) listen to.
3. The derived map is written back to the Tenrai cache, so a cold start does not
   have to wait for the overlay.

Tests: `test/schedule_reconcile_test.dart` (9 cases: authority of the live
reading, dropping an unscheduled run, `relatedLinks` pass-through, no input
mutation, live episode past the announced total, and the end-to-end case where
MAL 59741's row becomes episode 21 at the AniList slot and the card label reads
"EP 21").

## Second bug found while verifying: the profile's distributions are empty

User report: "score distribution , genre distribution , media ,source , studio
distribution have no data".

Same symptom class ("a screen silently renders nothing"), different cause: the
profile stats screen was requesting **`users//animelist`** -- an *empty*
username. The phone's own log shows it:

```
Cache ->> https://api.myanimelist.net/v2/users//animelist?fields=...&limit=1000
API   ->> https://api.myanimelist.net/v2/users//animelist?fields=...&limit=1000
```

`UserProfService.userProf` is a `Future`, so `UserPopSlideOpenPage._username`
resolved to `''` long enough for the first build to hand that empty string to
`UserStatsScreen`, which read a 404 into `UserInsights([])` -> every map empty
-> "No enough data to generate the graph".

Fix:
* `_username` now falls back to the already-cached signed-in profile
  (`UserProfService.userProfSync`, a new synchronous field) and finally `@me`,
  and the screen rebuilds when the profile future resolves.
* `UserStatsScreen.didUpdateWidget` re-reads the list when a real name arrives,
  so a first frame built with a placeholder cannot stay wrong.
* API-layer guards so the empty-name URL can never be built again:
  `MalUser.safeUsername` (MAL, where `@me` is a valid alias) and
  `JikanHelper.jikanUsername` (the mirror has no `@me`, so it refuses instead of
  building `users//full`), plus empty-name short-circuits in
  `DalApi.getUserAbout` and `MalForum.getUserClubs`.

Audit of the same class across the codebase (done): every remaining
user-scoped URL builder is now
`maluser.dart` (list, statistics, profile), `jikahelper.dart` (full/about/
clubs/favorites), `malforum.dart` (profile clubs) and `dalapi.dart`
(about/friends/history) -- the first three are guarded, the DAL ones take a
`username=` *query* parameter so they cannot produce a broken path.

## Verification status

* Offline suite: 56 tests pass (`animex_meta`, `animex_airing`,
  `schedule_reconcile`, `character_fallback`); `flutter analyze` clean on every
  touched file (only pre-existing warnings remain).
* On-device: the release build cannot be observed (Flutter release strips Dart
  `print`, so `logDal` never reaches logcat), and the emulator on this box has
  2 GB RAM and a broken TLS path, so the runtime wiring still needs a
  debuggable-but-release-signed build to confirm.