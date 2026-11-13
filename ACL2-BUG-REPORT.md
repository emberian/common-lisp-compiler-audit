# ACL2 consistency / robustness findings

Found by a differential audit of ACL2 against its two host Lisps. Each item has a
self-contained reproducer in `repros/<name>/` with a `run.sh` that takes the path
to a `saved_acl2` and prints the decisive lines.

**Environment**
- ACL2: development snapshot based on 8.7, commit `1d2b39a424`.
- Host A: SBCL 2.6.10. Host B: Clozure CL 1.14, darwin arm64 (Apple Silicon).
- Both hosts built from the same ACL2 sources (`saved_acl2` for each).

**Severity key**
- **Soundness** — `NIL` is provable, or a `defthm`/evaluation contradiction exists,
  with no trust tag, no `skip-proofs`, no `:program` mode, no redefinition.
- **Robustness** — a legal event errors, aborts from raw Lisp, or hangs; no wrong
  value observed.
- **Host divergence** — the same event behaves differently on the two hosts.

A note on provenance: items marked "re-run by the reporter" were reproduced by hand
in a fresh image on both hosts. The two proof-of-`NIL` stobj findings (S3, S4) were
independently re-run and minimized by a second worker (`VERIFY.md` in that repro
directory has the transcripts); S3 was additionally confirmed by certifying a book
that proves `NIL` on CCL. Every reproducer's `run.sh` / `.lisp` is the ground truth.

---

## 1. Soundness

### S1 — a stale compiled file from an older version of a book is loaded without warning

`repros/stale-compiled-file/` (`run.sh`, `race.sh`). Both hosts. Re-run by the reporter.

`include-book` loads a book's compiled file whenever the compiled file's write date
is `>=` the certificate's; nothing else ties the compiled file to the book. If a
compiled file left over from a *different version* of the book is present, its
function definitions, `*1*` functions and `defconst` values are installed as the
current definitions, while the logical world takes the bodies and constants from the
(new) certificate. The two then disagree and `NIL` is provable.

The deterministic variant uses only `cp -p` (what `rsync -t` or unpacking an archive
does), no editing of file internals:

1. `server/` certifies the **new** book: `book.lisp` = `(defun f (x) (cons x 'new))` plus `(defconst *k* 1)` and a theorem `f-is-new` stating `(equal (f x) (cons x 'new))`.
2. two seconds later `local/` certifies the **old** book: `(defun f (x) (cons x 'old))`, `(defconst *k* 2)`, same theorem name.
3. the new `book.lisp` and `book.cert` are copied into `local/` with `cp -p` (times preserved); the compiled file is **not** copied, so the old compiled file stays.
4. a fresh session does `(include-book "book")` in `local/`.

Observed, both hosts:
```
warnings printed by include-book: 0
@R (f 1) evaluates to (1 . OLD), *k* is 1
@R logical body of f: (CONS X 'NEW); world value of *k*: '1
@R NIL proved: :YES          ; (defthm contradiction nil :hints (("Goal" :use ((:instance f-is-new (x 1))))))
```
So `f-is-new` is in the world (it was proved against `(cons x 'new)`), evaluation
runs the old `(cons x 'old)`, and instantiating the theorem at a point where the two
differ proves `NIL`. No warning is printed.

`race.sh` reaches the same state with no copying at all: two hosts sharing a
directory, the second recertifying within the same one-second clock tick (dates have
1 s resolution and each host deletes only its own compiled-file extension).

Checksum book-hashes and `:load-compiled-file t` do not prevent it; `:load-compiled-file nil`
and `(set-compiler-enabled nil state)` do. The expansion file (`book@expansion.lsp`)
follows the same date rule. ACL2's own sources concede the mechanism:
`delete-auxiliary-book-files` comments that a leftover compiled file "might be
erroneously loaded, possibly causing inconsistency", and `:DOC book-hash` tells the
reader to `touch` the compiled file "to avoid a warning".

### S2 — a book with `#+`/`#-` reader conditionals certified by one host, included by the other

`repros/cross-host-reader-conditional/` (`run.sh CERT-IMAGE INC-IMAGE`). Both directions. Re-run by the reporter.

`rc.lisp` contains a function and a theorem whose definition depends on the host:
```lisp
(in-package "ACL2")
(defun rc () (declare (xargs :guard t)) #+sbcl 'sbcl #+ccl 'ccl #-(or sbcl ccl) 'other)
(defthm rc-value (equal (rc) #+sbcl 'sbcl #+ccl 'ccl #-(or sbcl ccl) 'other) :rule-classes nil)
```
Certify on one host, `include-book` on the other. The including host **reads and
compiles** the source (so `(rc)` evaluates to the *includer's* symbol), but takes the
logical body and the theorem `rc-value` from the certificate (the *certifier's*
symbol). They disagree and `NIL` is proved:
```
# certify on SBCL, include on CCL:
@R host :CCL: (rc) evaluates to CCL; logical body 'SBCL
@R NIL proved: :YES
# certify on CCL, include on SBCL:
@R host :SBCL: (rc) evaluates to SBCL; logical body 'CCL
@R NIL proved: :YES
```
The certificate records neither the host nor `*features*`, and there is no check.
`acl2.lisp` (the "Remarks on `*acl2-readtable*`" comment) already states that
`*features*` must be the same in all phases. With the including host's own compiled
file also present, there is no warning at all; the run above shows a routine
`[Compiled file]` warning only because the includer's compiled file was absent.

### S3 — `satisfies`-type cache makes a guard-verified stobj array read return a wrong value (CCL)

`repros/defstobj-satisfies-host/stale-type-cache/f8-min.lisp` (and `nil-book-min.lisp`,
a certifiable book form). **CCL only. Confirmed by independent re-run** (CCL proved
`NIL` and certified the book in three stable fresh runs; SBCL rejects the second
theorem and certification; no `skip-proofs`, trust tag, `:program` mode or raw Lisp).
```lisp
(encapsulate ()
  (local (defun p (x) (declare (xargs :guard t)) (integerp x)))
  (local (defun f1 (x)
           (declare (type (and (or null (integer 0 1)) (satisfies p)) x))
           x)))
(defun p (x) (declare (xargs :guard t)) (or (null x) (integerp x)))
(defstobj st
  (ar :type (array (and (or null (integer 0 1)) (satisfies p)) (4)) :initially 1))
(defun g () (declare (xargs :guard t))
  (with-local-stobj st (mv-let (v st) (mv (equal (ari 0 st) 1) st) v)))
(defthm g-is-t   (equal (g) t)   :hints (("Goal" :in-theory (disable (:e g)))))
(defthm g-is-nil (equal (g) nil) :hints (("Goal" :in-theory '((:e g)))))
(defthm contradiction nil :rule-classes nil
  :hints (("Goal" :use (g-is-t g-is-nil) :in-theory nil)))
```
`p` is first defined `local`ly (as `integerp`) inside the `encapsulate`, where the
declaration `(and (or null (integer 0 1)) (satisfies p))` is compiled; CCL simplifies
that type by *calling* `p` and caches the result keyed by the specifier text. `p` is
then redefined at top level to also accept `NIL`. The `defstobj`'s `make-array`
`:element-type` reuses the stale cache entry (a bit vector) while the accessor's
`(simple-array <spec> (*))` is parsed fresh (a general vector), so the guard-verified
read `(ari 0 st)` of a fresh `:initially 1` array returns garbage: `(g)` is `NIL` by
the executable counterpart yet `T` by the logic. On CCL both `g-is-t` (logic) and
`g-is-nil` (`(:e g)`) are admitted and `contradiction` proves `NIL`; the book
certifies. SBCL rejects `g-is-nil`. Same underlying CCL behaviour as H1 below.

### S4 — an empty `(and …)` array element type collapses a stobj to a string

`repros/defstobj-satisfies-host/string-stobj/f9-min.lisp`. **Both hosts. Confirmed by
independent re-run** (both hosts proved `NIL`; the live stobj fails its own recognizer).
```lisp
(defstobj s8 (a8 :type (array (or character (and integer symbol)) (2)) :initially #\a))
(defun h () (declare (xargs :guard t))
  (with-local-stobj s8 (mv-let (v s8) (mv (s8p s8) s8) v)))
(defthm h-is-t   (equal (h) t)   :hints (("Goal" :in-theory (disable (:e h)))))
(defthm h-is-nil (equal (h) nil) :hints (("Goal" :in-theory '((:e h)))))
(defthm contradiction nil :rule-classes nil
  :hints (("Goal" :use (h-is-t h-is-nil) :in-theory nil)))
```
`(and integer symbol)` is empty, so the element type is `(or character nil)` =
`character`. `maybe-contained-in-character` (`basis-a.lisp:8548`) does not detect this,
so `single-field-type-p` lets the stobj be represented as the bare array; both hosts
upgrade the element type to `character`, and the live stobj is an actual **string**,
which `live-stobjp` rejects. `(s8p s8)` evaluates to `NIL`, so `h-is-nil` holds by the
executable counterpart while `h-is-t` holds by the logic, and `contradiction` proves
`NIL` on both SBCL and CCL.

### S5 — guard-verified `count` uses `eql`, its logical definition uses `equal`

`derived-types/repros/count-eql-vs-equal/` (`run.sh [ccl|sbcl]`). Both hosts. Re-run by the reporter.
```lisp
(defun cnt-gv   (item lst) (declare (xargs :guard (true-listp lst)))                     (count item lst))
(defun cnt-nogv (item lst) (declare (xargs :guard (true-listp lst) :verify-guards nil))  (count item lst))
(cnt-gv   (list 1) (list (list 1)))   ; => 0
(cnt-nogv (list 1) (list (list 1)))   ; => 1
```
`count` is a macro for the logical `count-fn` only under `#+acl2-loop-only`
(`axioms.lisp`), so raw code calls `cl:count`, which compares with `eql`; the logical
`count-fn` compares with `equal`. The item `(1)` is `equal` but not `eql` to the `(1)`
inside the list, so the guard-verified function (raw path) returns 0 while its own
logical definition returns 1. Guard verification succeeds under the plain
`(true-listp lst)` guard; no redefinition, trust tag or `skip-proofs`. Both hosts.
(A one-line `NIL` proof from this divergence is being confirmed separately; the two
differing values above are firsthand.)

### S6 — stale `double-float` ftype proclamation survives `:u` + redefinition (CCL)

`derived-types/repros/stale-df-ftype/` (`run.sh [ccl|sbcl]`). CCL only; requires redefinition. Re-run by the reporter.
```lisp
(defun f (x) (declare (type double-float x)) (df+ x x))      ; proclaims f :: double-float -> double-float
:u
(defun f (x) (declare (xargs :guard (rationalp x))) (+ x 1180591620717411303424))   ; f now returns an integer
(defun g-gv   (x) (declare (xargs :guard (rationalp x)))                    (+ (f x) (f x)))
(defun g-nogv (x) (declare (xargs :guard (rationalp x) :verify-guards nil)) (+ (f x) (f x)))
(g-gv 1)     ; CCL => 1.0E-323        (garbage: integer bits read as a double-float)
(g-nogv 1)   ; CCL => 2361183241434822606850   (correct)
```
`proclaim-dfs` (`interface-raw.lisp`) proclaims an `(ftype (function (double-float …)
(values double-float …)) f)` for the first `f`; `:u` and the non-`df` redefinition do
not retract it, so the guard-verified caller miscompiles `f`'s now-integer result as a
`double-float`. The logical path is correct. SBCL returns the correct value on both
paths (it does not retain the stale proclamation).

**Scope note.** A separate sweep (`derived-types/`, ledger T1) checked the host
compiler's *inferred result type* of every primitive call against the logical value,
for guard-satisfying arguments of many declared types — about 7M checks per host,
6,542 functions, 265/264 operators — and found **zero** cases where an inferred type
excludes a constructible logical value, on either host. So none of the findings here
is an inference-narrowing bug of the kind fixed in the recent SBCL-related notes;
S5/S6 are a macro-equality mismatch and a stale proclamation.

---

## 2. Robustness (legal event, raw-Lisp error or abort; no wrong value)

### R1 — `loop$` body with an unused binding under `set-ignore-ok`: works in session, errors after `include-book`

`repros/loop-ignore-ok/`. Both hosts. (Pre-existing audit finding; `run.sh` is ground truth.)
```lisp
(in-package "ACL2")
(set-ignore-ok t)
(defun f (x)
  (declare (xargs :verify-guards nil))
  (loop$ for k from 0 to 3 sum (let ((unused x)) k)))
```
Certifies, and under `ld` `(f 1)` returns 6. After `(include-book "loop-ignore-ok")`,
`(f 1)` raises:
```
Implementation error: translate11-loop$ in oneify encountered an untranslatable LOOP$ ...
Please contact the ACL2 implementors.
```
`oneify` (the `loop$` case in `interface-raw.lisp`) re-translates the `loop$` when the
executable counterpart is built, but at include time the book's
`acl2-defaults-table` setting (here `set-ignore-ok`) is not in effect, so the unused
binding becomes a translation error. (The re-translation does see the book's own
earlier macros, so the only difference observed is the defaults table, which affects
legality, not meaning.)

### R2 — `lambda$` sibling of R1: aborts certification itself

`repros/lambda-ignore-ok/`. Both hosts.
```lisp
(in-package "ACL2")
(set-ignore-ok t)
(defun g (x)
  (declare (xargs :verify-guards nil))
  (apply$ (lambda$ (a) (let ((unused 1)) a)) (list x)))
```
Under `ld`, `(g 7)` returns 7. `(certify-book "lambda-ignore-ok")` fails with:
```
Implementation error: Translate11-lambda-object in oneify encountered an untranslatable LAMBDA$ ...
even though it was supposedly translated successfully earlier.
```
Same root cause as R1, in the `lambda$` path of `oneify`; here the book cannot be
certified at all.

### R3 — recertified portcullis sub-book makes `include-book` abort from raw Lisp with no detail

`repros/portcullis-book-changed-raw-abort/`. Both hosts.

`top` is certified with `(include-book "sub")` in its portcullis. `sub` is then
changed and recertified. `(include-book "top")` aborts:
```
************ ABORTING from raw Lisp ***********
Error: ... There is a problem with the certificate, which may be described below in detail.
```
No detail follows, and forms piped in after the `include-book` are silently discarded
(the raw abort unwinds past them). The pre-alist check in `chk-raise-portcullis`
(`other-events.lisp`, the `(consp ch-or-cert-obj)` branch) calls
`include-book-raw-error` after the early compiled-file load, outside the handler that
converts such errors into normal ACL2 errors.

### R4 — legal `defun` whose measure/body contains a ground call on a list is rejected by a hard error

`primitives/repros/defun-ground-call-assert.lisp`. Both hosts. Re-run by the reporter.
```lisp
(defun f (n)
  (declare (xargs :measure (nfix n)))
  (if (and (integerp n) (< 5 n)) (if (f '(3)) (f (- n 1)) 0) 0))   ; rejected
(defun g (n)                                                       ; admitted
  (declare (xargs :measure (nfix n)))
  (if (and (integerp n) (< 5 n)) (if (g 3) (g (- n 1)) 0) 0))
```
`f` (ground self-call on a cons, `'(3)`) is rejected with
`HARD ACL2 ERROR in ASSERT$: (ASSERT$ (AND (STRINGP (CAR FN)) (ALISTP (CDR FN))) FN)`;
`g` (ground self-call on an atom, `3`) is admitted. Audit's diagnosis (unverified by
the reporter): the null-body case of `ev-fncall-rec-logical` passes `(car arg-values)`
where `fn` is expected.

### R5 — `ev-fncall-rec-logical` checks only one argument of `binary-*`

`primitives/repros/ev-fncall-rec-logical-binary-star.lisp`. Both hosts. Re-run by the reporter.

`ev-fncall-rec-logical` on `binary-*` with `(#\a 0)` signals a host `TYPE-ERROR`,
where `(0 #\a)` returns `0`. The `BINARY-*` case tests only `y`. The reproducer calls
the evaluator from raw Lisp; whether a user-level event reaches this path is not
established.

### R6 — `flush-compress` has guard `t`, provably returns `nil`, but errors on a non-symbol

`primitives/repros/flush-compress-raw-error.lisp`. Both hosts. Re-run by the reporter.

`(thm (equal (flush-compress x) nil))` is proved and the guard is `t`, but
`(flush-compress 0)` aborts from raw Lisp (`The value 0 is not of type SYMBOL`). The
audit reports `throw-or-attach-call` and `null-body-er` behave the same (those two not
re-run by the reporter).

---

## 3. Host divergence (same event, different outcome on the two hosts)

### H1 — `defstobj` with a `(satisfies p)` element/field type: admitted on SBCL, rejected on CCL

`repros/defstobj-satisfies-host/` (`README.md` has a 22-case table). Re-run by the reporter.
```lisp
(defstub p (x) nil)
(defstobj st (fld :type (or null (satisfies p)) :initially nil))
```
SBCL-hosted ACL2 admits this; CCL-hosted ACL2 rejects it:
```
ACL2 Error [Evaluation] in TOP-LEVEL: ACL2 cannot ev the call of non-executable function P on argument list: (NIL)
```
Root cause: ACL2 writes the specifier into raw code as `(the (or null (satisfies p)) 'nil)`
(`basis-a.lisp:8534`, `:9166`) and into the accessor/updater declarations, without
testing the value against it. CCL's type parser, simplifying the union of `{NIL}` with
the `satisfies` type, calls `p` on each non-numeric member constant
(`ctypep`, `level-1/l1-typesys.lisp:3679`, from `type-union2`); ACL2's raw `defstub`
body throws. SBCL calls only foldable built-ins there (`src/code/typep.lisp:326`).
ACL2's logical admission check (`chk-stobj-field-type-term`) never evaluates `(p nil)`,
so SBCL's "admit" is the outcome ACL2's own story predicts. The same CCL rejection
occurs for `defun`/`let` type declarations, `the`, array element types, and for
predicates that call `hard-error`, `er hard` or `time-tracker`. This is the mechanism
that S3 turns into a wrong value via CCL's type cache.

---

## 4. Not an ACL2 bug — reported here for completeness (belongs to Clozure CL)

### C1 — CCL darwin-arm64 saved image hangs on an inline store into a purified ivector

`repros/ccl-saved-image-write/` (`NOTES.md` has the trigger matrix). Re-run by the reporter.

In a restarted `save-application` image, an inline-compiled store into a pre-save
specialised vector (bit, u8/16/32/64, s8/…, float) never returns when the store
instruction and the element lie in the same 16K page. `purify` copies ivectors into
the read-only area next to code vectors (`lisp-kernel/arm64-gc.c`), and the Apple
Silicon W^X fault handler (`arm64-darwin-mach.c`, `arm64-exceptions.c`) flips that
page RW for the write fault and RX for the instruction fetch, forever
(`CCL_DEBUG_WX=1` logs the alternation at one PC). In ACL2 on CCL this shows up as a
`defstobj` array update hanging after `save-exec`; which fields are hit depends on
page layout. SBCL-hosted ACL2 is unaffected. This is a CCL kernel issue on the
`darwinarm64` port, not an ACL2 or compiler-transform bug; noted because it was found
through ACL2's `save-exec`.

### C2 — CCL `(ash 1 k)` near `k = 2^60` returns a malformed object / kills the process

`derived-types/repros/ccl-ash-near-fixnum-limit/`. CCL only. Re-run by the reporter (two-value test).

For a fixnum `k` within a few bits of `2^60`, CCL 1.14 `(ash 1 k)` returns a malformed
bignum rather than signalling, so e.g. `(integer-length (ash 1 (1- (expt 2 60))))`
yields a negative number on both the logical and raw routes; slightly larger counts
crash the host. SBCL signals an error, correctly. This is a CCL runtime/bignum issue,
not ACL2 — but because ACL2's logical `ash` is evaluated by the host, the wrong value
appears inside the logic on CCL, so it is worth reporting to Clozure. (A prior lane
left a book that drives this to `NIL`; it has been set aside under
`.../prior-agent/` and not re-run, pending a careful check of whether the nil proof is
genuine or an artifact of the crash.)

---

## Reproducing

Each `run.sh` takes the path(s) to `saved_acl2`:
```
repros/stale-compiled-file/run.sh            /path/to/saved_acl2        # S1 (also race.sh)
repros/cross-host-reader-conditional/run.sh  /sbcl/saved_acl2 /ccl/saved_acl2   # S2
repros/defstobj-satisfies-host/stale-type-cache/f8-min.lisp                     # S3 (CCL; ld it)
repros/defstobj-satisfies-host/string-stobj/f9-min.lisp                         # S4 (both; ld it)
repros/defstobj-satisfies-host/run.sh        /sbcl/saved_acl2 /ccl/saved_acl2   # H1 (22-case table)
derived-types/repros/count-eql-vs-equal/run.sh   [ccl|sbcl]                     # S5
derived-types/repros/stale-df-ftype/run.sh       [ccl|sbcl]                     # S6 (CCL)
derived-types/repros/ccl-ash-near-fixnum-limit/run.sh                           # C2 (CCL)
repros/loop-ignore-ok/run.sh                 /path/to/saved_acl2        # R1
repros/lambda-ignore-ok/run.sh               /path/to/saved_acl2        # R2
repros/portcullis-book-changed-raw-abort/run.sh /path/to/saved_acl2     # R3
primitives/repros/*.lisp                                                # R4, R5, R6 (ld or :q then load)
repros/ccl-saved-image-write/run.sh                                     # C1 (CCL only)
```
