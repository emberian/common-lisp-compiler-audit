#!/usr/bin/env python3
"""classify.py sbcl|ccl -- turn results/HOST-signatures.tsv + HOST-violations.tsv into
results/HOST-table.tsv (one classified row per operator x declared signature) and
results/HOST-counts.json.

Classes
  A-top       agrees: the derived result type is T (no restriction to compare)
  A-narrow    agrees: narrower than T; every guard-satisfying boundary tuple of the declared
              types has its logical value in the type (column tuples-checked), and the distinct
              (operator, type) pairs were read by hand (README, "How class A was decided")
  B           narrower than the mathematical range, but every excluded value is larger than
              the host can hold; the rule that fired gives the bound and the reason
  C           narrower and a constructible logical value is outside it (a
              RESULT-NOT-IN-DERIVED or ARG-NOT-IN-DERIVED row in HOST-violations.tsv)
Rows of the planted control DT-CONTROL-FALSE-NARROWING are written with class CONTROL and
are not counted.  VALUE-MISMATCH violations (compiled typed call returns a value different
from the logical one) are not type rows; they are counted separately.
"""
import csv, json, re, sys, collections

host = sys.argv[1]
R = 'results/'

def read(name):
    with open(R + name) as f:
        return list(csv.reader(f, delimiter='\t', quoting=csv.QUOTE_NONE))

def opname(label):            # "(LOGAND 2)" -> LOGAND ; "ASH" -> ASH
    m = re.match(r'\((\S+)', label)
    return m.group(1) if m else label

# (operator names, regex on derived result, bound, reason)
B_RULES = {
 'sbcl': [
  (('INTEGER-LENGTH', 'LOGCOUNT'), r'\(UNSIGNED-BYTE 38\)',
   'result < 2^38',
   'an SBCL bignum has at most sb-bignum:maximum-bignum-length = 2^32-1 words of 64 bits '
   '(src/compiler/generic/early-vm.lisp; bignum.lisp signals an error past it), so no integer '
   'of 2^38 or more bits exists'),
  (('LENGTH',), r'\(INTEGER [01] 274877906943\)',
   'list length < 2^38',
   'sb-vm::max-dynamic-space-size is 2^42 bytes and a cons is 16 bytes (srctran.lisp, '
   'LENGTH derive-type), so a list of 2^38 conses does not fit in any SBCL heap'),
  (('LENGTH', 'COUNT', 'STRING<', 'STRING<=', 'STRING>', 'STRING>=', 'SYMBOL<'),
   r'\(UNSIGNED-BYTE 45\)',
   'result < 2^45',
   'array-dimension-limit is 2^45 (8 bits per byte of the 2^42-byte maximum heap); no string '
   'or list has 2^45 elements'),
  (('POSITION', 'SEARCH'), r'\(MOD 35184372088831\)',
   'index < 2^45 - 1',
   'an index is below the length, and array-dimension-limit is 2^45 (see LENGTH)'),
  (('LEN',), r'\(UNSIGNED-BYTE 62\)',
   'result < 2^62',
   'ACL2 declaims LEN to return a fixnum and its raw loop signals an error at '
   'most-positive-fixnum (axioms.lisp); a list of 2^62 conses needs 2^66 bytes'),
 ],
 'ccl': [],   # filled in below from what CCL actually reports
}
try:
    exec(open('classify-ccl-rules.py').read())   # optional: defines CCL_B_RULES
    B_RULES['ccl'] = CCL_B_RULES
except FileNotFoundError:
    pass

summary = read(host + '-summary.tsv')
sigs = read(host + '-signatures.tsv')[1:]
vios = read(host + '-violations.tsv')[1:]
crashed = []
try:
    crashed = [l.rstrip('\n') for l in open(R + host + '-crashed.txt')]
except FileNotFoundError:
    pass

# An operator that crashed the host has rows from the dead attempt followed by the rows of
# the re-run; keep only the rows from the last time its first signature appears.
def drop_dead_attempts(rows):
    out, byop = [], collections.OrderedDict()
    for r in rows:
        byop.setdefault(r[0], []).append(r)
    for op, rs in byop.items():
        if op in crashed:
            first = rs[0][1]
            last = max(i for i, r in enumerate(rs) if r[1] == first)
            rs = rs[last:]
        out.extend(rs)
    return out
sigs = drop_dead_attempts(sigs)
done = {r[0]: r for r in summary[1:] if len(r) > 2 and r[1] not in ('EXCLUDED', 'HOST-CRASH')}
sigs = [r for r in sigs if r[0] in done]

type_vio = collections.defaultdict(list)
value_vio = collections.defaultdict(list)
for v in vios:
    if len(v) < 4 or v[0] not in done:
        continue
    key = (v[0], v[1])
    if 'NOT-IN-DERIVED' in v[3]:
        type_vio[key].append(v)
    if 'VALUE-MISMATCH' in v[3]:
        value_vio[key].append(v)

counts = collections.Counter()
brule_counts = collections.Counter()
out = [['operator', 'declared-arg-types', 'derived-result', 'class', 'bound', 'reason',
        'tuples-checked', 'universe']]
for r in sigs:
    op, args, res, extra, nt = r[0], r[1], r[2], r[3], r[4]
    uni = done[op][-1]
    cls, bound, reason = None, '', ''
    if op == 'DT-CONTROL-FALSE-NARROWING':
        cls = 'CONTROL'
        reason = 'planted false declaration; %d violating rows reported' % len(type_vio[(op, args)])
    elif type_vio[(op, args)]:
        cls = 'C'
        reason = type_vio[(op, args)][0][2] + ' ' + type_vio[(op, args)][0][3]
    elif res in ('T', '*'):
        cls = 'A-top'
    else:
        for names, pat, b, why in B_RULES[host]:
            if opname(op) in names and re.search(pat, res):
                cls, bound, reason = 'B', b, why
                brule_counts[b + ' (' + '/'.join(names) + ')'] += 1
                break
        if cls is None:
            cls = 'A-narrow'
    counts[cls] += 1
    out.append([op, args, res, cls, bound, reason, nt, uni])

with open(R + host + '-table.tsv', 'w') as f:
    for row in out:
        f.write('\t'.join(row) + '\n')

ops = collections.OrderedDict((r[0], 1) for r in sigs if r[0] != 'DT-CONTROL-FALSE-NARROWING')
info = {
    'host': host,
    'operators': len(ops),
    'rows': sum(v for k, v in counts.items() if k != 'CONTROL'),
    'class-counts': dict(counts),
    'class-B-by-rule': dict(brule_counts),
    'tuple-checks': sum(int(done[o][4]) for o in ops),
    'guard-satisfying-tuples': sum(int(done[o][2]) for o in ops),
    'reference-timeouts': sum(int(done[o][7]) for o in ops),
    'slow-tuples-membership-only': sum(int(done[o][8]) for o in ops),
    'operators-run-on-reduced-universe': [o for o in ops if done[o][-1] == 'reduced'],
    'host-crash-operators': [r[0] for r in summary[1:] if len(r) > 1 and r[1] == 'HOST-CRASH'],
    'excluded': {r[0]: r[2] for r in summary[1:] if len(r) > 2 and r[1] == 'EXCLUDED'},
    'value-mismatch-rows': sorted(set('%s %s' % k for k in value_vio
                                      if k[0] != 'DT-CONTROL-FALSE-NARROWING')),
    'control-violations': sum(len(v) for k, v in type_vio.items()
                              if k[0] == 'DT-CONTROL-FALSE-NARROWING'),
}
with open(R + host + '-counts.json', 'w') as f:
    json.dump(info, f, indent=1)
print(json.dumps({k: v for k, v in info.items() if k != 'excluded'}, indent=1))

# Anything with a numeric bound and an unbounded declared argument that no B rule claimed is
# listed for the reader, so that a new representation limit cannot hide in class A.
UNB = ('T', '(INTEGER 0 *)', 'INTEGER', 'RATIONAL', '(COMPLEX RATIONAL)', 'STRING', 'SYMBOL', 'CONS')
seen = collections.OrderedDict()
for row in out[1:]:
    if row[3] == 'A-narrow' and re.search(r'\d{6,}', row[2]) and \
       any(re.search(r'(^|[( ])' + re.escape(u) + r'($|[) ])', row[1]) for u in UNB):
        seen.setdefault((opname(row[0]), re.sub(r'-?\d{6,}', '#', row[2])), row)
with open(R + host + '-review-large-bounds.tsv', 'w') as f:
    for (o, shape), row in seen.items():
        f.write('\t'.join([o, shape, row[1], row[2]]) + '\n')
