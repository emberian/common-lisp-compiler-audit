# ACL2 Guard-Obligation & Type-Declaration Soundness Audit (`RESEARCH.md` §4 — Lane 1)

**Target:** ACL2 Version 8.7+ (`1d2b39a424eabeab269f189b37c29148d49fc516`)  
**Hosts Verified:** SBCL 2.6.10 (`darwin-arm64`) and Clozure Common Lisp 1.14 (`darwin-arm64`)  
**Fuzzer & Harness:** `hunts/xdsmith-guards/` (`gen_xdsmith_guards.py`, `run_xdsmith.sh`)  
**Standalone Reproducers:** `repros/plain-loop-of-type-dropped-guard/`, `repros/flet-macrolet-known-dfs-nil/`, `repros/mv-let-retry-known-dfs-nil/`, `repros/loop-for-of-type-df-nil/`, `repros/loop-do-known-dfs-and-cl-cache-nil/`, `repros/loop-empty-type-ccl-crash/`

All findings below are brand-new and disjoint from `ACL2-BUG-REPORT.md` (`S1`–`S7`, `R1`–`R7`, `H1`), `reports/ACL2-BATCH-2.md` (`B2-R1`, `B2-R2`, `B2-S6b`), `dcl-guardian-nil.lisp`, and `bogus-exported-compliants` in `encapsulate`. Every soundness reproducer installs `(defthm nil-proved nil :rule-classes nil)` on fresh ACL2 sessions on **both** SBCL 2.6.10 and CCL 1.14 with `(ttag (w state)) = NIL`, `(global-val 'ttags-seen (w state)) = NIL`, and `(global-val 'skip-proofs-seen (w state)) = NIL` (no books, no `skip-proofs`, no trust tags, no redefinition).

---

## 1. Executive Summary

| ID | Category | Construct / Subsystem | Root Cause (`head-worktree`) | Impact (SBCL 2.6.10 & CCL 1.14) | Standalone Reproducer |
|---|---|---|---|---|---|
| **XDS-S1** | **Soundness** (`NIL` proved, zero `:df`, zero books) | Plain `FOR` `loop$` + `of-type` `(member …)`, `real`, `(real …)`, `(complex …)`, `(or)` | `type-expressions-from-type-spec` (`translate.lisp:3845`) uses `tflg = t` while `translate11-lambda-object` expands macros on `tflg = nil` (`axioms.lisp:11687,11784,11859,11884`), making `well-formed-lambda-objectp` return `NIL`; both `special-loop$-scion-callp` (`history-management.lisp:13269`) and `collect-certain-lambda-objects` (`translate.lisp:20585`) silently skip **all** `of-type`, `sum`, and loop-body guard obligations | `(defthm nil-proved nil)` Q.E.D. in pure `cons` + `eq` + `loop$` on both hosts (caught directly as `XDS-SURVIVOR-SOUNDNESS` by the negative fuzzer) | `repros/plain-loop-of-type-dropped-guard/` |
| **XDS-S2** | **Soundness** (`NIL` proved in 2 events / 4 steps) | `flet` & `macrolet` inside `:df` (`double-float`) scope | `translate11-flet` (`translate.lisp:22336`) and `translate11-macrolet` (`translate.lisp:22425,22471`) pass `nil ; known-dfs` when translating the body, letting unboxed `double-float`s flow into `equal`/ordinary slots without `from-df` | `(defthm nil-proved nil)` Q.E.D. in 2 events (zero `memoize`) on both hosts (`(equal 1.0d0 1)` = `NIL` vs logic `T`) | `repros/flet-macrolet-known-dfs-nil/` |
| **XDS-S3** | **Soundness** (`NIL` proved in 3 events / 61 steps) | Recursive `mv-let` inside `:df` (`double-float`) scope | `translate11-collecting-known-dfs` retry path (`translate.lisp:23020-23022`, entered when `stobjs-out-val` is still a function symbol) omits `(set-difference-eq top-known-dfs bound-vars)`, dropping all outer `:df` variables in the `mv-let` body | `(defthm nil-proved nil)` Q.E.D. in 3 events (zero `memoize`) on both hosts | `repros/mv-let-retry-known-dfs-nil/` |
| **XDS-S4** | **Soundness** (`NIL` proved in 4 events + CCL segfault) | `FOR` `loop$` + `of-type double-float` | `translate-vsts` (`translate.lisp:18601`) and `adjust-known-dfs-for-var-tuples` (`translate.lisp:24621`) allow `of-type double-float` on `FOR` `loop$`, binding `x` in `known-dfs` while compiling `(loop for x of-type double-float in lst …)` at `(safety 0)` over boxed rationals/bignums | Segfaults CCL / aborts SBCL on `'(1)`; reinterprets boxed `(expt 2 100)` as `0.0d0` -> `(0)` vs `(2^100)`, proving `(defthm nil-proved nil)` on both hosts | `repros/loop-for-of-type-df-nil/` |
| **XDS-S5a/b/c** | **Soundness** (`NIL` proved + `*cl-cache*` corruption) | `DO` `loop$` + `with … of-type double-float` | **S5a/b:** `translate-with-var-tuples` (`translate.lisp:24397`) adds `var` to `known-dfs` *before* translating `init-form` and fails to remove shadowed `var` from `known-dfs` when `spec != 'double-float`. **S5c:** `translate11-do-clause` (`translate.lisp:23790`) passes `stobjs-out = t` on an already-translated `binary-df+` body and `verify-guards` compiles that `LAMBDA` into `*cl-cache*` at `(safety 0)` on boxed `ALIST` entries | `(defthm nil-proved nil)` Q.E.D. on both hosts; even a completely well-typed non-shadowed `DO` `loop$` poisons `*cl-cache*` so unverified `do$` flips from `2^100` to `0` | `repros/loop-do-known-dfs-and-cl-cache-nil/` |
| **XDS-R1** | **Robustness + Dropped Inner Guard** | Direct `lambda$` + `(declare (type (member …) y))` / `real` / `(complex …)` | Same `well-formed-lambda-objectp = NIL` mismatch as `XDS-S1`: `collect-certain-lambda-objects` (`translate.lisp:20585`) skips both body guard verification and `*lambda-alist$*` registration | Guard-verified `defun` skips false `lambda$` body guards (`(car y)` on symbol) and crashes at runtime on valid inputs with `HARD ACL2 ERROR in APPLY$-LAMBDA` | `repros/plain-loop-of-type-dropped-guard/` |
| **XDS-R2** | **Host Divergence / Raw Lisp Crash** | `FOR` `loop$` + empty type `of-type (integer 1 0)` | Raw CL `(loop for x of-type (integer 1 0) …)` triggers CCL `ANSI-LOOP` `(subtypep '(integer 1 0) 'character)` default-init bug `(character 0)` | Admits & guard-verifies on SBCL 2.6.10; aborts from raw Lisp during `defun` compilation on CCL 1.14 | `repros/loop-empty-type-ccl-crash/` |
| **XDS-R3** | **Translation Bug** | `DO` `loop$` `:guard` with outer variable | `translate11-loop$` (`translate.lisp:24957-24964`) collects free variables of `measure`, `do-body`, and `finally` into `vars`, omitting `translated-do-body-guard` and `translated-fin-body-guard` | Legal `DO` `loop$` whose `:guard` mentions an outer formal absent from `do-body` fails translation with an internal `LAMBDA (ALIST)` free-variable error on both hosts | `repros/loop-empty-type-ccl-crash/` |

---

## 2. XDsmith Known-Outcome Negative-Guard Fuzzer (`hunts/xdsmith-guards/`)

Following `RESEARCH.md` §4, we built a deterministic, seedable negative-guard generator (`hunts/xdsmith-guards/gen_xdsmith_guards.py`) and dual-host driver (`hunts/xdsmith-guards/run_xdsmith.sh`) covering **360 tests** across **7 construct families** and **29 Common Lisp type specifiers** (`signed-byte`, `unsigned-byte`, `mod`, `bit`, inclusive & exclusive `integer`/`rational`/`real` intervals, `ratio`, `(string k)`, `standard-char`, `(member …)`, `(satisfies …)`, `(and …)`, `(or …)`, `(not …)`, `(complex …)`, and `(or t …)` prefixes):

1. **Dual Static Negative Oracles (`330` tests across Families F1–F7)**:
   Each generated function is admitted with `:verify-guards nil` and paired with a concrete counterexample witness satisfying the outer `:guard` while falsifying an inner `declare (type …)`, `the`, `of-type`, `:guard`, `:df`, or `stobj` obligation:
   - **Oracle `@NO` (`guard-obligation` witness check):** Extracts `(guard-obligation fn nil nil :limited … state)`, conjoins all generated clauses, substitutes the concrete witness, and verifies under `(with-guard-checking-error-triple :none …)` that the logical guard obligation evaluates to **`NIL`**.
   - **Oracle `@NV` (`verify-guards` rejection check):** Runs `(verify-guards-fn fn …)` and verifies both a non-`nil` error return and `(eq (symbol-class fn (w state)) :ideal)`. Any test where `verify-guards` succeeds or promotes `symbol-class` to `:common-lisp-compliant` is flagged immediately as `XDS-SURVIVOR-SOUNDNESS`.
2. **Dynamic `apply$` / `lambda$` Cache Oracle `@ND` (`30` tests in Family F4b)**:
   Pairs a guard-verified wrapper (`:common-lisp-compliant`) and an unverified wrapper (`:ideal`) around `(apply$ (lambda$ (y) (declare (type <spec> y)) …) (list x))` applied to an out-of-type witness `bad_val`, checking both that `(with-guard-checking-error-triple t …)` signals a guard error (never running the `(safety 0)` compiled `lambda$` body) and that `(with-guard-checking-error-triple :none …)` agrees identically between verified and unverified wrappers.
3. **Positive Bug-Probe Validation Suite (`suite_bug_probes.lisp`, `8` probes)**:
   Confirms that our differential soundness oracle catches `BUG1` (`flet`), `BUG1B` (`macrolet`), `BUG2` (`mv-let` retry), `BUG3` (`FOR` `loop$` `of-type double-float`), `BUG4A`/`BUG4B` (`DO` `loop$` `translate-with-var-tuples`), `BUG5` (`DO` `loop$` `*cl-cache*` corruption), and `BUG6` (`FOR` `loop$` dropped `of-type` & body guards).

### Fuzzer Results (Seed `20261113`, Identical on SBCL 2.6.10 & CCL 1.14, ~8s Total Runtime)

| Construct Family | Tests | `XDS-PASS` | Soundness Survivors / Bugs Caught by Fuzzer | Spurious Anomalies |
|---|---:|---:|---|---:|
| **F1:** `:split-types t` + compound CL types + `(or t …)` + 3-level `let*` / `mv-let` / open-`lambda` shadowing + `defun-inline` + `mbe` + stacked `declare` | 90 | 90 | 0 (`dcl-guardian` & `:split-types t` held on all 90) | 0 |
| **F2:** `FOR` `loop$` (`in`, `on` dotted lists, `from`/`to`, `when :guard`, fancy free-var `loop$`, multi-clause `for`/`as`) | 60 | 57 | **3 `XDS-SURVIVOR-SOUNDNESS`** (`XDS-F2-004-COMPLEX-UB4`, `XDS-F2-008-MEMBER-SYM`, `XDS-F2-010-NOT-ZERO` -> **`XDS-S1`**!) | 0 |
| **F3:** `DO` `loop$` (`with … of-type`, `setq`, `mv-setq`) | 45 | 45 | 0 (non-`:df` `DO` `of-type` obligations held; `:df` scoping bugs caught in `XDS-S5a/b/c`) | 0 |
| **F4a:** Static `lambda$` obligations (`the`, `:split-types t` + `let`, `collect$` + `lambda$`) | 45 | 45 | 0 | 0 |
| **F4b:** Dynamic `apply$` / `lambda$` `*cl-cache*` dispatch differential tests | 30 | 25 | **5 `XDS-BUG-LAMBDA-ALIST-CRASH`** (`(member …)`, `(complex …)`, `(real …)` -> **`XDS-R1`**!) | 0 |
| **F5:** `flet` local `declare (type …)`, multi-call obligations & shadowed formals | 35 | 35 | 0 (non-`:df` `flet` obligations held; `:df` drop caught in `XDS-S2`) | 0 |
| **F6:** `:df` (`double-float`) domain & range negative obligations (`to-df`, `df/`, `df-sqrt`, `df-log`, `df-acos`, `df-asin`, `df-atanh`, `df-acosh`, `df-expt`) | 30 | 30 | 0 | 0 |
| **F7:** `defstobj` scalar/array `(signed-byte 8)`, `(unsigned-byte 8)`, `(satisfies …)`, `(or …)`, OOB indices, `stobj-let`, `with-local-stobj` | 25 | 25 | 0 | 0 |
| **Total (`suite_negative.lisp`)** | **360** | **352** | **3 `XDS-SURVIVOR-SOUNDNESS` + 5 `XDS-BUG-LAMBDA-ALIST-CRASH`** | **0** |

---

## 3. Detailed Soundness Findings

### XDS-S1 — Plain `FOR` `loop$` with `of-type` `(member …)`, `real`, `(real …)`, `(complex …)`, or `(or)` silently drops `of-type`, `sum`, and loop-body guard obligations (Proves `NIL`, Zero `:df`, Zero Books)

- **Reproducer:** `repros/plain-loop-of-type-dropped-guard/` (`session.lisp`, `run.sh`)
- **Discovered by:** XDsmith negative-guard fuzzer (`XDS-F2-004-COMPLEX-UB4`, `XDS-F2-008-MEMBER-SYM`, `XDS-F2-010-NOT-ZERO`).

#### Minimal Proof of `NIL` (SBCL 2.6.10 & CCL 1.14)
```lisp
(defun loop-member-nil (x)
  (declare (xargs :guard t))
  (let ((lst (list (cons x x))))
    (car (loop$ for z of-type (member :a :b) in lst
                collect (eq z '(0 . 0))))))

(defthm loop-member-nil-logic
  (equal (loop-member-nil 0) t)
  :hints (("Goal" :in-theory (disable loop-member-nil))))

(memoize 'loop-member-nil)
(make-event (let ((ign (loop-member-nil 0)))
              (declare (ignore ign))
              '(value-triple :warmed)))

(defthm nil-proved
  nil
  :hints (("Goal" :use loop-member-nil-logic
                  :in-theory (disable loop-member-nil loop-member-nil-logic)))
  :rule-classes nil)
```

#### Root Cause
1. A plain `FOR` `loop$` (`make-plain-loop$-lambda-object`, `translate.lisp:18540-18554`) puts `(declare (type <spec> loop$-ivar))` directly into the generated `lambda$`.
2. `translate11-lambda-object` (`translate.lisp:24015-24290`) derives `:guard` by calling `(translate-declaration-to-guard spec var wrld)` (`tflg = nil`) and passing the result through `translate11`, which expands macros.
3. Later, `well-formed-lambda-objectp` (`translate.lisp:4912`) calls `syntactically-plausible-lambda-objectp` (`translate.lisp:4140-4141`), which checks:
   ```lisp
   (subsetp-equal (flatten-ands-in-lit-lst type-exprs)
                  (flatten-ands-in-lit guard))
   ```
   where `type-exprs` is computed by `type-expressions-from-type-spec` (`translate.lisp:3845`) calling `(translate-declaration-to-guard-gen spec var t nil)` (`tflg = t`).
4. For four families of legal Common Lisp type specifiers (and any compound `and`/`not`/`or` containing them), `tflg = t` does **not** match `translate11` of `tflg = nil`:
   - `(member …)` (`axioms.lisp:11784`): `tflg = t` produces `(MEMBER-EQUAL var '(…))`, whereas `tflg = nil` produces `(MEMBER var '(…))`, which expands via `member-eql` to an `mbe` lambda over `member-eql-exec`.
   - `real` and `(real lo hi)` (`axioms.lisp:11687, 11691, 11700, 11707`): `tflg = t` produces `(REAL/RATIONALP var)` (a macro!), whereas `translate11` expands it to `(RATIONALP var)`.
   - `(complex <subspec>)` (`axioms.lisp:11884`): `tflg = t` produces `(COMPLEX/COMPLEX-RATIONALP var)` (a macro!), whereas `translate11` expands it to `(COMPLEX-RATIONALP var)`.
   - `(or)` (`axioms.lisp:11859`): produces `'NIL`, which `syntactically-plausible-lambda-objectp1` (`translate.lisp:3891-3893`) rejects whenever `type-exprs` is non-empty.
5. Because `well-formed-lambda-objectp` returns `NIL` on the translated `LAMBDA` object:
   - `special-loop$-scion-callp` (`history-management.lisp:13269`) returns `NIL`, so `special-conjectures` (`history-management.lisp:13409`) generates **neither** Special Conjecture (a) (that elements of `lst` satisfy `of-type` and `:guard`) **nor** Special Conjecture (b) (`sum` numeric output check).
   - `collect-certain-lambda-objects` (`translate.lisp:20585`) *also* skips the `LAMBDA` object, so **the loop body's own internal guard obligations** (here `(eq z '(0 . 0))`, whose guard requires `(symbolp z)`) are never checked either!
   - Meanwhile, `loop-member-nil` is marked `:COMMON-LISP-COMPLIANT` and runs raw `(loop for z of-type (member :a :b) in (list (cons 0 0)) collect (cl:eq z '(0 . 0)))` at `(safety 0)`, returning `NIL` on a fresh cons cell while logic proves `(equal '(0 . 0) '(0 . 0)) = T`.

*(Note: Fancy `FOR` `loop$`s avoid this only because `make-fancy-loop$` lifts type guards into `:guard` without emitting `(declare (type … loop$-ivars))` on the `LAMBDA` header.)*

#### Suggested Fix
- In `axioms.lisp` (`translate-declaration-to-guard1-gen` and `translate-declaration-to-guard-gen-rec`), make `tflg = t` emit true translated terms matching `translate11` (e.g., `rationalp` / `real/rationalp` per `#+non-standard-analysis`, `complex-rationalp`, and consistent handling for `member` and `(or)`), **and** assert `(well-formed-lambda-objectp val wrld)` (or check syntactic plausibility) at the exit of `translate11-lambda-object` so `translate11` can never emit a `LAMBDA` object that downstream `verify-guards` / `special-loop$-scion-callp` silently ignores.

---

### XDS-S2 — `translate11-flet` and `translate11-macrolet` pass `nil` for `known-dfs`, leaking unboxed `double-float`s into `equal` (2-Event Proof of `NIL`)

- **Reproducer:** `repros/flet-macrolet-known-dfs-nil/` (`session.lisp`, `run.sh`)

#### Minimal Proof of `NIL` (SBCL 2.6.10 & CCL 1.14)
```lisp
(defun flet-df-nil ()
  (declare (xargs :guard t))
  (let ((x (to-df 1)))
    (declare (type double-float x))
    (flet ((id (y) y))
      (and (id t) (equal x 1)))))

(defthm nil-proved
  nil
  :hints (("Goal" :in-theory (disable flet-df-nil (:type-prescription flet-df-nil))
                  :use ((:instance (:type-prescription flet-df-nil)))))
  :rule-classes nil)
```
*(The identical `macrolet` trigger `(macrolet ((m (y) y)) (and (m t) (equal x 1)))` is included in `repros/flet-macrolet-known-dfs-nil/session.lisp`.)*

#### Root Cause
- In `translate11-flet` (`translate.lisp:22336`), the body of `flet` is translated with `nil ; known-dfs` instead of forwarding `known-dfs`.
- In `translate11-macrolet` (`translate.lisp:22425, 22471`), `translate11-macrolet` does not even accept a `known-dfs` parameter (`translate11` at line `25335` drops `known-dfs` when calling it) and passes `nil ; known-dfs` when translating the `macrolet` body.
- Consequently, any enclosing `:df` variable `x` (bound in raw Common Lisp to an unboxed IEEE-754 `double-float` `1.0d0`) is accepted without `from-df` in ordinary ACL2 positions such as `(equal x 1)`. At admission, type reasoning proves `(equal (flet-df-nil) t)` because `(to-df 1)` is logically `1`, while `(:executable-counterpart flet-df-nil)` invokes raw Common Lisp `(equal 1.0d0 1)` = `NIL`, proving `NIL` in 4 prover steps.

#### Suggested Fix
- Thread `known-dfs` into `translate11-macrolet` (`translate.lisp:22425, 22471, 25335`) and pass `known-dfs` (instead of `nil`) when translating the body in `translate11-flet` (`translate.lisp:22336`). (Note: local `flet` function bodies themselves have fresh lexical parameter scopes, so passing `nil` when translating local `flet` *definitions* is fine because ACL2 `flet` forbids free variable capture, whereas the `flet` *body* executes in the enclosing `known-dfs` scope.)

---

### XDS-S3 — `translate11-collecting-known-dfs` retry path drops enclosing `known-dfs` in `mv-let` (3-Event Proof of `NIL`)

- **Reproducer:** `repros/mv-let-retry-known-dfs-nil/` (`session.lisp`, `run.sh`)

#### Minimal Proof of `NIL` (SBCL 2.6.10 & CCL 1.14)
```lisp
(defun rec-mv-df (n d)
  (declare (type double-float d)
           (xargs :guard (natp n)))
  (if (not (zp n))
      (mv-let (a b)
        (rec-mv-df (- n 1) d)
        (mv a (or b (equal d 1))))
    (mv 0 nil)))

(defun trigger-mv-df ()
  (declare (xargs :guard t))
  (mv-let (a b)
    (rec-mv-df 1 (to-df 1))
    (declare (ignore a))
    b))

(defthm nil-proved
  nil
  :hints (("Goal" :in-theory (disable trigger-mv-df (:e rec-mv-df))
                  :use ((:instance (:definition trigger-mv-df)))
                  :expand ((rec-mv-df 1 1) (rec-mv-df 0 1))))
  :rule-classes nil)
```

#### Root Cause
- In `translate11-collecting-known-dfs` (`translate.lisp:23002-23055`), used to translate `mv-let`:
  - The normal path (`translate.lisp:23047-23051`) computes `new-known-dfs` as:
    ```lisp
    (append (collect-by-position '(:df) stobjs-out-val bound-vars)
            (set-difference-eq top-known-dfs bound-vars))
    ```
  - However, when `stobjs-out-val` is a symbol (which happens on a recursive call `(rec-mv-df (- n 1) d)` in the first branch of a `defun` before `rec-mv-df`'s output signature has been inferred), `translate11-collecting-known-dfs` enters its retry branch (`translate.lisp:23015-23026`) and computes `known-dfs` on lines `23020-23022` as:
    ```lisp
    (collect-by-position '(:df) stobjs-out-for-form bound-vars)
    ```
    omitting `(set-difference-eq top-known-dfs bound-vars)`!
- All enclosing `:df` variables (`d`) not rebound by `mv-let` vanish from `known-dfs` inside the `mv-let` body, allowing `(equal d 1)` on raw `1.0d0` (`NIL` in raw Lisp vs `T` in logic).

#### Suggested Fix
- In `translate.lisp:23020-23022`, replace `(collect-by-position '(:df) stobjs-out-for-form bound-vars)` with `(append (collect-by-position '(:df) stobjs-out-for-form bound-vars) (set-difference-eq top-known-dfs bound-vars))`.

---

### XDS-S4 — `FOR` `loop$` permits `of-type double-float`, reading boxed ACL2 rationals/bignums as raw IEEE-754 floats at `(safety 0)` (4-Event Proof of `NIL` + CCL Segfault)

- **Reproducer:** `repros/loop-for-of-type-df-nil/` (`session.lisp`, `run.sh`)

#### Minimal Proof of `NIL` (SBCL 2.6.10 & CCL 1.14)
```lisp
(defun df-loop-read (k)
  (declare (xargs :guard (equal k 100)))
  (let ((lst (list (expt 2 k))))
    (loop$ for x of-type double-float in lst
           collect (from-df (df+ x (to-df 0))))))

(memoize 'df-loop-read)
(make-event (let ((ign (df-loop-read 100)))
              (declare (ignore ign))
              '(value-triple :warmed)))

(defthm df-loop-read-logic
  (equal (df-loop-read 100) (list (expt 2 100)))
  :hints (("Goal" :in-theory (e/d (collect$ apply$)
                                  ((df-loop-read) (:e df-loop-read))))))

(defthm nil-proved
  nil
  :hints (("Goal" :use df-loop-read-logic
                  :in-theory (disable df-loop-read df-loop-read-logic)))
  :rule-classes nil)
```

#### Root Cause
- As explained in the comment in `authenticate-tagged-lambda$` (`defuns.lisp:9572-9609`), ACL2 explicitly forbade compiling `lambda$`s with `double-float` formals because ACL2 lists store boxed rationals (never raw `double-float`s).
- However, `translate-vsts` (`translate.lisp:18601`) and `adjust-known-dfs-for-var-tuples` (`translate.lisp:24619-24621`) allow `of-type double-float` on `FOR` `loop$` variables, adding `x` to `known-dfs` while Special Conjecture (a) only checks `(dfp newv)`.
- In raw Common Lisp at `(safety 0)`, `(loop for x of-type double-float in lst …)` binds `x` without `to-df` directly to a boxed ACL2 integer/bignum/ratio pointer and executes raw hardware float instructions (`+`) on the tagged pointer:
  - On `'(1)`, CCL segfaults (`Fault during read of memory address #x4`) and SBCL aborts from raw Lisp.
  - On `(list (expt 2 100))`, both SBCL 2.6.10 and CCL 1.14 read the bignum header bits as a subnormal/zero IEEE-754 float, returning `(0)` instead of `(1267650600228229401496703205376)`. Memoizing `df-loop-read` records `(0)` in the memo table and proves `NIL`.

#### Suggested Fix
- Reject `of-type double-float` (and compound type specs mentioning `float` / `double-float` / `single-float` / `short-float` / `long-float` if any) in `translate-vsts` for `FOR` `loop$` clauses (`in`, `on`, `from`/`to`/`by`), since `FOR` `loop$` targets always produce boxed ACL2 objects rather than `:df` values.

---

### XDS-S5a/b/c — Three `DO` `loop$` + `of-type double-float` Soundness Bugs (`translate-with-var-tuples` Scoping + `*cl-cache*` Unboxed `binary-df+` Compilation)

- **Reproducer:** `repros/loop-do-known-dfs-and-cl-cache-nil/` (`session.lisp`, `run.sh`)

#### Root Causes
1. **XDS-S5a (`translate-with-var-tuples`, `translate.lisp:24397` — Premature `known-dfs` addition):**
   Line `24397` binds `(known-dfs (if (eq spec 'double-float) (cons var known-dfs) known-dfs))` *before* translating `init-form` (`translate.lisp:24420`). Thus in:
   ```lisp
   (let ((v (expt 2 k)))
     (loop$ with v of-type double-float = v
            do :measure (acl2-count 0)
            (return (from-df (df+ v (to-df 0))))))
   ```
   the RHS `v` (an outer boxed bignum `2^100`) is mistakenly treated as already in `known-dfs` and passed without `to-df` into raw CL `(loop with v of-type double-float = v …)` at `(safety 0)`, evaluating to `0` instead of `2^100` and proving `(defthm nil-proved nil)` on both SBCL and CCL.
2. **XDS-S5b (`translate-with-var-tuples`, `translate.lisp:24397` — Unremoved shadowed `:df` variable):**
   When `spec` is *not* `double-float` (e.g., `with x = (expt 2 100)` shadowing an enclosing `:df` formal `x`), `translate-with-var-tuples` leaves `x` in `known-dfs` for subsequent `with` clauses (`with y of-type double-float = x`), again passing boxed bignum `x` into raw `double-float` `y` without `to-df` and returning `0` instead of `2^100`.
   *(Note: `translate11-loop$` around `translate.lisp:24850` should also be checked to ensure untyped `with x = …` removes `x` from `known-dfs` inside the `DO` and `FINALLY` bodies!)*
3. **XDS-S5c (`translate11-do-clause`, `translate.lisp:23788-23796` — `*cl-cache*` compiles unboxed `binary-df+` on boxed `ALIST` entries):**
   Even for a **completely well-typed, non-shadowed** `DO` `loop$`:
   ```lisp
   (loop$ with z of-type double-float = (to-df (expt 2 100))
          do :measure (acl2-count 0)
          (return (from-df (df+ z (to-df 0)))))
   ```
   `translate11-do-clause` (`translate.lisp:23790`) wraps the already-translated `do-body-term` into `(LAMBDA$ (ALIST) … (LET ((Z (CDR (ASSOC-EQ-SAFE 'Z ALIST)))) … (FROM-DF (BINARY-DF+ Z (TO-DF '0)))))` with `stobjs-out = t` ("not translating for execution"). However, when `verify-guards` runs on the enclosing `defun`, `authenticate-tagged-lambda$` (`defuns.lisp:9572`) sees only formal `(ALIST)` with no `(declare (type double-float …))` in the `LAMBDA` header, approves it, and **compiles that `LAMBDA` in raw Common Lisp in `*cl-cache*` at `(safety 0)`**! In `*1*` / `do$` execution, `ALIST` holds boxed rationals (`2^100`), so `(legal-do-df-unverified)` evaluates to `1267650600228229401496703205376` *before* `legal-do-df-verified` is admitted and **`0`** *after* `legal-do-df-verified` is admitted!

#### Suggested Fix
- **For S5a/S5b:** In `translate-with-var-tuples` (`translate.lisp:24397-24439`), translate `init-form` under the *incoming* `known-dfs`, then compute `next-known-dfs` as `(if (eq spec 'double-float) (cons var known-dfs) (remove1-eq var known-dfs))` for `guard-term`, `(cdr tuples)`, and the `DO`/`FINALLY` clauses.
- **For S5c:** In `authenticate-tagged-lambda$` (`defuns.lisp:9572-9609`) or `cl-cache` compilation (`apply-raw.lisp`), refuse raw compilation of any `LAMBDA` object whose body invokes `:df` primitives (`to-df`, `from-df`, `binary-df+`, etc., i.e., `df-functionp`), since `do$` `ALIST`s always store boxed rationals rather than raw `double-float`s.

---

## 4. Robustness & Host-Divergence Findings

### XDS-R1 — Direct `lambda$` with `(declare (type (member …) y))` / `real` / `(complex …)` skips body guard verification and crashes at runtime with `HARD ACL2 ERROR in APPLY$-LAMBDA`

- **Reproducer:** `repros/plain-loop-of-type-dropped-guard/` (`session.lisp`, `run.sh`)
- **Discovered by:** XDsmith negative-guard fuzzer (`F4B-LAMBDA-DYN-CACHE`).
- **Behavior (both SBCL & CCL):**
  1. `(defun bogus-body-lambda-member (x) (declare (xargs :guard t)) (apply$ (lambda$ (y) (declare (type (member :a :b) y)) (car y)) (list x)))` is admitted as `:COMMON-LISP-COMPLIANT` even though `(car y)` violates its guard on `:a`/`:b`, because `collect-certain-lambda-objects` (`translate.lisp:20585`) skips `LAMBDA` objects failing `well-formed-lambda-objectp`.
  2. `(defun valid-lambda-member (x) (declare (xargs :guard t)) (apply$ (lambda$ (y) (declare (type (member :a :b) y)) (list y)) (list x)))` admits as `:COMMON-LISP-COMPLIANT`, but calling `(valid-lambda-member :a)` aborts with `HARD ACL2 ERROR in APPLY$-LAMBDA: Apply$-lambda has encountered an untranslated lambda$ expression … not resolved by lambda-alist$`, because `collect-certain-lambda-objects :lambda$` also skipped registering it in `*lambda-alist$*`.
- **Fix:** Same fix as `XDS-S1`.

### XDS-R2 — `FOR` `loop$` with empty type `of-type (integer 1 0)` admits on SBCL 2.6.10, aborts from raw Lisp on CCL 1.14

- **Reproducer:** `repros/loop-empty-type-ccl-crash/` (`session.lisp`, `run.sh`)
- **Behavior:**
  ```lisp
  (defun empty-type-loop (lst)
    (declare (xargs :guard (null lst)))
    (loop$ for x of-type (integer 1 0) in lst collect x))
  ```
  Admits as `:COMMON-LISP-COMPLIANT` and evaluates `(empty-type-loop nil) => NIL` on SBCL 2.6.10, but aborts from raw Lisp during `defun` compilation on CCL 1.14:
  ```text
  ************ ABORTING from raw Lisp ***********
  Error:  The value 0 is not of the expected type (SATISFIES CCL::CHARACTER-DESIGNATOR-P).
  While executing: CHARACTER
  ```
  because CCL's `ANSI-LOOP` macroexpander tests `(subtypep '(integer 1 0) 'character) => T` (vacuously true for the empty type) and attempts `(character 0)` as the loop variable's initial value.

### XDS-R3 — `DO` `loop$` `:guard` mentioning an outer variable absent from `measure`/`do-body`/`finally` fails translation

- **Reproducer:** `repros/loop-empty-type-ccl-crash/` (`session.lisp`, `run.sh`)
- **Behavior (both hosts):**
  ```lisp
  (defun do-guard-free-var-bug (bound)
    (declare (xargs :guard (natp bound) :verify-guards nil))
    (loop$ with x = 0
           do :measure (acl2-count 0)
              :guard (<= x bound)
              (return x)))
  ```
  Fails translation because `translate11-loop$` (`translate.lisp:24957-24964`) computes `vars` (and `genvar-avoid-vars` at `24976-24984`) from `(list translated-mform translated-do-body translated-fin-body)`, omitting `translated-do-body-guard` and `translated-fin-body-guard`. Consequently `sigma` does not replace `bound` with `(cdr (assoc-eq-safe 'bound alist))` inside `make-do-body-lambda$`, leaving `bound` free inside `(LAMBDA$ (ALIST) …)`.
- **Suggested Fix:** Include `translated-do-body-guard` and `translated-fin-body-guard` in the `all-vars1-lst` and `all-vars-bound-and-free1-lst` lists at `translate.lisp:24959-24963` and `24979-24983`.

### Minor Source-Audit Notes (Non-Exploitable as Standalone Bugs)
- `axioms.lisp:11848`: `(translate-declaration-to-guard-gen-rec '(and) var t wrld)` returns unquoted `t` instead of `(kwote? tflg t)` (`'t`).
- `translate.lisp:21268`: `returns-df?` on `(the type form)` returns `'(:df)` / `'(nil)` (both non-`nil` truthy lists in CL!) rather than a boolean; callers only stay safe because `translate11-the` separately checks `stobjs-out` compatibility.

---

## 5. Verification Summary

Every standalone reproducer can be re-verified end-to-end on fresh SBCL and CCL images via:
```bash
for d in \
  plain-loop-of-type-dropped-guard \
  flet-macrolet-known-dfs-nil \
  mv-let-retry-known-dfs-nil \
  loop-for-of-type-df-nil \
  loop-do-known-dfs-and-cl-cache-nil \
  loop-empty-type-ccl-crash
do
  /Users/ember/dev/compiler-audit/repros/$d/run.sh
done
```
And the full 360-test XDsmith negative-guard fuzzer + 8-probe positive validation suite can be regenerated and executed on both hosts via:
```bash
/Users/ember/dev/compiler-audit/hunts/xdsmith-guards/run_xdsmith.sh
```
