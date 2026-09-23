# MINERVA P5 campaign image. Linked at CPU address 0x0003_0000.
# Build: riscv64-unknown-elf-as -march=rv32i -mabi=ilp32 workload.S -o w.o
#        riscv64-unknown-elf-ld -m elf32lriscv -Ttext=0x30000 w.o -o w.elf
#        riscv64-unknown-elf-objcopy -O binary w.elf w.bin   (model.py reads w.bin)
    .option norvc
    .text
    .globl _start
_start:
# ---- harness preamble: zero x1..x31 (regfile has no reset) ----
    .irp r,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
    addi x\r, x0, 0
    .endr
# ---- gate: spin until the FI master overwrites this word with a NOP ----
gate:
    jal  x0, gate
# ================= workload (sweep targets start here) =================
work:
    addi s0, x0, 0x000        # src  = input array   (dmem 0x000)
    addi s1, x0, 0x100        # dst  = output array  (dmem 0x100)
    addi t0, x0, 8            # n
    addi a0, x0, 0            # checksum
copy:                         # copy input->output, checksum = (cs<<1) ^ x
    lw   t1, 0(s0)
    sw   t1, 0(s1)
    slli a0, a0, 1
    xor  a0, a0, t1
    addi s0, s0, 4
    addi s1, s1, 4
    addi t0, t0, -1
    bne  t0, x0, copy
    sw   a0, 0x120(x0)        # checksum -> 0x120
    addi t0, x0, 7            # bubble sort, 7 passes (signed ascending)
outer:
    addi s1, x0, 0x100
    addi t3, x0, 7
inner:
    lw   t1, 0(s1)
    lw   t2, 4(s1)
    bge  t2, t1, noswap
    sw   t2, 0(s1)
    sw   t1, 4(s1)
noswap:
    addi s1, s1, 4
    addi t3, t3, -1
    bne  t3, x0, inner
    addi t0, t0, -1
    bne  t0, x0, outer
    lui  t1, 0x600D1          # done marker 0x600D_1000
    sw   t1, 0x124(x0)
    lui  s2, 0x1              # evict the three dirty output lines
    lw   t4, 0x100(s2)        #   (same index, different tag)
    lw   t4, 0x110(s2)
    lw   t4, 0x120(s2)
done:
    jal  x0, done