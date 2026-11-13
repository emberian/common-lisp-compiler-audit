# FINDINGS — stobj/array/attachment raw code vs logic

ACL2 8.7+ dev (commit 1d2b39a424).  Hosts: SBCL 2.6.10 (`acl2-sbcl`),
CCL 1.14 (`acl2-ccl`).  All probes runnable via
`/Users/ember/dev/compiler-audit/scouts/lisp-run.sh HOST SCRIPT`; transcripts
are `SCRIPT.HOST.out` next to each script.

## Confirmed

1. **`aset1` on an `:order :none`/`:order nil` array at its `:maximum-length`
   is a *total function* in the logic but a HARD ERROR in raw execution**
   (divergence of class ERROR-where-a-value-was-expected; NOT a soundness
   claim, and the error is documented — see caveat).
   - Reproducer: `probe9-maxlen.lisp` (acl2-sbcl AND acl2-ccl; identical
     behavior).
   - Observed (probe9-maxlen.lisp.acl2-sbcl.out, .acl2-ccl.out):
     - `(array1p 'tgh *a-tight*)` => T (dims 3, max-length 4, alist length
       4 — `array1p` requires `dimensions < maximum-length` but nothing
       bounds alist length against maximum-length);
     - `ASET-TIGHT-LOG` **proves**
       `(equal (aset1 'tgh *a-tight* 1 9) ((1 . 9) <header> (0 . 5) (1 . 6) (2 . 7)))`
       by executable-counterpart of ASET1 — the logical `aset1` takes its
       `(compress1 name l')` branch and the logical `compress1` with order
       nil is `(prog2$ <hard-error tripwire> l)`, i.e. returns the pushed
       alist;
     - raw `(compress1 'tgh *a-tight*)` then `(aset1 'tgh *a-tight* 1 9)`:
       `HARD ACL2 ERROR in COMPRESS1: Attempted to compress a one-dimensional
       array named TGH whose header specifies :ORDER NIL and whose length, 5,
       exceeds its maximum-length, 4.` (Evaluation aborted.)
   - Mechanism: raw `aset1`'s registered fast path hits the to-go=0 branch
     (axioms.lisp:13371-13396) and calls raw `compress1`, whose order-nil
     length check (axioms.lisp:13092-13101) hard-errors; the logical
     definitions carry no such restriction (`hard-error` is logically inert).
     The ordered variants (`:order <` / `:order >`) rebuild instead and agree
     with the logic (checked in the same probe: value 8 raw = 8 logical).
   - Caveat (why filed as documented divergence, not a bug): ACL2 release
     notes (doc.lisp:92316-92321) state this exact behavior as a deliberate
     fix so that `:maximum-length` "is respected" for `:order :none` arrays;
     logical totality vs raw partiality is an accepted implementation
     restriction, like `array-dimension-limit`.  Recorded because the logic
     can *prove a value* for a guard-legal call (ASET-TIGHT-LOG) that raw
     execution cannot produce — the logic/raw disagreement class this audit
     inventories.

## Refuted

1. **Raw `alphorder`/`lexorder` mis-dispatch on raw double-floats** — raw
   `alphorder` sends non-`rationalp` numbers to the `symbol<` branch
   (axioms.lisp:27163-27181); a raw double-float from `to-df` is not
   `rationalp`. But `to-df` results have stobjs-out shape `:DF` and translate
   rejects them in `*` contexts ("signature mismatch ... result of shape :DF
   where a result of shape * is required"). Float constants are rejected as
   bad Lisp objects; `#d1.5` reads as the rational 3/2. Unreachable from
   legal events. (probe1-lexorder-df.lisp)
2. **Scalar/array typed field round-trips diverge** — matrix of 14 scalar
   types ((integer -5 10), (integer 0 *), (signed-byte 63), (signed-byte 64),
   (unsigned-byte 62/64), rational, character, string, symbol,
   (or integer string), (member foo bar baz), (satisfies my-even) with total
   pred, bit) and 6 array types ((signed-byte 8), (unsigned-byte 32),
   (signed-byte 64), string, t, resizable (integer 0 9) incl. resize up +
   default fill + boundary values 2^62-1 / 2^63-1 / -2^63 / 2^64-1): raw on
   the live stobj equals logical ec evaluation on (create-...) everywhere.
   (probe2-matrix.lisp: acl2-sbcl and acl2-ccl, 0 FAILED)
3. **Hash-table fields diverge** — get/put (duplicate-key overwrite), boundp,
   keys (raw hash-iteration -> merge-sort-lexorder vs logical alist ->
   merge-sort-lexorder + remove-adjacent-duplicates), count (count-keys
   dedup vs hash-table-count), rem, clear, get?, miss defaults, tests
   eql/equal/hons-equal/eq, element type (integer 0 9) with default 7: all
   consistent raw vs logic; hons-equal lookup with a fresh-but-equal cons
   key hits (hons-copy canonicalization). (probe3-hash.lisp: acl2-sbcl,
   acl2-ccl, 0 FAILED)
4. **`(satisfies pred)` with non-total pred, incl. array/hash element types**
   — defstobj rejects `(satisfies evenp)` ("produces the term, (EVENP X),
   which ACL2 is unable to check is guard-verified"); the scalar and
   :element-type paths share `chk-stobj-field-type-term`
   (other-events.lisp:19784-19787). The stricter guard-must-be-T checker
   (`chk-unrestricted-guards-for-type-spec-term`, other-events.lisp:19624)
   is dead code, but the live guard-clauses check covers the same cases.
5. **defabsstobj pass-2 / ld-skip-proofsp hole (B18)** — already fixed in
   this snapshot (books/system/tests/defabsstobj-pass2-constrained-exec.lisp
   records the history).
6. **stobj-let / nested stobjs / stobj-table / congruent stobjs** — child
   field update+readback, child in array, child in resizable array (resize
   creates fresh kids with creator defaults, raw and logically), stobj-table
   get/put/count/keys, with-local-stobj programs, congruent stobj aliasing:
   raw = logic everywhere. (probe4-nested.lisp: acl2-sbcl, acl2-ccl)
7. **Memoize staleness via discarded destructive child update** — the
   note-6-5 memoize-flush fires when the child is a producer var; the
   "sibling" (discard the updater's stobj result via prog2$/let*) is
   rejected at translate ("illegal to invoke UPDATE-KFLD ... returns a result
   of shape KID where a result of shape * is required"). Statically blocked.
   (probe5-memo-flush.lisp)
8. **stobj-let double binding on one stobj-table key / one child type** —
   rejected: the bound variable must BE the key's stobj name, and each bound
   variable must be a distinct known stobj name, so two same-typed (or
   same-key) bindings are unrepresentable. (probe6-table-alias.lisp,
   probe7-swap-inline.lisp)
9. **swap-stobjs** — both-live swap through with-local-stobj matches logic
   (raw (99 12 55 12) = logical theorem, ec disabled). Inside proofs, ec
   evaluation creates a real local stobj object and `swap-stobjs-check`
   correctly fires ("the value of S2 is a live stobj but the value of S1 is
   not") — the 8.7 fix working as designed; the theorem fails cleanly.
   `:inline t` (DEFABBREV) accessors round-trip correctly; depth-2 nested
   stobj-let writes match logic. (probe7-swap-inline.lisp)
10. **aref1/aset1/compress1 differential (order :none/</`>`, duplicate keys,
    default-valued writes)** — raw (registered-vector fast path) equals
    logical ec on the same terms. (probe8-aref1.lisp)
11. **EQL-vs-EQUAL hash-key mismatch for bignums/ratios/complexes** — both
    hosts' EQL is value-based ((:BIGNUM-EQL T :RATIO-EQL T :COMPLEX-EQL T)
    on SBCL and CCL), so raw EQL tables agree with logical
    hons-assoc-equal: two equal-but-distinct bignums are ONE entry both raw
    and logically (count 1, second value wins, keys singleton).
    (probe10-keys.lisp: acl2-sbcl, acl2-ccl)
12. **defabsstobj with attachable (constrained) recognizer logic** — the
    required {correspondence}/{preserved} theorems are unprovable for a
    constrained st$ap, so the defabsstobj is rejected at definition
    (probe11-absstobj.lisp: st2 rejected, "events must be admitted before
    the given defabsstobj"). A working absstobj's exports round-trip
    correctly raw vs logic (abs-test 8 = 8).
13. **`(satisfies p)` where p calls a constrained function, then
    defattach** — defstobj itself rejects the field because the :initially
    type check must *evaluate* the type-term and ACL2 "cannot ev the call of
    non-executable function CONSTR-FLG" (probe12-sat-attach.lisp). The
    subsequent defattach succeeds only because no stobj depends on the
    constrained function.
14. **`:ubt` then redefinition of a stobj with a different layout** — after
    `ubt!` the redefinition is accepted and the live object is a FRESH one
    of the new layout (u1=5, u2="x", u3i 0=NIL, ubp=T), not the old vector
    reinterpreted; stale references are impossible because anything that
    could hold the old object depends on the undone defstobj.
    (probe13-ubt-redef.lisp, probe13b-ubt-redef-read.lisp)
15. **Mixed-type key sort order** — keys {-5, 3/4, 100, 1267650600228229401496703205376,
    #\c, alpha, beta} sort identically raw and logically: numbers by value,
    then characters, then symbols (probe10-keys.lisp, both hosts).

## Not checked (most promising first)

- **df (double-float) field end-to-end**: not differential-testable — the
  logical value of `to-df`-derived data is a *constrained* rational, so no
  theorem can pin it to a specific number; raw IEEE values are therefore
  vacuously "consistent".  The generators' df-aware defaults (hashp-init,
  make-stobj-scalar-field to-df on dfp inits, non-dfp inits rejected by the
  :initially check) were read and look covered.
- 2-d arrays (aref2/aset2/compress2) — same fast-path architecture as the
  1-d case probed in probe8, but not executed.
- tb-count/clean-stobj-table after :ubt of a stobj (raw table mutation vs
  pure count-keys): dead entries require redefining a stobj after :ubt
  while a live parent persists — the parent depends on the undone defstobj,
  so the scenario appears unreachable without raw mode.
- memoize + updates routed through abstract-stobj :exec functions
  (memoize-flush via congruent-stobj-rep-raw of an attached stobj).
- GCL-specific paths (get-stobj-scalar-field's 1-element-array
  representation; copy-array-fix-aref) — no GCL host available.
