#!/usr/bin/env python3
"""classify-stage1.py -- results/sbcl-enumeration.tsv -> results/sbcl-unconstrained-table.tsv:
for every function symbol of the ACL2 world, the result type SBCL derives for a call with
undeclared arguments, classified as in classify.py (the stage-2 table has the typed rows)."""
import csv, re, json, collections
exec(open('classify.py').read().split("summary = read")[0].replace("host = sys.argv[1]", "host = 'sbcl'"))
rows = read('sbcl-enumeration.tsv')[1:]
stage2 = set(opname(r[0]) for r in read('sbcl-table.tsv')[1:])
prims = None
def first_value(d):
    m = re.match(r'\(FUNCTION (NIL|\(.*?\)) (.*)\)$', d)
    if not m: return None
    r = m.group(2)
    if r == '*': return 'T'
    if r == 'NIL': return 'NIL'
    m2 = re.match(r'\(VALUES (.*?)( &OPTIONAL| &REST T)?\)$', r)
    if not m2: return r
    s = m2.group(1); d = 0; cur = ''
    for ch in s:
        if ch == '(': d += 1
        if ch == ')': d -= 1
        if ch == ' ' and d == 0: break
        cur += ch
    return cur
c = collections.Counter(); notin2 = []
with open(R + 'sbcl-unconstrained-table.tsv', 'w') as f:
    f.write('symbol\tlogic-kind\tarity\traw-kind\tderived-result-unconstrained\tclass\tbound\tin-typed-table\n')
    for r in rows:
        sym, kind, ar, rk, d = r[0], r[2], r[3], r[4], r[12]
        if d == ':NOT-ATTEMPTED':
            cls, res = 'not-attempted (%s is a %s in raw Lisp)' % (kind, rk), ''
        else:
            res = first_value(d); bound = ''
            if res is None: cls = 'compile-error'
            elif res == 'T': cls = 'A-top'
            elif res == 'NIL': cls = 'A-narrow (never returns: SBCL derives NIL)'
            else:
                cls = 'A-narrow'
                for names, pat, b, why in B_RULES['sbcl']:
                    if sym in names and re.search(pat, res): cls, bound = 'B', b
        k = cls.split(' (')[0]
        c[kind + ':' + k] += 1
        in2 = 'yes' if sym in stage2 else 'no'
        if kind == 'function' and k in ('A-narrow', 'B') and in2 == 'no': notin2.append((sym, res))
        f.write('\t'.join([sym, kind, ar, rk, res or '', cls, bound if d != ':NOT-ATTEMPTED' and res else '', in2]) + '\n')
print(dict(c)); print(len(notin2), notin2)
mac = [r[0] for r in rows if r[2] == 'macro' and r[4] == 'function']
print(len(mac), 'macro/host-function; not in typed table:', sorted(m for m in mac if m not in stage2))
json.dump({'counts': dict(c), 'narrow-result-not-in-typed-table': notin2,
           'macros-that-are-host-functions': len(mac),
           'of-those-not-in-typed-table': sorted(m for m in mac if m not in stage2)},
          open(R + 'sbcl-unconstrained-counts.json', 'w'), indent=1)
