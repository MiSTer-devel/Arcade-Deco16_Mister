#!/usr/bin/env python3
"""Deterministically vendor jtframe/jtcores HDL into this MiSTer-devel core.

This core is a JOTEGO jtframe core (built in the jtcores repo) re-hosted on the
MiSTer-devel arcade template. The RTL under rtl/<module>/ is a straight COPY of
the jtcores sources; only WHICH files are copied is curated (the files.qip
manifest). This tool refreshes those copies from a jtcores checkout so a fix made
in jtcores lands here byte-for-byte, reproducibly.

Three classes of file:
  * VENDORED  - rtl/<module>/<name> is copied from the matching jtcores source
                (found by basename under the module's jtcores root).
  * GENERATED - jt<core>_game_sdram.v / mem_ports.inc / fir_*.hex come from a
                jtframe BUILD (jtframe mem / filter gen), not from jtcores hdl.
  * HAND      - emu.sv, sys/, pll*, analog_hsize.sv, the .qsf/.qpf/.sdc and the
                MRA are maintained by hand and NEVER touched here.

The manifest (files.qip) is the source of truth for the file SET. Adding or
removing a module is a manual manifest edit; this tool only refreshes content.

Usage:
  tools/vendor.py --jtroot ../jtcores [--build DIR] [--core cninja] [--check]

  --jtroot  path to the jtcores checkout (required)
  --build   dir holding the jtframe-generated files (jt<core>_game_sdram.v,
            mem_ports.inc, fir_*.hex). Default: <jtroot>/cores/<core>/mister/game
            then a few known fallbacks; a compile-one 'generated-*' artifact's
            <core>/mister/0/build dir also works.
  --core    core name = the rtl/<core> subdir. Default: autodetect the single
            rtl/ module that holds a jt*_game.v.
  --check   dry run: report VENDORED-changed / identical / MISSING, touch nothing.
"""
import argparse, os, re, shutil, sys

# rtl/<module>  ->  jtcores path (relative to --jtroot) searched for basenames.
# {core} is filled in from --core. jt49 is nested inside jt12 in jtcores.
MODULE_ROOTS = {
    "jtframe": "modules/jtframe/hdl",
    "jt12":    "modules/jt12/hdl",
    "jt49":    "modules/jt12/jt49/hdl",
    "jt51":    "modules/jt51/hdl",
    "jt6295":  "modules/jt6295/hdl",
    "fx68k":   "modules/fx68k/hdl",
    "huc6280": "modules/HUC6280/hdl",
}
# rtl basenames that are jtframe-GENERATED (from the build), not jtcores hdl.
GEN_RE = re.compile(r"(_game_sdram\.v|^mem_ports\.inc$|^fir_.*\.hex$)")
# rtl module dirs that are hand-maintained (never vendored).
HAND_DIRS = {"pll"}
HAND_FILES = {"emu.sv", "analog_hsize.sv", "crt_adjust.sv", "pll.v", "pll.qip"}

QIP_RE = re.compile(r"set_global_assignment\s+-name\s+[A-Z_]*FILE\s+(.+?)\s*$")

FILETYPE = {".v": "VERILOG_FILE", ".sv": "SYSTEMVERILOG_FILE", ".vhd": "VHDL_FILE",
            ".qip": "QIP_FILE", ".sdc": "SDC_FILE"}
SKIP_PARTS = {"target", "verilator", "ver", "sim", "tb", "test"}

def src_to_rtl(src_rel, core):
    """jtcores-relative source path -> rtl/<module>/<subpath>, or None if it maps
    to nothing we vendor (jtframe's MiSTer target, a sim/tb variant, or a module we
    don't host). Longest roots first so jt49 (nested in jt12) wins over jt12."""
    roots = sorted(dict(MODULE_ROOTS, **{core: "cores/%s/hdl" % core}).items(),
                   key=lambda kv: -len(kv[1]))
    s = src_rel.replace("\\", "/")
    for mod, root in roots:
        pre = root + "/"
        if s.startswith(pre):
            rest = s[len(pre):]
            if set(rest.split("/")) & SKIP_PARTS: return None
            return "rtl/%s/%s" % (mod, rest)
    return None   # e.g. modules/jtframe/target/... -> replaced by sys/emu here

# Verilog/SV keywords that can appear in "ident ident (" / "ident #(" position but
# are NOT module instantiations.
_KW = set("""module endmodule input output inout wire reg logic assign always
initial begin end if else for while case casex casez endcase generate endgenerate
function endfunction task endtask parameter localparam genvar integer real signed
unsigned posedge negedge or and not xor buf notif nand nor xnor typedef struct enum
packed union return break continue default disable fork join wait repeat forever
supply0 supply1 tri time""".split())
_INST = re.compile(r"\b([A-Za-z_]\w*)\s*#\s*\(|\b([A-Za-z_]\w*)\s+[A-Za-z_]\w*\s*\(")
_DEF  = re.compile(r"^\s*(?:module|primitive)\s+([A-Za-z_]\w*)", re.M)
_ENT  = re.compile(r"^\s*(?:entity|architecture\s+\w+\s+of|package(?:\s+body)?)\s+([A-Za-z_]\w*)", re.M | re.I)
_VENT = re.compile(r"\bentity\s+(?:work\.)?([A-Za-z_]\w*)", re.I)  # VHDL instantiation
_VUSE = re.compile(r"\buse\s+work\.([A-Za-z_]\w*)", re.I)          # VHDL package dep
_SIMF = re.compile(r"_(sim|tb|test)\.(v|sv|vhd)$")                 # sim-only file names

def _strip_comments(t):
    t = re.sub(r"/\*.*?\*/", " ", t, flags=re.S)
    t = re.sub(r"//[^\n]*", " ", t)
    t = re.sub(r"--[^\n]*", " ", t)   # VHDL line comment
    return t

def build_module_index(jtroot, core, build, here):
    """name(lower) -> abs file path, over the SYNTHESIS sources: jtcores
    cores/<core>/hdl + modules/**, the build (generated), and this repo's rtl/.
    Skips sim/target/tb variants."""
    idx = {}
    roots = [os.path.join(jtroot, "cores", core, "hdl"),
             os.path.join(jtroot, "modules"),
             os.path.join(here, "rtl")]
    if build: roots.append(build)
    for root in roots:
        if not os.path.isdir(root): continue
        for dp, dns, fns in os.walk(root):
            dns[:] = [d for d in dns if d not in SKIP_PARTS]
            for fn in fns:
                if os.path.splitext(fn)[1] not in (".v", ".sv", ".vhd"): continue
                if _SIMF.search(fn): continue        # jtframe_*_sim.v / *_tb.v etc.
                fp = os.path.join(dp, fn)
                try: txt = _strip_comments(open(fp, errors="ignore").read())
                except Exception: continue
                for rx in (_DEF, _ENT):
                    for nm in rx.findall(txt):
                        idx.setdefault(nm.lower(), fp)   # first wins (rtl/ before jtcores)
    return idx

def emit_qip(jtroot, build, core, cur_manifest, here):
    """Walk the dependency closure from emu.sv + the generated game_sdram, map the
    used files to rtl/ paths, and print files.qip lines (flagging NEW ones). This is
    the ACTUAL consumed set - not jtframe's candidate superset."""
    idx = build_module_index(jtroot, core, build, here)
    # roots
    roots = [os.path.join(here, "rtl", "emu.sv")]
    gs = "jt%s_game_sdram.v" % core
    for cand in ([os.path.join(build, gs)] if build else []) + [os.path.join(here, "rtl", core, gs)]:
        if os.path.isfile(cand): roots.append(cand); break
    used, queue, seen = set(), list(roots), set()
    while queue:
        fp = queue.pop()
        if fp in seen: continue
        seen.add(fp); used.add(fp)
        try: txt = _strip_comments(open(fp, errors="ignore").read())
        except Exception: continue
        names = set()
        for a, b in _INST.findall(txt): names.add((a or b))
        names |= set(_VENT.findall(txt))         # VHDL entity instantiation
        names |= set(_VUSE.findall(txt))         # VHDL `use work.PKG` package dep
        for nm in names:
            if nm in _KW: continue
            tgt = idx.get(nm.lower())
            if tgt and tgt not in seen: queue.append(tgt)

    def to_rtl(fp):
        if fp.startswith(os.path.join(here, "rtl") + os.sep):
            return os.path.relpath(fp, here)                       # already vendored (emu.sv, pll...)
        if build and fp.startswith(build.rstrip("/") + os.sep):
            return "rtl/%s/%s" % (core, os.path.basename(fp))       # generated
        return src_to_rtl(os.path.relpath(fp, jtroot), core)        # jtcores source

    have = set(cur_manifest)
    rtls = {}
    for fp in used:
        r = to_rtl(fp)
        if r: rtls[r] = fp
    add = sorted(r for r in rtls if r not in have)
    stale = sorted(r for r in cur_manifest if r.startswith("rtl/") and r not in rtls
                   and r.split("/")[1] not in HAND_DIRS
                   and os.path.basename(r) not in HAND_FILES
                   and not GEN_RE.search(os.path.basename(r))
                   and os.path.splitext(r)[1] in FILETYPE)
    if add:
        print("# ---- NEW: consumed by the core but not in files.qip (review + add) ----")
        for r in add:
            print("set_global_assignment -name %-18s %s" % (FILETYPE[os.path.splitext(r)[1]], r))
    else:
        print("# (no new files - files.qip already covers the dependency closure)")
    if stale:
        print("\n# ---- in files.qip but NOT reached from emu/game_sdram (candidates to remove) ----",
              file=sys.stderr)
        for r in stale: print("#   " + r, file=sys.stderr)
    print("\n# closure: %d files consumed | %d new, %d stale" %
          (len(rtls), len(add), len(stale)), file=sys.stderr)
    print("# NOTE: the walk does NOT evaluate `ifdef`, so it over-includes guarded\n"
          "#       alternatives (e.g. the j68 CPU when fx68k is the one built) - review,\n"
          "#       don't paste blindly. The core's own rtl/%s/ additions are reliable." % core,
          file=sys.stderr)

def die(msg):
    print("vendor: ERROR: " + msg, file=sys.stderr); sys.exit(1)

def parse_manifest(qip):
    files = []
    for line in open(qip):
        m = QIP_RE.match(line.strip())
        if not m: continue
        p = m.group(1).strip().strip('"')
        # strip the [file join $::quartus(qip_path) ...] wrapper if present
        p = re.sub(r".*qip_path\)\s+", "", p).rstrip("]")
        if p in ("ON", "OFF"): continue
        if p.startswith("rtl/"):
            files.append(p)
    return files

def find_source(jtroot, root_rel, basename):
    """Locate basename under jtroot/root_rel (recursive). Return path or None;
    die on ambiguity so a wrong copy can never happen silently."""
    root = os.path.join(jtroot, root_rel)
    # skip sim/target/testbench variants (e.g. hdl/verilator/fx68k.sv) - synthesis
    # sources only; sys/emu replaces jtframe's own MiSTer target.
    SKIP = {"target", "verilator", "ver", "sim", "tb", "test"}
    hits = []
    for dp, dns, fns in os.walk(root):
        dns[:] = [d for d in dns if d not in SKIP]
        if basename in fns:
            hits.append(os.path.join(dp, basename))
    if len(hits) > 1:
        die("ambiguous %s under %s:\n  " % (basename, root_rel) + "\n  ".join(hits))
    return hits[0] if hits else None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--jtroot", required=True)
    ap.add_argument("--build", default=None)
    ap.add_argument("--core", default=None)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--emit-qip", action="store_true",
                    help="print files.qip lines for the dependency closure of emu.sv + "
                         "the generated game_sdram (the ACTUAL consumed set), flagging "
                         "NEW/stale vs the current files.qip; edits nothing")
    a = ap.parse_args()

    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # repo root
    jtroot = os.path.abspath(a.jtroot)
    if not os.path.isdir(os.path.join(jtroot, "modules", "jtframe")):
        die("--jtroot %s is not a jtcores checkout" % jtroot)
    qip = os.path.join(here, "files.qip")
    if not os.path.isfile(qip): die("no files.qip in %s" % here)

    manifest = parse_manifest(qip)

    # autodetect core = the rtl/<dir> that holds a jt*_game.v
    core = a.core
    if not core:
        for p in manifest:
            m = re.match(r"rtl/([^/]+)/jt.*_game\.v$", p)
            if m: core = m.group(1); break
        if not core: die("could not autodetect --core (no rtl/*/jt*_game.v)")
    MODULE_ROOTS_C = dict(MODULE_ROOTS, **{core: "cores/%s/hdl" % core})

    # locate the build (generated) dir
    build = os.path.abspath(a.build) if a.build else None
    if not build:
        for cand in ("cores/%s/mister/game" % core,
                     "cores/%s/ver/game" % core):
            d = os.path.join(jtroot, cand)
            if os.path.isfile(os.path.join(d, "jt%s_game_sdram.v" % core)):
                build = d; break

    if a.emit_qip:
        emit_qip(jtroot, build, core, manifest, here)
        return

    n_ok = n_chg = n_gen = n_skip = 0; missing = []
    for rel in manifest:
        parts = rel.split("/")            # rtl/<mod>/<name...>
        if len(parts) < 3:
            n_skip += 1; continue          # rtl/emu.sv, rtl/pll.v, ...
        mod, name = parts[1], parts[-1]
        dst = os.path.join(here, rel)
        if mod in HAND_DIRS or name in HAND_FILES:
            n_skip += 1; continue
        if GEN_RE.search(name):
            if not build: die("generated file %s needs --build (jtframe mem output)" % name)
            src = os.path.join(build, name)
            if not os.path.isfile(src): missing.append((rel, "build:"+src)); continue
            n_gen += 1
        else:
            root = MODULE_ROOTS_C.get(mod)
            if not root: die("no jtcores root mapped for rtl module '%s'" % mod)
            src = find_source(jtroot, root, name)
            if not src: missing.append((rel, root)); continue
        same = os.path.isfile(dst) and open(src,'rb').read() == open(dst,'rb').read()
        if same: n_ok += 1
        else:
            n_chg += 1
            print(("would update " if a.check else "updated ") + rel + "  <- " +
                  os.path.relpath(src, jtroot if src.startswith(jtroot) else build))
            if not a.check:
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copy2(src, dst)
    # mem_ports.inc is an `include`, not always listed in files.qip - carry it too
    if build:
        mp = os.path.join(build, "mem_ports.inc")
        dstmp = os.path.join(here, "rtl", core, "mem_ports.inc")
        if os.path.isfile(mp) and (not os.path.isfile(dstmp) or
           open(mp,'rb').read()!=open(dstmp,'rb').read()):
            print(("would update " if a.check else "updated ") + "rtl/%s/mem_ports.inc"%core)
            if not a.check: shutil.copy2(mp, dstmp)

    print("\nvendor: %d changed, %d identical, %d generated, %d hand-skipped%s" %
          (n_chg, n_ok, n_gen, n_skip,
           (", %d MISSING" % len(missing)) if missing else ""))
    if missing:
        print("MISSING (in manifest but not found in jtcores/build):", file=sys.stderr)
        for rel, where in missing: print("  %s  (looked in %s)" % (rel, where), file=sys.stderr)
        sys.exit(2)

if __name__ == "__main__":
    main()
