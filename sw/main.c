/*
 * main.c -- MINERVA P4 bring-up application (Zynq PS, bare metal)
 *
 * Runs on the ZedBoard's ARM core. Drives the RISC-V CPU in the PL:
 * loads a program into instruction memory, releases the CPU from reset,
 * reads results back, then runs fault-injection campaigns against both
 * data and instruction memory.
 *
 * ================== THE ADDRESS TRAP ==================
 * The CPU and the PS see the SAME physical memories at DIFFERENT
 * addresses. Each BRAM is true-dual-port with its own AXI BRAM
 * Controller per side.
 *
 *   what                 CPU sees        PS sees (this file)
 *   ------------------   -------------   -------------------
 *   data memory (16K)    0x0000_0000     0x4001_0000
 *   dma_reg              0x0001_0000     (internal to p4_top)
 *   periph (tied off)    0x0002_0000     --
 *   instruction mem (4K) 0x0003_0000     0x4002_0000
 *   fi_cfg registers     --              0x4000_0000
 *   cpu reset GPIO       --              0x4003_0000
 *
 * The PS physically cannot reach 0x0000_0000 through M_AXI_GP0 -- that
 * aperture is fixed at 0x4000_0000..0x7FFF_FFFF.
 *
 * CRITICAL: the fault-injection master sits on the CPU's crossbar, so
 * its TARGET_ADDR must be written in CPU addresses. To corrupt an
 * instruction you write 0x0003_0030, NOT 0x4002_0030 -- even though you
 * loaded the program through 0x4002_0000. Getting this backwards
 * produces a campaign that reports DONE and changes nothing.
 */

#include <stdio.h>
#include "xil_printf.h"
#include "xil_io.h"
#include "sleep.h"

/* ---------- PS-side base addresses ---------- */
#define FI_CFG_BASE     0x40000000u
#define DMEM_PS_BASE    0x40010000u
#define IMEM_PS_BASE    0x40020000u
#define CPU_RST_BASE    0x40030000u

/* ---------- CPU-side base addresses (for TARGET_ADDR) ---------- */
#define DMEM_CPU_BASE   0x00000000u
#define IMEM_CPU_BASE   0x00030000u

/* ---------- fault injection registers ---------- */
#define FI_TARGET_ADDR  (FI_CFG_BASE + 0x00)
#define FI_INJECT_DATA  (FI_CFG_BASE + 0x04)
#define FI_INJECT_MASK  (FI_CFG_BASE + 0x08)
#define FI_CTRL         (FI_CFG_BASE + 0x0C)
#define FI_STATUS       (FI_CFG_BASE + 0x10)

#define FI_CTRL_START   0x1u
#define FI_CTRL_MODE1   0x2u   /* read-modify-XOR; clear = stuck-at */

#define FI_STATUS_BUSY  0x1u
#define FI_STATUS_DONE  0x2u
#define FI_STATUS_ERROR 0x4u

/* ---------- AXI GPIO: data register at +0x00 ---------- */
#define GPIO_DATA       (CPU_RST_BASE + 0x00)

#define CPU_HELD        0x1u
#define CPU_RUNNING     0x0u

/* =====================================================================
 * Test program, RV32I machine code.
 *
 * Identical to the one in tb_p4_system.sv, so hardware behaviour can be
 * compared directly against the simulation results.
 *
 *  +00  addi x10,x0,0      a0 = 0
 *  +04  addi x5,x0,5       t0 = 5   (loop count)
 *  +08  addi x6,x0,0       t1 = 0
 * L:
 *  +0C  addi x10,x10,3     a0 += 3
 *  +10  addi x6,x6,1       t1 += 1
 *  +14  blt  x6,x5,L       loop while t1 < t0
 *  +18  addi x7,x0,7       t2 = 7
 *  +1C  sw   x10,0(x0)     store a0 to data mem word 0
 *  +20  lw   x11,0(x0)     a1 = data mem word 0
 *  +24  addi x10,x11,0     a0 = a1  (round trip through memory)
 *  +28  lui  x8,0x1        t3 = 0x1000
 *  +2C  lw   x9,0(x8)      touch 0x1000 -- same cache index, different
 *                          tag, so this EVICTS the dirty line and forces
 *                          the writeback that makes word 0 visible in
 *                          main memory
 * END:
 *  +30  jal  x0,0          spin here forever
 *
 * Expected: a0 = 15, and data memory word 0 = 15 after the eviction.
 * ===================================================================== */
static const unsigned int test_program[] = {
    0x00000513u,  /* addi x10,x0,0   */
    0x00500293u,  /* addi x5,x0,5    */
    0x00000313u,  /* addi x6,x0,0    */
    0x00350513u,  /* addi x10,x10,3  */
    0x00130313u,  /* addi x6,x6,1    */
    0xFE534CE3u,  /* blt  x6,x5,-8   */
    0x00700393u,  /* addi x7,x0,7    */
    0x00A02023u,  /* sw   x10,0(x0)  */
    0x00002583u,  /* lw   x11,0(x0)  */
    0x00058513u,  /* addi x10,x11,0  */
    0x00001437u,  /* lui  x8,0x1     */
    0x00042483u,  /* lw   x9,0(x8)   */
    0x0000006Fu   /* jal  x0,0       */
};
#define PROGRAM_WORDS (sizeof(test_program)/sizeof(test_program[0]))

/* Offset of the spin instruction, used by the instruction-fault test */
#define SPIN_OFFSET  0x30u

/* ===================================================================== */

static void cpu_hold(void)    { Xil_Out32(GPIO_DATA, CPU_HELD);    }
static void cpu_release(void) { Xil_Out32(GPIO_DATA, CPU_RUNNING); }

static void load_program(void)
{
    unsigned int i;
    for (i = 0; i < PROGRAM_WORDS; i++)
        Xil_Out32(IMEM_PS_BASE + i*4, test_program[i]);
}

static int verify_program(void)
{
    unsigned int i;
    int bad = 0;
    for (i = 0; i < PROGRAM_WORDS; i++) {
        unsigned int got = Xil_In32(IMEM_PS_BASE + i*4);
        if (got != test_program[i]) {
            xil_printf("  MISMATCH word %2d: got %08x expected %08x\r\n",
                       i, got, test_program[i]);
            bad++;
        }
    }
    return bad;
}

static void clear_data_mem(unsigned int words)
{
    unsigned int i;
    for (i = 0; i < words; i++)
        Xil_Out32(DMEM_PS_BASE + i*4, 0);
}

/*
 * Run one fault-injection campaign.
 *   target_cpu_addr : address in the CPU's address space (see header)
 *   mode1           : 0 = stuck-at overwrite, 1 = read-modify-XOR
 * Returns 0 on success, non-zero on timeout or reported error.
 */
static int fi_campaign(const char *label, unsigned int target_cpu_addr,
                       unsigned int data, unsigned int mask, int mode1)
{
    unsigned int status;
    int timeout = 100000;

    Xil_Out32(FI_TARGET_ADDR, target_cpu_addr);
    Xil_Out32(FI_INJECT_DATA, data);
    Xil_Out32(FI_INJECT_MASK, mask);
    Xil_Out32(FI_CTRL, FI_CTRL_START | (mode1 ? FI_CTRL_MODE1 : 0));

    do {
        status = Xil_In32(FI_STATUS);
        if (--timeout == 0) {
            xil_printf("  FAIL %s: timeout, status=%08x\r\n", label, status);
            return 1;
        }
    } while ((status & FI_STATUS_DONE) == 0);

    Xil_Out32(FI_STATUS, FI_STATUS_DONE);   /* write 1 to clear */

    if (status & FI_STATUS_ERROR) {
        xil_printf("  FAIL %s: ERROR flag set, status=%08x\r\n", label, status);
        return 1;
    }
    return 0;
}

/* ===================================================================== */

int main(void)
{
    unsigned int a0_result, mem0, instr_before, instr_after;
    int errors = 0;

    xil_printf("\r\n");
    xil_printf("=====================================\r\n");
    xil_printf(" MINERVA P4 -- bring-up\r\n");
    xil_printf("=====================================\r\n");

    /* ---- 1. hold the CPU BEFORE touching memory --------------------
     * The GPIO powers up asserting reset, so the CPU should already be
     * halted. Asserting again is harmless and makes the intent explicit
     * (and covers a re-run without a power cycle). */
    xil_printf("[1] Holding CPU in reset...\r\n");
    cpu_hold();
    usleep(1000);

    /* ---- 2. load the program --------------------------------------- */
    xil_printf("[2] Loading program (%d words) to 0x%08x...\r\n",
               PROGRAM_WORDS, IMEM_PS_BASE);
    load_program();

    if (verify_program() != 0) {
        xil_printf("    program readback FAILED -- stopping\r\n");
        xil_printf("    (if every word reads back as 0, the PS is not\r\n");
        xil_printf("     reaching imem: check the address map)\r\n");
        return 1;
    }
    xil_printf("    program verified\r\n");

    /* ---- 3. clear data memory so results are unambiguous ------------ */
    xil_printf("[3] Clearing data memory...\r\n");
    clear_data_mem(64);

    /* ---- 4. release the CPU ----------------------------------------- */
    xil_printf("[4] Releasing CPU...\r\n");
    cpu_release();

    /* The program is ~13 instructions with a 5-iteration loop, but every
     * fetch is a blocking AXI read through the crossbar and the data
     * accesses miss the cache. Simulation reached the spin in ~145
     * cycles; 10 ms at 100 MHz is a million cycles, so this is a very
     * generous margin. */
    usleep(10000);

    /* ---- 5. read the result ----------------------------------------- *
     * The program stores a0 to data word 0, then evicts the line, so the
     * value should have been written back to main memory by now. */
    mem0 = Xil_In32(DMEM_PS_BASE + 0);
    xil_printf("[5] data mem word 0 = %d (expected 15)\r\n", mem0);
    if (mem0 != 15) {
        xil_printf("    FAIL -- program did not produce the expected result\r\n");
        xil_printf("    if 0: CPU may not have run, or the writeback did\r\n");
        xil_printf("          not happen. Check the ILA on if_pc_out.\r\n");
        errors++;
    } else {
        xil_printf("    PASS\r\n");
    }
    a0_result = mem0;

    /* ---- 6. DATA fault injection ------------------------------------ *
     * Target 0x800 in CPU space -- well clear of the program's data at
     * word 0 and of the 0x1000 eviction address. */
    xil_printf("[6] Data-memory fault injection...\r\n");

    if (fi_campaign("data stuck-at", DMEM_CPU_BASE + 0x800,
                    0xFEEDFACEu, 0, 0) != 0) {
        errors++;
    } else {
        unsigned int v = Xil_In32(DMEM_PS_BASE + 0x800);
        xil_printf("    stuck-at: mem[0x800] = %08x (expected FEEDFACE)\r\n", v);
        if (v != 0xFEEDFACEu) { errors++; xil_printf("    FAIL\r\n"); }
        else                  { xil_printf("    PASS\r\n"); }
    }

    if (fi_campaign("data bitflip", DMEM_CPU_BASE + 0x800,
                    0, 0x0000FFFFu, 1) != 0) {
        errors++;
    } else {
        unsigned int v = Xil_In32(DMEM_PS_BASE + 0x800);
        xil_printf("    bitflip:  mem[0x800] = %08x (expected FEED0531)\r\n", v);
        if (v != 0xFEED0531u) { errors++; xil_printf("    FAIL\r\n"); }
        else                  { xil_printf("    PASS\r\n"); }
    }

    /* ---- 7. INSTRUCTION fault injection ----------------------------- *
     * The point of the whole AXI-fetch change: instruction memory is a
     * crossbar slave, so the FI master can rewrite CODE. The CPU is
     * spinning on "jal x0,0" at +0x30 and refetches it every iteration,
     * so replacing it with "addi x10,x0,42" makes the injected
     * instruction actually execute.
     *
     * NOTE the address: IMEM_CPU_BASE, not IMEM_PS_BASE. */
    xil_printf("[7] Instruction-memory fault injection...\r\n");

    instr_before = Xil_In32(IMEM_PS_BASE + SPIN_OFFSET);
    xil_printf("    before: imem[0x%02x] = %08x\r\n", SPIN_OFFSET, instr_before);

    if (fi_campaign("instr overwrite", IMEM_CPU_BASE + SPIN_OFFSET,
                    0x02A00513u /* addi x10,x0,42 */, 0, 0) != 0) {
        errors++;
    } else {
        instr_after = Xil_In32(IMEM_PS_BASE + SPIN_OFFSET);
        xil_printf("    after:  imem[0x%02x] = %08x (expected 02A00513)\r\n",
                   SPIN_OFFSET, instr_after);
        if (instr_after != 0x02A00513u) {
            xil_printf("    FAIL -- injection did not reach imem\r\n");
            xil_printf("    the usual cause is writing TARGET_ADDR in PS\r\n");
            xil_printf("    address space (0x4002xxxx) instead of CPU\r\n");
            xil_printf("    space (0x0003xxxx)\r\n");
            errors++;
        } else {
            xil_printf("    PASS -- instruction rewritten\r\n");
        }
    }

    /* Let the CPU refetch the corrupted instruction and execute it.
     * a0 becomes 42, and the following "sw" is long past, so the visible
     * effect must be observed on the ILA (debug_out) rather than in
     * memory. Kept here as an explicit checkpoint for the ILA capture. */
    usleep(10000);
    xil_printf("    (observe debug_out on the ILA: a0 should now be 42)\r\n");

    /* ---- 8. summary -------------------------------------------------- */
    xil_printf("=====================================\r\n");
    if (errors == 0) xil_printf(" ALL CHECKS PASSED\r\n");
    else             xil_printf(" %d CHECK(S) FAILED\r\n", errors);
    xil_printf("=====================================\r\n");

    (void)a0_result;
    return errors;
}