# B rules for CCL 1.14 (read by classify.py).  Filled in from the rows CCL actually reports.
CCL_B_RULES = [
  (('LEN',), r'^FIXNUM$',
   'result < 2^60',
   'ACL2 declaims LEN to return a fixnum (axioms.lisp) and CCL uses the declaration; the raw '
   'loop signals an error at most-positive-fixnum, and a list of 2^60 conses needs 2^64 bytes'),
]
