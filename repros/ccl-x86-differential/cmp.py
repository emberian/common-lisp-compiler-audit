#!/usr/bin/env python3
# Compare fuzzer outputs row-by-row. Equality rule:
#  - integers/ratios/chars/strings: exact.
#  - floats: exact IEEE bits (sign.significand.exponent via integer-decode-float).
#  - signed zeros collapsed (+0.0 == -0.0, numerically equal).
#  - a row position where EITHER side is non-finite (overflow/inf/nan) is SKIPPED:
#    once overflow enters, downstream float values track trap policy, not semantics.
import sys, re

NONFIN = {'E:FPOVER','E:FPUNDER','SINF+','SINF-','DINF+','DINF-',
          'SNAN','DNAN','SNONFIN','DNONFIN'}

def load(path):
    d = {}
    with open(path) as f:
        for line in f:
            if not re.match(r'^\d+\t', line): continue
            parts = line.rstrip('\n').split('\t')
            if len(parts) != 3: continue
            seed, safe, fast = parts
            d[int(seed)] = (safe, fast)
    return d

def canon(r):
    if r in ('SZ+','SZ-'): return 'SZ'
    if r in ('DZ+','DZ-'): return 'DZ'
    return r

def differ(a, b):
    """True if whole-seed strings a,b differ on a comparable row."""
    ra, rb = a.split('|'), b.split('|')
    if len(ra) != len(rb): return True
    for x, y in zip(ra, rb):
        if x in NONFIN or y in NONFIN:   # tainted by overflow/inf/nan -> skip
            continue
        if canon(x) != canon(y):
            return True
    return False

ccl = load(sys.argv[1]); sbcl = load(sys.argv[2])
common = sorted(set(ccl) & set(sbcl))
cross_safe=[]; cross_fast=[]; within_ccl=[]; within_sbcl=[]
for s in common:
    cs, cf = ccl[s]; ss, sf = sbcl[s]
    if differ(cs, ss): cross_safe.append(s)
    if differ(cf, sf): cross_fast.append(s)
    if differ(cs, cf): within_ccl.append(s)
    if differ(ss, sf): within_sbcl.append(s)

print(f"files: {sys.argv[1]} vs {sys.argv[2]}")
print(f"common seeds: {len(common)}")
print(f"CROSS safe  (CCL.safe != SBCL.safe): {len(cross_safe)}")
print(f"CROSS fast  (CCL.fast != SBCL.fast): {len(cross_fast)}")
print(f"WITHIN CCL  (safe != fast)         : {len(within_ccl)}")
print(f"WITHIN SBCL (safe != fast)         : {len(within_sbcl)}")

def show(label, seeds, a, b):
    if not seeds: return
    print(f"\n==== {label} ({len(seeds)}; showing up to 30) ====")
    for s in seeds[:30]:
        print(f"seed {s}:")
        print(f"  {a[0]} = {ccl[s][a[1]] if a[2]=='c' else sbcl[s][a[1]]}")
        print(f"  {b[0]} = {ccl[s][b[1]] if b[2]=='c' else sbcl[s][b[1]]}")

show("CROSS safe", cross_safe, ("CCL.safe",0,'c'), ("SBCL.safe",0,'s'))
show("CROSS fast", cross_fast, ("CCL.fast",1,'c'), ("SBCL.fast",1,'s'))
show("WITHIN CCL safe-vs-fast", within_ccl, ("CCL.safe",0,'c'), ("CCL.fast",1,'c'))
show("WITHIN SBCL safe-vs-fast", within_sbcl, ("SBCL.safe",0,'s'), ("SBCL.fast",1,'s'))
