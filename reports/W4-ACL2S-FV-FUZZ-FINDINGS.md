# Wave-4 Lane 2: ACL2s + FV Engines Mechanical Fuzzing Findings

**Date:** 2026-11-13  
**Scope:** Mechanical fuzzing of `books/acl2s/` (`fuzz_acl2s_deep.py`) and `books/centaur/{gl,satlink,ipasir}`, `books/clause-processors/`, `books/projects/smtlink/` (`fuzz_gl_fgl_cp.py`) across **ACL2 8.7+ on SBCL 2.6.10**, **ACL2 8.7+ on CCL 1.14**, and **Z3 5.4.1** (via `/opt/homebrew/bin/python3`), strictly beyond `ACL2S-1..4` and `FV-1..6`.

---

## 1. Campaign Metrics

### 1.1 `hunts/w4-acl2s-fv-fuzz/fuzz_acl2s_deep.py`
| Runtime | Executed | Exit Code | Novel Bug Classes Confirmed |
|---|---:|---:|---|
| SBCL 2.6.10 | 91 / 91 | 0 | 3 (`defunc` SEGV, `match` capture/crash, `defdata/map` + `record` collision) |
| CCL 1.14 | 91 / 91 | 0 | 3 (`defunc` abort, `match` capture/crash, `defdata/map` + `record` collision) |

### 1.2 `hunts/w4-acl2s-fv-fuzz/fuzz_gl_fgl_cp.py`
| Suite | SBCL 2.6.10 (`executed / rc / findings`) | CCL 1.14 (`executed / rc / findings`) | Verified Novel Findings |
|---|---|---|---|
| `smtlink` (end-to-end ACL2 + Z3 5.4.1) | 20 / 0 / 1 | 20 / 0 / 1 | `SOUNDNESS_THM_NIL` (`uninterpreted-fn-cp.lisp` `let`-shadowing) |
| `gl` (`bfr-fraig-satlink` + 30 differential + edge) | 34 / 0 / 1 | 34 / 0 / 1 | `SOUNDNESS_THM_NIL` (`bfr-fraig-satlink.lisp:41-42` `create-state`) |
| `sat` (`ipasir` + `satlink` Dimacs/CNF) | 22 / 0 / 1 | 22 / 0 / 1 | `IPASIR_DIMACS_INT32_GUARD_GAP` (`INT32_MIN` + `2^31` overflow) |
| `cp` (54 malformed-hint & false-goal tests) | 54 / 0 / 0 | 54 / 0 / 0 | 0 (no crash or soundness bypass observed) |
| **Total** | **130 / 0 / 3** | **130 / 0 / 3** | **3 distinct novel FV findings** |

---

## 2. Verified Novel Findings

### Finding 1 — `defunc` Ignores `pseudo-translate` Error Flag, Crashing `(safety 0)` `all-fnnames1`
- **Source:** `books/acl2s/defunc.lisp:1629-1631` (`parse-defunc`)
- **Severity / Class:** Raw Lisp Memory Fault / Hard Abort (`SIGSEGV` at `#x2` / `#x27` on SBCL 2.6.10; `ACL2::ALL-FNNAMES1` abort on CCL 1.14)
- **Threat Model / `:ttags`:** Standard ACL2s user event (`defunc` with an undefined symbol in body).
- **Mechanism:** `parse-defunc` calls `(mv-let (erp p-body) (acl2::pseudo-translate ...) ...)` at line 1629, ignores `?erp`, and passes `p-body` (which on translation failure is an ACL2 error `msgp` rather than a `pseudo-termp`) to `(acl2::all-fnnames p-body)` at line 1631, crashing `(safety 0)` `all-fnnames1`.
- **Reproducer:** `repros/w4-fv-acl2s-defunc-all-fnnames-segv/run.sh` (verified exit `0` on SBCL 2.6.10 & CCL 1.14)
- **Fix:** Check `erp` immediately after `pseudo-translate` and raise a clean ACL2 soft/hard error before calling `all-fnnames`.

### Finding 2 — `acl2s/match` Silent `:logic` Outer-Variable Capture (`!sym`), Empty `!`, and Unguarded `match-fun` Crash
- **Source:** `books/acl2s/match.lisp:195-204, 248-255, 306-317`
- **Severity / Class:** Silent `:logic`-mode Miscompilation + Macroexpansion Raw Lisp Crash
- **Threat Model / `:ttags`:** Pure `:logic` code (zero `:ttags`).
- **Mechanism:**
  1. In `(match x ((a . !a) (list a)) (& nil))`, `!a` emits `(equal a ...)` into the outer `cond` test before pattern-bound `a` is bound, silently capturing an outer `a` (e.g., `a=42`) and proving `(equal (match-bang-capture '(1 . 42) 42) '(1))` instead of `nil`.
  2. Bare `!` slices `(subseq "!" 1)` to `""` (line 199), emitting unbound symbol `||`.
  3. `defmacro match` (lines 306-317) calls `(safety 0)` `definec` helper `match-fun` without validating clause shape (`(1 . 2)`), crashing raw Lisp inside `defunc` / `:guard-checking :none`.
- **Reproducer:** `repros/w4-fv-acl2s-match-capture-and-crash/run.sh` (verified exit `0` on SBCL 2.6.10 & CCL 1.14)
- **Fix:** Resolve `!sym` against pattern bindings (or reject shadowing/unbound `!`), reject bare `!`, and validate `args` shape in `defmacro match` before calling `match-fun`.

### Finding 3 — `defdata` `map.lisp` `?valpred` Copy-Paste Bug & Cross-Package `record` Variable Collision
- **Source:** `books/acl2s/defdata/map.lisp:160-162, 199-201`; `books/acl2s/defdata/record.lisp`
- **Severity / Class:** Codegen / Admission Failure in Mutually-Recursive Maps & Cross-Package Records
- **Threat Model / `:ttags`:** Standard `defdata` events.
- **Mechanism:**
  1. In `map.lisp:160, 199`, `?valpred` checks `(and (proper-symbolp keybody) (assoc-eq keybody M) (predicate-name valbody A M))` (testing `keybody` instead of `valbody`), causing mutually-recursive `(defdata (kmap (map k v)) (k nat) (v (oneof nil kmap)))` to emit bogus `MUTUAL-RECURSION` on `KMAPP`.
  2. `(defdata cross-rec (record (acl2::a . nat) (acl2s::a . integer)))` intern-collides both fields onto `VAR-CROSS-REC-A` inside a single `LET` in `CROSS-RECP`.
- **Reproducer:** `repros/w4-fv-acl2s-defdata-map-and-record/run.sh` (verified exit `0` on SBCL 2.6.10 & CCL 1.14)
- **Fix:** Check `valbody` in `map.lisp:160, 199`; include package-disambiguated suffixes when generating `LET` binders for `record` fields.

### Finding 4 — `bfr-fraig-satlink.lisp:41-42` Non-Local `(remove-untouchable acl2::create-state t)` Soundness Leak
- **Source:** `books/centaur/gl/bfr-fraig-satlink.lisp:41-42`
- **Severity / Class:** Soundness (`(defthm ... nil)` `Q.E.D.` under `(defttag nil)`)
- **Threat Model / `:ttags`:** Requires `:ttag aig-fraig->cnf` during `include-book`; **afterward under `(defttag nil)`**, any `:verify-guards nil` function can call `with-local-state`.
- **Mechanism:** `bfr-fraig-satlink.lisp:41-42` executes non-local `(remove-untouchable acl2::create-state t)` without restoring untouchability. Under `(defttag nil)`, `with-local-state` + `f-get-global` can observe two different values of a global across `make-event (assign ...)` and derive `NIL`.
- **Reproducer:** `repros/w4-fv-gl-fraig-untouchable-create-state/run.sh` (verified exit `0` on SBCL 2.6.10 & CCL 1.14)
- **Fix:** Wrap `remove-untouchable` in `local` or restore `acl2::create-state` as untouchable before ending the book.

### Finding 5 — `ipasir` / `satlink` 32-Bit Dimacs Literal `INT32_MIN` & `2^31` Overflow + Missing `:logic` Guards
- **Source:** `books/centaur/ipasir/ipasir-logic.lisp:249-268, 315-325, 480-490`; `books/centaur/ipasir/ipasir-interface-raw.lsp:329-383`
- **Severity / Class:** C FFI Signed-Integer Overflow / Guard Domain Gap
- **Threat Model / `:ttags`:** Pure `:logic` / `:program` usage of `satlink::satlink-to-dimacs-lit` and `ipasir::ipasir-add-lit$a` / `ipasir-assume$a`.
- **Mechanism:**
  1. `(satlink::make-lit 2147483647 1)` is a valid `satlink::litp`, but `satlink::satlink-to-dimacs-lit` maps it to `-2147483648` (`INT32_MIN`), whose negation overflows `int32_t` (`(:NEGATED-OVERFLOWS-S32 T)`), directly affecting `(- dimacs-lit)` in `ipasir-interface-raw.lsp:375`.
  2. `(satlink::make-lit 2147483647 0)` maps to `+2147483648`, which is not `(signed-byte-p 32 ...)`.
  3. `ipasir-add-lit$a` and `ipasir-assume$a` accept literals `>= 2^32` (tested with `4294967295` and `(satlink::make-lit (expt 2 40) 0)`).
- **Reproducer:** `repros/w4-fv-ipasir-int32-dimacs-bounds/run.sh` (verified exit `0` on SBCL 2.6.10 & CCL 1.14)
- **Fix:** Strengthen `satlink::lit->var` / `ipasir` guards to `< (expt 2 31) - 1` (excluding `2147483647`) so Dimacs literals and their negations fit in `signed-byte-p 32`.

### Finding 6 — End-to-End ACL2 + Z3 `SMTLink` Soundness Bug via `let`/Lambda Variable Shadowing
- **Source:** `books/projects/smtlink/verified/uninterpreted-fn-cp.lisp:105-142, 388`
- **Severity / Class:** End-to-End Soundness (`(defthm ... nil)` `Q.E.D.` in ACL2 + Z3 5.4.1)
- **Threat Model / `:ttags`:** Standard `:smtlink-custom` hint with `:functions` (`w4-id-fn :formals ((z rationalp)) :returns ((r integerp))`).
- **Mechanism:** `uninterpreted-fn-cp` emits a return-type hypothesis whose lambda/let binding shadows outer variable `y` (`(let ((y 1/2)) (w4-id-fn y))`) while `(integerp y)` remains in scope, allowing Z3 5.4.1 to discharge `w4-let-shadow-lemma` and ACL2 to prove `NIL` (`Q.E.D.`).
- **Reproducer:** `repros/w4-fv-smtlink-let-shadow-unsound/run.sh` (verified exit `0` on SBCL 2.6.10 & CCL 1.14)
- **Fix:** Alpha-rename lambda/let binders in `uninterpreted-fn-cp` using fresh symbols disjoint from all free variables in the clause.

---

## 3. Falsified / Negative Leads
1. **`books/acl2s/ccg/ccg.lisp:7566` (`chk-assumption-free-ttree nil`)**: Tested `force`, `case-split`, and `fc-derivation` rules inside CCG termination proofs; `fc-derivation` / forced-assumption ttrees were not leaked into `(thm nil)` under `(defttag nil)` (0 leaks in `fuzz_acl2s_deep.py`).
2. **`books/centaur/gl/symbolic-arithmetic` & `eval-g-base` differential**: 30 randomized + edge-case concrete-vs-symbolic evaluations (`+`, `-`, `*`, `logand`, `logior`, `logxor`, `ash`, `truncate`, `rem`, 0-bit `bfr-integer-length-s`, `bfr-logapp-nss`, `eval-g-base` `g-ite`) produced `0` mismatches on both SBCL 2.6.10 and CCL 1.14.
3. **`books/clause-processors/*` & `centaur/misc/*`**: 54 malformed-hint and false-goal tests across `equality`, `generalize`, `replace-equalities`, `autohide`, `remove-hyp`, `null-fail-hints`, and `collect-like-terms` produced `0` crashes or unsound proofs on both runtimes.
4. **Other `SMTLink` probes (`smt_defalist_extensionality_nil`, `smt_defattach_cnf_nil`, `smt_lambda_div_zero`)**: Under full ACL2 + Z3 5.4.1 execution in `fuzz_gl_fgl_cp.py`, `w4-defalist-lemma` failed translation/proof in `SMT-trusted-cp`, `w4-defattach-contradiction` failed without proving `NIL`, and `((lambda (z) (/ z)) '0)` returned a counterexample rather than aborting with `Z3Exception` (0 unsound theorems proved).
