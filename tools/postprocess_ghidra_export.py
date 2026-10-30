"""Clean up ExportPS2Functions.java output so it can be used and committed.

Run after every export (Ghidra open with GhidraMCPPlugin enabled):
  python -I tools/postprocess_ghidra_export.py

- Rewrites the absolute paths in config/ghidra_export.toml to repo-relative ones and
  sends recompiler output to generated/ (the script's default, config/output, would be committed).
- Writes config/ghidra_functions_only.csv: the export minus Ghidra's ~23k code labels
  (entry_*, caseD_*, ...). PS2Recomp turns every label into its own entry point, which tripled
  the generated code (77 MB -> 286 MB) and doubled the unresolved-JR warnings, while the
  recompiler already derives ~31k internal entry points itself. If a runtime "function not found"
  ever points at a label address, switch ghidra_output back to config/ghidra_functions.csv.
- Writes config/function_map.csv (what the recompiler reads): those functions plus
  config/extra_functions.csv, the ones Ghidra never found (tools/find_missing_functions.py).
"""
import csv
import re
import sys

sys.path.insert(0, "tools")
from ghidra_apply_sdk_names import ghidra_functions  # noqa: E402

TOML = "config/ghidra_export.toml"
FULL_CSV = "config/ghidra_functions.csv"
FUNCS_CSV = "config/ghidra_functions_only.csv"
EXTRA_CSV = "config/extra_functions.csv"
MAP_CSV = "config/function_map.csv"


def main():
    # --starts <file>: the function starts tools\ghidra_headless.cmd wrote (DumpFunctionStarts.java), no GhidraMCP
    if "--starts" in sys.argv:
        with open(sys.argv[sys.argv.index("--starts") + 1]) as f:
            starts = {int(line, 16) for line in f if line.strip()}
    else:
        starts = set(ghidra_functions("http://127.0.0.1:8080/"))
    with open(FULL_CSV, newline="") as f:
        rows = list(csv.reader(f))
    keep = [rows[0]] + [r for r in rows[1:] if int(r[1], 16) in starts]
    with open(FUNCS_CSV, "w", newline="") as f:
        csv.writer(f).writerows(keep)
    print(f"{FUNCS_CSV}: kept {len(keep) - 1} function rows of {len(rows) - 1} (Ghidra has {len(starts)} functions)")

    with open(EXTRA_CSV, newline="") as f:
        extra = [r for r in list(csv.reader(f))[1:] if int(r[1], 16) not in starts]
    merged = sorted(keep[1:] + extra, key=lambda r: int(r[1], 16))
    with open(MAP_CSV, "w", newline="") as f:
        csv.writer(f).writerows([keep[0]] + merged)
    print(f"{MAP_CSV}: {len(keep) - 1} Ghidra functions + {len(extra)} from {EXTRA_CSV}")

    with open(TOML) as f:
        text = f.read()
    for key, value in (("input", "game/disc/SLUS_203.28"), ("output", "generated/"), ("ghidra_output", MAP_CSV)):
        text = re.sub(rf"^{key} = .*$", f'{key} = "{value}"', text, count=1, flags=re.M)
    with open(TOML, "w") as f:
        f.write(text)
    print(f"{TOML}: input/output/ghidra_output set to repo-relative paths")


if __name__ == "__main__":
    main()
