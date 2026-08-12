#!/usr/bin/env python3
"""Generate/check the machine-readable persistent-state inventory for s32_v60.

This is deliberately a source inventory rather than an HDL parser.  The V60
core follows a constrained declaration style; this program fails when that
style changes, or when an assignment target cannot be tied to an inventoried
module-scope symbol.  That makes adding state an explicit review event.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "rtl/cpu/v60/s32_v60.sv"
MANIFEST = ROOT / "verif/v60/state_inventory.json"
INCLUDE = ROOT / "verif/v60/v60_state_accessors.svh"


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def names_from_decl(body: str) -> list[str]:
    body = re.sub(r"\[[^\]]+\]", " ", body)
    result = []
    for item in body.split(","):
        item = item.split("=")[0].strip()
        m = re.match(r"([A-Za-z_]\w*)", item)
        if m:
            result.append(m.group(1))
    return result


def inventory() -> dict:
    raw = SOURCE.read_text(encoding="utf-8")
    text = strip_comments(raw)
    lines = text.splitlines()
    declarations: dict[str, dict] = {}
    constants: list[str] = []
    wires: list[str] = []
    automatic: list[str] = []
    depth = 0
    in_subprogram = False
    # Ports which are storage are part of the context just like internal regs.
    header = text[: text.find(");") + 2]
    for m in re.finditer(r"\boutput\s+reg\s*(\[[^\]]+\])?\s*([A-Za-z_]\w*)", header):
        declarations[m.group(2)] = {"kind": "output_reg", "width": (m.group(1) or "1").strip(), "line": text[:m.start()].count("\n") + 1}

    for lineno, line in enumerate(lines, 1):
        s = line.strip()
        if re.match(r"^(function|task)\b", s):
            in_subprogram = True
        if not in_subprogram and depth == 0:
            m = re.match(r"^(reg|integer|wire|localparam)\b\s*(signed\s+)?(\[[^\]]+\]\s*)?(.*?);\s*$", s)
            if m:
                kind, signed, width, body = m.group(1), m.group(2), m.group(3), m.group(4)
                for name in names_from_decl(body):
                    if kind in ("reg", "integer"):
                        declarations[name] = {"kind": kind, "width": (width or ("integer" if kind == "integer" else "1")).strip(), "signed": bool(signed), "line": lineno}
                    elif kind == "wire":
                        wires.append(name)
                    else:
                        constants.append(name)
            m = re.match(r"^(st_t|cls_t)\s+(.*?);", s)
            if m:
                for name in names_from_decl(m.group(2)):
                    declarations[name] = {"kind": m.group(1), "width": "[6:0]" if m.group(1) == "st_t" else "[4:0]", "line": lineno}
        if in_subprogram:
            for m in re.finditer(r"\b(?:input|output|inout|logic|reg|integer)\b\s*(?:logic\s+|reg\s+)?(?:signed\s+)?(?:\[[^\]]+\]\s*)?([A-Za-z_]\w*)", s):
                automatic.append(m.group(1))
        if re.match(r"^(endfunction|endtask)\b", s):
            in_subprogram = False

    # Combinational blocks are the only module-scope regs which are not state.
    comb_targets: set[str] = set()
    for block in re.findall(r"always\s*@\*\s*begin(.*?)\bend\b", text, flags=re.S):
        comb_targets.update(re.findall(r"(?<![.\w])([A-Za-z_]\w*)(?:\s*\[[^;=<>]*\])?\s*=\s*", block))

    assigned = set(re.findall(r"(?<![.\w])([A-Za-z_]\w*)(?:\s*\[[^;=<>]*\])?\s*<=", text))
    # SystemVerilog block-scoped ``logic`` objects are procedural temporaries,
    # never context state in this core (persistent objects deliberately use
    # module-scope ``reg`` or the two enum typedefs).
    for m in re.finditer(r"\blogic\b\s*(?:signed\s+)?(?:\[[^\]]+\]\s*)?([^;]+);", text):
        automatic.extend(names_from_decl(m.group(1)))
    # Continuous wires can contain relational <= and are not assignment LHS.
    for m in re.finditer(r"\bwire\b\s*(?:signed\s+)?(?:\[[^\]]+\]\s*)?([^;]+);", text):
        wires.extend(names_from_decl(m.group(1)))
    # Tasks called by the clocked FSM use blocking assignments intentionally.
    for block in re.findall(r"task\b.*?endtask", text, flags=re.S):
        automatic.extend(re.findall(r"\b(?:input|output|inout|logic|reg|integer)\b\s*(?:logic\s+|reg\s+)?(?:signed\s+)?(?:\[[^\]]+\]\s*)?([A-Za-z_]\w*)", block))
        # ANSI task argument lists may continue with ``input`` omitted.
        for arglist in re.findall(r"task\s+automatic\s+\w+\s*\((.*?)\)\s*;", block, flags=re.S):
            automatic.extend(re.findall(r"(?:^|,)\s*(?:input|output|inout)?\s*(?:logic|reg|integer)?\s*(?:signed\s+)?(?:\[[^\]]+\]\s*)?([A-Za-z_]\w*)", arglist))
        assigned.update(re.findall(r"(?<![.\w])([A-Za-z_]\w*)(?:\s*\[[^;=<>]*\])?\s*=\s*", block))
    unknown = sorted(x for x in assigned if x not in declarations and x not in automatic and x not in wires and x not in constants and x not in {"i", "j"})
    if unknown:
        raise SystemExit("unclassified sequentially-assigned symbol(s): " + ", ".join(unknown))

    entries = []
    for name, meta in sorted(declarations.items(), key=lambda kv: (kv[1]["line"], kv[0])):
        if name == "init_reg_i":
            cls = "initialization_iterator"
        elif name == "v60_active_ctx":
            cls = "context_control"
        else:
            cls = "combinational" if name in comb_targets and name not in assigned else "persistent"
        entries.append({"name": name, "class": cls, **meta})
    return {
        "schema": 1,
        "source": SOURCE.relative_to(ROOT).as_posix(),
        "source_sha256": hashlib.sha256(raw.encode()).hexdigest(),
        "contract": "CONTEXTS=1 flat hierarchy; generated enumeration prepares later banked save/restore",
        "persistent_count": sum(e["class"] == "persistent" for e in entries),
        "symbols": entries,
        "constants": sorted(set(constants)),
        "wires": sorted(set(wires)),
        "automatic_temporaries": sorted(set(automatic)),
    }


def include_text(data: dict) -> str:
    out = ["// Generated by tools/v60_state_inventory.py -- do not hand edit.",
           "// X(symbol) enumerates every persistent module-scope V60 state object.",
           "`define S32_V60_PERSISTENT_STATE(X) \\"]
    state = [e["name"] for e in data["symbols"] if e["class"] == "persistent"]
    out += [f"    X({name})" + (" \\" if i != len(state) - 1 else "") for i, name in enumerate(state)]
    return "\n".join(out) + "\n"


def banks_text(data: dict) -> str:
    """Emit the physical context store and the complete exchange operation.

    The live objects deliberately retain their historical names/hierarchy.  In
    CONTEXTS=2 they are the shared execution latch; this generated store holds
    the inactive architectural/microarchitectural image.
    """
    state = [e for e in data["symbols"] if e["class"] == "persistent"]
    out = ["// Generated by tools/v60_state_inventory.py -- do not hand edit."]
    for e in state:
        name, width, kind = e["name"], e["width"], e["kind"]
        if name == "r":
            out += ["reg [31:0] v60_ctx_r0 [0:31];", "reg [31:0] v60_ctx_r1 [0:31];"]
        elif name in ("fb", "fb_prev"):
            out += [f"reg [7:0] v60_ctx_{name}0 [0:23];", f"reg [7:0] v60_ctx_{name}1 [0:23];"]
        elif kind in ("st_t", "cls_t"):
            out.append(f"{kind} v60_ctx_{name} [0:1];")
        else:
            decl_width = "" if width == "1" else width + " "
            out.append(f"reg {decl_width}v60_ctx_{name} [0:1];")
    out += ["integer v60_ctx_i;", "integer v60_ctx_init_i;", "initial begin",
            "    for (v60_ctx_init_i = 0; v60_ctx_init_i < 32; v60_ctx_init_i = v60_ctx_init_i + 1) begin",
            "        v60_ctx_r0[v60_ctx_init_i] = 32'd0;",
            "        v60_ctx_r1[v60_ctx_init_i] = 32'd0;",
            "    end", "end", "task automatic v60_context_exchange;", "begin"]
    for e in state:
        name = e["name"]
        if name == "r":
            out += ["    for (v60_ctx_i = 0; v60_ctx_i < 32; v60_ctx_i = v60_ctx_i + 1) begin",
                    "        if (v60_active_ctx) v60_ctx_r1[v60_ctx_i] = r[v60_ctx_i];",
                    "        else                v60_ctx_r0[v60_ctx_i] = r[v60_ctx_i];",
                    "    end"]
        elif name in ("fb", "fb_prev"):
            out += ["    for (v60_ctx_i = 0; v60_ctx_i < 24; v60_ctx_i = v60_ctx_i + 1) begin",
                    f"        if (v60_active_ctx) v60_ctx_{name}1[v60_ctx_i] = {name}[v60_ctx_i];",
                    f"        else                v60_ctx_{name}0[v60_ctx_i] = {name}[v60_ctx_i];",
                    "    end"]
        else:
            out.append(f"    v60_ctx_{name}[v60_active_ctx] = {name};")
    out.append("    v60_active_ctx = ~v60_active_ctx;")
    for e in state:
        name = e["name"]
        if name == "r":
            out += ["    for (v60_ctx_i = 0; v60_ctx_i < 32; v60_ctx_i = v60_ctx_i + 1)",
                    "        r[v60_ctx_i] = v60_active_ctx ? v60_ctx_r1[v60_ctx_i] : v60_ctx_r0[v60_ctx_i];"]
        elif name in ("fb", "fb_prev"):
            out += ["    for (v60_ctx_i = 0; v60_ctx_i < 24; v60_ctx_i = v60_ctx_i + 1)",
                    f"        {name}[v60_ctx_i] = v60_active_ctx ? v60_ctx_{name}1[v60_ctx_i] : v60_ctx_{name}0[v60_ctx_i];"]
        else:
            out.append(f"    {name} = v60_ctx_{name}[v60_active_ctx];")
    out += ["end", "endtask"]
    return "\n".join(out) + "\n"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()
    data = inventory()
    manifest = json.dumps(data, indent=2) + "\n"
    include = include_text(data)
    banks = banks_text(data)
    banks_path = ROOT / "verif/v60/v60_state_banks.svh"
    if args.write:
        MANIFEST.write_text(manifest, encoding="utf-8")
        INCLUDE.write_text(include, encoding="utf-8")
        banks_path.write_text(banks, encoding="utf-8")
        print(f"wrote {data['persistent_count']} persistent symbols")
        return
    failures = []
    if not MANIFEST.exists() or MANIFEST.read_text(encoding="utf-8") != manifest:
        failures.append(str(MANIFEST.relative_to(ROOT)))
    if not INCLUDE.exists() or INCLUDE.read_text(encoding="utf-8") != include:
        failures.append(str(INCLUDE.relative_to(ROOT)))
    if not banks_path.exists() or banks_path.read_text(encoding="utf-8") != banks:
        failures.append(str(banks_path.relative_to(ROOT)))
    if failures:
        raise SystemExit("stale V60 state inventory: " + ", ".join(failures) + "; run with --write")
    print(f"V60 STATE INVENTORY PASS ({data['persistent_count']} persistent symbols, 100% classified)")


if __name__ == "__main__":
    main()
