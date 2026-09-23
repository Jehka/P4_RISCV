"""MINERVA P5 reference model: RV32I ISS + the P4 memory system as seen by the PS.
Models: 4 KB direct-mapped write-back D-cache (256 lines x 4 words), no I-cache,
CPU-space map from the crossbar; ALL data accesses are cached (no bypass), so a
stray store to imem only lands on eviction. Unmapped access = HANG (the crossbar
never responds). DMA-register / periph access = UNCERTAIN. Fetch is uncached AXI, so a
wild jump into dmem executes the BRAM contents (not the cache's). Unknown opcode = NOP (matches id_stage.sv default). A known opcode with an
undefined funct3/funct7 = UNCERTAIN: depends on alu_decoder details not modelled."""
import struct, sys
IMEM_BASE, IMEM_SZ = 0x30000, 0x1000
DMEM_SZ = 0x4000
GATE, WORK_START = 0x7C, 0x80
INPUT = [0x13, -7, 0x7FFF, 42, 0, -1000, 5, 0x1234]
MARKER = 0x600D1000
M32 = 0xFFFFFFFF
def sx(v, b): v &= (1 << b) - 1; return v - (1 << b) if v >> (b - 1) else v
def s32(v): return sx(v, 32)

class Hang(Exception): pass
class Illegal(Exception): pass

def run(image, flip=None, max_steps=20000):
    imem = list(image) + [0] * (IMEM_SZ // 4 - len(image))
    dmem = [0] * (DMEM_SZ // 4)
    for i, v in enumerate(INPUT): dmem[i] = v & M32
    if flip:
        region, word, bit = flip
        if region == 'imem': imem[word] ^= 1 << bit
        else:                dmem[word] ^= 1 << bit
    imem[GATE // 4] = 0x00000013                      # gate opened
    tag = [None] * 256; dat = [[0]*4 for _ in range(256)]; dirty = [False]*256
    def back_rd(wa):                                   # word address -> backing store
        a = wa << 2
        if a < DMEM_SZ: return dmem[wa]
        if IMEM_BASE <= a < IMEM_BASE + IMEM_SZ: return imem[(a - IMEM_BASE) >> 2]
        if 0x10000 <= a <= 0x100FF or 0x20000 <= a <= 0x200FF: raise Illegal  # DMA regs / periph
        raise Hang('fill %x' % a)
    def back_wr(wa, v):
        a = wa << 2
        if a < DMEM_SZ: dmem[wa] = v
        elif IMEM_BASE <= a < IMEM_BASE + IMEM_SZ: imem[(a - IMEM_BASE) >> 2] = v
        elif 0x10000 <= a <= 0x100FF or 0x20000 <= a <= 0x200FF: raise Illegal
        else: raise Hang('writeback %x' % a)
    def line(a):                                       # every data access goes through the cache
        idx, t = (a >> 4) & 0xFF, a >> 12
        if tag[idx] != t:
            if tag[idx] is not None and dirty[idx]:
                base = ((tag[idx] << 12) | (idx << 4)) >> 2
                for k in range(4): back_wr(base + k, dat[idx][k])
            base = (a & ~0xF) >> 2
            dat[idx] = [back_rd(base + k) for k in range(4)]; tag[idx] = t; dirty[idx] = False
        return idx
    def load(a): return dat[line(a)][(a >> 2) & 3]
    def store(a, v): i = line(a); dat[i][(a >> 2) & 3] = v & M32; dirty[i] = True
    x = [0] * 32; pc = IMEM_BASE; steps = 0
    try:
        while steps < max_steps:
            if pc & 3: raise Illegal          # misaligned fetch: HW behaviour not modelled
            ins = back_rd(pc >> 2); steps += 1  # fetch bypasses the D-cache
            op, rd, f3, rs1, rs2, f7 = ins & 0x7F, (ins>>7)&31, (ins>>12)&7, (ins>>15)&31, (ins>>20)&31, ins>>25
            a, b = x[rs1], x[rs2]; npc = pc + 4; w = None
            ii = sx(ins >> 20, 12); si = sx(((ins >> 25) << 5) | ((ins >> 7) & 31), 12)
            bi = sx(((ins>>31)<<12)|(((ins>>7)&1)<<11)|(((ins>>25)&0x3F)<<5)|(((ins>>8)&0xF)<<1), 13)
            ji = sx(((ins>>31)<<20)|(((ins>>12)&0xFF)<<12)|(((ins>>20)&1)<<11)|(((ins>>21)&0x3FF)<<1), 21)
            if op == 0x37: w = ins & 0xFFFFF000
            elif op == 0x17: w = pc + (ins & 0xFFFFF000)
            elif op == 0x6F: w = pc + 4; npc = pc + ji
            elif op == 0x67 and f3 == 0: w = pc + 4; npc = (a + ii) & ~1
            elif op == 0x63:
                c = {0: a == b, 1: a != b, 4: s32(a) < s32(b), 5: s32(a) >= s32(b), 6: a < b, 7: a >= b}.get(f3)
                if c is None: raise Illegal
                if c: npc = pc + bi
            elif op == 0x03:
                ad = (a + ii) & M32
                if f3 not in (0, 1, 2, 4, 5): raise Illegal
                wd = load(ad & ~3); sh = (ad & 3) * 8
                w = {0: sx(wd >> sh, 8), 1: sx(wd >> sh, 16), 2: wd, 4: (wd >> sh) & 0xFF, 5: (wd >> sh) & 0xFFFF}[f3]
            elif op == 0x23:
                ad = (a + si) & M32
                if f3 == 2: store(ad & ~3, b)
                elif f3 in (0, 1):
                    old = load(ad & ~3); sh = (ad & 3) * 8; m = (0xFF if f3 == 0 else 0xFFFF) << sh
                    store(ad & ~3, (old & ~m) | ((b << sh) & m))
                else: raise Illegal
            elif op in (0x13, 0x33):
                o = ii if op == 0x13 else b
                sh = o & 31; alt = (f7 == 0x20)
                if op == 0x33 and f7 not in (0, 0x20): raise Illegal
                w = {0: (a - o) if (op == 0x33 and alt) else a + o, 1: a << sh, 2: int(s32(a) < s32(o)),
                     3: int(a < (o & M32)), 4: a ^ o, 5: (s32(a) >> sh) if alt else (a >> sh), 6: a | o, 7: a & o}[f3]
            else: pass   # id_stage.sv: unknown opcode -> all controls 0 -> NOP
            if w is not None and rd: x[rd] = w & M32
            if npc == pc: break                             # reached a self-loop
            pc = npc & M32
        else: raise Hang('timeout')
    except Hang: return 'HANG', None
    except Illegal: return 'UNCERTAIN', None
    out = dmem[0x100 >> 2: (0x124 >> 2) + 1]
    return 'RUN', out

def classify(res, golden):
    st, out = res
    if st != 'RUN': return st
    if out[-1] != MARKER: return 'NO_RESULT'
    return 'MASKED' if out == golden else 'SDC'

if __name__ == '__main__':
    img = list(struct.unpack('<%dI' % (len(open('w.bin','rb').read()) // 4), open('w.bin','rb').read()))
    st, golden = run(img)
    exp = sorted(s32(v & M32) for v in INPUT); cs = 0
    for v in INPUT: cs = ((cs << 1) ^ (v & M32)) & M32
    assert st == 'RUN' and [s32(v) for v in golden[:8]] == exp and golden[8] == cs and golden[9] == MARKER, golden
    print('golden OK:', ' '.join('%08x' % v for v in golden))
    rows = []
    for region, words in (('imem', range(WORK_START // 4, len(img))), ('dmem', range(8))):
        tally = {}
        for wd in words:
            for bit in range(32):
                c = classify(run(img, (region, wd, bit)), golden); tally[c] = tally.get(c, 0) + 1
                rows.append((region, wd * 4, bit, c))
        n = sum(tally.values())
        print(region, n, {k: '%d (%.1f%%)' % (v, 100 * v / n) for k, v in sorted(tally.items())})
    with open('predicted.csv', 'w') as f:
        f.write('region,offset,bit,model_class\n')
        for r in rows: f.write('%s,0x%03x,%d,%s\n' % r)
    print('wrote predicted.csv')