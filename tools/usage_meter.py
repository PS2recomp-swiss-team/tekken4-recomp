"""Estimate Claude Code plan usage from local transcripts.

The plan meter itself is server-side (/usage, status-line rate_limits). This
tool does not call the network and does not read credentials. It sums deduped
assistant token counts, weights them by the model prices baked into Claude
Code 2.1.307, and scales those weights with a calibration taken from /usage.

Stdout is only the status line, the hook JSON, or nothing. Transcript text is
never printed.

  python -I tools/usage_meter.py --status
  python -I tools/usage_meter.py --hook
  python -I tools/usage_meter.py --calibrate 53 --resets 05:45 --note "reading ..."
  python -I tools/usage_meter.py --calibrate 53 --resets 05:45 --weekly 12 --weekly-resets "2026-10-25 05:45"
"""

import argparse
import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

THRESHOLDS = (50, 60, 70, 75, 78, 85, 90, 95)
BLOCK_MS = 5 * 60 * 60 * 1000
WEEK_MS = 7 * 24 * 60 * 60 * 1000
CACHE_VERSION = 1

# USD per million tokens: input, output, cache write 5m, cache write 1h, cache read.
# Source: pricing_tiers object baked into Claude Code 2.1.307 (claude.exe).
PRICES = {
    "claude-3-5-haiku": (0.8, 4.0, 1.0, 1.6, 0.08),
    "claude-haiku-4-5": (1.0, 5.0, 1.25, 2.0, 0.1),
    "claude-haiku-5-5": (0.1, 0.5, 0.125, 0.2, 0.01),
    "claude-3-5-sonnet": (3.0, 15.0, 3.75, 6.0, 0.3),
    "claude-3-7-sonnet": (3.0, 15.0, 3.75, 6.0, 0.3),
    "claude-sonnet-4": (3.0, 15.0, 3.75, 6.0, 0.3),
    "claude-sonnet-4-5": (3.0, 15.0, 3.75, 6.0, 0.3),
    "claude-sonnet-4-6": (3.0, 15.0, 3.75, 6.0, 0.3),
    "claude-sonnet-5": (2.0, 10.0, 2.5, 4.0, 0.2),
    "claude-sonnet-5-5": (2.0, 10.0, 2.5, 4.0, 0.1),
    "claude-opus-4": (15.0, 75.0, 18.75, 30.0, 1.5),
    "claude-opus-4-1": (15.0, 75.0, 18.75, 30.0, 1.5),
    "claude-opus-4-5": (5.0, 25.0, 6.25, 10.0, 0.5),
    "claude-opus-4-6": (5.0, 25.0, 6.25, 10.0, 0.5),
    "claude-opus-4-7": (5.0, 25.0, 6.25, 10.0, 0.5),
    "claude-opus-4-8": (5.0, 25.0, 6.25, 10.0, 0.5),
    "claude-opus-5": (5.0, 25.0, 6.25, 10.0, 0.5),
    "claude-opus-5-5": (4.0, 20.0, 5.0, 8.0, 0.2),
    "claude-fable-5": (10.0, 50.0, 12.5, 20.0, 1.0),
    "claude-fable-5-1": (10.0, 50.0, 12.5, 20.0, 0.25),
    "claude-mythos-5": (10.0, 50.0, 12.5, 20.0, 1.0),
    "claude-mythos-5-1": (10.0, 50.0, 12.5, 20.0, 0.25),
}
# Haiku 5.5 long-prompt tier (catalog: above_prompt_tokens 1e5), whole request.
HAIKU55_LONG = (0.5, 2.5, 0.625, 1.0, 0.05)
_PRICE_KEYS = sorted(PRICES, key=len, reverse=True)
_DATE_SUFFIX = re.compile(r"-\d{8}(?:-v\d+(?::\d+)?)?$")
_VER_SUFFIX = re.compile(r"-v\d+:\d+$")
_ASSISTANT = (b'"type":"assistant"', b'"type": "assistant"')

REPO = Path(__file__).resolve().parent.parent


def repo_path(*parts):
    return REPO.joinpath(*parts)


def default_roots():
    roots = []
    projects = Path.home() / ".claude" / "projects"
    if projects.is_dir():
        roots.append(projects)
    local = os.environ.get("LOCALAPPDATA")
    if local:
        temp = Path(local) / "Temp" / "claude"
        if temp.is_dir():
            roots.append(temp)
    return roots


def parse_pct(text):
    raw = str(text).strip()
    if raw.endswith("%"):
        raw = raw[:-1].strip()
    try:
        value = float(raw)
    except ValueError:
        fail("percent must be a number")
    if not 0 < value <= 100:
        fail("percent must be > 0 and <= 100")
    return value


def fail(message):
    sys.stderr.write(message + "\n")
    raise SystemExit(1)


def atomic_write(path, obj):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(obj, separators=(",", ":")), encoding="utf-8")
    os.replace(tmp, path)


def load_json(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def num(obj, key):
    if not isinstance(obj, dict):
        return 0
    value = obj.get(key)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return 0
    if value < 0:
        return 0
    return int(value)


def parse_ts_ms(value):
    if not isinstance(value, str) or len(value) < 10:
        return None
    text = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return to_ms(parsed)


def to_ms(dt):
    return int(dt.timestamp() * 1000)


def normalize_model(model):
    text = model.strip()
    for prefix in ("us.anthropic.", "eu.anthropic.", "anthropic."):
        if text.startswith(prefix):
            text = text[len(prefix):]
            break
    if text.endswith("[1m]"):
        text = text[:-4]
    text = _DATE_SUFFIX.sub("", text)
    text = _VER_SUFFIX.sub("", text)
    return text


def price_for(model):
    name = normalize_model(model)
    if name in PRICES:
        row = PRICES[name]
    else:
        row = None
        for key in _PRICE_KEYS:
            if name.startswith(key):
                row = PRICES[key]
                name = key
                break
        if row is None:
            low = name.lower()
            if "haiku" in low:
                name, row = "claude-haiku-5-5", PRICES["claude-haiku-5-5"]
            elif "sonnet" in low:
                name, row = "claude-sonnet-5-5", PRICES["claude-sonnet-5-5"]
            elif "fable" in low or "mythos" in low:
                name, row = "claude-fable-5", PRICES["claude-fable-5"]
            else:
                name, row = "claude-opus-5-5", PRICES["claude-opus-5-5"]
    return name, row


def weight_usd(model, inn, out, c5, c1, cr):
    name, row = price_for(model)
    if name == "claude-haiku-5-5" and (inn + c5 + c1 + cr) > 100_000:
        row = HAIKU55_LONG
    pin, pout, pc5, pc1, pcr = row
    return (inn * pin + out * pout + c5 * pc5 + c1 * pc1 + cr * pcr) / 1_000_000


def merge_rec(old, new):
    tokens = [max(a, b) for a, b in zip(old[2:], new[2:])]
    model = new[1] if sum(new[2:]) >= sum(old[2:]) else old[1]
    return [min(old[0], new[0]), model, *tokens]


def extract_assistant(obj):
    """Pull only the allowlisted fields off one decoded object."""
    if not isinstance(obj, dict) or obj.get("type") != "assistant":
        return None
    message = obj.get("message")
    if not isinstance(message, dict):
        return None
    model = message.get("model")
    if not isinstance(model, str) or model == "<synthetic>":
        return None
    message_id = message.get("id")
    if not isinstance(message_id, str) or not message_id:
        message_id = obj.get("requestId")
        if not isinstance(message_id, str) or not message_id:
            return None
    ts = parse_ts_ms(obj.get("timestamp"))
    if ts is None:
        return None
    usage = message.get("usage")
    if not isinstance(usage, dict):
        usage = {}
    inn = num(usage, "input_tokens")
    out = num(usage, "output_tokens")
    cr = num(usage, "cache_read_input_tokens")
    created = usage.get("cache_creation")
    if isinstance(created, dict):
        c5 = num(created, "ephemeral_5m_input_tokens")
        c1 = num(created, "ephemeral_1h_input_tokens")
        if c5 == 0 and c1 == 0:
            c5 = num(usage, "cache_creation_input_tokens")
    else:
        c5 = num(usage, "cache_creation_input_tokens")
        c1 = 0
    return message_id, [ts, model, inn, out, c5, c1, cr]


def consume_line(line, ids):
    if _ASSISTANT[0] not in line and _ASSISTANT[1] not in line:
        return
    try:
        obj = json.loads(line)
    except ValueError:
        return
    got = extract_assistant(obj)
    if got is None:
        return
    message_id, rec = got
    prev = ids.get(message_id)
    ids[message_id] = rec if prev is None else merge_rec(prev, rec)


def read_slice(path, start, limit, ids):
    offset = start
    with open(path, "rb") as handle:
        handle.seek(start)
        while offset < limit:
            line = handle.readline()
            if not line:
                break
            next_off = offset + len(line)
            if next_off > limit or not line.endswith(b"\n"):
                break
            consume_line(line, ids)
            offset = next_off
    return offset


def candidate_files(roots):
    found = []
    for root in roots:
        root = Path(root)
        if not root.is_dir():
            continue
        for dirpath, _dirnames, filenames in os.walk(root):
            base = os.path.basename(dirpath)
            for name in filenames:
                path = os.path.join(dirpath, name)
                if name.endswith(".jsonl"):
                    found.append(path)
                elif name.endswith(".output") and base == "tasks":
                    try:
                        with open(path, "rb") as handle:
                            first = handle.read(1)
                    except OSError:
                        continue
                    if first == b"{":
                        found.append(path)
    found.sort()
    return found


def load_entries(roots, cache_path):
    cache = load_json(cache_path) or {}
    if cache.get("v") != CACHE_VERSION:
        cache = {"v": CACHE_VERSION, "files": {}}
    files = cache.get("files")
    if not isinstance(files, dict):
        files = {}
        cache["files"] = files
    live = set()
    dirty = False
    for path in candidate_files(roots):
        live.add(path)
        try:
            st = os.stat(path)
        except OSError:
            continue
        size = st.st_size
        mtime = st.st_mtime_ns
        cached = files.get(path)
        if (
            isinstance(cached, dict)
            and cached.get("size") == size
            and cached.get("mtime_ns") == mtime
            and isinstance(cached.get("ids"), dict)
        ):
            continue
        ids = {}
        start = 0
        if (
            isinstance(cached, dict)
            and isinstance(cached.get("ids"), dict)
            and isinstance(cached.get("offset"), int)
            and isinstance(cached.get("size"), int)
            and size > cached["size"]
            and 0 <= cached["offset"] <= cached["size"]
        ):
            ids = dict(cached["ids"])
            start = cached["offset"]
        try:
            offset = read_slice(path, start, size, ids)
        except OSError:
            continue
        # Store the pre-read snapshot. If the file grew mid-read, the next run
        # sees a larger size and resumes from offset instead of double-counting.
        files[path] = {
            "size": size,
            "mtime_ns": mtime,
            "offset": offset,
            "ids": ids,
        }
        dirty = True
    for path in list(files):
        if path not in live:
            del files[path]
            dirty = True
    if dirty:
        atomic_write(cache_path, cache)
    merged = {}
    for entry in files.values():
        ids = entry.get("ids")
        if not isinstance(ids, dict):
            continue
        for message_id, rec in ids.items():
            if not isinstance(rec, list) or len(rec) != 7:
                continue
            prev = merged.get(message_id)
            merged[message_id] = rec if prev is None else merge_rec(prev, rec)
    return merged


def chain_open(points, now_ms, length_ms, seed_ms):
    """Return the block that contains now, as (start_ms or None, weight).

    seed_ms None: the first point starts a block.
    seed_ms set: points before that instant are ignored. The first point at or
    after it starts a block. A point at or after start+length starts the next.
    A point that would start a block after now does not erase the open one.
    """
    start = None
    current = 0.0
    open_start = None
    open_weight = 0.0
    for ts, usd in points:
        if seed_ms is not None and start is None and ts < seed_ms:
            continue
        if start is None or ts >= start + length_ms:
            start = ts
            current = 0.0
        current += usd
        if start <= now_ms < start + length_ms:
            open_start = start
            open_weight = current
        elif start > now_ms:
            break
    return open_start, open_weight


def fixed_open(points, now_ms, end_ms, length_ms):
    """Anchored window [end-length, end) while now is still before end.

    At or after end, the next window is chain_open seeded at end.
    """
    if now_ms < end_ms:
        start = end_ms - length_ms
        weight = 0.0
        for ts, usd in points:
            if ts < start:
                continue
            if ts >= end_ms:
                break
            weight += usd
        return start, weight
    return chain_open(points, now_ms, length_ms, end_ms)


def window_view(merged, now_ms, five_end_ms, week_end_ms):
    points = []
    for rec in merged.values():
        ts = rec[0]
        if not isinstance(ts, int):
            continue
        usd = weight_usd(rec[1], rec[2], rec[3], rec[4], rec[5], rec[6])
        points.append((ts, usd))
    points.sort()
    if five_end_ms is None:
        start, w5 = chain_open(points, now_ms, BLOCK_MS, None)
    else:
        start, w5 = fixed_open(points, now_ms, five_end_ms, BLOCK_MS)
    if week_end_ms is None:
        cut = now_ms - WEEK_MS
        week = 0.0
        for ts, usd in points:
            if ts >= cut:
                week += usd
        return start, w5, week, None, False
    week_start, week = fixed_open(points, now_ms, week_end_ms, WEEK_MS)
    return start, w5, week, week_start, True


def round_pct(value):
    if value < 0:
        value = 0.0
    return int(value + 0.5)


def pct_of(weight, side):
    if not isinstance(side, dict):
        return None
    budget = side.get("budget_usd")
    if not isinstance(budget, (int, float)) or budget <= 0:
        return None
    return round_pct(weight / budget * 100.0)


def hhmm(ms):
    moment = datetime.fromtimestamp(ms / 1000, timezone.utc).astimezone()
    return f"{moment.hour:02d}:{moment.minute:02d}"


def age_text(at_iso, now):
    try:
        text = at_iso[:-1] + "+00:00" if isinstance(at_iso, str) and at_iso.endswith("Z") else at_iso
        then = datetime.fromisoformat(text)
    except (TypeError, ValueError):
        return None
    if then.tzinfo is None:
        then = then.replace(tzinfo=timezone.utc)
    seconds = (now - then).total_seconds()
    if seconds < 0:
        seconds = 0
    if seconds < 45:
        return "0m"
    if seconds < 90 * 60:
        return f"{int(seconds / 60 + 0.5)}m"
    if seconds < 48 * 3600:
        return f"{int(seconds / 3600 + 0.5)}h"
    return f"{int(seconds / 86400 + 0.5)}d"


def format_status(start, w5, week, cal, now):
    five = cal.get("five_hour") if isinstance(cal, dict) else None
    weekly = cal.get("weekly") if isinstance(cal, dict) else None
    p5 = pct_of(w5, five)
    p7 = pct_of(week, weekly)
    five_txt = "n/a" if p5 is None else f"~{p5}%"
    week_txt = "n/a" if p7 is None else f"~{p7}%"
    resets = hhmm(start + BLOCK_MS) if start is not None else "--:--"
    stamp = None
    if isinstance(five, dict) and five.get("at"):
        stamp = five.get("at")
    elif isinstance(weekly, dict) and weekly.get("at"):
        stamp = weekly.get("at")
    age = age_text(stamp, now) if stamp else None
    tail = f"calibrated {age}" if age else "uncalibrated"
    return f"5h {five_txt} (resets {resets}), week {week_txt}, {tail}"


def notice_text(kind, pct):
    # User rule (2026-10-22): only the 5-hour window triggers the 78% hand-off; the weekly figure is information only.
    label = "5-hour" if kind == "5-hour" else "weekly"
    if kind == "5-hour" and pct >= 78:
        return f"Usage ~{pct}% of the 5-hour window (estimate): hand off per the 78% rule"
    if kind != "5-hour":
        return f"Usage ~{pct}% of the weekly window (estimate; information only, no hand-off)."
    return f"Usage ~{pct}% of the {label} window (estimate)."


HOOK_EVENT = "UserPromptSubmit"  # --event: the hook event this run answers (UserPromptSubmit or PostToolUse)


def hook_output(text):
    payload = {
        "hookSpecificOutput": {
            "hookEventName": HOOK_EVENT,
            "additionalContext": text,
        }
    }
    sys.stdout.write(json.dumps(payload, ensure_ascii=True) + "\n")


def load_state(path):
    data = load_json(path)
    if not isinstance(data, dict) or data.get("v") != 1:
        data = {"v": 1, "five_hour": {"window_start": None, "notified": []}, "weekly": {"notified": []}}
    if not isinstance(data.get("five_hour"), dict):
        data["five_hour"] = {"window_start": None, "notified": []}
    if not isinstance(data.get("weekly"), dict):
        data["weekly"] = {"notified": []}
    return data


def as_int_list(value):
    if not isinstance(value, list):
        return []
    out = []
    for item in value:
        if isinstance(item, int) and not isinstance(item, bool):
            out.append(item)
    return out


def cross(pct, notified):
    """Return (kept, newly crossed). kept drops thresholds the percent fell under."""
    if pct is None:
        return notified, []
    kept = {t for t in notified if pct >= t}
    new = [t for t in THRESHOLDS if pct >= t and t not in kept]
    return kept, new


def run_hook(start, p5, p7, state_path, week_start=None, week_anchored=False):
    state = load_state(state_path)
    five = state["five_hour"]
    if five.get("window_start") != start:
        five["window_start"] = start
        five["notified"] = []
    notified5 = set(as_int_list(five.get("notified")))
    kept5, new5 = cross(p5, notified5)
    weekly = state["weekly"]
    if week_anchored and weekly.get("window_start") != week_start:
        weekly["window_start"] = week_start
        weekly["notified"] = []
    notified7 = set(as_int_list(weekly.get("notified")))
    kept7, new7 = cross(p7, notified7)
    five["notified"] = sorted(kept5 | set(new5))
    weekly["notified"] = sorted(kept7 | set(new7))
    chosen = None
    if new5 or new7:
        cands = []
        if new5:
            cands.append(("5-hour", p5))
        if new7:
            cands.append(("weekly", p7))
        hot = [item for item in cands if item[1] >= 78]
        chosen = max(hot, key=lambda item: item[1]) if hot else cands[0]
    fresh = {"v": 1, "five_hour": five, "weekly": weekly}
    if fresh != load_state(state_path):
        atomic_write(state_path, fresh)
    if chosen is not None:
        hook_output(notice_text(chosen[0], chosen[1]))


def apply_calibration(path, now, pct5, w5, pct7, w7, five_resets, week_resets, note):
    if w5 <= 0:
        fail("current 5-hour window has no weighted usage; refused to calibrate")
    if pct7 is not None and w7 <= 0:
        fail("weekly window has no weighted usage; refused to calibrate")
    current = load_json(path) or {}
    weekly = current.get("weekly") if isinstance(current.get("weekly"), dict) else None
    stamp = now.isoformat()
    five = {
        "percent": pct5,
        "weighted_usd": w5,
        "budget_usd": w5 / (pct5 / 100.0),
        "at": stamp,
    }
    if five_resets:
        five["resets_at"] = five_resets
    if isinstance(note, str) and note.strip():
        five["note"] = note.strip()
    if pct7 is not None:
        weekly = {
            "percent": pct7,
            "weighted_usd": w7,
            "budget_usd": w7 / (pct7 / 100.0),
            "at": stamp,
        }
        if week_resets:
            weekly["resets_at"] = week_resets
    atomic_write(path, {"v": 1, "five_hour": five, "weekly": weekly})


def stored_end(side):
    if not isinstance(side, dict):
        return None, None
    iso = side.get("resets_at")
    if not isinstance(iso, str) or not iso:
        return None, None
    ms = parse_ts_ms(iso)
    if ms is None:
        return None, None
    return iso, ms


def as_local(naive, label):
    try:
        return naive.astimezone()
    except (OSError, OverflowError, ValueError):
        fail(label)


def next_local_hhmm(text, now_utc):
    match = re.fullmatch(r"(\d{2}):(\d{2})", text.strip())
    if match is None:
        fail("--resets must be HH:MM in local time")
    hour = int(match.group(1))
    minute = int(match.group(2))
    if hour > 23 or minute > 59:
        fail("--resets must be HH:MM in local time")
    local_now = now_utc.astimezone()
    naive = local_now.replace(hour=hour, minute=minute, second=0, microsecond=0, tzinfo=None)
    candidate = as_local(naive, "--resets must be HH:MM in local time")
    if candidate <= now_utc:
        candidate = as_local(naive + timedelta(days=1), "--resets must be HH:MM in local time")
    return candidate


def parse_local_stamp(text):
    label = '--weekly-resets must be "YYYY-MM-DD HH:MM" in local time'
    match = re.fullmatch(r"(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})", text.strip())
    if match is None:
        fail(label)
    year, month, day, hour, minute = (int(part) for part in match.groups())
    if hour > 23 or minute > 59:
        fail(label)
    try:
        naive = datetime(year, month, day, hour, minute)
    except ValueError:
        fail(label)
    return as_local(naive, label)


def parse_now(text):
    if text is None:
        return datetime.now(timezone.utc)
    raw = text[:-1] + "+00:00" if text.endswith("Z") else text
    try:
        parsed = datetime.fromisoformat(raw)
    except ValueError:
        fail("--now must be an ISO timestamp")
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def build_parser():
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("--status", action="store_true")
    parser.add_argument("--hook", action="store_true")
    parser.add_argument("--event", default="UserPromptSubmit", choices=["UserPromptSubmit", "PostToolUse"])
    parser.add_argument("--calibrate", metavar="PCT")
    parser.add_argument("--resets", metavar="HH:MM")
    parser.add_argument("--weekly", metavar="PCT")
    parser.add_argument("--weekly-resets", metavar="YYYY-MM-DD HH:MM")
    parser.add_argument("--note")
    parser.add_argument("--root", action="append", default=None)
    parser.add_argument("--state", default=None)
    parser.add_argument("--cache", default=None)
    parser.add_argument("--calibration", default=None)
    parser.add_argument("--now", default=None)
    return parser


def main(argv):
    args = build_parser().parse_args(argv)
    if args.weekly is not None and args.calibrate is None:
        fail("--weekly requires --calibrate")
    if args.resets is not None and args.calibrate is None:
        fail("--resets requires --calibrate")
    if args.weekly_resets is not None and args.weekly is None:
        fail("--weekly-resets requires --weekly")
    if args.note is not None and args.calibrate is None:
        fail("--note requires --calibrate")
    global HOOK_EVENT
    HOOK_EVENT = args.event
    if args.hook and args.status:
        fail("pass only one of --hook and --status")
    now = parse_now(args.now)
    if args.root:
        roots = [Path(item) for item in args.root]
        for root in roots:
            if not root.is_dir():
                fail("transcript root is not a directory")
        base = repo_path("logs", "grok", "usage-meter-root")
        cache_path = Path(args.cache) if args.cache else base / "cache.json"
        state_path = Path(args.state) if args.state else base / "state.json"
        cal_path = Path(args.calibration) if args.calibration else base / "calibration.json"
    else:
        roots = default_roots()
        cache_path = Path(args.cache) if args.cache else repo_path("logs", "usage_meter_cache.json")
        state_path = Path(args.state) if args.state else repo_path("logs", "usage_meter_state.json")
        cal_path = Path(args.calibration) if args.calibration else repo_path("logs", "usage_calibration.json")
    existing = load_json(cal_path) or {}
    old_five = existing.get("five_hour") if isinstance(existing.get("five_hour"), dict) else None
    old_week = existing.get("weekly") if isinstance(existing.get("weekly"), dict) else None
    if args.resets is not None:
        five_dt = next_local_hhmm(args.resets, now)
        five_iso, five_end = five_dt.isoformat(), to_ms(five_dt)
    else:
        five_iso, five_end = stored_end(old_five)
    if args.weekly_resets is not None:
        week_dt = parse_local_stamp(args.weekly_resets)
        week_iso, week_end = week_dt.isoformat(), to_ms(week_dt)
    else:
        week_iso, week_end = stored_end(old_week)
    merged = load_entries(roots, cache_path)
    now_ms = to_ms(now)
    start, w5, week, week_start, week_anchored = window_view(merged, now_ms, five_end, week_end)
    if args.calibrate is not None:
        pct5 = parse_pct(args.calibrate)
        pct7 = parse_pct(args.weekly) if args.weekly is not None else None
        apply_calibration(
            cal_path, now, pct5, w5, pct7, week, five_iso, week_iso, args.note
        )
    cal = load_json(cal_path) or {}
    p5 = pct_of(w5, cal.get("five_hour") if isinstance(cal, dict) else None)
    p7 = pct_of(week, cal.get("weekly") if isinstance(cal, dict) else None)
    if args.hook:
        run_hook(start, p5, p7, state_path, week_start, week_anchored)
        return 0
    sys.stdout.write(format_status(start, w5, week, cal, now) + "\n")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except BrokenPipeError:
        raise SystemExit(0)
