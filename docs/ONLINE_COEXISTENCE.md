# Two launchers: coexistence checks

Package 5 remains unproved. The OpenRecomp-FGC launcher and the existing
T5DR launcher must remain usable alongside each other. Neither launcher's
source is present in this copy; only the standalone T4 launcher was inspected.
No cross-launcher fix or successful coexistence run is claimed.

## What the T4 source does

The [launcher core](../launcher/t4core.py) keeps `logs/run.lock` under its own
installation root. `run_lock_holder()` treats a recorded live PID as a holder;
`take_run_lock()` writes the launcher PID, and `release_run_lock()` empties
the file only when that PID still owns it. Taking the lock requires
`tools/run_lock.ps1` to exist. The [PowerShell helper](../tools/run_lock.ps1)
also uses a lock under the supplied root and checks whether its PID is alive.

The [T4 GUI](../launcher/t4_launcher.pyw) checks its own running-game state and
the lock before Play or Host/Join. It starts the process before writing the
lock. Completion and normal launcher shutdown call the release helper.
Host/Join starts the direct-IP helper; there is no lobby search in this UI.

These are source observations, not execution results. They leave these gaps:

- Different installation roots use different files. This is not a shared
  machine-wide game guard, and says nothing about the other launchers.
- Checking a PID and then writing a file is not an atomic reservation.
  Two simultaneous starts can both pass the check before either writes it.
- The recorded PID belongs to the launcher. A launcher crash can leave a
  running child game with a lock whose recorded process is gone.
- A spawn failure, a lock-write failure after spawn, and an abnormal shutdown
  need separate real-entry checks. The normal release calls do not prove them.

Do not change this lock based on source inspection alone. A shared guard needs
an agreed implementation in both launchers and execution through their actual
start and search actions. The other source trees must be reviewed by their
owners; this copy's rules prohibit opening them.

## Accounts and saved login

The current supplied server rule is one login per account: a second login
takes over and the first receives `kicked`. The first launcher must show the
reason and stop reconnecting automatically. This has not been checked here.
Different accounts must remain usable at once. Shared accounts with separate
concurrent T4/T5DR sessions are a later target, after the T4 release; they are
not supplied by today's takeover rule. No server change is authorized here.

Whether the launchers share saved login remains undecided. This T4 core saves
game settings in its own `launcher/settings.json`; it has no login settings.
That does not establish what either other launcher stores. See the
[account requirements](ONLINE_ACCOUNTS.md).

## Owner checks through the actual launchers

Use the exact candidate builds in the authorized validation checkout. Record
which launcher, game, account case and outcome were checked, without publishing
credentials, addresses or personal paths. Each row remains **unrun** here.

| Actual entry action | Required observation |
|---|---|
| Open both launchers with different accounts | Both remain usable; no forced migration or unexpected logout. |
| Log in to the same account in the second launcher | The first shows the takeover reason and does not start a reconnect loop. |
| Start a game, then search/start from the other launcher | The agreed one-game-per-PC guard refuses the second search/start clearly. Repeat with the launchers reversed and with separate install folders. |
| Press start/search in both launchers together | Exactly one reservation wins; neither silently starts a second game. |
| Stop or finish the first game | A later permitted start succeeds; stopping a nonowner does not release another session's reservation. |
| Fail before spawn, fail after spawn, or close/crash a launcher | No orphan game is ignored and no dead reservation prevents a later permitted start. |
| Restart both launchers after choosing the saved-login policy | The agreed policy holds; takeover still requires a visible user action. |

These checks require real launcher execution and game runs. A mock, a lock-file
unit test or a same-PC rollback pair cannot prove them. Do not run the games or
build tools in this clean copy. Follow [AGENTS.md](../AGENTS.md) and keep the
remaining work in [CODEX_PROGRESS.md](../CODEX_PROGRESS.md).
