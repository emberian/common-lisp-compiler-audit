#!/usr/bin/env python3
# Stricter comparator for the fuzz3 targeted sweep. Suppresses the three benign
# buckets root-caused in the smoke test so any residual diff is NOVEL:
#   (1) both sides error (different condition class is not a soundness bug)
#   (2) signed zero (+0.0 == -0.0 numerically): DZ+/DZ-/SZ+/SZ- collapsed
#   (3) integer-decode-float/decode-float of ZERO: CCL exponent -1074 vs SBCL 0
import sys, re
NONFIN = {'E:FPOVER','E:FPUNDER','SINF+','SINF-','DINF+','DINF-','SNAN','DNAN','SNONFIN','DNONFIN'}
def load(p):
    d={}
    for line in open(p):
        if not re.match(r'^\d+\t',line): continue
        a=line.rstrip('\n').split('\t')
        if len(a)==3: d[int(a[0])]=(a[1],a[2])
    return d
def errlike(s): return all(r.startswith(('E:','E?:','OUTER','CERR')) for r in s.split('|'))
def canon_token(t):
    if t in ('DZ+','DZ-'): return 'DZ'
    if t in ('SZ+','SZ-'): return 'SZ'
    if t=='-1074': return '0'            # decode-float-of-zero exponent (CCL) == SBCL 0
    return t
def canon_row(r):
    # tokenize on the structural separators and canonicalize each token
    toks=re.split(r'([(), ])', r)
    return ''.join(canon_token(t) for t in toks)
def differ(a,b):
    ra,rb=a.split('|'),b.split('|')
    if len(ra)!=len(rb): return True
    for x,y in zip(ra,rb):
        if x in NONFIN or y in NONFIN: continue
        if x.startswith(('E:','E?:','OUTER','CERR')) and y.startswith(('E:','E?:','OUTER','CERR')):
            continue   # both error on this row
        if canon_row(x)!=canon_row(y): return True
    return False
ccl=load(sys.argv[1]); sbcl=load(sys.argv[2])
common=sorted(set(ccl)&set(sbcl))
cs=[s for s in common if differ(ccl[s][0],sbcl[s][0])]
cf=[s for s in common if differ(ccl[s][1],sbcl[s][1])]
wc=[s for s in common if differ(ccl[s][0],ccl[s][1])]
ws=[s for s in common if differ(sbcl[s][0],sbcl[s][1])]
print(f"{sys.argv[1]}: common={len(common)}  NOVEL cross-safe={len(cs)} cross-fast={len(cf)} within-CCL={len(wc)} within-SBCL={len(ws)}")
for lbl,seeds,ai,bi,src in [("NOVEL cross-safe",cs,0,0,'cs'),("NOVEL cross-fast",cf,1,1,'cf'),
                             ("NOVEL within-CCL",wc,0,1,'wc'),("NOVEL within-SBCL",ws,0,1,'ws')]:
    for s in seeds[:15]:
        if src in ('cs','cf'):
            print(f"  {lbl} seed {s}: CCL={ccl[s][ai]}  SBCL={sbcl[s][bi]}")
        elif src=='wc':
            print(f"  {lbl} seed {s}: safe={ccl[s][0]}  fast={ccl[s][1]}")
        else:
            print(f"  {lbl} seed {s}: safe={sbcl[s][0]}  fast={sbcl[s][1]}")
