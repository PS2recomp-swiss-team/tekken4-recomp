# Server handoff: Tekken 4 online (for the T5DR coordinator)

## Package 5 decisions (owner, 2026-10-31; recorded 2026-11-02)

These decisions supersede the separate-login and deployment proposals below.
Package 5 starts after the planned 2026-11-03 reset; this document does not
claim that reset or a deployment has happened.

- OpenRecomp-FGC and the existing T5DR launcher must keep working beside each
  other against the same lobby protocol and matching game builds. Protocol
  version stays **1** unless Main agrees otherwise. T4 players on either
  launcher must be able to meet; T4 must never match T5DR.
- One account, same name and password; existing T5DR accounts carry over
  without registering again. T4 keeps its own sessions, matches and ratings,
  not its own logins. The owner's target permits both games online at once.
  Account work follows the T4 release; `codex/accounts` is a draft needing
  review against these decisions. **No server change is authorized here.**
- Today's reported same-account launcher takeover sends `kicked` with
  "logged in from another place". The new launcher must show it and stop
  automatic login; the old launcher's reconnect behavior still needs checking.
  Cross-game sessions need the later account design; do not assume today's
  takeover behavior implements them.
- T4 ranks use Tekken 8 names as client text only, with no game changes or
  rank artwork. Ranked results still need an authoritative game match result.
  The existing optional `TEKKEN4_NET_RESULT` session report writes
  `winner: null`, `score: null`, `match_result_proven: false`; it is diagnostic
  and has no game match-end detector. See [rank/result limits](docs/ONLINE_RANKS.md).
- Implement and prove login/search, then match/ready/result, then
  rooms/friends, then tournaments/spectating. Each stage needs a real launcher
  run with the existing launcher beside it.

The shared launcher and private lobby source are absent from this copy.
Exact outgoing fields and capability flags still need comparison with the
authorized T5DR protocol source and real entry-point tests. The historical
`hello`, ports, magics and private-copy test claims below are not a verified
package-5 specification. A common lobby protocol does not make T4 and T5DR
game packets interchangeable: T4's game wire and build identity remain
game-specific. The standalone T4 launcher's Host/Join starts the direct-IP
helper; it does not log in to a shared server. No lobby, server, launcher GUI
or game was run for this update.

## Historical handoff (2026-10-29)

Historical 2026-10-29 handoff. The private `lobby/` code, logs and external checkout paths below are absent
from this clean source copy. Follow `AGENTS.md`; these paths and deployment examples do not authorize access
or deployment. This is a proposed lobby route, not a tested public beta service. Current release scope is in
`docs/BETA_RELEASE_NOTES.md`; local test claims below were not reproduced during this source audit.

From the Tekken 4 port (repo Lautreck/tekken4-recomp, branch `us-slus20328`, folder `D:\tekken4-us`), 2026-10-29.
Details: `docs/LOBBY.md` (lobby integration), `docs/ROLLBACK_PHASE3.md` (netplay), `lobby/` (the code).
**`lobby/` is a copy of the private T5DR lobby code and is NOT in the git repo** (the T4 repo is public): it exists only
locally in `D:\tekken4-us\lobby\` (git-excluded); where it is kept long term (a private repo) is the owner's decision.
Nothing was deployed and no remote server was contacted; everything below was run on 127.0.0.1 only. No T5DR key,
certificate or fingerprint is used by T4 (T5DR's `lobby/servers.json` was deliberately not copied).

## (1) Protocol

**Reuse of the T5DR lobby protocol**, same code: `lobby/t4lobby` is a copy of T5DR's `lobby/t5lobby` (server, client
library, NAT traversal, relay, regional relay nodes, admin, store) with the package renamed and only the game identity
changed. Lobby protocol version stays 1; every T5DR message keeps its meaning. Changes:

| where | T5DR | T4 | why |
|---|---|---|---|
| control `hello` (client -> server) | no game field | **+ `"game": "t4"`** (top level and in `build`) | the server refuses another game with `error` `version_mismatch` ("this is a Tekken 4 lobby server"); a T5DR launcher sends no `game` = "t5" -> refused |
| control `welcome` (server -> client) | no game field | **+ `"game": "t4"`** | the T4 client refuses a server without it (a T5DR server) with `version_mismatch` |
| `build` object | `id, elf, code, net, release` | same + `game`; `id` recomputed with the **"t4dr-build"** prefix | section 2 |
| UDP lobby magic (`proto.UDP_MAGIC`) | `T5LB` | **`T4LB`** | a T4 client and a T5 server (or vice versa) never understand each other's REGISTER/PROBE/PING/PUNCH/RELAY_BIND |
| game packet magic the relay and the relay bridge forward (`proto.GAME_MAGIC`) | `T5NP` | **`T4NP`** | the T4 game's netplay packets (`runtime/tekken4_net.cpp`); a T4 relay drops `T5NP` and vice versa (tested) |
| default port (`proto.DEFAULT_PORT`) | 7781 (UDP probe 7782) | **7791 (UDP probe 7792)**, proposed | section 3 |
| local status port | 7780 | **7790**, proposed | both servers can run on one host |
| `data/fighters.json` | T5DR roster/stages, game ids | T4 roster (22) + 10 VS stages, **keys and names only** (no direct fight yet) | the server resolves "random" characters/stage from it for its records only |

No other message, field or rule was added or changed. The `match_start` the server sends is T5DR's (role, slot,
peer, path, rtt, key, seed, build, input_delay, ...); the T4 client maps it to the T4 game's environment itself
(`lobby/t4lobby/t4game.py`, table in `docs/LOBBY.md`). Server settings keep T5DR's `T5L_*` environment variable names.
The UDP and game magics live in `proto.py` only, so one code base can be configured for either game; running **one
server process per game** (two systemd units, own ports, own database) was the historical proposal/test setup.
Its independent database must not become a separate T4 account store; the account decision above supersedes that interpretation.

## (2) Build identity

- `build id = sha1("t4dr-build:<elf_sha1>:<code_id>:<net>")[:16]` (T5DR: `"t5dr-build:..."`), computed at build time by
  `tools/t4_buildid.py` (run by `docs/rollback/net_build.cmd`) and written to `<exe dir>/t4net_build.txt`
  (`<id> <elf_sha1> <code_id> <net>`); the lobby client reads that file (`BuildInfo.from_out_dir`), the server
  recomputes the id from elf/code/net (it never trusts the client's `id`), the game puts the same id into its netplay
  HELLO (`TEKKEN4_NET_BUILD`; another id -> `build_mismatch`, both games go on offline).
  - `elf_sha1` = SHA-1 of `SLUS_203.28` (SLUS-20328 v1.00: `a4b7dde20a2918c550badd127a245db155c36815`)
  - `code_id` = SHA-1 over the PS2Recomp tree's commit + uncommitted diff, `patches/*.patch`, `config/*.toml|*.csv`,
    and the game modules staged into the runner (`*_overrides.cpp`, `tekken4_net*`)
  - `net` = the netplay wire version (`runtime/tekken4_net.h` `kNetVersion` = 1)
  - Current build (`D:\tekken4-fork-net\out\net`): `9e86181788650d64`.
- **T4 never matches T5**: (a) different prefix, so even identical inputs give different ids (tested); the inputs also
  differ (another ELF, another code tree); (b) the `game` field: a T4 server refuses a T5 launcher and a T4 launcher
  refuses a T5 server at hello (tested both ways); (c) different UDP and game-packet magics; (d) different ports.
  If the coordinator ever wants a build allow-list, T5DR's `T5L_BUILDS` works unchanged with T4 ids.

## (3) Network

**What a match connection needs** (identical to T5DR, same code):
- UDP between the two games. First choice **direct** (the launcher registers its game socket with the server, the
  server swaps candidates, both sides **hole-punch**, incl. symmetric-NAT port prediction and the router port-map
  option), then the launcher closes its socket and the game binds the same port and talks straight to the opponent.
- **Relay** for players who cannot connect directly: both bind to the server's UDP port (or a regional relay node),
  which forwards `T4NP` packets between the two bound endpoints; current clients keep the socket and run the
  **relay bridge** (the game talks to 127.0.0.1, the launcher forwards and later upgrades to direct). Also T5DR's
  `nat_fallback` (direct path silent for the game -> move to the relay) is used by the T4 client (after 20 s).
- The T4 game needed no change for this: `host:<port>` + `TEKKEN4_NET_PEER` (the host calls the peer at once and
  follows the address the HELLO comes from), `join:<peer>` + `TEKKEN4_NET_PORT`, `TEKKEN4_NET_KEY` (SipHash-2-4 tag on
  every packet), binds 127.0.0.1 by itself when the peer is the bridge. IPv4 only, like T5DR.

**Ports** (proposal; the final choice is the coordinator's):
| | T5DR | T4 proposal |
|---|---|---|
| lobby control | TCP 7781 | **TCP 7791** |
| lobby UDP: register, ping, relay | UDP 7781 | **UDP 7791** |
| NAT probe (second UDP port) | UDP 7782 | **UDP 7792** |
| status/health/metrics (local only) | 127.0.0.1:7780 | **127.0.0.1:7790** |
| regional relay nodes | UDP 7781 | UDP 7791 on the node (if T4 gets nodes) |
| game side (players' PCs) | any free UDP port picked by the launcher (or the player's forwarded port) | same (the T4 game binds the punched port; nothing fixed) |

**Bandwidth per match** (from `logs\net\*\{host,join}\rb_frames.log` `NETSUMMARY final`: packets out / wall time =
live frames / run fps; two processes on one PC, network simulator with 3 % loss):

| run | RTT | packets/s out, host / join | of which resends/s | fps |
|---|---|---|---|---|
| `n0b` | 0 | 91.5 / 95.0 | 10 / 12 | 40.6 |
| `n50b` | 48 | 115.6 / 115.7 | 35 / 33 | 39.0 |
| `n100perf` | 100 | 128.7 / 131.3 | 25 / 23 | 50.0 |
| `n150b` | 148 | 115.8 / 115.7 | 35 / 34 | 38.9 |
| `smoke1` | 48 | 137.6 / 139.8 | 27 / 29 | 53.8 |

- Bytes per packet for these historical runs (computed from the wire format, `runtime/tekken4_net.cpp`):
  INPUT = 16 header + 12 + 6 x max(8, unacknowledged inputs) + 12 x 8 latest state hashes (+ 8 tag with a match key) =
  **172-200 bytes of payload** (180-208 keyed), +28 IP/UDP; PING 33 bytes (rare during play).
- `NETSUMMARY` now prints cumulative `payload bytes out` / `in` for the counted packets (source change, not yet built or run).
  These include authentication tags and exclude IP/UDP headers. Out counts sendTo attempts before simulated loss;
  in follows packetsIn (HELLO/REJECT excluded). These are transport counters, not a measured on-wire bandwidth rate.
- So at the full 60 fps expect **~150 packets/s and ~250 kbit/s per direction per player** on the wire (lower at the
  current 38-54 fps); a relayed match costs the relay about **2 x 150 packets/s in and out, ~0.5 Mbit/s each way**.
  T5DR's game sends ~60 packets/s / ~85 kbit/s; T4 sends more (an INPUT per frame plus resends every 15 ms while
  unacknowledged, and 8 redundant hashes per packet). It fits under T5DR's per-player relay limits (400 packets/s,
  512 kbit/s), but with less headroom: keep those limits for T4, or raise to 600 packets/s / 768 kbit/s if relayed
  matches show drops. (Trimming the redundant hashes would halve the packet size: T4-side open item.)

## (4) Day-one features (recommended minimal set)

- **Guests** (name only) + **casual**: quick match, challenge a player in the lobby list, open rooms; lobby chat
  (it is in the protocol already and costs nothing).
- **Accounts** optional (they need TLS on a public server: T5DR's rule); **no ranked + leaderboard yet**: the T4 game
  writes no result file, so results are the players' own answers; ranked waits for the game-side result file.
- Off for day one: tournaments, spectating, regional relay nodes (the main server's relay is enough to start),
  private rooms with codes (works, but not needed), Discord presence (T5DR's app id), T6-style options.
- Client: a **command-line client** (`python -I lobby/run.py cli --server <host>:7791 --name X --quick`) that starts
  the T4 game itself (process mode: one game boot per match). A Tk "Online" tab like T5DR's is realistic later
  (the copied `tk_*` code), not day one.

## (5) Netcode

Deterministic rollback (GGPO-style, T5DR's wire design trimmed to two PS2 pads): the whole machine state (EE RAM,
scratchpad, VU0, the IOP with its RAM, SPU2 and threads, the EE cycle) is snapshotted every frame and re-simulated on
a misprediction; both games compare a hash of the full state every 30 frames. **Tested between two game processes on
one PC** over loopback UDP with an in-process network simulator (3 % loss, +-5 ms jitter), boot -> menus -> VS fights
-> next match, 12 000 frames (6 000 for `n100perf`), **0 mismatches** in every run:

| run | RTT | loss | hashes compared | mismatches | also equal to the offline reference |
|---|---|---|---|---|---|
| `n0b` | 0 ms | 3 % | 399 | 0 | yes (418 frames compared) |
| `n50b` | 48 ms | 3 % | 399 | 0 | yes (416) |
| `n100perf` | 100 ms | 3 % | 200 | 0 | (not compared) |
| `n150b` | 148-151 ms | 3 % | 399 | 0 | yes (402) |

(`docs/ROLLBACK_PHASE3.md`; logs `logs\net\<run>\{host,join}`; `ndesync` proves the detector fires on a forced
desync, `nbuild` that another build id is refused.)
Through the lobby: the full flow (hello, quick match, punch / relay / relay bridge, match_start, game start, result
report) was tested with a **stub game** on 127.0.0.1 (and the copied T5DR server/client/NAT/relay suite, 415 tests, passes on the T4 copy after two expected test adaptations: default port, no `deploy/`) (`lobby/tests/test_t4.py`, `lobby/tools/t4_lobby_pair.py`); the
**real T4 game launched by the lobby is pending** (the user's T5DR build holds the machine: `HEAVY.lock`; command in
`docs/LOBBY.md`).

**Not yet tested: two physical PCs, a real NAT/router, a real WAN or a real relay hop, and human play.**
Also: the port runs 38-54 fps on the VS stages on this PC (not yet a steady 60), a lobby match boots the game
(~20 s) per opponent, and there is no in-game result file.

## (6) Names (owner's decision)

- Product name players see: proposal **"Tekken 4 Online"** (short "T4 Online"; internal ids stay `t4`/`t4dr`).
  Owner's decision.
- Release/update channel: proposal **its own GitHub repository** (e.g. a public `tekken4-online` release repo, with
  releases signed like T5DR's), separate from T5DR's channel so neither updater can install the other game.
  Owner's decision.

## Historical coordinator checklist (not deployment instructions for package 5)

Do not execute this checklist before the later account review. Its separate
database, optional-account and private-copy assumptions need reconciliation
with the current decisions above.

- [ ] Pick T4's ports (proposal TCP 7791, UDP 7791-7792, local status 7790) and open them in the cloud firewall and
      host firewall (T5DR's `HOSTING.md` "Firewall rules" with the T4 numbers).
- [ ] Install `lobby/` (from `D:\tekken4-us\lobby\` or the private repo the owner picks; not in the public T4 repo) as its own service (own user, own `T5L_DB` file e.g. `t4lobby.db`,
      `T5L_PORT=7791 T5L_UDP_PORT=7791 T5L_UDP_PORT2=7792 T5L_STATUS_PORT=7790`); T5DR's `deploy/linux` unit and
      install script work with the paths/names changed (they were not copied).
- [ ] TLS: a **new** certificate for T4 (self-signed via `python -I lobby/run.py admin gen-cert --name <host>` or a CA cert), never T5DR's;
      publish its fingerprint in a T4 `servers.json` (format `t5dr-servers/1`, file not created yet).
- [ ] Decide day-one settings: guests on, accounts on/off, ranked off (`T5L_*` as for T5DR), relay on.
- [ ] Relay limits: keep `T5L_RELAY_PPS=400` / `T5L_RELAY_KBPS=512` per player or raise (section 3); `T5L_MAX_RELAYS`.
- [ ] Optional: a build allow-list (`T5L_BUILDS`) with the release build's id once a release exists.
- [ ] Names and release channel (section 6).

## Open items

- Real game through the lobby on this PC (pending `HEAVY.lock`), then **two PCs over the internet** (direct, relay).
- Game-side **result file** (winner, score, final hash, fps, reason) -> ranked and leaderboard.
- Direct fight (lobby-chosen characters/stage, T4 ids in `data/fighters.json`), persistent game, rematch in session,
  no-pause online, online save (unlocks).
- Fewer redundant hashes per packet; validate the new `NETSUMMARY` byte counters in a real build/run.
- T4 Online tab (Tk) and T4 texts/art; the copied i18n catalogs mention T5DR in places.
- Regional relay nodes for T4 (the code is there; secrets/ids would be T4's own).
