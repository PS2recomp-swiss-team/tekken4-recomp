"""Report host presentation intervals without claiming an exclusive hitch cause.

Examples:
  python tools/perf_present_report.py RUN --qpc-freq 10000000 --from 40 --to 100 --out RUN/fight
  python tools/perf_present_report.py RUN/frame_trace.csv --from 40 --to 100 --out RUN/fight

Writes PREFIX.json and PREFIX.hitches.csv (every interval strictly >20 ms).
Modern t_s is relative to ps2_perf_stats::start(), not process creation. t_ns is
an absolute steady-clock value; adjacent present timestamps retain ns precision.
interval_us is truncated by the runtime and used only when no preceding absolute
timestamp exists. Legacy QPC needs a recorded frequency; never infer 10 MHz.
Without --qpc-origin/params perf_start_qpc, legacy zero is the first valid logged
vblank (or first swap), and is NOT a proven process/perf-start epoch. Rounded
[frames] and [hitch] text is deliberately not treated as exact frame timing.

Windows select intervals by their END timestamp: --from inclusive, --to exclusive.
One interval can start before --from. Rates use the intersection of the requested
window and observed interval coverage. Quantiles use linear interpolation.
Counters from EE/GS threads overlap and may lag their actual work. A large swap
or wait counter establishes time in that instrumented span, not its root cause.
This is a swap-return trace, not a monitor scanout or OS scheduler trace.
"""

import argparse
import csv
import io
import json
import math
import re
import sys
from pathlib import Path


NUMBER = re.compile(r"([A-Za-z_][A-Za-z_0-9]*)=(-?\d+(?:\.\d+)?)")
NS_FIELDS = ("upload_ns", "draw_ns", "swap_ns", "shared_wait_ns", "ee_gif_ns",
             "gs_pubwait_ns", "gs_drainwait_ns", "gs_worker_ns", "hostwait_ns")
WARNINGS = [
    "Swap return timestamps do not measure monitor scanout or input latency.",
    "EE/GS counters overlap across threads; never sum them as an exclusive frame breakdown.",
    "Shader compilation, allocation/GC, file I/O, audio/IOP, timer resolution and OS scheduling "
    "cannot be individually proven from these counters; untraced delay remains unknown.",
]


def percentile(values, fraction):
    if not values:
        return None
    ordered = sorted(values)
    position = (len(ordered) - 1) * fraction
    left = math.floor(position)
    right = math.ceil(position)
    return ordered[left] + (ordered[right] - ordered[left]) * (position - left)


def find_metadata(data, names):
    """Known numeric metadata keys only; do not interpret environment text as clocks."""
    if not isinstance(data, dict):
        return None
    for name in names:
        value = data.get(name)
        if value is not None:
            try:
                return float(value)
            except (ValueError, TypeError):
                raise ValueError(f"metadata {name} must be numeric") from None
    for value in data.values():
        if isinstance(value, dict):
            found = find_metadata(value, names)
            if found is not None:
                return found
    return None


def number(raw, key):
    value = raw.get(key)
    if value in (None, ""):
        return None
    try:
        return int(value)
    except ValueError:
        try:
            return float(value)
        except ValueError:
            raise ValueError(f"invalid {key}={value!r}") from None


def modern(path, metadata):
    lines = path.read_text(encoding="utf-8-sig").splitlines()
    warnings = [line for line in lines if line.startswith("#") and "DROPPED" in line]
    data_lines = [(index, line) for index, line in enumerate(lines, 1) if line and not line.startswith("#")]
    reader = csv.DictReader(io.StringIO("\n".join(line for _, line in data_lines)))
    if not reader.fieldnames or not {"kind", "tick"}.issubset(reader.fieldnames):
        raise ValueError("frame trace must have kind and tick headers")
    if "t_s" not in reader.fieldnames and "t_ns" not in reader.fieldnames:
        raise ValueError("frame trace must have t_s or t_ns")
    origin = find_metadata(metadata, ("perf_start_ns", "perf_t0_ns"))
    rows = []
    previous = {}
    for row_index, raw in enumerate(reader, 1):
        index = data_lines[row_index][0]
        if None in raw or any(v is None for v in raw.values()):
            raise ValueError(f"{path}:{index}: row does not match CSV header (possibly truncated)")
        kind = {"p": "present", "g": "guest", "present": "present", "guest": "guest"}.get(raw["kind"])
        if kind is None:
            continue
        try:
            absolute = number(raw, "t_ns")
            relative = number(raw, "t_s")
            if relative is None:
                if origin is None:
                    raise ValueError("t_ns-only trace requires params perf_start_ns")
                relative = (absolute - origin) / 1e9
            elif absolute is not None and origin is None:
                origin = absolute - round(relative * 1e9)
            row = dict(kind=kind, t_s=float(relative), t_ns=absolute, raw=raw,
                       source_line=index, source_file=str(path), tick=number(raw, "tick"),
                       tick_role="completed" if "requested_tick" in raw else "requested")
            prior = previous.get(kind)
            if prior is not None and absolute is not None and prior["t_ns"] is not None:
                row["interval_ms"] = (absolute - prior["t_ns"]) / 1e6
                row["interval_precision"] = "adjacent_absolute_ns"
            elif prior is not None:
                row["interval_ms"] = (relative - prior["t_s"]) * 1000
                row["interval_precision"] = "adjacent_t_s"
            else:
                interval = number(raw, "interval_us")
                row["interval_ms"] = interval / 1000 if interval else None
                row["interval_precision"] = "runtime_truncated_us" if interval else "no_previous_frame"
            if row["interval_ms"] is not None and row["interval_ms"] <= 0:
                raise ValueError("non-increasing timestamps; multiple sessions or invalid clock order")
            row["previous"] = prior
            previous[kind] = row
            rows.append(row)
        except ValueError as error:
            raise ValueError(f"{path}:{index}: {error}") from None
    return rows, {"format": "frame_trace_csv", "time_origin": "perf_stats_start",
                  "perf_start_ns_inferred": origin, "headers": reader.fieldnames,
                  "tick_semantics": "completed surface; requested_tick separate" if "requested_tick" in reader.fieldnames
                  else "legacy requested identity; shared_tick is completed surface when available"}, warnings


def legacy(paths, metadata, frequency, origin):
    events = []
    frequencies = set()
    warnings = []
    for path in paths:
        for index, line in enumerate(path.read_text(encoding="utf-8-sig", errors="replace").splitlines(), 1):
            if "DROPPED" in line:
                warnings.append(line)
            if "[present]" not in line:
                continue
            raw = dict(NUMBER.findall(line.split("[present]", 1)[1]))
            if not {"tick", "vb", "latch", "swap"}.issubset(raw):
                continue
            if int(raw.get("qpc_freq", "0")) > 0:
                frequencies.add(int(raw["qpc_freq"]))
            events.append((path, index, raw))
    if not events:
        raise ValueError("no valid [present] QPC records found")
    if len(frequencies) > 1:
        raise ValueError("conflicting QPC frequencies in input")
    recorded = next(iter(frequencies), None)
    configured = frequency or find_metadata(metadata, ("qpc_freq", "qpc_frequency", "qpc_frequency_hz"))
    if recorded and configured and recorded != configured:
        raise ValueError("explicit/params QPC frequency conflicts with logged frequency")
    frequency = recorded or configured
    if frequency is None or frequency <= 0:
        raise ValueError("legacy QPC frequency absent: pass --qpc-freq or record qpc_freq in params.json")
    if origin is None:
        origin = find_metadata(metadata, ("perf_start_qpc", "qpc_origin", "start_qpc"))
    origin_name = "explicit_or_params_qpc_origin"
    if origin is None:
        first = events[0][2]
        origin = int(first["vb"]) or int(first["swap"])
        origin_name = "first_logged_vblank_or_swap_NOT_perf_start"
        warnings.append("Legacy zero uses first logged vblank/swap; startup alignment with modern t_s is unproven.")
    rows = []
    previous = None
    for path, index, raw in events:
        swap = int(raw["swap"])
        if previous is not None and swap <= int(previous["raw"]["swap"]):
            raise ValueError(f"{path}:{index}: QPC swap not increasing; concatenate only one ordered session")
        row = dict(kind="present", t_s=(swap-origin)/frequency, t_ns=None, raw=raw,
                   source_line=index, source_file=str(path), tick=int(raw["tick"]), tick_role="requested", previous=previous,
                   interval_ms=(swap-int(previous["raw"]["swap"]))*1000/frequency if previous else None,
                   interval_precision="adjacent_QPC" if previous else "no_previous_frame")
        rows.append(row)
        previous = row
    return rows, {"format": "legacy_present_qpc", "qpc_frequency_hz": frequency,
                  "qpc_origin": origin, "time_origin": origin_name}, warnings


def repeated(row, field):
    prior = row["previous"]
    if prior is None:
        return False
    current = number(row["raw"], field)
    previous = number(prior["raw"], field)
    return current is not None and previous is not None and current == previous


def metrics(rows, start, end):
    selected = [row for row in rows if start <= row["t_s"] < end and row["interval_ms"] is not None]
    if not selected:
        return {"intervals": 0, "p50_ms": None, "p95_ms": None, "p99_ms": None,
                "max_ms": None, "over_20ms": 0, "over_20ms_per_minute": None}, selected
    samples = [row["interval_ms"] for row in selected]
    lo = max(start, selected[0]["t_s"] - selected[0]["interval_ms"] / 1000)
    hi = min(end, selected[-1]["t_s"])
    duration = max(0.0, hi-lo)
    count = sum(value > 20 for value in samples)
    shared = [row for row in selected if (number(row["raw"], "shared_sequence") or 0) > 0]
    fresh = [number(row["raw"], "shared_fresh") for row in shared]
    def requested_key(row):
        return "requested_tick" if "requested_tick" in row["raw"] else "tick"
    skipped = sum(max(0, number(row["raw"], requested_key(row))-
                      number(row["previous"]["raw"], requested_key(row))-1)
                  for row in selected if row["previous"] is not None)
    is_present = selected[0]["kind"] == "present"
    return dict(intervals=len(samples), exposure_s=duration, observed_from_s=lo, observed_to_s=hi,
                p50_ms=percentile(samples, .50), p95_ms=percentile(samples, .95),
                p99_ms=percentile(samples, .99), max_ms=max(samples), over_20ms=count,
                over_20ms_per_minute=count*60/duration if duration else None,
                tick_repeats=sum(repeated(row, "tick") for row in selected),
                requested_tick_repeats=sum(repeated(row, requested_key(row)) for row in selected) if is_present else None,
                completed_tick_repeats=sum(repeated(row, "tick") for row in selected if row["tick_role"] == "completed") +
                    sum(repeated(row, "shared_tick") for row in shared if row["tick_role"] != "completed") if is_present else None,
                completed_tick_available=sum(row["tick_role"] == "completed" for row in selected) +
                    sum(number(row["raw"], "shared_tick") is not None for row in shared if row["tick_role"] != "completed")
                    if is_present else 0,
                requested_ticks_skipped=skipped if is_present else None,
                shared_sequence_available=len(shared),
                shared_sequence_repeats=sum(repeated(row, "shared_sequence") for row in shared),
                shared_fresh_true=sum(value == 1 for value in fresh),
                shared_fresh_false=sum(value == 0 for value in fresh),
                shared_fresh_unavailable=len(selected)-len(shared)+sum(value is None for value in fresh)), selected


def evidence(row):
    raw = row["raw"]
    spans = [f"{key}={number(raw, key)/1e6:.3f}ms" for key in NS_FIELDS
             if number(raw, key) is not None and number(raw, key) >= 1_000_000]
    counts = [f"{key}={raw[key]}" for key in ("texdec", "rtup", "drains")
              if number(raw, key)]
    return "; ".join(spans + counts + ["nonexclusive evidence; remaining/root cause unknown"])


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("input", type=Path, help="run folder, frame_trace.csv, or a [present] text log")
    parser.add_argument("--params", type=Path, help="metadata JSON (default: input folder/params.json)")
    parser.add_argument("--qpc-freq", type=float, help="recorded QueryPerformanceFrequency, Hz; legacy only")
    parser.add_argument("--qpc-origin", type=int, help="recorded startup/perf-start QPC; legacy only")
    parser.add_argument("--from", dest="start", type=float, default=0, help="inclusive relative seconds")
    parser.add_argument("--to", dest="end", type=float, default=math.inf, help="exclusive relative seconds")
    parser.add_argument("--label", default="", help="scene/window label, e.g. steady fight")
    parser.add_argument("--out", "--output", required=True, type=Path, help="output prefix, optionally ending .json")
    args = parser.parse_args(argv)
    try:
        if not math.isfinite(args.start) or args.end <= args.start:
            raise ValueError("window requires finite --from < --to")
        folder = args.input if args.input.is_dir() else args.input.parent
        params = args.params or folder / "params.json"
        metadata = json.loads(params.read_text(encoding="utf-8-sig")) if params.exists() else {}
        source = args.input / "frame_trace.csv" if args.input.is_dir() else args.input
        if source.is_file() and source.suffix.lower() == ".csv":
            rows, identity, warnings = modern(source, metadata)
            inputs = [source]
        else:
            inputs = [folder / name for name in ("stderr.txt", "stdout.txt")] if args.input.is_dir() else [args.input]
            inputs = [path for path in inputs if path.exists()]
            rows, identity, warnings = legacy(inputs, metadata, args.qpc_freq, args.qpc_origin)
        present, selected = metrics([row for row in rows if row["kind"] == "present"], args.start, args.end)
        guest, guest_rows = metrics([row for row in rows if row["kind"] == "guest"], args.start, args.end)
        hitches = [row for row in selected + guest_rows if row["interval_ms"] > 20]
        hitches.sort(key=lambda row: (row["t_s"], row["kind"]))
        prefix = args.out.with_suffix("") if args.out.suffix == ".json" else args.out
        prefix.parent.mkdir(parents=True, exist_ok=True)
        json_path = Path(str(prefix) + ".json")
        csv_path = Path(str(prefix) + ".hitches.csv")
        report = dict(label=args.label, inputs=[str(path.resolve()) for path in inputs],
                      params=str(params.resolve()) if params.exists() else None, clock=identity,
                      window=dict(from_s=args.start, to_s=args.end if math.isfinite(args.end) else None,
                                  selection="interval end >= from and < to"),
                      present=present, guest=guest, hitches_csv=str(csv_path.resolve()),
                      hitch_rows=len(hitches), trace_incomplete=any("DROPPED" in warning for warning in warnings),
                      warnings=WARNINGS + warnings,
                      precision="Adjacent absolute timestamps preferred; legacy QPC/frequency; first CSV interval_us truncated.")
        json_path.write_text(json.dumps(report, indent=2, allow_nan=False) + "\n", encoding="utf-8")
        raw_keys = sorted({key for row in hitches for key in row["raw"]})
        with csv_path.open("w", encoding="utf-8", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=["kind", "relative_s", "interval_ms", "interval_precision",
                                                       "source_file", "source_line", "evidence"] + ["raw_"+key for key in raw_keys])
            writer.writeheader()
            for row in hitches:
                record = dict(kind=row["kind"], relative_s=f"{row['t_s']:.9f}",
                              interval_ms=f"{row['interval_ms']:.9f}", interval_precision=row["interval_precision"],
                              source_file=row["source_file"], source_line=row["source_line"], evidence=evidence(row))
                record.update({"raw_"+key: value for key, value in row["raw"].items()})
                writer.writerow(record)
        print(json.dumps({"json": str(json_path), "hitches_csv": str(csv_path), "present": present}, allow_nan=False))
        return 0
    except (ValueError, OSError, csv.Error) as error:
        parser.error(str(error))


if __name__ == "__main__":
    sys.exit(main())
