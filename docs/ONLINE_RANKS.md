# T4 client rank text, package 5

> **Superseded 2026-11-04 (owner):** T4 ranked uses Tekken 7's rank names, our own badge pictures and in-game name
> plates -- see [T4_RANKED.md](T4_RANKED.md). The text below is the earlier package-5 requirement, kept for history.

The owner's requirement is Tekken 8 rank names as text in the client only.
Nothing in the T4 game changes for that display. No rank icons, screenshots or
other Bandai Namco art belong in this work. These are Bandai Namco's names;
the owner still needs that attribution brought to their attention. No rank
name list or rating thresholds are selected or implemented here.

## What the source supports

The [standalone launcher](../launcher/t4_launcher.pyw) offers direct-IP/VPN
Host/Join and explicitly says there is no lobby or ranked play. Neither it nor
[its core](../launcher/t4core.py) implements account ratings or rank labels.
The shared OpenRecomp-FGC launcher and private lobby sources are absent from
this copy. This document records requirements, not a working rank feature.

The historical [lobby notes](LOBBY.md) say a result file is pending. Since 2026-11-04 the online game writes a
proven result itself ([MATCH_RESULT_T4.md](MATCH_RESULT_T4.md)): winner, round score, fighters and stage, decided
on frames both games had confirmed, with the compared state hash. The lobby client reports it with source `game`
and the T4 server stores it (history, per-fighter statistics); the manual answer stays as the fallback. Ranked
T4 (ratings from these results) is still off on the server.

## Implementation boundary

- Rank names label a T4 rating supplied by the agreed account/rating system.
  They do not determine the rating, thresholds, account identity or result.
- T4 matches and ratings stay separate from T5DR's. A shared account does not
  make a T5DR rank a T4 rank. See [the account requirements](ONLINE_ACCOUNTS.md).
- Missing or unverified T4 rating data must remain visibly unavailable or
  unrated. Do not fabricate a starting rank or promote a player from a
  process exit, connection success, player answer or diagnostic report.
- Ranked remains blocked on a proven game result and its validated reporting
  path. Winner, round score and terminal match state need game-side proof;
  disconnects and aborted games need agreed handling before rating changes.

## Required checks through the real launcher

These are owner acceptance cases, all **unrun** here. They require the actual
shared launcher, agreed server implementation and reviewed game build.

1. Open T4 with a shared account that has no T4 rating. Show unrated or
   unavailable text; a T5DR rating must not fill the gap.
2. Load a known T4 rating through the actual login and lobby path. Show the
   agreed text label consistently in each implemented T4 rank view; change
   games and verify T5DR retains its own rating.
3. Complete, draw, abort and disconnect real matches. Until the winner,
   score and match-end path is proven, each must leave ranked unavailable.
   A session JSON with null results must never award a win or rank change.
4. After that result path exists, verify both peers and server agree on a
   completed result, and stale or repeated reports cannot rate it twice.
5. Inspect the actual launcher package and T4 game: rank labels are client
   text, no rank art was added, and the display feature changes no game data.

The local document checker can check links and syntax only. No GUI, game,
result producer, rating change or shared-server operation was run here.
