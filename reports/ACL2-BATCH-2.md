# ACL2 Findings — Batch 2 (Post-`ACL2-BUG-REPORT.md`)

All findings below are distinct from both the initial 7 reproducers sent to Eric Smith and
Batch 1 (`ACL2-BUG-REPORT.md` `S1`–`S7`, `R1`–`R7`, `H1`). Verified on ACL2 `1d2b39a424`
under SBCL 2.6.10 and Clozure CL 1.14 (darwin-arm64).

---

## 1. Robustness / Translation & Proclamation Bugs

### B2-R1 (F16) — Guard-verified `:df` function whose tail call returns multiple values in CL aborts at runtime and inside `thm` (SBCL)

- **Reproducer:** `repros/df-tail-multiple-values/` (`df-floor.lisp`, `session.lisp`, `run.sh`)
- **Host impact:** Aborts from raw Lisp on SBCL 2.6.10; succeeds (`2`) on CCL 1.14.
- **No `skip-proofs`, no trust tag, no redefinition.**

```lisp
(in-package "ACL2")

(defun zdf-floor (x)
  (declare (type double-float x))
  (floor (from-df x) 1))

;; Admitted and guard-verified cleanly (:COMMON-LISP-COMPLIANT).
;; Logically (zdf-floor (to-df 5/2)) = 2, and (let ((r (floor (from-df x) 1))) r) returns 2.
;; Calling it directly — or proving a theorem that evaluates it — aborts from raw Lisp on SBCL:
(zdf-floor (to-df 5/2))
(thm (equal (zdf-floor (to-df 5/2)) 2))
```

**Observed on SBCL:**
```text
************ ABORTING from raw Lisp ***********
Error: Values [2 1/2] from (FLOOR (FROM-DF X) 1) in
       ... is not of the declared return type of the function
       (VALUES T &OPTIONAL).
```

**Root cause:** `proclaim-dfs` (`interface-raw.lisp`) proclaims
`(ftype (function (double-float &optional) (values t &optional)) zdf-floor)` whenever a
function has a `:df` formal. Because ACL2's logical `floor` (and `truncate`, `ceiling`,
`round`) is a macro over a single-valued logical definition while raw Common Lisp code
invokes `cl:floor` (returning two values: quotient and remainder), a tail call forwards both
values out of `zdf-floor`, violating `(values t &optional)` under SBCL's return-value count
check.

---

### B2-R2 (F17) — `loop$` variable prematurely shadows outer `:df` formal inside the `in`/`from`/`to` target expression (both hosts)

- **Reproducer:** `repros/loop-shadows-df/` (`session.lisp`, `run.sh`)
- **Host impact:** Both SBCL and CCL (ACL2 translation bug).

```lisp
(in-package "ACL2")

;; Control 1 (different loop var y): admitted, evaluates to 2.
(defun zdf-loop-y (x)
  (declare (type double-float x) (xargs :verify-guards nil))
  (loop$ for y in (list (floor (from-df x) 1)) sum y))

;; Control 2 (let shadowing df formal x): admitted, evaluates to 3.
(defun zdf-let-x (x)
  (declare (type double-float x) (xargs :verify-guards nil))
  (let ((x (floor (from-df x) 1))) (+ x 1)))

;; Bug: loop$ variable x shadows df formal x, but (from-df x) is in the outer list target!
(defun zdf-loop-x (x)
  (declare (type double-float x) (xargs :verify-guards nil))
  (loop$ for x in (list (floor (from-df x) 1)) sum x))
```

**Observed (both hosts):**
```text
ACL2 Error in ( DEFUN ZDF-LOOP-X ...):  The form X represents an ordinary
object, but it is being used where a form representing a :DF was expected,
namely, as an argument to a call of FROM-DF in (FROM-DF X).
```

**Root cause:** In `(loop$ for x in EXPR ...)`, `EXPR` is evaluated *outside* the scope of
the loop binding `x` (just like `let`), yet `loop$` translation strips/shadows `x` from
`df-vars` before translating `EXPR`.

---

## 2. Sibling Triggers of Batch-1 Bugs

### B2-S6b (F13-stobj) — Stale `double-float` `ftype` via `defstobj` accessor survives `(u)` and faults memory on CCL

- **Reproducer:** `repros/stale-df-ftype-stobj/` (`session.lisp`, `run.sh`)
- **Relation:** Stobj-accessor trigger of Batch 1 `S6` (`proclaim-dfs` `ftype` not retracted
  on undo), causing a raw memory-read fault (`#x-4`) in a fresh guard-verified function with
  no trust tags or redefinition:

```lisp
(in-package "ACL2")
(defstobj zst2 (zfld :type double-float :initially 0))
(u)
(defstobj zst2 (zfld :type (unsigned-byte 129) :initially 0))
(defun zread-nogv (zst2) (declare (xargs :stobjs zst2 :verify-guards nil)) (+ 1 (zfld zst2)))
(defun zread-gv   (zst2) (declare (xargs :stobjs zst2))                    (+ 1 (zfld zst2)))

(zread-nogv zst2) ; => 1 (both hosts)
(zread-gv   zst2) ; => 1 on SBCL; ABORTING from raw Lisp: Fault during read of memory address #x-4 on CCL!
```

### Note on `ME1` (`siblings/make-event-trust/`)
The systematic audit of `make-event` expansion-trust (`siblings/make-event-trust/MAKE-EVENT-TRUST.md`)
confirmed that without tampering or setting `boot-strap-flg` (which requires a trust tag in
normal sessions unless invoked via raw Lisp as in your earlier reproducer #2), `.cert`
recording prevents `:expansion?` spoofing; all 7 untampered `make-event` inclusion paths
tested clean on both hosts.
