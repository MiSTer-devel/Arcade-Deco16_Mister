---
name: vendor-from-jtframe
description: Deterministically refresh this MiSTer-devel arcade core's RTL from a jtcores/jtframe checkout. Use after fixing the core in jtcores (to pull the fix here byte-for-byte), when syncing jtframe module updates, or to regenerate files.qip. Covers the vendored/generated/hand file split, the vendoring/vendor.py runner, where the generated files come from, and what must be edited by hand (emu.sv, the manifest, sys/).
---

# Vendor jtframe/jtcores HDL into this MiSTer-devel core

This repo is a JOTEGO **jtframe** core (developed in the `jtcores` repo) re-hosted on
the **MiSTer-devel** arcade template. The RTL under `rtl/<module>/` is a straight
**copy** of the jtcores sources — nothing is rewritten, only *curated*. So a fix made
in jtcores must be *re-copied* here; this skill does that deterministically.

Golden rule: **do not hand-edit vendored RTL here.** Fix it in jtcores, then re-vendor.
A hand-edit is silently overwritten on the next refresh and diverges from upstream.

## The three file classes

| Class | What | Source | Touched by vendor.py |
|---|---|---|---|
| **VENDORED** | `rtl/<module>/*.v`,`*.sv`,`*.vhd`, core `*.hex` (e.g. `jtcninja_*`, `jtframe_*`, `jt12/*`, `fx68k/*`) | jtcores, copied by basename under the module's jtcores root | **yes** — refreshed |
| **GENERATED** | `jt<core>_game_sdram.v`, `mem_ports.inc`, `fir_*.hex` | a jtframe **build** (`jtframe mem` / filter gen) | **yes** — copied from `--build` |
| **HAND** | `rtl/emu.sv`, `rtl/pll*`, `rtl/analog_hsize.sv`, `sys/`, `*.qsf/.qpf/.sdc`, the MRA | maintained by hand | **never** |

`rtl/<module>` → jtcores root map (in `vendoring/vendor.py`): `jtframe`→`modules/jtframe/hdl`,
`jt12`→`modules/jt12/hdl`, `jt49`→`modules/jt12/jt49/hdl` (nested!), `jt51`,`jt6295`,
`fx68k`→`modules/<m>/hdl`, `huc6280`→`modules/HUC6280/hdl`, `<core>`→`cores/<core>/hdl`.
The search skips `target/`,`verilator/`,`ver/`,`sim/`,`tb/` so no sim/MiSTer-target
variant is ever pulled (sys/emu replaces jtframe's own MiSTer target).

## files.qip IS the manifest

`files.qip` (auto-generated header) is the source of truth for **which** files are in
the build — the curated subset of jtframe's full candidate list (drops the unused alt
68k `j68`, sim-only files, joydb, etc.). `vendor.py` reads it and only refreshes
**content**. **Adding or removing a module is a manual `files.qip` edit** (add the
`set_global_assignment -name VERILOG_FILE rtl/<mod>/<file>` line, then re-run).

## Run it

```bash
# from the repo root; --jtroot points at your jtcores checkout
vendoring/vendor.py --jtroot ../jtcores --build <BUILD_DIR> --check   # dry run: show what would change
vendoring/vendor.py --jtroot ../jtcores --build <BUILD_DIR>           # apply
```
- `--core` autodetects from `rtl/*/jt*_game.v`; pass it if ambiguous.
- The tool **dies on an ambiguous basename** (so a wrong copy can't happen silently)
  and **exits non-zero listing any manifest file it couldn't find** — never ignore that.

### Deriving files.qip lines (`--emit-qip`)

When the core gained/lost a module you don't want to hand-hunt the `files.qip` line:

```bash
vendoring/vendor.py --jtroot ../jtcores --build <BUILD_DIR> --emit-qip
```
It walks the **dependency closure** from `rtl/emu.sv` + the generated `game_sdram`
(resolving module instantiations and VHDL `use work.PKG` against jtcores), and prints:
- to **stdout**: `set_global_assignment` lines for files reached but NOT in `files.qip`
  (with the right FILE type) — the block to review and add;
- to **stderr**: files in `files.qip` NOT reached (candidates to remove) + a count.

**Do NOT paste blindly.** The walk does not evaluate `` `ifdef ``, so it over-includes
guarded *alternatives* — e.g. the `j68` CPU when the build uses `fx68k`, or the
burst-SDRAM path. Those show as "new" but must NOT be added. The reliable signal is a
new file under **`rtl/<core>/`** (the core's own HDL — no ifdef ambiguity) and the
"candidates to remove" list. Everything else is a human judgement call; there is no
fully-deterministic file list without a macro-aware elaborator (which is exactly why
`files.qip` is hand-curated once and only refreshed after).

### Where `--build` comes from (the GENERATED files)

Either:
1. **compile-one artifact** (easiest): download the `generated-<core>-<target>-run<N>`
   artifact from the jtcores `compile-one.yaml` run; the dir is
   `<artifact>/<core>/mister/0/build` — it holds `jt<core>_game_sdram.v`,
   `mem_ports.inc`, `fir_*.hex`. (As of the self-contained-sources change, that
   artifact also carries `sources/` — the exact jtcores HDL that build used, a handy
   cross-check for `--jtroot`.)
2. **locally**: run `jtframe mem <core>` in jtcores (Docker) and point `--build` at its
   output. If the mem map / clocks didn't change you can reuse the last `--build`.

## After vendoring

1. `--check` first; sanity the change list (should be only files you actually changed
   in jtcores + intended jtframe syncs — not surprise churn).
2. If a **new module** was pulled in (new instantiation in the core), add its file(s)
   to `files.qip` by hand and re-run.
3. If the **game interface changed** (ports on `jt<core>_game_sdram`), update
   `rtl/emu.sv` by hand to match — vendor.py does NOT touch it.
4. Build in Quartus (`Arcade-Deco16.qpf`) or the MiSTer CI to confirm it compiles and
   closes timing, then test the `.rbf`.

## What this does NOT do (by design)

- Doesn't author `emu.sv` — that MiSTer↔jtframe glue is hand-written per core and only
  changes when the game's top-level ports change.
- Doesn't curate the file SET — that's `files.qip`, edited by hand on add/remove.
- Doesn't touch `sys/` (MiSTer framework, from Template_MiSTer) or the MRA.
