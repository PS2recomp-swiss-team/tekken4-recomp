# T4 online accounts and takeover

Package 5 requirements, recorded 2026-11-02. This is a contract and an owner
test list, not an implemented login. Follow [AGENTS.md](../AGENTS.md).
Package 5 starts after the agreed 2026-11-03 reset; the account server work
waits until after the T4 release. No server change is authorized here.

## Account target and current limitation

- T4 and T5DR use the same account name and password. Existing T5DR accounts
  carry over without registering again. T4 has its own matches and ratings.
- The account target has a separate session per game, allowing T4 and T5DR
  to be online at once. Other developers' games keep their own login unless
  their manifest selects this service; developers receive no account access.
- Main's supplied description of today's server is one login at a time:
  the second login wins; the old connection receives `kicked` with reason
  "logged in from another place". `_take_over` moves an ongoing match or set
  to the new connection. Different accounts are unaffected by that rule.
- That current behavior does not prove the later separate-session target.
  Two launchers using one account concurrently are not supported by the
  described current rule. The owner must resolve the session/search rules
  with the server coordinator before advertising the later target.

The private server and T5DR launcher are absent here. The supplied takeover
behavior was not inspected or reproduced. Do not turn it into a claimed
server regression test. See [the handoff](../SERVER_HANDOFF_T4.md) and
[the lobby notes](LOBBY.md) for the historical integration scope.

## Launcher behavior required before login/search ships

Show `kicked` and its reason clearly in the launcher. Stop login and search
activity for that connection. Do not automatically log back in: two
launchers would otherwise repeatedly take over from one another. A later
login must follow a new user action. Ordinary connection retry must not
override the `kicked` state.

The T5DR launcher's reaction to `kicked` remains unverified. If it logs in
again automatically, its maintainer must fix it in that project. Do not copy
its private implementation into this GPL-3 source tree.

Saved login remains undecided: shared with T5DR or separate. Do not add
passwords to the T4 settings file, logs, test fixtures, command lines or this
tree. Account transfer must preserve the existing account; it is not a new
registration flow. No saved-credential format or migration is established
by these notes.

## What this source copy actually has

Read-only inspection of [t4core.py](../launcher/t4core.py) and
[t4_launcher.pyw](../launcher/t4_launcher.pyw) found direct-IP Host/Join.
`OnlineRun` explicitly has no lobby. The settings defaults contain game and
build options, with no account or password fields. No account login,
`kicked` handler or lobby reconnect implementation is supplied by those
entry points. This inspection does not establish the behavior of the shared
launcher or T5DR launcher.

Python and private Python are unavailable in this copy. The GUI, login,
search, takeover and password migration stayed unrun. No production code was
changed on the strength of a mocked login or a source search.

## Owner checks through the actual launchers

Use authorized test accounts and the exact reviewed launcher/server builds
in the real validation environment. Keep credentials and personal details
out of the evidence copied here. Perform these checks in order:

| Entry and action | Required observation |
|---|---|
| Sign into OpenRecomp-FGC with an existing T5DR account | Login succeeds without creating another account; T4 matches/ratings stay separate. |
| Keep the T5DR launcher open; log in with the same account in OpenRecomp-FGC | Under today's stated rule, the first launcher visibly reports `kicked` and its reason; it does not log back in or restart search automatically. |
| Reverse the two launchers and repeat | The other direction also stays stopped after `kicked`; observe beyond the normal reconnect interval. |
| Repeat while searching, during ready check, during a match, and between games of a set | Confirm the coordinator's takeover rules at each stage; record both launchers' visible state and ensure no duplicate search or game is started. |
| Use two different accounts, one in each launcher | Neither receives a takeover kick caused only by the other account's login; both reach the allowed search state. |
| Log in again by a deliberate user action after a kick | Login can resume without a background loop; stale search/ready state is cleared according to the protocol. |
| Later, after the authorized per-game session change | The same account can stay online in T4 and T5DR together, with separate matches and ratings; this is a new acceptance run, not today's behavior. |

Run login/search before match/ready/result, then rooms/friends, then
tournaments/spectating. Each stage needs the T5DR launcher running beside
OpenRecomp-FGC. The one-game-per-PC rule needs its own coexistence check;
having both launchers open does not authorize starting two games on one PC.

The owner must supply the missing shared-launcher/server sources in their
authorized lanes, settle saved login and session rules, then run these real
entries. A document/link check here can only verify this record, not online
functionality.
