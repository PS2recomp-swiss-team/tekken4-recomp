"""Copy the SCE SDK names found by ps2_analyzer into the open Ghidra program.

ExportPS2Functions.java doesn't use the SCE symbol database, so without this step the
Ghidra export loses every SDK name and the recompiler can't bind runtime handlers.

Usage (Ghidra open on SLUS_203.28 with GhidraMCPPlugin enabled):
  python -I tools/ghidra_apply_sdk_names.py            # dry run, prints what would change
  python -I tools/ghidra_apply_sdk_names.py --apply    # rename in Ghidra

Only renames a function whose start address matches exactly and whose name is still a
Ghidra default (FUN_...). Never touches names set by hand.
"""
import argparse
import json
import re
import sys
import tomllib
import urllib.error
import urllib.parse
import urllib.request

GENERIC_HANDLERS = {"ret0", "ret1", "reta0"}


def call(base, method, endpoint, **params):
    data = urllib.parse.urlencode(params)
    if method == "GET":
        req = urllib.request.Request(f"{base}{endpoint}?{data}")
    else:
        req = urllib.request.Request(f"{base}{endpoint}", data=data.encode(), method="POST")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = json.load(resp)
    except urllib.error.HTTPError as e:  # GhidraMCP reports errors as JSON with a 4xx status
        body = json.load(e)
    if not body.get("success"):
        raise RuntimeError(f"{endpoint}: {body.get('error')}")
    return body.get("data")


def sdk_names(toml_path):
    with open(toml_path, "rb") as f:
        general = tomllib.load(f)["general"]
    names = {}
    for key in ("stubs", "entry_points", "untracked_stubs"):
        for entry in general.get(key, []):
            m = re.fullmatch(r"(.+)@0x([0-9A-Fa-f]+)", entry)
            if m and m.group(1) not in GENERIC_HANDLERS:
                names[int(m.group(2), 16)] = m.group(1)
    return names


def ghidra_functions(base):
    funcs, offset = {}, 0
    while True:
        page = call(base, "GET", "functions", offset=offset, limit=1000)
        for item in page["items"]:
            funcs[int(item["address"], 16)] = item["name"]
        if not page["has_more"]:
            return funcs
        offset += len(page["items"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--toml", default="config/analyzer_seed.toml")
    ap.add_argument("--server", default="http://127.0.0.1:8080/")
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    wanted = sdk_names(args.toml)
    have = ghidra_functions(args.server)
    print(f"SDK names in {args.toml}: {len(wanted)}   Ghidra functions: {len(have)}")

    rename, already, conflict, missing = [], [], [], []
    for addr, name in sorted(wanted.items()):
        current = have.get(addr)
        if current is None:
            missing.append((addr, name))
        elif current == name:
            already.append((addr, name))
        elif current.startswith("FUN_"):
            rename.append((addr, name))
        else:
            conflict.append((addr, name, current))

    print(f"to rename: {len(rename)}  already named: {len(already)}  "
          f"conflicts (non-default name, left alone): {len(conflict)}  "
          f"no Ghidra function at that address: {len(missing)}")
    for addr, name, current in conflict:
        print(f"  conflict 0x{addr:08x} ghidra={current} analyzer={name}")
    for addr, name in missing:
        print(f"  missing  0x{addr:08x} {name}")

    if not args.apply:
        print("dry run; pass --apply to rename")
        return
    failed = 0
    for addr, name in rename:
        try:
            call(args.server, "POST", "rename_function_by_address", function_address=f"{addr:08x}", new_name=name)
        except Exception as e:  # report and keep going
            failed += 1
            print(f"  FAILED 0x{addr:08x} {name}: {e}", file=sys.stderr)
    print(f"renamed {len(rename) - failed}, failed {failed}")


if __name__ == "__main__":
    main()
