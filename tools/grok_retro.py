"""Metrics of Grok runs since a time, for the morning retro (docs/ai/grok-retro.md).

  python -I tools/grok_retro.py --since "2026-10-21 22:00" [--until "2026-10-22 07:00"] [--no-unified] [--json]

Source 1: logs/grok/<task>_<YYYYMMDD_HHMMSS>.json (grok_task.ps1 results; stamp = local start time). Per task: runs,
answered (parsed JSON answer), no_answer, hung_exit (wrapper had to end a finished-but-hung Grok), premature (answer
verdict IN_PROGRESS/reading or < 15 turns with conf 0 -- heuristic), mean conf of answered, cost $, minutes.
Source 2 (unless --no-unified): ~/.grok/logs/unified.jsonl, grouped by pid in the window: prompts done, clean exits
(session_end.worker_join), done-without-exit (the CLI hang), tool execs / failed tool execs, inference retries.
Prints a compact table. Compare today's totals with the previous entry in the log of docs/ai/grok-retro.md.
"""
import argparse
import collections
import datetime as dt
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME_RE = re.compile(r"^(?P<task>.+)_(?P<stamp>\d{8}_\d{6})\.json$")


def parse_time(s):
    for fmt in ("%Y-%m-%d %H:%M", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d"):
        try:
            return dt.datetime.strptime(s, fmt)
        except ValueError:
            pass
    raise SystemExit(f"bad time {s!r}, use 'YYYY-MM-DD HH:MM'")


def load_runs(since, until):
    runs = []
    for path in glob.glob(os.path.join(ROOT, "logs", "grok", "*_*.json")):
        m = NAME_RE.match(os.path.basename(path))
        if not m:
            continue
        start = dt.datetime.strptime(m["stamp"], "%Y%m%d_%H%M%S")
        if start < since or (until and start > until):
            continue
        try:
            with open(path, encoding="utf-8-sig") as f:
                d = json.load(f)
        except (OSError, ValueError):
            continue
        if not isinstance(d, dict) or "task" not in d:
            continue
        ans = d.get("answer")
        parsed = isinstance(ans, dict)
        verdict = str(ans.get("verdict", "")) if parsed else ""
        turns = d.get("turns") if isinstance(d.get("turns"), (int, float)) else None
        conf = ans.get("conf") if parsed and isinstance(ans.get("conf"), (int, float)) else None
        premature = parsed and (verdict.upper().startswith("IN_PROGRESS") or
                                (turns is not None and turns < 15 and d.get("mode") == "work" and (conf or 0) == 0))
        runs.append(dict(task=d["task"], mode=d.get("mode"), start=start, parsed=parsed, conf=conf,
                         cost=d.get("cost_usd") if isinstance(d.get("cost_usd"), (int, float)) else 0.0,
                         seconds=d.get("seconds") or 0, hung=bool(d.get("hung_exit")), premature=premature,
                         turns=turns, sid=d.get("session") if isinstance(d.get("session"), str) else None))
    return sorted(runs, key=lambda r: r["start"])


def unified_by_pid(since, until):
    path = os.path.expanduser("~/.grok/logs/unified.jsonl")
    out = collections.defaultdict(lambda: collections.Counter())
    if not os.path.exists(path):
        return out
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if '"pid"' not in line:
                continue
            try:
                d = json.loads(line)
                t = dt.datetime.fromisoformat(d["ts"].replace("Z", "+00:00")).astimezone().replace(tzinfo=None)
            except (ValueError, KeyError):
                continue
            if t < since or (until and t > until):
                continue
            c = out[d.get("pid")]
            msg = d.get("msg", "")
            if msg == "shell.handle_prompt.done":
                c["done"] += 1
            elif msg == "session_end.worker_join":
                c["clean_exit"] += 1
            elif msg == "shell.tool.exec_done":
                c["tools"] += 1
                if (d.get("ctx") or {}).get("success") is False:
                    c["tool_fail"] += 1
            elif msg == "shell.turn.inference_retry":
                c["retries"] += 1
            elif msg == "shell.handle_prompt.start":
                c["prompts"] += 1
    return out


def row(label, rs):
    ans = [r for r in rs if r["parsed"]]
    confs = [r["conf"] for r in ans if r["conf"] is not None]
    return [label, len(rs), len(ans), len(rs) - len(ans), sum(r["hung"] for r in rs), sum(r["premature"] for r in rs),
            f"{sum(confs) / len(confs):.2f}" if confs else "-", f"{sum(r['cost'] for r in rs):.2f}",
            round(sum(r["seconds"] for r in rs) / 60)]


def table(rows, head):
    w = [max(len(str(x)) for x in col) for col in zip(head, *rows)]
    for r in [head] + rows:
        print("  ".join(str(x).ljust(w[i]) for i, x in enumerate(r)).rstrip())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", required=True)
    ap.add_argument("--until")
    ap.add_argument("--no-unified", action="store_true")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    since, until = parse_time(a.since), parse_time(a.until) if a.until else None
    runs = load_runs(since, until)
    by = collections.defaultdict(list)
    for r in runs:
        by[r["task"]].append(r)
    head = ["task", "runs", "answered", "no_answer", "hung_exit", "premature", "conf", "cost$", "min"]
    rows = [row(t, rs) for t, rs in sorted(by.items())]
    total = row("TOTAL", runs)
    uni = None if a.no_unified else unified_by_pid(since, until)
    if a.json:
        print(json.dumps({"since": a.since, "until": a.until, "head": head, "tasks": rows, "total": total,
                          "unified": {str(k): dict(v) for k, v in (uni or {}).items()}}))
        return
    print(f"since {a.since}" + (f" until {a.until}" if a.until else ""))
    table(rows + [total], head)
    if uni is not None:
        done = sum(c["done"] for c in uni.values())
        clean = sum(c["clean_exit"] for c in uni.values())
        hang = sum(1 for c in uni.values() if c["done"] and not c["clean_exit"])
        print(f"unified.jsonl: {len(uni)} pids, {sum(c['prompts'] for c in uni.values())} prompts, {done} done, "
              f"{clean} clean exits, {hang} pids done-without-exit (hang; a live interactive Grok counts too), "
              f"{sum(c['tools'] for c in uni.values())} tool execs ({sum(c['tool_fail'] for c in uni.values())} failed), "
              f"{sum(c['retries'] for c in uni.values())} inference retries")


if __name__ == "__main__":
    main()
