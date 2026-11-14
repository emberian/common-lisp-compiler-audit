# Wave-4 Lane 5: `claude-kimi` (`Kimi K3.1-pro`) Rake Summary

**Harness:** [rake_kimi.py](file:///Users/ember/dev/compiler-audit/hunts/w4-kimi-core/rake_kimi.py)  
**Invocation Protocol:** Pre-sliced ~1,150–1,450-line annotated chunks staged in `/tmp/w4-core-chunks/`, invoked from empty `/tmp` scratch directories with `--allowedTools "Read,Grep,Glob"`, `--strict-mcp-config --mcp-config '{"mcpServers":{}}'`, `< /dev/null`, and 360s timeout.

## Slice Outcomes & Lead Triage

| Slice | Target Files & Line Ranges | Kimi Outcome | Leads Produced | Verification Outcome |
|---|---|---|---|---|
| `01-acl2-tau-bounders-rules` | `tau.lisp:1600-3050, 9900-11300` | `rc=0` (341.3s) | Clean (no defects reported in sliced ranges) | N/A |
| `02-acl2-bdd-nonlinear` | `bdd.lisp:1840-3235`, `non-linear.lisp:55-986` | `rc=0` (293.3s, 53 lines) | `non-linear.lisp:143-144,104-106,432-433` (`invert-var`/`varify!`/`inverse-vars-p`) | **TRUE POSITIVE (`W4-KC-5b`)** — `eql` on `''-1` + `varify!` strips scalar factor `2` + `inverse-vars-p` unconditionally returns `T` for `EXPT` |
| `03-acl2-linear-ab` | `linear-a.lisp`, `linear-b.lisp` | `rc=124` (360s) | Timed out | Manual check clean on target slices |
| `04-acl2-apply-float` | `apply.lisp`, `float-a.lisp` | `rc=124` (360s) | Timed out | Manual audit discovered **`W4-KC-1`** (`float-b.lisp:409-430` + CCL `RATIONALIZE`/`FLOAT`) & **`W4-KC-5a`** (`apply.lisp:2046-2059, 1430-1457` `badge-table-guard1` bypass) |
| `05-acl2-par-iface` | `parallel-raw.lisp:1-1435`, `interface-raw.lisp:1120-2350` | `rc=0` (330.6s, 123 lines) | 4 leads in `parallel-raw.lisp` (`pand`, `spec-mv-let`, `remove-thread-array-from-work-queue-rec`, `eval-and-save-result`) | **4 TRUE POSITIVES (`W4-KC-6`)** — verified live against `saved_acl2` (`:acl2-par` vs `:logic`) |
| `06-ccl-front-opt` | `nx1.lisp`, `optimizers.lisp` | `rc=124` (360s) | Timed out | Covered by sibling `w4-fuzz-compilers` |
| `07-ccl-arm64-x86-p2` | `arm642.lisp`, `x862.lisp` | `rc=124` (360s) | Timed out | Manual audit discovered **`W4-KC-2`** (`arm642.lisp:1883,2641`) & **`W4-KC-3`** (`x862.lisp:2093..2172`) |
| `08-sbcl-tran-arm64` | `float-tran.lisp`, `arm64/float.lisp` | `rc=124` (360s) | Timed out | Manual audit discovered **`W4-KC-4`** (`ir1opt.lisp:3799-3809` + `arm64/values.lisp:155`) |
| `09-sbcl-array-modarith` | `array-tran.lisp:1800-2400`, `modarith.lisp:350-950` | `rc=0` (346.5s, 113 lines) | 4 leads (1 `array-tran`, 3 `modarith`) | **1 TRUE POSITIVE (`W4-KC-7`)**: `array-tran.lisp:2354-2364` drops `start` on simple 2D `%with-array-data`; **3 FALSE POSITIVES** (`modarith.lisp` backquote uses lambda-param `count`, not let-bound `count`) |
