# MINERVA P5 — Session Context

Read this first at the start of P5. It captures what P4 delivered, what is
verified vs. assumed, what P5 inherits, and the decisions that need making
before any RTL is written.

---

## 1. Where MINERVA stands

| Phase | Deliverable | Status |
|---|---|---|
| P1 | CDC heterogeneous FIFO arbiter | Hardware-verified |
| P2 | 5-stage RV32I pipeline, hazards + forwarding | Hardware-verified |
| P3 | L1 cache, DMA, AXI4-Lite arbiter | Hardware-verified |
| P4 | 3×4 AXI4-Lite crossbar, AXI instruction fetch, fault-injection master | **Hardware-verified, 2026-09-21** |
| P5 | Fault-injection campaigns + path to physical design | **Starting** |

**P4 hardware result:** a fault written by the FI master over the crossbar
into instruction memory was refetched by the running CPU and executed —
ILA showed `debug_out` (x10) change `0x0F → 0x2A` with `fi_irq` pulsing
immediately before. All six UART checks passed.

---

## 2. What P5 inherits

### Hardware platform
- ZedBoard, Zynq-7020 `xc7z020clg484-1`, 100 MHz, **WNS +0.290 ns**
- Vivado / Vitis **2025.2** (migrated from 2025.1 mid-P4; IP upgraded)
- Repo: `MINERVA-P4/` — see its README for layout

### Memory map (CPU view ≠ PS view)

| Resource | CPU | PS |
|---|---|---|
| Data memory 16 KB | `0x0000_0000` | `0x4001_0000` |
| DMA registers | `0x0001_0000` | — |
| Periph (tied off) | `0x0002_0000` | — |
| Instruction memory 4 KB | `0x0003_0000` | `0x4002_0000` |
| FI registers | — | `0x4000_0000` |
| CPU reset GPIO | — | `0x4003_0000` (bit0: 1 = held) |

**FI `TARGET_ADDR` takes CPU addresses.** Most likely bug in any new
campaign code.

### Fault-injection master (the P5 workhorse)
```
+0x00 TARGET_ADDR   CPU-space address
+0x04 INJECT_DATA   mode 0 value
+0x08 INJECT_MASK   mode 1 XOR mask
+0x0C CTRL          bit0 START (self-clear), bit1 MODE (0 stuck-at, 1 bit-flip)
+0x10 STATUS        bit0 BUSY, bit1 DONE (W1C), bit2 ERROR
```
Current capabilities: **one-shot, one word, memory-mapped targets only.**
It cannot currently reach architectural state that isn't memory-mapped
(register file, pipeline registers, PC, cache tag/valid/dirty arrays).

### Software control loop that already works
`sw/main.c`: hold CPU → load program via `0x4002_0000` → clear dmem →
release → read results via `0x4001_0000` → run FI campaigns. This is the
skeleton a campaign harness grows from.

### Observability
ILA probes: `if_pc_out`, `debug_out` (x10 only), `if_stall_out`,
`mem_stall_out`, `dma_irq`, `fi_irq`. 4096-deep. Crossbar arbitration
state is **not** probed.

---

## 3. Known issues carried into P5

| Issue | Impact on P5 |
|---|---|
| **LUT-driven async reset** (`LUTAR-1`, 5 instances) — CPU reset is an OR of power-on reset and GPIO | Fine on FPGA today; **not acceptable for an ASIC flow**. Fix before PD. |
| Blocking instruction fetch, ~10 cycles/instr | Campaigns run slowly; affects how many injections per second |
| Regfile built from FFs, not LUTRAM | Area only on FPGA; irrelevant for ASIC (becomes flops or a macro anyway) |
| `mem_stage_axi.sv:44` `unique case` warning | Pre-existing, unexplained. **Resolve before PD** — an unhandled case means undefined behaviour after synthesis. |
| `debug_out` exposes only x10 | Limits what a campaign can observe without a memory store |
| Timing margin +0.29 ns | Adequate, not generous. Adding FI logic inside the core may push it negative. |

---

## 4. The decisions P5 needs first

These shape everything; settle them before writing RTL.

### 4a. What does "physical design" mean for P5?
The phrase covers very different amounts of work:

- **(i) FPGA-only fault campaigns**, no ASIC flow. Smallest scope.
- **(ii) ASIC flow on the core only** — OpenLane/OpenROAD on Sky130, taking
  the pipeline (and possibly cache) through synthesis → floorplan →
  place → CTS → route → STA/DRC/LVS. No tapeout.
- **(iii) Actual shuttle tapeout** (e.g. an open MPW / Tiny Tapeout slot).
  Deadlines and area limits then drive the whole design.

**What must change for (ii)/(iii):** everything Xilinx-specific stays on
the FPGA side. The ASIC boundary is roughly `riscv_cpu_p4` + cache +
crossbar + FI master; the PS, AXI BRAM controllers, AXI GPIO, ILA and
`ps7` are FPGA-only. BRAM inferences become SRAM macros (Sky130 OpenRAM or
DFFRAM), and the async-reset OR gate must become a proper synchronised
reset.

### 4b. What should the fault campaigns measure?
A campaign is only interesting if it produces a result someone can read.
Candidate questions:
- **Vulnerability by location**: inject single-bit flips across every
  instruction word and every data word; classify each run as
  *masked / silent data corruption / crash (hang) / detected*.
- **Vulnerability by bit position**: which instruction bits are fatal
  (opcode, rd, imm) and which are masked.
- **Temporal sensitivity**: does the injection moment matter?

This needs a **golden-run comparison** and a **hang detector** (watchdog
on PC progress) — neither exists yet.

### 4c. Reach: memory only, or architectural state too?
The current FI master only hits memory-mapped addresses. Real soft-error
studies care about the register file and pipeline registers. Options:
- keep campaigns memory-only (no core changes, timing untouched)
- add a scan-style or mux-based injection port into the regfile / pipeline
  registers (core changes, timing risk, but far more meaningful results)

### 4d. Hardening — measure only, or also mitigate?
P5 could stop at characterising vulnerability, or go on to add
protection (parity/ECC on memories, TMR on critical registers) and show
the vulnerability numbers drop. The second is a much stronger portfolio
story but roughly doubles the scope.

---

## 5. Suggested first steps (once 4a–4d are settled)

1. **Fix the two PD blockers first**, while the design is known-good:
   registered/synchronised CPU reset, and the `mem_stage_axi` case warning.
   Re-run all eight testbenches.
2. **Build the campaign harness in software**: golden run → loop over
   targets and bit positions → inject → run → compare → classify → UART
   (CSV-formatted) output.
3. **Add a hang detector** — either a PS-side timeout on a result word or
   a PL watchdog on `if_pc_out`.
4. Only then touch the core, if 4c chose architectural-state injection.

---

## 6. Working agreements that held up in P4

- Verify each block standalone before integration; never debug on hardware
  what could be caught in simulation.
- When a test fails, check the **measurement** before the design — twice in
  P4 the RTL was right and the checker was wrong.
- New modules beside verified ones, not edits to them (`if_stage_axi.sv`
  next to `if_stage.sv`), so a known-good fallback always exists.
- Read the critical path before changing RTL for timing.
- Script repetitive Vivado work; verify the result by printing it.

## 7. Traps (from P4 — do not repeat)

- `reset_run synth_1` does **not** rebuild `p4_top`'s out-of-context
  checkpoint. Also reset `p4_bd_p4_top_0_0_synth_1`.
- Check which file Vivado is actually synthesising (`get_files *name*`);
  simulation and synthesis can silently use different copies.
- The GUI Project Summary caches timing. Use `report_timing_summary` in the
  console.
- `assign_bd_address` fails silently. Print the map.
- Tcl paths: forward slashes only.
- Open the serial terminal **before** launching the app (DTR resets the board).
- Free-running ILA = 41 µs window. Always use a trigger.
- In the Vitis launch config, untick "Program Device" / "Reset Entire
  System" when an ILA is armed.
- **Export ILA data before closing the Hardware Manager** — it is not saved
  otherwise. P5 will want captures to compare runs.
