# Wave-4 Lane 5: ACL2 Core & Host-Compiler (`SBCL 2.6.10` / `CCL 1.14`) Audit Report

**Lane:** `w4-kimi-core-compilers` (Kimi K3.1-pro rake + manual kernel/codegen verification)  
**Targets Verified Live:**
- ACL2 8.7+ (`git 1d2b39a42`) on SBCL 2.6.10 (`/Users/ember/dev/acl2-fix/head-worktree/saved_acl2`) and CCL 1.14 (`/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2`)
- Clozure CL 1.14 (`darwin-arm64`: `/Users/ember/dev/ccl/darm64cl`; `linux-x86-64`: `hbox` `/home/hbox/ca-x86-ccl/ccl-dl/extracted/ccl/lx86cl64`)
- SBCL 2.6.10 (`darwin-arm64`: `/opt/homebrew/bin/sbcl`)

---

## Executive Summary

| ID | Target & Component | Bug Class / Impact | Severity | Reproducer |
|---|---|---|---|---|
| **W4-KC-1** | ACL2 8.7+ (`float-b.lisp:409-430`) + CCL 1.14 (`lib/numbers.lisp:418-461`, `level-0/l0-float.lisp:385-446`) | Unsound `to-df-of-df-rationalize` / `to-dfp-of-rize` axiom on CCL 1.14 + ANSI CL `(= (float (rationalize f) f) f)` violation -> **1-event, 13-step `(defthm nil-proved nil)` in `:ttag nil` ACL2** | **CRITICAL** (`NIL` proof + CLHS violation) | [w4-kc-acl2-ccl-rize-nil/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-kc-acl2-ccl-rize-nil/run.sh) |
| **W4-KC-2** | CCL 1.14 ARM64 (`arm642.lisp:1883,2641`) | `arm642-vref1` omits `* 4` byte scaling for constant bit index `> 131040` at `(safety 3)` -> **wrong-code (`0` vs `1`) & `:ttag nil` `(defthm nil-proved nil)` in ACL2**; `arm642-vset1` crashes `COMPILE` (`bad regspec: NIL`) at `(safety 0)` | **CRITICAL** (`NIL` proof + `(safety 3)` wrong-code + ICE) | [w4-kc-ccl-arm64-bitvec-const-idx/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-kc-ccl-arm64-bitvec-const-idx/run.sh) |
| **W4-KC-3** | CCL 1.14 x86-64 (`x862.lisp:2093,2116,2136,2148,2159,2172`) | `x862-vref1` double-adds `target-misc-data-offset` (`-5 + -5 = -10`) for large constant indices at `(safety 3)` -> unaligned cross-element read (`#xFF00991122334455` vs `#xAABBCCDDEEFF0099`) & bogus `fulltag-misc` pointer tag in GC node register | **HIGH** (`(safety 3)` wrong-code + GC hazard) | [w4-kc-ccl-x86-vref1-double-offset/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-kc-ccl-x86-vref1-double-offset/run.sh) |
| **W4-KC-4** | SBCL 2.6.10 ARM64 (`ir1opt.lisp:3799-3809`, `arm64/values.lisp:151-173`) | `(values-list (reverse x))` in single-value or for-effect context at `(safety 3)` compiles full call to undefined `SB-C::REVERSE-VALUES-LIST` (`UNDEFINED-FUNCTION`) | **HIGH** (`(safety 3)` runtime crash) | [w4-kc-sbcl-arm64-reverse-values-list/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-kc-sbcl-arm64-reverse-values-list/run.sh) |
| **W4-KC-5** | ACL2 8.7+ (`apply.lisp:1405-1457,2046-2059`) | `badge-table-guard1` drops unprovable `NATP-MEASURE-OF-fn` obligation on the floor, installing `warrantp=T` in `:ttag nil` ACL2 for transfinite-measure `G2` functions | **HIGH** (kernel invariant bypass) | [w4-kc-acl2-warrant-g2-bypass/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-kc-acl2-warrant-g2-bypass/run.sh) |
| **W4-KC-6** | ACL2(p) 8.7+ (`parallel-raw.lisp:1199-1200,1276-1286,721-725` vs `parallel.lisp:570,876`) | Zero-arg `(pand)` evaluates to `NIL` in raw Lisp vs `T` in ACL2 logic; `spec-mv-let` leaks/hijacks `the-very-obscure-feature` (mismatched spelling `the-very-obscure-future` in `parallel.lisp:876`); `remove-thread-array-from-work-queue-rec` decrements sibling budget on unrelated queue entries | **HIGH** (logic-vs-raw mismatch & hygiene/queue bugs) | [w4-kc-acl2p-parallel-raw-bugs/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-kc-acl2p-parallel-raw-bugs/run.sh) |
| **W4-KC-7** | SBCL 2.6.10 (`array-tran.lisp:2354-2364`) | `transform-%with-array-data/mumble` on simple multidimensional arrays silently replaces `start` with constant `0` in both `(safety 3)` bounds-checked and unchecked paths | **MEDIUM** (wrong-code in internal `sb-kernel:with-array-data`) | [w4-kc-sbcl-with-array-data-start/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-kc-sbcl-with-array-data-start/run.sh) |

---

## Detailed Findings & Root-Cause Analyses

### W4-KC-1: ACL2 `to-df-of-df-rationalize` / `to-dfp-of-rize` Unsound Axiom on CCL 1.14 + CCL `RATIONALIZE`/`FLOAT` Round-Trip Violation

- **Sources:**
  - `/Users/ember/dev/acl2-fix/head-worktree/float-b.lisp:409-430` (`to-df-of-df-rationalize`, `to-dfp-of-rize`), `float-a.lisp:544-586`
  - `/Users/ember/dev/ccl/lib/numbers.lisp:418-461` (`rationalize`)
  - `/Users/ember/dev/ccl/level-0/l0-float.lisp:385-446` (`%double-float` on `ratio`)
- **Root Cause:**
  1. For IEEE-754 double `f = 2.2804169364638254D-18` (`0x1.5087b74fd37e8p-59`), `(rationalize f)` returns `r = 1/438516301124596164`. Although `r` lies strictly below the IEEE midpoint to `0x1.5087b74fd37e9p-59`, CCL 1.14's ratio-to-double-float conversion (`%double-float` -> `float-rat-neg-exp`) rounds `r` UP to `2.2804169364638257D-18` (`0x1.5087b74fd37e9p-59`), violating CLHS `(= (float (rationalize f) f) f)` at `(safety 3)` on both `darwin-arm64` and `x86-64-linux`.
  2. In `float-a.lisp:544-586`, ACL2 disables `to-df-monotonicity` (`#+to-df-monotonicity`) because of CCL's inaccurate ratio-to-float rounding, but leaves `to-df-of-df-rationalize` (`float-b.lisp:409-414`) and `to-dfp-of-rize` (`float-b.lisp:426-430`) unconditionally enabled.
- **Impact:** A single `defthm` event with `:ttag nil` proves `NIL` in `0.00s` (`13` prover steps) in `/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2`:
  ```lisp
  (defthm nil-proved
    nil
    :rule-classes nil
    :hints (("Goal" :use ((:instance to-dfp-of-rize
                                     (x 740037605959421/324518553658426726783156020576256))))))
  ```

### W4-KC-2: CCL 1.14 ARM64 `arm642-vref1` / `arm642-vset1` 1-Bit Vector Constant-Index Miscompilation

- **Sources:** `/Users/ember/dev/ccl/compiler/ARM64/arm642.lisp:1883` (`arm642-vref1`) and `:2641` (`arm642-vset1`).
- **Root Cause:** For constant bit indices `> target-max-1-bit-constant-index` (`131040`, i.e., `>= 131072`), `arm642-vref1` computes the word byte offset as `(+ (arch::target-misc-data-offset arch) (ash index-known-fixnum -5))` instead of `(ash (ash index-known-fixnum -5) 2)` — omitting the 4-byte word scaling! It therefore loads from 1/4 the intended byte offset (unaligned when `(ash idx -5)` is odd, e.g., `131105`) even at `(optimize (speed 1) (safety 3))`. In `arm642-vset1` (`:2641`), `unscaled-idx` is `NIL` when `safe` is `NIL` (`(safety 0)`), crashing `COMPILE` with `Error: bad regspec: NIL`.
- **Impact:** Silent wrong-code in CCL 1.14 ARM64 `(safety 3)` (`(sbit bv 131105)` reads bit `32777` instead of `131105`), `COMPILE` ICE at `(safety 0)`, and a pure `:ttag nil` `(defthm nil-proved nil)` in ACL2 8.7+ (`ccl-worktree/saved_acl2`) via an inline `(array bit (200000))` stobj.

### W4-KC-3: CCL 1.14 x86-64 `x862-vref1` Double `misc-data-offset` (`-5 + -5 = -10`)

- **Sources:** `/Users/ember/dev/ccl/compiler/X86/x862.lisp:2093, 2116, 2136, 2148, 2159, 2172` and `X8664/x8664-vinsns.lisp:67-175`.
- **Root Cause:** The x86-64 `misc-ref-*` vinsns already encode `x8664::misc-data-offset` (`-5`) in the memory displacement, yet `x862-vref1` adds `(arch::target-misc-data-offset arch)` (`-5`) a second time into `unscaled-idx` when `index-known-fixnum` exceeds the inline constant bound (e.g. `#x10000000` on `(unsigned-byte 64)` vectors).
- **Impact:** At `(safety 3)` on `lx86cl64`, `(aref arr #x10000000)` loads 5 bytes early across element boundaries (`#xFF00991122334455` instead of `#xAABBCCDDEEFF0099`) and places `#x7FFFFFFB` (`fulltag-misc = 3`) in GC-traced `:lisp` node register `arg_z`.

### W4-KC-4: SBCL 2.6.10 ARM64 `values-list` Transform Emits Call to Undefined `SB-C::REVERSE-VALUES-LIST`

- **Sources:** `src/compiler/ir1opt.lisp:3799-3809` (`deftransform values-list`) and `src/compiler/arm64/values.lisp:151-173`.
- **Root Cause:** At `(safety 3)`, single-value or for-effect `(values-list (reverse x))` skips clause 1 (`(< safety 3)`) and matches clause 2 (`(vop-existsp :named reverse-values-list)`, true on ARM64), rewriting to `(sb-c::reverse-values-list list (length (the list list)))`. Because `sb-c::reverse-values-list` only has an unknown-values IR2 translation and no Lisp function definition, non-unknown-values contexts compile a full call to the undefined symbol, signaling `UNDEFINED-FUNCTION` at runtime. (Additionally, `arm64/values.lisp:155` omits `:from (:argument 1)` on `:results (start ...)`.)

### W4-KC-5: ACL2 `badge-table-guard1` `G2` Warrant Bypass

- **Sources:** `/Users/ember/dev/acl2-fix/head-worktree/apply.lisp:1405-1457, 2046-2059`.
- **Root Cause:** `chk-acceptable-defwarrant1` returns `(mv nil events)` where `events` contains the unproved `(defthm NATP-MEASURE-OF-fn (natp m))` obligation for `G2` functions justified with `o<` and non-`natp` measures. `badge-table-guard1` (`apply.lisp:2046-2058`) checks only `erp` and `(eq val t)`, silently discarding `events` and admitting `warrantp=T` into `badge-table` in `:ttag nil` ACL2 even when `(natp m)` is refutable (e.g. `omega^omega + (acl2-count x)`).

### W4-KC-6: ACL2(p) `parallel-raw.lisp` vs `parallel.lisp` Discrepancies (Kimi Leads)

- **Sources:** `/Users/ember/dev/acl2-fix/head-worktree/parallel-raw.lisp:1199-1200, 1276-1286, 721-725` vs `parallel.lisp:570, 876`.
- **Root Cause & Impact:**
  - **6a:** Raw `(pand)` expands to `(if nil t nil)` (`NIL`) whereas logical `(pand)` equals `T`.
  - **6b:** `spec-mv-let` in `parallel-raw.lisp:1276` binds unhygienic `the-very-obscure-feature`, while `parallel.lisp:876` checks `the-very-obscure-future` (typo!), allowing user variables named `the-very-obscure-feature` to leak raw `MT-FUTURE` structs or hijack inner `future-read` results (`99` vs `10`).
  - **6c:** `remove-thread-array-from-work-queue-rec` (`parallel-raw.lisp:721-725`) decrements `array-positions-left` on non-matching queue entries, stranding later siblings.

### W4-KC-7: SBCL 2.6.10 `%with-array-data` Drops `START` on Simple Multidimensional Arrays (Kimi Lead)

- **Source:** `src/compiler/array-tran.lisp:2354-2364` (`transform-%with-array-data/mumble`).
- **Root Cause:** For simple multidimensional arrays, both the `(safety 3)` bounds-checked branch (`:2361`) and unchecked branch (`:2364`) return `(values data 0 real-end 0)`, replacing the user's `start` argument with constant `0`.

---

## Verification Ledger

All 7 reproducers were executed end-to-end on the target binaries with `chmod +x` and exited `0`:
- [w4-kc-acl2-ccl-rize-nil/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-kc-acl2-ccl-rize-nil/run.sh) — `PASS` (`0`)
- [w4-kc-ccl-arm64-bitvec-const-idx/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-kc-ccl-arm64-bitvec-const-idx/run.sh) — `PASS` (`0`)
- [w4-kc-ccl-x86-vref1-double-offset/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-kc-ccl-x86-vref1-double-offset/run.sh) — `PASS` (`0`)
- [w4-kc-sbcl-arm64-reverse-values-list/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-kc-sbcl-arm64-reverse-values-list/run.sh) — `PASS` (`0`)
- [w4-kc-acl2-warrant-g2-bypass/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-kc-acl2-warrant-g2-bypass/run.sh) — `PASS` (`0`)
- [w4-kc-acl2p-parallel-raw-bugs/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-kc-acl2p-parallel-raw-bugs/run.sh) — `PASS` (`0`)
- [w4-kc-sbcl-with-array-data-start/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-kc-sbcl-with-array-data-start/run.sh) — `PASS` (`0`)
