#!/usr/bin/env python3
"""Turn a PCSX2 .pnach into runtime-switchable [patches] instructions.

Reads a .pnach file or one entry of a zip (PCSX2's patches.zip). Checks the
CRC in the file name against the ELF (XOR of every little-endian word, the
PCSX2 CRC). Each [section] becomes one switch name. Words the recompiler
cannot switch are omitted and printed as comments:

  - branch or jump words (the emitter ignores a switch on the branch itself,
    and throws if the patched word is a branch or jump)
  - delay slots of a branch or jump (function_emitter.cpp throws)
  - words outside a function in the Ghidra map (never recompiled)
  - functions in [general].skip
  - library functions the runtime replaces (configured stub or a PS2_STUB_LIST
    name whose handler resolves in ps2_call_list.h)

Switch names: "Widescreen 16:9" -> widescreen, "No-Interlacing" -> no_interlace.
Anything else is a lowercase slug of the section title.

  python -I tools/pnach_to_switch.py --entry SCES-50878_2251E14D.pnach external/pcsx2/resources/patches.zip
  python -I tools/pnach_to_switch.py --elf game/disc/SCES_508.78 game.pnach

Exit codes: 0 ok (flagged words are still exit 0), 2 bad input or CRC mismatch.
"""

from __future__ import print_function

import argparse
import importlib.util
import os
import re
import sys
import zipfile

TOOL = "pnach_to_switch.py"

# PCSX2's built-in group titles, and the switch names this port already uses.
SWITCH_ALIASES = {
    "widescreen 16:9": "widescreen",
    "widescreen": "widescreen",
    "no-interlacing": "no_interlace",
    "no interlacing": "no_interlace",
    "no-interlace": "no_interlace",
    "no interlace": "no_interlace",
}

# REGIMM rt values that are branches (the rest are traps, no delay slot).
_REGIMM_BRANCH = (0, 1, 2, 3, 16, 17, 18, 19)


def fail(msg):
    print("%s: error: %s" % (TOOL, msg), file=sys.stderr)
    return 2


def repo_of(config_path):
    folder = os.path.dirname(os.path.abspath(config_path))
    if os.path.basename(folder).lower() == "config":
        return os.path.dirname(folder)
    return os.getcwd()


def load_pnach_module():
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(here, "console-skill", "console-mod", "pnach.py")
    if not os.path.isfile(path):
        raise RuntimeError("vendored pnach.py not found: %s" % path)
    spec = importlib.util.spec_from_file_location("pnach_vendor", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def read_text(path):
    with open(path, "rb") as f:
        data = f.read()
    if data.startswith(b"\xef\xbb\xbf"):
        data = data[3:]
    return data.decode("utf-8", "replace")


def toml_string_array(text, key):
    """Body of a top-level `key = [ ... ]` array, as the quoted strings inside it."""
    match = re.search(r"(?m)^%s\s*=\s*\[" % re.escape(key), text)
    if not match:
        return []
    depth = 1
    chars = []
    for ch in text[match.end():]:
        if ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0:
                break
        chars.append(ch)
    return re.findall(r'"([^"]*)"', "".join(chars))


def toml_string(text, key):
    match = re.search(r'(?m)^%s\s*=\s*"([^"]*)"' % re.escape(key), text)
    return match.group(1) if match else None


def parse_selectors(items):
    """'Name@0xADDR' from the recompiler config. Returns (names, starts, bind)."""
    names = set()
    starts = set()
    bind = {}
    for item in items:
        name, _, addr = item.partition("@")
        name = name.strip()
        if name:
            names.add(name)
        if addr:
            try:
                start = int(addr.strip(), 16)
            except ValueError:
                continue
            starts.add(start)
            if name:
                bind[start] = name
    return names, starts, bind


def macro_names(text, macro):
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if not line.startswith("#define %s" % macro):
            continue
        buf = [line]
        while buf[-1].rstrip().endswith("\\") and i + 1 < len(lines):
            i += 1
            buf.append(lines[i])
        return re.findall(r"\bX\(([A-Za-z_][A-Za-z0-9_]*)\)", "\n".join(buf))
    return []


def resolves(name, stubs, syscalls):
    """Same alias rule as ps2_runtime_calls::resolveNameWithOptionalLeadingUnderscoreAlias."""
    def hit(table):
        if name in table:
            return True
        if name.startswith("_") and name[1:] in table:
            return True
        if ("_" + name) in table:
            return True
        return False
    if hit(syscalls):
        return "syscall"
    if hit(stubs):
        return "stub"
    return None


def find_calls_header(repo):
    candidates = []
    env = os.environ.get("TEKKEN4_SRC")
    if env:
        candidates.append(os.path.join(env, "ps2xRuntime", "include", "ps2_call_list.h"))
    candidates.append(os.path.normpath(os.path.join(
        repo, "..", "tekken4-fork-ps2recomp", "ps2xRuntime", "include", "ps2_call_list.h")))
    candidates.append(r"H:\tekken4-fork-ps2recomp\ps2xRuntime\include\ps2_call_list.h")
    for path in candidates:
        if path and os.path.isfile(path):
            return path
    return None


def transfer_kind(word):
    """'branch' or 'jump' when the word is a control transfer with a delay slot.

    Matches the cases R5900Decoder marks isBranch/isJump/hasDelaySlot for the
    ordinary MIPS encodings (j/jal, branches, jr/jalr, bc0/bc1/bc2). Traps and
    eret are not included: the emitter does not reject those.
    """
    op = (word >> 26) & 0x3F
    if op == 0:
        fn = word & 0x3F
        if fn in (0x08, 0x09):  # jr, jalr
            return "jump"
        return None
    if op in (0x02, 0x03):  # j, jal
        return "jump"
    if op in (0x04, 0x05, 0x06, 0x07, 0x14, 0x15, 0x16, 0x17):
        return "branch"
    if op == 0x01:  # regimm
        rt = (word >> 16) & 31
        if rt in _REGIMM_BRANCH:
            return "branch"
        return None
    if op in (0x10, 0x11, 0x12):  # cop0/cop1/cop2 bc*
        rs = (word >> 21) & 31
        if rs == 8:
            return "branch"
        return None
    return None


def switch_name(section):
    key = (section or "").strip().lower()
    if key in SWITCH_ALIASES:
        return SWITCH_ALIASES[key]
    slug = re.sub(r"[^a-z0-9]+", "_", key).strip("_")
    if not slug:
        return "ungrouped"
    if slug[0].isdigit():
        slug = "p_" + slug
    return slug


def load_source(pn, path, entry):
    """Return (parse result, display name). path is a .pnach or a .zip."""
    if entry or path.lower().endswith(".zip"):
        if not os.path.isfile(path):
            raise pn.UsageError("zip not found: %s" % path)
        try:
            zf = zipfile.ZipFile(path)
        except zipfile.BadZipFile:
            raise pn.UsageError("not a zip: %s" % path)
        names = zf.namelist()
        if not entry:
            shown = [n for n in names if n.lower().endswith(".pnach")]
            raise pn.UsageError("zip entry required (--entry NAME). pnach entries: %s"
                                % ", ".join(shown[:20]))
        want = entry.replace("\\", "/").split("/")[-1].lower()
        hits = [n for n in names if n.replace("\\", "/").split("/")[-1].lower() == want]
        if not hits:
            raise pn.UsageError("no zip entry named %s" % entry)
        if len(hits) > 1:
            raise pn.UsageError("several zip entries named %s: %s" % (entry, ", ".join(hits)))
        raw = zf.read(hits[0])
        if b"\0" in raw[:4096]:
            raise pn.UsageError("%s looks binary, not a .pnach" % hits[0])
        res = pn.parse_pnach_text(raw.decode("utf-8", "replace"))
        res["path"] = path + "!" + hits[0]
        res["name"] = hits[0].replace("\\", "/").split("/")[-1]
        return res
    res = pn.load_pnach(path)
    return res


def filter_sections(pn, res, only):
    if not only:
        return res
    wanted = set(only)
    missing = [s for s in only if s not in res["sections"] and s != ""]
    if missing:
        raise pn.UsageError("section(s) not in %s: %s (have: %s)" % (
            res["name"], ", ".join(missing), ", ".join(res["sections"]) or "none"))
    for key in ("writes", "manual"):
        res[key] = [w for w in res[key] if w["section"] in wanted]
    return res


def function_at(funcs, addr):
    for start, end, name in funcs:
        if start <= addr < end:
            return start, end, name
        if start > addr:
            break
    return None


def main(argv=None):
    pn = load_pnach_module()
    parser = argparse.ArgumentParser(prog=TOOL, description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("pnach", help=".pnach file, or a .zip together with --entry")
    parser.add_argument("--entry", help="member of a zip (basename match, e.g. SCES-50878_2251E14D.pnach)")
    parser.add_argument("--elf", help="ELF to check the CRC against and to read original words from")
    parser.add_argument("--config", default="config/ghidra_export.toml",
                        help="recompiler toml (stubs, skip, default elf and function map)")
    parser.add_argument("--functions", help="function map CSV (Name,Start,End,Size). Default: ghidra_output in the config")
    parser.add_argument("--calls", help="ps2_call_list.h (default: the fork tree next to this repo)")
    parser.add_argument("--section", action="append", metavar="NAME", help="only this [section] (repeatable)")
    parser.add_argument("--ignore-crc", action="store_true",
                        help="classify even when the CRC in the file name is not this ELF's")
    args = parser.parse_args(argv)

    config_path = args.config
    if not os.path.isfile(config_path):
        return fail("config not found: %s" % config_path)
    config_text = read_text(config_path)
    repo = repo_of(config_path)

    elf_path = args.elf
    if not elf_path:
        rel = toml_string(config_text, "input")
        if not rel:
            return fail("no --elf and %s has no input =" % config_path)
        elf_path = rel if os.path.isabs(rel) else os.path.join(repo, rel.replace("/", os.sep))
    if not os.path.isfile(elf_path):
        return fail("ELF not found: %s" % elf_path)

    map_path = args.functions
    if not map_path:
        rel = toml_string(config_text, "ghidra_output") or "config/function_map.csv"
        map_path = rel if os.path.isabs(rel) else os.path.join(repo, rel.replace("/", os.sep))
    if not os.path.isfile(map_path):
        return fail("function map not found: %s" % map_path)

    calls_path = args.calls or find_calls_header(repo)
    stub_names_rt = set()
    syscall_names = set()
    calls_note = None
    if calls_path and os.path.isfile(calls_path):
        calls_text = read_text(calls_path)
        stub_names_rt = set(macro_names(calls_text, "PS2_STUB_LIST"))
        syscall_names = set(macro_names(calls_text, "PS2_SYSCALL_LIST"))
        if not stub_names_rt:
            calls_note = "no PS2_STUB_LIST in %s; every configured stub is treated as replaced" % calls_path
    else:
        calls_path = None
        calls_note = "ps2_call_list.h not found; every configured stub is treated as replaced"

    try:
        src = load_source(pn, args.pnach, args.entry)
        src = filter_sections(pn, src, args.section)
    except pn.UsageError as exc:
        return fail(str(exc))

    elf = pn.Elf(elf_path)
    have = elf.pcsx2_crc()
    want = pn.crc_from_pnach_name(src["name"])
    crc_note = "file name has no PCSX2 CRC"
    if want is not None and want != have and not args.ignore_crc:
        return fail("%s is for PCSX2 CRC %08X but %s has %08X "
                    "(addresses will not line up; --ignore-crc to classify anyway)"
                    % (src["name"], want, elf.name, have))
    if want is not None and want != have:
        crc_note = "name says %08X, ELF has %08X (--ignore-crc)" % (want, have)
    elif want is not None:
        crc_note = "name %08X matches ELF" % have

    funcs = []
    for start, end, name in pn.FuncMap(map_path).ranges:
        funcs.append((start, end, name))

    stub_cfg_names, stub_starts, stub_bind = parse_selectors(toml_string_array(config_text, "stubs"))
    skip_names, skip_starts, _ = parse_selectors(toml_string_array(config_text, "skip"))

    def replaced(func):
        start, _end, name = func
        configured = start in stub_starts or name in stub_cfg_names
        by_list = resolves(name, stub_names_rt, set()) == "stub"
        if not configured and not by_list:
            return None
        handler = stub_bind.get(start, name)
        if not calls_path:
            # Export policy: [general].stubs are the runtime-known names.
            if configured or by_list:
                return handler or name
            return None
        if resolves(handler, stub_names_rt, syscall_names):
            return handler
        return None

    try:
        classified = pn.classify(src, elf, pn.FuncMap(map_path))
    except pn.UsageError as exc:
        return fail(str(exc))

    accepted = []
    flagged = []

    for key in ("gsaspectratio", "gsinterlacemode", "author", "description", "comment"):
        if key not in ("gsaspectratio", "gsinterlacemode"):
            continue
        for item in src["meta"].get(key, []):
            if args.section and item["section"] not in args.section:
                continue
            flagged.append((0, "# flag [%s] %s=%s: PCSX2 display setting, not an EE instruction"
                            % (item["section"] or "ungrouped", key, item["value"])))

    seen_manual = set()
    for manual in classified["manual"]:
        line = manual.get("line", 0)
        if line in seen_manual:
            continue
        seen_manual.add(line)
        flagged.append((line, "# flag line %d [%s] %s" % (
            line, manual.get("section") or "ungrouped", manual.get("reason", "manual"))))

    for cw in classified["code"]:
        addr = cw["vaddr"]
        section = next((s for s in cw["sections"] if s), "")
        reasons = []
        func = function_at(funcs, addr)
        if func is None:
            reasons.append("outside every function in %s (not recompiled)" % os.path.basename(map_path))
        else:
            start, _end, name = func
            if start in skip_starts or name in skip_names:
                reasons.append("function %s is in [general].skip (not recompiled)" % name)
            handler = replaced(func)
            if handler:
                reasons.append("runtime replaces library function %s (stub %s)" % (name, handler))
            if addr - 4 >= start:
                prev = elf.read_ram(addr - 4, 4)
                if prev and len(prev) == 4:
                    prev_word = int.from_bytes(prev, "little")
                    kind = transfer_kind(prev_word)
                    if kind:
                        reasons.append("delay slot of the %s at %s (function_emitter.cpp rejects a switch there)"
                                       % (kind, pn.hex32(addr - 4)))
        orig_kind = transfer_kind(cw["original"])
        new_kind = transfer_kind(cw["new"])
        if orig_kind:
            reasons.append("original word is a %s; the recompiler emits that %s and does not apply a switch on it"
                           % (orig_kind, orig_kind))
        if new_kind:
            reasons.append("patched word is a %s (function_emitter.cpp rejects a switch that is a branch or jump)"
                           % new_kind)
        if cw["original"] == cw["new"]:
            reasons.append("no change (ELF already has %s)" % pn.hex32(cw["original"]))
        where = pn.hex32(addr)
        old_txt = pn.describe(cw["original"], addr)
        new_txt = pn.describe(cw["new"], addr)
        if reasons:
            who = func[2] if func else "?"
            flagged.append((min(cw["lines"]), "# flag %s [%s] %s: %s (%s -> %s)" % (
                where, section or "ungrouped", who, "; ".join(reasons), old_txt, new_txt)))
            continue
        accepted.append({
            "line": min(cw["lines"]),
            "addr": addr,
            "value": cw["new"],
            "switch": switch_name(section),
            "comment": "%s -> %s" % (old_txt, new_txt),
        })

    accepted.sort(key=lambda e: (e["line"], e["addr"]))
    flagged.sort(key=lambda e: e[0])

    out = []
    out.append("# pnach_to_switch: %s" % src["name"])
    out.append("# elf %s  PCSX2 CRC %08X  (%s)" % (elf.name, have, crc_note))
    out.append("# config %s  functions %s" % (os.path.basename(config_path), os.path.basename(map_path)))
    if calls_path:
        out.append("# runtime calls %s  (stubs %d, syscalls %d)" % (
            calls_path, len(stub_names_rt), len(syscall_names)))
    if calls_note:
        out.append("# NOTE: " + calls_note)
    out.append("# accepted %d, flagged %d" % (len(accepted), len(flagged)))
    for _line, text in flagged:
        out.append(text)
    out.append("[patches]")
    out.append("instructions = [")
    for entry in accepted:
        out.append('  { address = "%s", value = "%s", switch = "%s" }, # %s' % (
            pn.hex32(entry["addr"]), pn.hex32(entry["value"]), entry["switch"], entry["comment"]))
    out.append("]")
    sys.stdout.write("\n".join(out) + "\n")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        # A missing vendored module or a bug, not a usage error.
        print("%s: error: %s" % (TOOL, exc), file=sys.stderr)
        sys.exit(2)
