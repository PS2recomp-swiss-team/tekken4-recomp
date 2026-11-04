# Tekken 4 round setting (US SLUS-20328 v1.00)

The round markers under the life bars and the match-winning threshold use the same
active rounds-to-win value, a 32-bit integer at physical RDRAM `0x357d74`.
Setting it to 3 gives three markers per side and a match decided at three round wins.
This is separate from a ranked set's number of matches.

## Options to fight initialization

The saved Options Round value is the byte at `0x36c2b9`, encoded as the displayed
number minus one. Getter `FUN_001e2070` reads it. During mode initialization,
`FUN_001dd7f8` calls that getter at `0x1dd848`, adds one at `0x1dd850`, then stores
the actual number in the byte `0x2a8bf8+0x2b` (`0x2a8c23`) at `0x1dd858`.
The VS setup screens can adjust that byte through their normal 1..5 range
(`FUN_001e3348`, `0x1e3440..0x1e3454`, and `FUN_001e54b0`).

At match initialization, `FUN_00198b48` calls setter `FUN_00197b68` at
`0x198bd8`, loading the match rule byte into its argument in the delay slot
`0x198bdc`. The setter writes that argument to `0x357d74` at `0x197b70`.
An alternate initialization branch obtains its argument from `FUN_0019aba0`
and calls the same setter at `0x198bc8`.

Afterwards the initializer checks the upper bound (5), reads the active value
through getter `FUN_00197b78`, and computes `2*n-1`. It stores this maximum total
round count at `0x357d78` through setter `FUN_00197b88` (`0x198bfc..0x198c10`).
Only then does it clear the player round-win counters (`0x198c18` onwards).

The online override therefore belongs at the rounds setter, before the original
setter executes. A later isolated boundary write could leave the derived total
round cap inconsistent with the new rule. The setter is part of guest execution;
using an immutable negotiated rule on every invocation also reproduces it during
rollback and on subsequent match initialization. No saved option needs changing.

## HUD and result consumers

`FUN_001f0b50` reads `FUN_00197b78` at `0x1f0ba0`, keeps the result as its marker
loop bound, and draws one marker for each index from zero through `n-1`
(`0x1f0c00`, `0x1f0d90..0x1f0d98`). Both sides use this routine.

The judge `FUN_001bbe70` reads the same getter and compares it against each
player's signed 16-bit round wins at player `+0x8e` (for example,
`0x1bbf24..0x1bbf40`). The normal game then publishes its match decision at
`0x2a8bf8+0x2c`; see [MATCH_RESULT_T4.md](MATCH_RESULT_T4.md).
The existing result tracker reads the active rounds-to-win value, so it follows
the negotiated rule without changing set scoring.

## Online contract

`TEKKEN4_NET_ROUNDS=1..5` is the negotiated number of round wins. An unset value
retains the game's own option for direct-IP compatibility; malformed values stop
online configuration. `tekken4_rounds.h` reads this setting once. The rollback
driver mixes the value and setter contract into the boot HELLO fingerprint even
when automatic VS navigation and online names are disabled. A rounds mismatch
uses the existing `auto_vs_mismatch` refusal before input priming.

When an explicit value is present, the driver wraps setter `0x197b68`, replaces
its argument, and calls the original setter. It repeats this for every guest
invocation, including rollback replay and subsequent match setup. No saved
profile byte is changed, no host time or local role controls the write, and no
hash mask is added. The normal initializer consequently computes the matching
total-round cap before it clears the scores. Both markers and game-proven result
tracking follow the game's resulting active value.

The server latches ranked rounds at 3 separately from set length. Casual uses
the challenger's/room's 1..5 choice, or the previous actual default of 2. Both
match tickets and the fight line carry that count; launcher adapters export it
without allowing player environment settings to replace it. Server and modern
launcher changes are supplied as local patches when their worktrees are outside
the session's writable roots; the local artifact report names their bases.

`tools/net_play.ps1 -Rounds 3` and the standalone launcher's `rounds=3` argument
support direct-IP tests. `tools/net_pair.ps1 -Env 'TEKKEN4_NET_ROUNDS=3;...'`
sets the shared pair value; `-JoinEnv 'TEKKEN4_NET_ROUNDS=2'` exercises refusal.

## Verification scope

These addresses and instruction relationships were inspected in the local lifted
US code and independently checked against the original local ELF's instructions
by `python -I tools/test_rounds_setting.py`. That test pins the US ELF identity,
reads its LOAD segments, and checks the option read, mode copy, setter, derived
round cap, HUD loop and judge call sites. No generated game code is changed or
copied by the test. Real-game pair runs and screenshots are reported separately;
static instruction checks alone are not visual or synchronization proof.

## Local pair acceptance (2026-11-04)

Candidate `4ff2edac9043da48`, built from this working tree including the existing
native names/badges. Two local game processes per pair, bind/join 127.0.0.1,
muted, background, BelowNormal, isolated homes/cards. Both sends use
`lat=75,jitter=5,loss=3`. Each build/pair acquired and released one atomic HEAVY slot.

| Run under `logs/net/` | Confirmed hashes at frame 16000 (host/join) | Mismatches | Rollbacks |
|---|---|---|---|
| `v4_rounds3_rb` | 533 / 533 | 0 / 0 | 6 / 1732 |
| `v4_rounds3_ls` (`RBSTART=1000000`) | 533 / 533 | 0 / 0 | 0 / 0 |
| `v4_rounds3_mismatch` (host 3, join 2) | HELLO refused on both before fight | no match | none |

All four accepted games call the setter at frame 2176, start the fight at 2208,
count wins at 6129 (KO), 10673 (time), and 14057 (KO), and end 3-0 at 14057.
They continue after the second win. All four result files prove P1 won, native
decision code 1, target 3, deciding hash `55c15ca84ea8da15` at frame 14070,
`hash_agreed=true`, and `desync=0`. Each full match's 533 shared confirmed hashes
also match the lockstep replay of the same deterministic input script. Online
rollback resimulation was exercised; no standalone replay-file player was added.

Host/join window captures `hud_75s.png` were visually checked in both modes:
three original markers beneath each life bar, with the previous native names
and badges preserved. Required copies are `shots/v4_rounds3_host.png` and
`shots/v4_rounds3_join.png` in the local t4ranked build artifact folder; lockstep
copies add `ls_` before the side. No screenshots or game-derived data are tracked.

`logs/rounds3-tests/verification.json` records exact results/capture hashes and
asserts all four outcomes and 533 hashes agree. `cross_mode_compare.txt` contains
the independent reference comparison. Unit/static checks cover the native
instruction sites, first-to-three result tracking and a corrected predicted
third win, normalized HELLO inputs, launcher forwarding, and build identity.
Server and modern launcher patch manifests and every run (including corrected
failures) are in their local staged reports and the top-level artifact report.
