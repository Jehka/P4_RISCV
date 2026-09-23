/*
 * p5_campaign.c -- MINERVA P5 fault-injection campaign (Zynq PS, bare metal)
 *
 * Exhaustive single-bit-flip sweeps over the workload's instruction words
 * and input data words. Every run:
 *
 *   hold CPU -> load image + input -> release CPU
 *     CPU runs a preamble that zeroes x1..x31, then spins on the GATE word
 *   FI master: bit-flip the target word (skipped for golden runs)
 *   PS reads the target back to confirm the flip landed
 *   FI master: overwrite GATE with a NOP -> workload starts
 *   poll the done marker in dmem (timeout = HANG/NO_RESULT)
 *   compare the 10 result words against golden -> classify -> CSV line
 *
 * Both injections go through the CPU's crossbar, so the fault is in place
 * before the first workload instruction is fetched. The crossbar and FI
 * master are held in reset with the CPU, which is why injection happens
 * after release, while the CPU is parked on the gate.
 *
 * Classes:  MASKED     finished, all results == golden
 *           SDC        finished (marker seen), results differ
 *           NO_RESULT  no marker before timeout: hang, runaway, or results
 *                      stuck in the write-back cache (the three can't be
 *                      told apart from the PS side)
 *           INJFAIL    the flip did not read back -- a harness fault, not
 *                      a design result. Any non-zero count invalidates the run.
 *
 * FI TARGET_ADDR takes CPU addresses (IMEM 0x0003_xxxx, DMEM 0x0000_xxxx).
 * Workload source: sw/p5/workload.S. Reference model: sw/p5/model.py.
 */

#include "xil_printf.h"
#include "xil_io.h"
#include "xtime_l.h"
#include "sleep.h"

/* ---------- PS-side ---------- */
#define FI_CFG_BASE     0x40000000u
#define DMEM_PS_BASE    0x40010000u
#define IMEM_PS_BASE    0x40020000u
#define GPIO_DATA       0x40030000u
/* ---------- CPU-side (FI TARGET_ADDR) ---------- */
#define DMEM_CPU_BASE   0x00000000u
#define IMEM_CPU_BASE   0x00030000u

#define FI_TARGET_ADDR  (FI_CFG_BASE + 0x00)
#define FI_INJECT_DATA  (FI_CFG_BASE + 0x04)
#define FI_INJECT_MASK  (FI_CFG_BASE + 0x08)
#define FI_CTRL         (FI_CFG_BASE + 0x0C)
#define FI_STATUS       (FI_CFG_BASE + 0x10)
#define FI_CTRL_START   0x1u
#define FI_CTRL_MODE1   0x2u
#define FI_STATUS_DONE  0x2u
#define FI_STATUS_ERROR 0x4u

/* ---------- image layout (must match workload.S) ---------- */
#define GATE_OFF        0x07Cu
#define WORK_START      0x080u          /* first sweep target            */
#define NOP_INSN        0x00000013u     /* addi x0,x0,0                  */
#define IN_OFF          0x000u          /* dmem: 8 input words           */
#define IN_WORDS        8u
#define OUT_OFF         0x100u          /* dmem: 8 sorted + cksum + mark */
#define OUT_WORDS       10u
#define MARKER          0x600D1000u
#define MARKER_OFF      (OUT_OFF + 4u * (OUT_WORDS - 1u))

/* ---------- campaign settings ---------- */
#define TIMEOUT_US      2000u           /* golden run is tens of us       */
#define GOLDEN_REPEATS  10u
#define RUN_DMEM_SWEEP  1               /* 256 runs, model predicts 100% SDC */

static const unsigned int image[] = {
    0x00000093u,  /* +0x000  addi x1,x0,0   (preamble) */
    0x00000113u,  /* +0x004  addi x2,x0,0   (preamble) */
    0x00000193u,  /* +0x008  addi x3,x0,0   (preamble) */
    0x00000213u,  /* +0x00C  addi x4,x0,0   (preamble) */
    0x00000293u,  /* +0x010  addi x5,x0,0   (preamble) */
    0x00000313u,  /* +0x014  addi x6,x0,0   (preamble) */
    0x00000393u,  /* +0x018  addi x7,x0,0   (preamble) */
    0x00000413u,  /* +0x01C  addi x8,x0,0   (preamble) */
    0x00000493u,  /* +0x020  addi x9,x0,0   (preamble) */
    0x00000513u,  /* +0x024  addi x10,x0,0   (preamble) */
    0x00000593u,  /* +0x028  addi x11,x0,0   (preamble) */
    0x00000613u,  /* +0x02C  addi x12,x0,0   (preamble) */
    0x00000693u,  /* +0x030  addi x13,x0,0   (preamble) */
    0x00000713u,  /* +0x034  addi x14,x0,0   (preamble) */
    0x00000793u,  /* +0x038  addi x15,x0,0   (preamble) */
    0x00000813u,  /* +0x03C  addi x16,x0,0   (preamble) */
    0x00000893u,  /* +0x040  addi x17,x0,0   (preamble) */
    0x00000913u,  /* +0x044  addi x18,x0,0   (preamble) */
    0x00000993u,  /* +0x048  addi x19,x0,0   (preamble) */
    0x00000A13u,  /* +0x04C  addi x20,x0,0   (preamble) */
    0x00000A93u,  /* +0x050  addi x21,x0,0   (preamble) */
    0x00000B13u,  /* +0x054  addi x22,x0,0   (preamble) */
    0x00000B93u,  /* +0x058  addi x23,x0,0   (preamble) */
    0x00000C13u,  /* +0x05C  addi x24,x0,0   (preamble) */
    0x00000C93u,  /* +0x060  addi x25,x0,0   (preamble) */
    0x00000D13u,  /* +0x064  addi x26,x0,0   (preamble) */
    0x00000D93u,  /* +0x068  addi x27,x0,0   (preamble) */
    0x00000E13u,  /* +0x06C  addi x28,x0,0   (preamble) */
    0x00000E93u,  /* +0x070  addi x29,x0,0   (preamble) */
    0x00000F13u,  /* +0x074  addi x30,x0,0   (preamble) */
    0x00000F93u,  /* +0x078  addi x31,x0,0   (preamble) */
    0x0000006Fu,  /* +0x07C  GATE: jal x0,0  -> opened by FI */
    0x00000413u,  /* +0x080  li s0,0 */
    0x10000493u,  /* +0x084  li s1,256 */
    0x00800293u,  /* +0x088  li t0,8 */
    0x00000513u,  /* +0x08C  li a0,0 */
    0x00042303u,  /* +0x090  lw t1,0(s0) */
    0x0064A023u,  /* +0x094  sw t1,0(s1) */
    0x00151513u,  /* +0x098  slli a0,a0,0x1 */
    0x00654533u,  /* +0x09C  xor a0,a0,t1 */
    0x00440413u,  /* +0x0A0  addi s0,s0,4 */
    0x00448493u,  /* +0x0A4  addi s1,s1,4 */
    0xFFF28293u,  /* +0x0A8  addi t0,t0,-1 */
    0xFE0292E3u,  /* +0x0AC  bnez t0,30090 <copy> */
    0x12A02023u,  /* +0x0B0  sw a0,288(zero) */
    0x00700293u,  /* +0x0B4  li t0,7 */
    0x10000493u,  /* +0x0B8  li s1,256 */
    0x00700E13u,  /* +0x0BC  li t3,7 */
    0x0004A303u,  /* +0x0C0  lw t1,0(s1) */
    0x0044A383u,  /* +0x0C4  lw t2,4(s1) */
    0x0063D663u,  /* +0x0C8  bge t2,t1,300d4 <noswap> */
    0x0074A023u,  /* +0x0CC  sw t2,0(s1) */
    0x0064A223u,  /* +0x0D0  sw t1,4(s1) */
    0x00448493u,  /* +0x0D4  addi s1,s1,4 */
    0xFFFE0E13u,  /* +0x0D8  addi t3,t3,-1 */
    0xFE0E12E3u,  /* +0x0DC  bnez t3,300c0 <inner> */
    0xFFF28293u,  /* +0x0E0  addi t0,t0,-1 */
    0xFC029AE3u,  /* +0x0E4  bnez t0,300b8 <outer> */
    0x600D1337u,  /* +0x0E8  lui t1,0x600d1 */
    0x12602223u,  /* +0x0EC  sw t1,292(zero) */
    0x00001937u,  /* +0x0F0  lui s2,0x1 */
    0x10092E83u,  /* +0x0F4  lw t4,256(s2) */
    0x11092E83u,  /* +0x0F8  lw t4,272(s2) */
    0x12092E83u,  /* +0x0FC  lw t4,288(s2) */
    0x0000006Fu,  /* +0x100  j 30100 <done> */};
#define IMAGE_WORDS  (sizeof(image) / sizeof(image[0]))

static const int input[IN_WORDS] = { 0x13, -7, 0x7FFF, 42, 0, -1000, 5, 0x1234 };

/* Expected golden output, from model.py. The hardware golden run must match. */
static const unsigned int expected[OUT_WORDS] = {
    0xFFFFFC18u, 0xFFFFFFF9u, 0x00000000u, 0x00000005u, 0x00000013u,
    0x0000002Au, 0x00001234u, 0x00007FFFu, 0x000FE8DEu, MARKER
};

enum { C_MASKED, C_SDC, C_NORESULT, C_INJFAIL, C_N };
static const char *cname[C_N] = { "MASKED", "SDC", "NO_RESULT", "INJFAIL" };

/* ===================================================================== */

static unsigned int now_us(void)
{
    XTime t; XTime_GetTime(&t);
    return (unsigned int)(t / (COUNTS_PER_SECOND / 1000000u));
}

static int fi_op(unsigned int cpu_addr, unsigned int data, unsigned int mask, int mode1)
{
    unsigned int st; int timeout = 100000;
    Xil_Out32(FI_TARGET_ADDR, cpu_addr);
    Xil_Out32(FI_INJECT_DATA, data);
    Xil_Out32(FI_INJECT_MASK, mask);
    Xil_Out32(FI_CTRL, FI_CTRL_START | (mode1 ? FI_CTRL_MODE1 : 0));
    do {
        st = Xil_In32(FI_STATUS);
        if (--timeout == 0) return -1;
    } while ((st & FI_STATUS_DONE) == 0);
    Xil_Out32(FI_STATUS, FI_STATUS_DONE);
    return (st & FI_STATUS_ERROR) ? -1 : 0;
}

/* One run. region: 0 = golden (no fault), 'i' = imem, 'd' = dmem.
 * off = byte offset in that memory. Fills out[] and *us. Returns class. */
static int run_one(char region, unsigned int off, unsigned int bit,
                   const unsigned int *golden, unsigned int *out, unsigned int *us)
{
    unsigned int i, t0, mask = 1u << bit;

    /* 1. hold (also resets crossbar, FI master, cache valid/dirty) */
    Xil_Out32(GPIO_DATA, 1);
    usleep(1);

    /* 2. fresh image, input, and output area -- a faulty run can have
     *    stored anywhere in dmem or imem */
    for (i = 0; i < IMAGE_WORDS; i++) Xil_Out32(IMEM_PS_BASE + 4*i, image[i]);
    for (i = 0; i < IN_WORDS;   i++) Xil_Out32(DMEM_PS_BASE + IN_OFF + 4*i, (unsigned int)input[i]);
    for (i = 0; i < OUT_WORDS;  i++) Xil_Out32(DMEM_PS_BASE + OUT_OFF + 4*i, 0);

    /* 3. release: CPU zeroes x1..x31 and parks on the gate */
    Xil_Out32(GPIO_DATA, 0);

    /* 4. inject + verify it landed (PS reads the BRAM's other port) */
    if (region) {
        unsigned int cpu = (region == 'i') ? IMEM_CPU_BASE + off : DMEM_CPU_BASE + off;
        unsigned int ps  = (region == 'i') ? IMEM_PS_BASE  + off : DMEM_PS_BASE  + off;
        unsigned int orig = (region == 'i') ? image[off/4] : (unsigned int)input[(off - IN_OFF)/4];
        if (fi_op(cpu, 0, mask, 1) != 0 || Xil_In32(ps) != (orig ^ mask))
            return C_INJFAIL;
    }

    /* 5. open the gate */
    if (fi_op(IMEM_CPU_BASE + GATE_OFF, NOP_INSN, 0, 0) != 0) return C_INJFAIL;
    t0 = now_us();

    /* 6. wait for the marker */
    while (Xil_In32(DMEM_PS_BASE + MARKER_OFF) != MARKER) {
        if (now_us() - t0 > TIMEOUT_US) { *us = TIMEOUT_US; return C_NORESULT; }
    }
    *us = now_us() - t0;

    /* 7. compare */
    for (i = 0; i < OUT_WORDS; i++) out[i] = Xil_In32(DMEM_PS_BASE + OUT_OFF + 4*i);
    if (!golden) return C_MASKED;
    for (i = 0; i < OUT_WORDS; i++) if (out[i] != golden[i]) return C_SDC;
    return C_MASKED;
}

static void print_row(char region, unsigned int off, unsigned int bit, int c,
                      unsigned int us, const unsigned int *out)
{
    xil_printf("R,%s,0x%03x,%d,%s,%d\r\n",
               region == 'i' ? "imem" : "dmem", off, bit, cname[c], us);
    (void)out;
}

int main(void)
{
    unsigned int golden[OUT_WORDS], out[OUT_WORDS], us, off, bit, i, r;
    unsigned int tally[2][C_N] = {{0}};
    int c, bad = 0;

    xil_printf("\r\n=====================================\r\n");
    xil_printf(" MINERVA P5 -- fault-injection campaign\r\n");
    xil_printf("=====================================\r\n");

    /* ---- golden: must match the model, and be repeatable ---- */
    for (r = 0; r < GOLDEN_REPEATS; r++) {
        c = run_one(0, 0, 0, 0, out, &us);
        if (c != C_MASKED) { xil_printf("golden run %d: %s -- stopping\r\n", r, cname[c]); return 1; }
        for (i = 0; i < OUT_WORDS; i++) {
            if (r == 0) golden[i] = out[i];
            else if (out[i] != golden[i]) bad = 1;
        }
        xil_printf("golden %d: %d us\r\n", r, us);
    }
    for (i = 0; i < OUT_WORDS; i++) {
        xil_printf("  out[%d] = %08x  model %08x%s\r\n", i, golden[i], expected[i],
                   golden[i] == expected[i] ? "" : "  <-- MISMATCH");
        if (golden[i] != expected[i]) bad = 1;
    }
    if (bad) { xil_printf("golden runs disagree with model or each other -- stopping\r\n"); return 1; }
    xil_printf("golden OK\r\n");

    /* ---- sweeps ---- */
    xil_printf("CSV_BEGIN\r\nR,region,offset,bit,class,us\r\n");
    for (off = WORK_START; off < 4 * IMAGE_WORDS; off += 4)
        for (bit = 0; bit < 32; bit++) {
            c = run_one('i', off, bit, golden, out, &us);
            tally[0][c]++; print_row('i', off, bit, c, us, out);
        }
#if RUN_DMEM_SWEEP
    for (off = IN_OFF; off < IN_OFF + 4 * IN_WORDS; off += 4)
        for (bit = 0; bit < 32; bit++) {
            c = run_one('d', off, bit, golden, out, &us);
            tally[1][c]++; print_row('d', off, bit, c, us, out);
        }
#endif
    xil_printf("CSV_END\r\n");

    /* ---- closing golden: catches drift during the campaign ---- */
    c = run_one(0, 0, 0, golden, out, &us);
    xil_printf("closing golden: %s\r\n", cname[c]);

    xil_printf("=====================================\r\n");
    for (r = 0; r < 2; r++) {
        xil_printf("%s:", r ? "dmem" : "imem");
        for (c = 0; c < C_N; c++) xil_printf("  %s=%d", cname[c], tally[r][c]);
        xil_printf("\r\n");
    }
    if (tally[0][C_INJFAIL] || tally[1][C_INJFAIL])
        xil_printf("INJFAIL > 0: harness problem, results not valid\r\n");
    xil_printf("=====================================\r\n");
    return 0;
}