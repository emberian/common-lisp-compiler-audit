# Three Pure `:logic`-Mode Proofs of `NIL` in ACL2 on SBCL 2.6.10 (and Boot-Time Mitigations for ACL2)

**Target:** ACL2 8.7+ (`1d2b39a424`) hosted on **SBCL 2.6.10** (`darwin-arm64` and `x86-64-linux`)  
**Cross-References:** Full Z3 proofs and plain-SBCL details are in [`Z3-COMPILER-EQUIVALENCE.md`](Z3-COMPILER-EQUIVALENCE.md) (`Z3-1` / `Z3-1-ACL2`) and [`HOST-COMPILERS-WAVE3.md`](HOST-COMPILERS-WAVE3.md) (`HC-W3-1`, `HC-W3-2`). This standalone summary extracts the **three pure `:logic`-mode ACL2 proofs of `NIL` caused solely by SBCL 2.6.10 compiler bugs** so ACL2 maintainers can evaluate build-time checks (`acl2-check.lisp`) and optional `#+sbcl` hot-patches independent of upstream SBCL release timing.

---

## Overview

In all three cases below:
- **ACL2 itself is sound** (on Clozure CL 1.14, all three functions evaluate to their logical values and `(defthm nil-proved nil)` fails as expected).
- Every exploit uses **pure elementary `:logic`-mode ACL2** (`ash`/`logand`, `char-code`/`eql`, `char-equal`/`eql`) with **zero books, zero trust tags (`:ttag nil`, `:ttags-seen nil`), zero `skip-proofs`, zero `redef!`, zero stobjs, zero `loop$`, zero `:df`, zero `memoize`, and zero `defattach`**.
- All three SBCL bugs trigger even at **`(optimize (speed 1) (safety 3))`** (not merely ACL2's `(safety 0)` raw-compilation policy), so compiling with `(set-compiler-enabled ...)` at higher safety does **not** prevent them.

| Bug ID | Architectures Affected | Elementary ACL2 Primitives | SBCL 2.6.10 Root Cause | Standalone Reproducer |
|---|---|---|---|---|
| **`HC-W3-1`** | `arm64` (`darwin-arm64`, `linux-arm64`) | `logand`, `ash`, unary `-`, `(the integer x)` | `srctran.lisp:4084,4118` (`ash-inverted` tests `(:not (integer * 0))` = "not `<= 0`" instead of "`>= 0`") + `arm64/arith.lisp:1158-1189` (`LSL` mod-64 on `|x| >= 64`) | [`repros/host-w3-sbcl-ash-inverted-arm64/`](../repros/host-w3-sbcl-ash-inverted-arm64/acl2-nil-proved.lisp) |
| **`HC-W3-2`** | **`arm64` & `x86-64`** | `char-code`, `eql`, `<=`, `(the (integer 10 20) y)` | `constraint-back.lisp:505-516` (`char-code` `eq` back-propagation negates non-singleton range `[low, high]` on `not-eq` branch) | [`repros/host-w3-sbcl-char-code-constraint/`](../repros/host-w3-sbcl-char-code-constraint/acl2-nil-proved.lisp) |
| **`Z3-1-ACL2`** | **`arm64` & `x86-64`** | `eql`, `char-equal` | `equality-constraints.lisp:153-163` (`inherit-equality-p` returns `from` [`eql`] instead of lattice meet when chaining `(eql y z)` with `(char-equal x y)`) | [`repros/z3-acl2-sbcl-char-equal-nil/`](../repros/z3-acl2-sbcl-char-equal-nil/repro.lisp) |

---

## 1. `HC-W3-1` — Modular Right/Left Shift `(logand #xffffffffffffffff (ash 1 (- x)))` (`arm64`)

### 16-Line ACL2 Proof of `NIL`
```lisp
(in-package "ACL2")

(defun bad-ash (x)
  (declare (xargs :guard (integerp x)))
  (logand #xffffffffffffffff (ash 1 (- (the integer x)))))

(defthm bad-ash-eval
  (equal (bad-ash -1) 0)
  :rule-classes nil)

(defthm bad-ash-def
  (equal (bad-ash -1) 2)
  :hints (("Goal" :in-theory (disable (:executable-counterpart bad-ash))))
  :rule-classes nil)

(defthm nil-proved
  nil
  :hints (("Goal" :use (bad-ash-eval bad-ash-def)))
  :rule-classes nil)
```

### Why It Happens
In SBCL's `src/compiler/srctran.lisp:4084` (`word` modular `ash`) and `:4118` (`signed-word` modular `ash`), the `ash-inverted` transform matches `(ash n (%negate x))` guarded by:
```lisp
(combination-typed-p use %negate (:not (integer * 0)))
```
In SBCL's `combination-typed-p` (`srctran.lisp:4026-4029`), `(:not T)` means `(not (csubtypep arg-type T))` — i.e., "`x` is **not proven `<= 0`**", rather than "`x` is **proven `> 0`**"! Any `x` typed merely as `integer` (which includes `-1`) passes this guard and gets wrapped in `(truly-the (mod 64) x)` for a right-shift `ash-inverted`, computing `1 >> (-1 mod 64) = 1 >> 63 = 0` instead of `1 << 1 = 2`. (A second bug in `src/compiler/arm64/arith.lisp:1181-1188` also miscompiles `(type (signed-byte 64) x)` at `x = -64` to `-9223372036854775808` instead of `0`.)

---

## 2. `HC-W3-2` — `(eql (char-code c) y)` Non-Singleton Range Negation (`arm64` & `x86-64`)

### 22-Line ACL2 Proof of `NIL`
```lisp
(in-package "ACL2")

(defun bad-cc (c y)
  (declare (xargs :guard (and (characterp c) (integerp y) (<= 10 y) (<= y 20))))
  (let ((y (the (integer 10 20) y)))
    (if (eql (char-code c) y)
        :eq
        (if (and (<= 10 (char-code c)) (<= (char-code c) 20))
            :in
            :out))))

(defthm bad-cc-eval
  (equal (bad-cc (code-char 10) 15) :out)
  :rule-classes nil)

(defthm bad-cc-def
  (equal (bad-cc (code-char 10) 15) :in)
  :hints (("Goal" :in-theory (disable (:executable-counterpart bad-cc))))
  :rule-classes nil)

(defthm nil-proved
  nil
  :hints (("Goal" :use (bad-cc-eval bad-cc-def)))
  :rule-classes nil)
```

### Why It Happens
In SBCL's `src/compiler/constraint-back.lisp:505-516`, `(defoptimizer (char-code constraint-propagate-back) ...)` handles `(eq (char-code c) y)` when `y` has integer interval `[low, high]` by constructing `type = (character-set ((low . high)))` and passing `alternative` (the `else` branch!) with `not-p = t` to `conset-add-constraint-to-eql`. That asserts `c` is **not** in `(character-set ((low . high)))` whenever `(char-code c) != y` — which is valid **only** when `low = high` (a singleton constant), and unsound whenever `low < high`.

---

## 3. `Z3-1-ACL2` — `(eql y z)` + `(char-equal x y)` Equivalence-Lattice Coarsening (`arm64` & `x86-64`)

### 20-Line ACL2 Proof of `NIL`
```lisp
(in-package "ACL2")

(defun char-eq-coarsen (x y z)
  (declare (xargs :guard (and (characterp x)
                              (characterp y)
                              (characterp z))))
  (if (eql y z)
      (if (char-equal x y)
          (eql x z)
          nil)
      nil))

(comp 'char-eq-coarsen)

(defthm nil-proved
  nil
  :hints (("Goal" :use ((:instance (:definition char-eq-coarsen)
                                   (x #\a) (y #\A) (z #\A)))))
  :rule-classes nil)
```

### Why It Happens
Because ACL2's logical definition of `char-equal` (`axioms.lisp:18530`) is `#+acl2-loop-only`, compiled ACL2 code calls `cl:char-equal` directly. In SBCL's `src/compiler/equality-constraints.lisp:153-163`, `inherit-equality-p` computes the transitive equality relation across `(from y z)` (`eql`) and `(new x y)` (`char-equal`) and returns **`from` (`eql`)** instead of the coarser relation **`new` (`char-equal`)**. SBCL therefore constant-folds `(eql x z)` to `T` on `(#\a #\A #\A)`, whereas logical `char-eq-coarsen` reduces to `(eql #\a #\A) = NIL`.

---

## 4. Candidate Boot-Time Self-Checks for ACL2 (`acl2-check.lisp`)

ACL2 already runs host Common Lisp sanity checks in `acl2-check.lisp` during bootstrap. Adding compiled self-checks for these three patterns ensures `make` / `save-exec` immediately detects an affected SBCL build:

```lisp
;; Candidate regression probes for acl2-check.lisp:
(let ((f1 (compile nil '(lambda (x)
                          (declare (type integer x))
                          (logand #xffffffffffffffff (ash 1 (- x))))))
      (f2 (compile nil '(lambda (c y)
                          (declare (type character c) (type (integer 10 20) y))
                          (if (eql (char-code c) y)
                              :eq
                              (if (<= 10 (char-code c) 20) :in :out)))))
      (f3 (compile nil '(lambda (x y z)
                          (declare (type character x y z))
                          (if (eql y z)
                              (if (char-equal x y) (eql x z) nil)
                              nil)))))
  (assert (eql (funcall f1 -1) 2))
  (assert (eq  (funcall f2 (code-char 10) 15) :in))
  (assert (eq  (funcall f3 #\a #\A #\A) nil)))
```
