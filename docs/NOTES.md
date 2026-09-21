# MINERVA P4 — Engineering Notes


> Working log kept during P4 development. For the polished overview see the top-level README; for starting P5 see `P5_CONTEXT.md`.

## Toolchain
Vivado **2025.2** (`C:/AMDDesignTools/2025.2`) — migrated mid-project from
2025.1. All IP upgraded, no locks outstanding.

Project: `C:/Users/OSHIO/Verilog/RISC-V_P4/RISC-V_P4.xpr`

---

## WHERE THINGS STAND

**Verified in simulation** — all five testbenches pass on 2025.2:

| Testbench | Covers |
|---|---|
| `tb_p3_top` | cache allocate / hit / write-hit / dirty eviction / DMA |
| `tb_concurrent_stress` | cache vs DMA contention through the arbiter |
| `tb_ex_branch` | all six branch types incl. the fixed BLTU/BGEU |
| `tb_riscv_cpu_p4` | pipeline with real branches over AXI fetch |
| `tb_p4_system` | full stack + instruction-level fault injection |

**Timing: MET at 100 MHz**, WNS **+0.230 ns**, 0 failing endpoints.

**Block design**: CPU reset GPIO has just been added; the design was saved
but the post-GPIO implementation run has NOT been done yet.

---

## NEXT SESSION — RUN THIS FIRST

The GPIO is in the BD but nothing downstream has been rebuilt. Full rebuild:

```tcl
# 1. regenerate everything (BD changed -> OOC checkpoints are stale)
reset_target all [get_files p4_bd.bd]
generate_target all [get_files p4_bd.bd]
create_ip_run [get_files p4_bd.bd]

# 2. reset BOTH the top synth run and p4_top's out-of-context run.
#    Resetting synth_1 alone is NOT enough -- p4_top is a BD module and
#    synthesises separately into its own .dcp. This cost several hours
#    earlier in the project: three "fresh" runs returned byte-identical
#    timing numbers because the stale checkpoint was being re-read.
reset_run synth_1
reset_run p4_bd_p4_top_0_0_synth_1

# 3. build
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

# 4. CHECK TIMING FROM THE CONSOLE, not the GUI Project Summary
#    (the GUI caches and has repeatedly shown stale numbers)
open_run impl_1
report_timing_summary
```

Expect WNS to drop somewhat from +0.230 — the GPIO adds a fourth
interconnect master port. Anything comfortably positive is fine.

Then verify the GPIO landed and the address map is intact:

```tcl
foreach seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces ps7/Data]] {
    puts [format "  %-50s offset=%s range=%s" $seg \
        [get_property offset $seg] [get_property range $seg]]
}
```

Then regenerate the hardware handoff — **the existing .xsa is stale**
(exported before the v2 cache and before the GPIO):

```tcl
write_hw_platform -fixed -include_bit -force \
    -file C:/Users/OSHIO/Verilog/RISC-V_P4/p4_platform.xsa
```

---

## MEMORY MAP — the CPU and the PS see different addresses

This distinction will cause confusion at bring-up if not kept in mind.
The two BRAMs are true-dual-port with a separate AXI BRAM Controller on
each side, so the same physical memory is at different addresses
depending on who is looking.

| What | CPU address | PS address |
|---|---|---|
| data memory (16K) | `0x0000_0000` | `0x4001_0000` |
| dma_reg | `0x0001_0000` (internal to p4_top) | — |
| periph (tied off) | `0x0002_0000` | — |
| instruction memory (4K) | `0x0003_0000` | `0x4002_0000` |
| fi_cfg registers | — | `0x4000_0000` |
| CPU reset GPIO | — | `0x4003_0000` |

The PS cannot reach `0x0000_0000` through M_AXI_GP0 at all — that
aperture is fixed at `0x4000_0000`–`0x7FFF_FFFF`.

**The trap**: the fault-injection master sits on the crossbar, so its
`TARGET_ADDR` must be written in *CPU* addresses. To corrupt an
instruction you write `0x0003_0030`, NOT `0x4002_0030` — even though the
program was loaded via `0x4002_0000`.

---

## FAULT INJECTION REGISTERS (at PS `0x4000_0000`)

```
+0x00  TARGET_ADDR   address to hit, in CPU address space
+0x04  INJECT_DATA   value written directly in MODE 0
+0x08  INJECT_MASK   XOR mask applied in MODE 1
+0x0C  CTRL          bit0 = START (self-clearing)
                     bit1 = MODE  0 = stuck-at overwrite
                                  1 = read-modify-XOR bit flip
+0x10  STATUS        bit0 BUSY, bit1 DONE (write 1 to clear), bit2 ERROR
```

## CPU RESET GPIO (at PS `0x4003_0000`)

```
bit0 = 1  CPU held in reset
bit0 = 0  CPU runs
```
Powers up at **1**, so the CPU stays halted until software releases it.
That default is deliberate: imem BRAM is uninitialised at power-up, and
without it the CPU would fetch zeros, execute garbage, and be
unrecoverable before the app ever ran.

---

## REMAINING WORK

Offline (no board needed):
1. Rebuild + timing check + fresh `.xsa` — the commands above
2. **Vitis bare-metal app** — not started. Needs to: hold CPU in reset,
   write a program to `0x4002_0000`, release reset, poll/wait, run a
   fault campaign via `0x4000_0000`, read results from `0x4001_0000`,
   report over UART.
3. **ILA** — not added. Probes worth having: `grant_valid`, `grant_idx`
   (crossbar arbitration), `if_stall_out`, `if_pc_out`, `mem_stall_out`,
   `debug_out`.
4. Documentation: README, docs/notes.md, LinkedIn post, resume bullets,
   theologysubtext.space update.

Needs the ZedBoard:
5. Program device, run the app, capture ILA, verify fault injection on
   real hardware.

---

## HOW TIMING WAS CLOSED (for the writeup)

Started at WNS **-4.316 ns** with 42,575 failing endpoints. Four changes:

1. **BRAM cache inference** (`cache_controller_bram.sv`). `data_array`
   was in an `always_ff` with async reset, so Vivado built it from
   32,768 flip-flops. Moving it to a reset-free block with a registered
   read port dropped endpoints 80,591 → 20,265 and TNS 78×.
2. **Removed the regfile's hierarchical reference.**
   `assign debug_out = u_id.u_regfile.regs[10];` blocked memory
   inference. Replaced with a real `dbg_x10` port: −1,000 LUTs.
3. **Dedicated branch comparator** (`ex_stage.sv`). `branch_condition`
   depended on the full ALU result, `zero` and `overflow`, putting the
   whole ALU in series ahead of `branch_taken`. Comparing rs1/rs2
   directly took WNS −2.129 → −0.760.
4. **Registered tag compare** (`cache_controller_bram_v2.sv`). New
   `TAG_LOOKUP` state registers the hit result, so the long tag path
   terminates at a flop. WNS +0.002 → **+0.230**, and it costs no extra
   latency because it absorbed the old `READ_DATA` state.

Also fixed along the way: **BLTU/BGEU were functionally wrong**. The old
decode used the *signed* overflow flag for *unsigned* comparisons, so
they gave incorrect results whenever the operands differed in their MSB.
No existing test caught it because the bubble-sort program only uses
`blt`. `tb_ex_branch` now covers all six branch types.

---

## TRAPS THAT COST REAL TIME — DON'T REPEAT

- **OOC checkpoints.** `p4_top` synthesises separately. `reset_run
  synth_1` does not invalidate it. Always reset
  `p4_bd_p4_top_0_0_synth_1` too, or `reset_target all` on the BD.
  Symptom: identical timing numbers across "fresh" runs.
- **Simulation and synthesis can disagree.** xsim reads RTL directly;
  synthesis reads checkpoints. A testbench passing does not mean
  synthesis is building the same thing. (Two `cache_controller` files
  were once both in the project — sim took one, synthesis the other.)
- **The GUI Project Summary caches timing.** Always
  `open_run impl_1; report_timing_summary` from the console.
- **Address auto-assignment fails silently.** `assign_bd_address` left
  four of five segments unassigned. Always print the map and read it.
- **Tcl paths need forward slashes.** Backslashes get eaten as escapes.
- **`add_cpu_reset_gpio.tcl` is not idempotent.** It makes several
  changes before the one that can fail. If it errors partway, delete
  `cpu_reset_gpio` and `cpu_rst_or` and restore the direct reset
  connection before retrying.

---

## KNOWN, NOT BLOCKING

- `mem_stage_axi.sv:44` — `unique case` with no matching branch, fires
  ~40× per simulation. Pre-existing P3 code, predates all P4 work.
  Worth a look eventually.
- `u_axi_eng` inside the cache is ~1,045 LUTs; the identical module under
  DMA is 23. Cross-hierarchy optimisation is smearing cache logic into
  it, but the 45× difference is still worth understanding before PD.
- The reset net fans out to 2,351 loads with ~95% route delay. Currently
  meets timing; pipelining it is the cheap next step if more margin is
  ever needed.
- `regfile` still infers as flip-flops, not LUTRAM. Removing the
  hierarchical reference helped but did not enable inference — the
  write-first forwarding logic likely still blocks it.
