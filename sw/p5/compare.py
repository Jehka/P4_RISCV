"""Compare a hardware campaign log (UART capture) against model predictions.
usage: python3 compare.py uart_log.txt predicted.csv [mismatches.csv]"""
import sys, csv, collections
# The PS can't distinguish a hang from results stuck in the cache.
HW_EQUIV = {'HANG': 'NO_RESULT', 'NO_RESULT': 'NO_RESULT'}
hw, inside = {}, False
for line in open(sys.argv[1], errors='replace'):
    line = line.strip()
    if line == 'CSV_BEGIN': inside = True; continue
    if line == 'CSV_END': break
    if inside and line.startswith('R,') and not line.startswith('R,region'):
        _, reg, off, bit, cls, us = line.split(',')
        hw[(reg, int(off, 16), int(bit))] = (cls, int(us))
model = {(r['region'], int(r['offset'], 16), int(r['bit'])): r['model_class']
         for r in csv.DictReader(open(sys.argv[2]))}
missing = set(model) - set(hw)
print('hardware rows: %d   model rows: %d   missing from log: %d' % (len(hw), len(model), len(missing)))
conf = collections.Counter(); mism = []
for k, m in model.items():
    if k not in hw: continue
    h = hw[k][0]; mm = HW_EQUIV.get(m, m)
    conf[(k[0], mm, h)] += 1
    if m != 'UNCERTAIN' and h != mm: mism.append((*k, m, h, hw[k][1]))
for reg in ('imem', 'dmem'):
    print('\n%s  (rows = model, cols = hardware)' % reg)
    cls = ['MASKED', 'SDC', 'NO_RESULT', 'INJFAIL']
    print('%-10s' % '' + ''.join('%11s' % c for c in cls))
    for m in ['MASKED', 'SDC', 'NO_RESULT', 'UNCERTAIN']:
        print('%-10s' % m + ''.join('%11d' % conf[(reg, m, c)] for c in cls))
print('\nmodel/hardware disagreements (excluding UNCERTAIN): %d' % len(mism))
out = sys.argv[3] if len(sys.argv) > 3 else 'mismatches.csv'
with open(out, 'w') as f:
    f.write('region,offset,bit,model,hardware,us\n')
    for r in mism: f.write('%s,0x%03x,%d,%s,%s,%d\n' % r)
print('wrote', out)