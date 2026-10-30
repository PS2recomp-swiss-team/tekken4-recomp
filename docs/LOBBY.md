# Online play through a lobby (rollback phase 4)

Status 2026-10-29. Tekken 4 reuses the lobby of the user's T5DR Online project (C:\T5DROnline, `lobby/t5lobby`,
`docs/ONLINE.md`, `NETPLAY.md`, `HOSTING.md`, `RANKED.md` there, "T5 ..." below): server, client library, NAT traversal,
relay and the match flow are T5DR's code, copied into `lobby/` and adapted where the game differs. The game side is
phase 3's netplay (`runtime/tekken4_net.{h,cpp}`, `docs/ROLLBACK_PHASE3.md`), unchanged: its environment already had
everything a lobby match needs. The server hand-off for the T5DR coordinator is `SERVER_HANDOFF_T4.md`.

## What is where

```
lobby/
  run.py             python -I lobby/run.py server | cli | admin | host | relay
  t4lobby/           T5DR's lobby/t5lobby, package renamed (every "t5lobby" -> "t4lobby"), plus:
    proto.py         GAME "t4", GAME_NAME, UDP_MAGIC b"T4LB", GAME_MAGIC b"T4NP", DEFAULT_PORT 7791 (proposed)
    buildid.py       T4 build identity (= tools/t4_buildid.py: "t4dr-build:<elf>:<code_id>:<net>"), from t4net_build.txt
    server/lobby.py  hello: refuses a launcher of another game; welcome carries "game"
    client.py        hello carries "game"; refuses a server whose welcome is not "t4"
    server/config.py status port 7790 (T5: 7780); server/admin.py the same
    fighters.py, data/fighters.json   T4 roster (22) and the 10 VS stages: keys + names only (no direct fight yet,
                     ids are placeholders); data/fighters_t5.json = T5's table, for the copied tests
    t4game.py        NEW: MatchTicket -> TEKKEN4_NET* environment; start/watch the T4 game (net.log, rb_frames.log);
                     T4Match = one lobby match (game_started, game_playing, relay fallback, result report)
    cli.py           T4 player client (replaces T5's cli: starts the T4 game, not t5dr.exe)
  tests/             T5DR's tests (renamed) + test_t4.py (NEW)
  tools/             T5DR's tools (renamed) + t4_stub_game.py, t4_lobby_pair.py, run_tests.py (NEW)
tools/net_lobby_pair.ps1   two real T4 games through a local lobby (run lock; refuses while T5DR's HEAVY.lock exists)
```

Unchanged T5DR files that are T5-specific and unused by T4 for now: the Online tab (`tk_*.py`, `theme.py`,
`padnav.py`, `padmap.py`, `fighter_art.py`, `rank_art.py`, `discord_rpc.py` with T5's app id, `notify.py`),
`match_driver.py` (T5's direct-fight / persistent-game driver), `spectate.py`, tournaments, the i18n catalogs
(texts name T5DR in places), `ranks.py` (T5's rank tiers). They are kept so the copy stays diffable against T5DR
and the server runs unchanged; T4 uses `t4game.py` + `cli.py`. Not copied: `lobby/servers.json` (T5DR's public
server and its pinned certificate fingerprint), `lobby/deploy`, `Dockerfile`, `compose.yaml`.

## The match, end to end

1. **Hello.** `{"t":"hello","proto":1,"game":"t4","build":{"id","elf","code","net","release","game":"t4"},...}`.
   The server recomputes the build id from elf/code/net (T4 scheme) and refuses another game (`version_mismatch`:
   a T5DR launcher sends no "game"); the welcome says `"game":"t4"` and the T4 client refuses a server without it.
2. **Login**: guest (day one) or account. **Quick match / challenge / room** as T5DR; players are only ever paired
   with the same build id.
3. **NAT traversal** exactly as T5DR (`nat.py`): the client opens the game's UDP socket, registers it with the
   server (`T4LB` REGISTER/PROBE), punches to the opponent, measures the round trip; if that fails both bind to the
   relay (server UDP port), and two current clients keep the socket and relay through a **relay bridge** on
   127.0.0.1 (which also upgrades to the direct path later).
4. **match_start** -> `MatchTicket` (role host/join, local port, peer, key, seed, build, path) -> `t4game.game_env`:

   | ticket | T4 game environment |
   |---|---|
   | host (P1, slot 0) | `TEKKEN4_NET=host:<local port>`, `TEKKEN4_NET_PEER=<peer ip:port>` (the host calls the peer at once) |
   | join (P2, slot 1) | `TEKKEN4_NET=join:<peer ip:port>`, `TEKKEN4_NET_PORT=<local port>` |
   | build | `TEKKEN4_NET_BUILD` (16 hex; the peer's HELLO with another id -> `build_mismatch`) |
   | key | `TEKKEN4_NET_KEY` (SipHash-2-4 tag on every packet; with it the game follows the peer to a new address) |
   | seed | `TEKKEN4_NET_SEED` (mixed into srand) |
   | input_delay (ranked) / the player's setting | `TEKKEN4_NET_DELAY` (auto or 0..4; the host's value wins) |
   | timeout | `TEKKEN4_NET_TIMEOUT` |
   | (tests) `T5_NET_BIND` | `TEKKEN4_NET_BIND` |

   The peer is the opponent's punched endpoint (direct/LAN), the server's relay port, or `127.0.0.1:<bridge>`; the
   game binds exactly the punched port (port handover, T5's default) or, on the bridge, the bridge's game port on
   127.0.0.1 (the game binds 127.0.0.1 by itself when the peer is loopback). The relay and the bridge forward
   packets that start with `GAME_MAGIC` = `T4NP`, the T4 transport's magic -- that is the one place where T5DR's
   relay knew the game.
5. **The game** boots, netplay connects at frame 1 (handshake, delay pick), boot + intro in lockstep, then rollback
   through menus, select and fights (phase 3). `T4Match` watches `net.log` / `rb_frames.log`: "connected" ->
   `game_started`; the first `NETSUMMARY` (600 live frames) -> `game_playing`; no "connected" 20 s after the start on
   a direct path -> `nat_fallback` (the server moves the match onto the relay; the second match_start restarts the
   game with the new ticket).
6. **Result**: the T4 game writes no result file yet. The client reports the player's answer (`--winner`, or asked
   on the console), else "no result" (winner null), with the netplay evidence (`desync` = hash mismatches, `frames`)
   and the reason when the session failed (`peer_timeout`, `peer_quit`, `no_peer`, `build_mismatch`).

Day one = **process mode**: one game process per match (each boots ~20 s to the menus); characters and stage are
picked in the game's own VS BATTLE menus (host = P1 menus). No direct fight, no persistent game, no rematch inside
the running games yet.

## Local test (2026-10-29)

Unit/integration tests (no game; the server, clients and stub games all on 127.0.0.1, plain TCP, in-memory DB):
```
python -I lobby/tools/run_tests.py test_t4           # T4: 12 tests, OK
python -I lobby/tools/run_tests.py                   # the T4 set: test_t4 + the copied T5DR server/client/NAT/relay tests
```
T4 set run: 415 tests, 11 skipped, 2 failures that were T4 adaptations, not bugs (`test_relays_json` expected the
default port 7781 -> now `proto.DEFAULT_PORT`; `test_relay_only_install_runs` needs `lobby/deploy`, not copied ->
skipped without it); both rerun OK afterwards.
`test_t4`: build-id scheme (T4 id != T5 id for the same inputs; the real `t4net_build.txt` of
`D:\tekken4-fork-net\out\net` gives the id the game uses), magics, T4 table; a T5DR-style hello is refused, a T4 client
refuses a server without `"game":"t4"`; two guests quick-match -> both `match_start`, host/join, each one's peer =
the other's punched port, same key/seed/build, the TEKKEN4_* environment; forced relay: `T4NP` packets go through
the server's relay, `T5NP` ones do not; relay bridge: the env points at 127.0.0.1:<bridge>, packets flow; the T4
driver with the stub game, direct and through the relay bridge: both connected, NETEND, result confirmed.

Separate processes (server + two `cli` clients + stub games):
```
python -I lobby/tools/t4_lobby_pair.py --stub --name stub_direct      # both: connected, frames 300, mismatches 0
python -I lobby/tools/t4_lobby_pair.py --stub --relay --name stub_relay
```
(the lobby voids these results as `too_short`: a 5-second stub "match" is under the server's minimum match length.)

Real games through the lobby (heavy; pending while `C:\T5DROnline\build\int115\HEAVY.lock` exists):
```
$v = 'TEKKEN4_RAND_SEED=1;TEKKEN4_RB_INPUT=500:Start,800:Start,960:Down,1020:Down,1080:Cross,1320:Cross,1560:Cross,1800:Cross;TEKKEN4_RB_INPUT2=1320:Cross,1560:Cross,1800:Cross;TEKKEN4_RB_FUZZ=2400;TEKKEN4_RB_FUZZ2=2400;TEKKEN4_SOUND=1;TEKKEN4_NET_LOCALPAD=0;TEKKEN4_NET_DESYNC_DUMP=1'
powershell -ExecutionPolicy Bypass -File tools\net_lobby_pair.ps1 -Name lp_direct -End 6000 -Env $v -Sim "lat=25,jitter=5,loss=3"
powershell -ExecutionPolicy Bypass -File tools\net_lobby_pair.ps1 -Name lp_relay -End 6000 -Env $v -Relay
Select-String logs\online\lp_*\*\rb_frames.log -Pattern 'NETSUMMARY final'
```
Pass = both games `connected`, `NETEND`, `hashes compared N mismatches 0` on both sides.

## Playing by hand (two PCs, a lobby server reachable by both)

```
# the server (a PC or VPS both players reach; TCP+UDP 7791, UDP 7792 open):
python -I lobby/run.py server --port 7791
# each player (his own T4 netplay build: docs/rollback/net_build.cmd; the same build on both PCs):
python -I lobby/run.py cli --server <host>:7791 --name <name> --quick --pad 1
```
Plain TCP is fine for guests; accounts need TLS on a public server (T5DR's rule, `T5L_TLS_CERT/KEY`).

## Open items

- **Result file** in the game (winner, round score, final hash, fps, lost reason) like T5DR's `T5_NET_RESULT_FILE`:
  needed for ranked; until then results are the players' answers.
- **Direct fight** (skip the menus: characters/stage from the lobby) and the T4 ids in `data/fighters.json`;
  **persistent game** (one process for all matches, rematches inside the session); **online save** (unlocks).
- **No pause online**, KO/result only on confirmed frames (T5DR's match rules).
- **Online tab** (Tk) for T4: the copied tk_* files with T4 art and texts, or a smaller own UI; the CLI is day one.
- **Bandwidth**: ~92-140 packets/s per direction (more than T5DR's ~60/s), ~172-200 bytes of payload each
  (SERVER_HANDOFF_T4.md); within T5DR's relay limits (400 packets/s, 512 kbit/s per player). Bytes per packet are
  computed from the wire format, not counted: `NETSUMMARY` has no byte counter yet.
- **Socket handover** (`T5_NET_SOCKET_FILE`): not in the T4 game (port handover only, as T5DR's default).
- Not tested: two physical PCs, a real NAT, a real WAN, the regional relay nodes, TLS with a real certificate.
