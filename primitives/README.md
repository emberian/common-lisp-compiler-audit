# Logical definition vs executed code: bounded-exhaustive sweep of ACL2 built-ins

ACL2 commit 1d2b39a424 (Version 8.7), two images: SBCL 2.6.10
(`acl2-fix/head-worktree/saved_acl2`) and CCL 1.14 (`acl2-fix/ccl-worktree/saved_acl2`).
Run of 2026-11-13.

## Result in one paragraph

1132 built-in `:logic` functions were swept over a 30-object universe (30^arity tuples,
arity 0 to 3): 4,464,475 tuples on CCL and 4,429,704 on SBCL. **No tuple produced two
different values**, on any route, on either image. Three defects were found and reproduce
in fresh sessions on both images; all three are errors (robustness), none is a wrong value
(soundness). Logical results agree across the two hosts for every comparable function.

## What is compared

For each function `f` and argument tuple:

| side | how |
|---|---|
| logical | `ev-fncall-rec-logical` with `*ev-shortcut-okp*` nil, `gc-off` t, `safe-mode` nil, `aok` nil, `hard-error-returns-nilp` t, `big-n` 6000: interprets `f`'s unnormalized body, and every callee's body, down to the 31 primitives |
| actual `:none` | `*1*f` with state global `guard-checking-on` = `:none` (every tuple) |
| actual `:prim` | the raw `apply$-prim` dispatch for `f` (only for the apply$ primitives) |
| actual `t` | `*1*f` with `guard-checking-on` = `t` (only when the guard, evaluated logically, holds) |
| actual `raw` | `(apply (symbol-function 'f) args)` (only when the guard holds, `f` is guard-verified, `*1*f` returned a value, and `f` is a function, not a raw macro) |

Raw code is never called on guard-violating arguments. Every single evaluation has a depth
bound (`big-n` 6000, logical side) and a 2 s wall-clock bound (watchdog thread). A function
is abandoned after 40 timeouts or 1800 s and reported `PARTIAL`.

Outcome classes per route: equal values / neither side a value / **value mismatch** /
actual aborted (logic has a value) / logical evaluator had no value. Only a value mismatch
is soundness-relevant.

## Function list (derived from the image)

6546 function symbols in the world (4 are this harness's controls).

| count | reason |
|---|---|
| 1132 | **swept** (22 of arity 0, 548 of arity 1, 410 of arity 2, 152 of arity 3; 25 return `mv`) |
| 4842 | program mode |
| 203 | `state` formal or result |
| 164 | no body: constrained |
| 116 | arity > 3 |
| 34 | `:df` formal or result |
| 31 | no body: primitive (see below) |
| 2 | non-executable (`apply$-equivalence`, `write-user-stobj-alist`) |
| 2 | no fixed output signature (`if`, `read-user-stobj-alist`) |
| 16 | unsafe to call (side effects outside the value): `good-bye-fn sys-call setenv$ break$ sleep gc$-fn gc-verbose-fn set-gc-strategy-fn extend-world retract-world set-bad-lisp-consp-memoize never-memoize-fn set-absstobj-debug-fn print-call-history hons-acons hons-acons!` |

Full list with reasons: `results/<image>/excluded.tsv`. 174 of the swept functions have
separate raw Lisp code in their source (`results/dual-definitions.tsv`, textual scan for
`acl2-loop-only` inside the defun); the other 958 are swept too, which compares the
host-compiled code against the interpreted body.

### Primitives NOT swept, and why

The 31 primitives have no logical body, so there is nothing to interpret:
`acl2-numberp bad-atom<= binary-* binary-+ unary-- unary-/ < car cdr char-code characterp
code-char complex complex-rationalp coerce cons consp denominator equal imagpart integerp
intern-in-package-of-symbol numerator pkg-imports pkg-witness rationalp realpart stringp
symbol-name symbol-package-name symbolp` (plus `if`). `ev-fncall-rec-logical` executes them
with the host's own function when the guard holds and through the `*1*` function (`ec-call`)
otherwise. **Both sides of this sweep therefore share the primitives; a wrong primitive, or
a wrong completion of one, is invisible here.** They need a different oracle (the completion
axioms).

## Universe (30 objects)

`0 1 -1 2 2^29-1 2^29 2^60 2^62 -2^63 2^64 10^40 1/2 -7/3 #c(0 1) #c(1/2 -3) #\a
(code-char 0) (code-char 127) (code-char 255) "" "abc" "<255><space><0>A" nil t :key abc car
(1 2 3) (a b . c) ((a . 1) (b . 2))`. All pass `bad-lisp-objectp`. `#c(1 0)` and `#c(1/2 0)`
read as the rationals 1 and 1/2 (checked in `meta.txt`), so they are not separate objects.

## Totals

| | CCL | SBCL |
|---|---|---|
| functions fully swept / partial | 1131 / 1 | 1125 / 7 |
| tuples evaluated | 4,464,475 | 4,429,704 |
| logical side: value / error / depth-bounded / timed out | 4,367,644 / 39,389 / 57,401 / 41 | 4,327,427 / 41,866 / 60,410 / 1 |
| `*1*` `:none`: compared / equal values / mismatch | 4,407,014 / 4,342,382 / **0** | 4,369,158 / 4,302,074 / **0** |
| raw `apply$-prim`: compared / mismatch | 3,816,283 / **0** | 3,778,426 / **0** |
| `*1*` `t`, guard holds: compared / mismatch | 698,488 / **0** | 698,312 / **0** |
| raw function, guard holds: compared / mismatch | 615,502 / **0** | 615,297 / **0** |
| logical guard vs `*1*` guard check disagree | 0 | 0 |

Per function (domain 30^arity, tuples swept, status, counts, result, both images):
`results/per-function.tsv`. Aggregate: `results/SUMMARY.txt`. Bounded tuples per function:
`results/<image>/bounded.tsv`. Raw records: `results/<image>/divergences.lisp`.

### Not completed

| function | CCL | SBCL | cause |
|---|---|---|---|
| `string-prefixp-1`/3 | 2013 of 27000 | 23522 of 27000 (1800 s cap) | index up to 10^40: logical recursion hits the depth bound, slowly |
| `scan-past-whitespace`/3 | full | 5591 | SBCL: host `char` with index 2^60 does not return in 2 s |
| `member-char-stringp`/3 | full | 20407 | same |
| `decimal-string-to-number`/3 | full | 201 | same |
| `all-dots`/2, `standard-string-p1`/2 | full | 307 each | same |
| `char`/2 | full | 607 | same |

61 (CCL) / 63 (SBCL) functions have depth-bounded tuples, mostly huge counts
(`subseq`, `make-list-ac`, `update-nth`, `resize-list`, `first-n-ac`, `gsym`, `mod-expt`,
`ash`, `expt`, `nthcdr`): 57,401 / 60,410 tuples not compared.

## Controls

Positive (fresh `:logic` functions admitted in the session, then only the executable side
replaced in raw Lisp; ACL2 sources untouched). All reported on both images:

- `psw-ctl-pos-raw`: raw definition wrong at exactly `(1 -1)` -> 1 mismatch on routes `t` and `raw` (and `:none`, since `*1*` calls raw for guard `t`), 899 agree.
- `psw-ctl-pos-guarded`: raw wrong at exactly `2^60` -> 1 mismatch on `t` and `raw`, 0 on `:none`.
- `psw-ctl-pos-star1`: `*1*` wrong at the guard-violating `"abc"` -> 1 mismatch on `:none` plus 1 guard disagreement.

Negative: `psw-ctl-neg` 900 tuples, 0 mismatches; and `nfix`, `len`, `binary-append`
checked against hand-written models independent of ACL2's definitions (30, 30, 900 tuples,
0 mismatches, both sides, both images).

## Divergences and classification

No value mismatch exists. Everything else that was not plain agreement:

### Real defects (reproduce in a fresh session on both images; robustness, not soundness)

1. **`repros/defun-ground-call-assert.lisp`** - a legal `defun` whose measure conjecture
   contains a ground call of the function being admitted with a cons argument, `(f '(3))`,
   is rejected with `HARD ACL2 ERROR in ASSERT$: Assertion failed: (ASSERT$ (AND (STRINGP
   (CAR FN)) (ALISTP (CDR FN))) FN)`. The same definition with `(g 3)` is admitted.
   Cause: the null-body case of `ev-fncall-rec-logical` (translate.lisp, the final
   `ev-fncall-null-body-er` call) passes `(car arg-values)` and `(cadr arg-values)` where
   `fn` and `arg-values` are meant. Error, no wrong value.
2. **`repros/ev-fncall-rec-logical-binary-star.lisp`** - the `BINARY-*` case of
   `ev-fncall-rec-logical` tests only `(acl2-numberp y)`; with a non-number `x` it calls the
   host `*` and gets a host `TYPE-ERROR`, with guard checking off (logical value 0) and on
   (should be a guard violation). `(binary-* 0 #\a)` is handled correctly. Defect in the
   logical evaluator, not in `binary-*` (`*1*` returns 0). Error, no wrong value. In the
   first sweep it hid every tuple of `floor mod rem round truncate ceiling evenp oddp
   power-eval` with a non-number first argument; the final sweep routes exactly that case
   to `*1*binary-*` (`psw-install-workarounds`).
3. **`repros/flush-compress-raw-error.lisp`** - `flush-compress` (guard `t`, logical value
   `nil`, `(thm (equal (flush-compress x) nil))` proves) aborts with a raw Lisp type error
   on any non-symbol: its raw code is `(set-acl2-array-property name nil)`. Same pattern:
   `throw-or-attach-call` and `null-body-er` (guard `t`, raw code `(eval `(defvar
   ,(attachment-symbol fn) nil))`). Logical/raw disagreement of the abort kind: 25 + 780 +
   22,620 tuples. Error, no wrong value.

Transcripts: `repros/transcripts/*.{sbcl,ccl}.out`.

### Host behaviour (hang, not a value; SBCL only; not a separate repro file)

`(nth 2^60 nil)`, `(char "" 2^60)`-style calls whose logical value is immediate but whose
host implementation walks the index: 276 actual-side timeouts on SBCL, 56 on CCL. Measured
in a fresh session: `(nth 536870911 '(1 2 3))` takes 166 ms on SBCL, 0 ms on CCL.

### Expected, documented behaviour

- `abort!`, `p!`: logically `nil`, actually throw to the top level (documented).
- `fmx-cw-fn`, `fmx!-cw-fn` on guard-violating arguments: `hard-error` from `fmt` (894-896
  tuples; the count differs by host because some of them time out printing).
- `fast-alist-fork`, `fast-alist-fork!` with an integer final cdr (a size hint): host type
  error or timeout, 12 tuples; `hons-acons` likewise exhausted a 12 GB heap and is excluded.
- 356 tuples where the guard holds but a callee reached by `ec-call` raises a guard error
  under guard-checking `t` (`ev$-list`, `sum$-ac`, `append$-ac`, ...).

### Artifacts of the probe

- **Package locks (SBCL).** Raw Lisp after `:q` has SBCL's package locks on; inside `(lp)`
  they are off. Nine functions that intern new symbols into `COMMON-LISP` (`add-suffix
  packn-pos gsym make-var-lst the-live-var warrant-name df-events df-events-1
  record-accessor-function-name`) therefore errored on both sides on SBCL and showed
  different logical digests from CCL. Fixed in `sweep.lisp` (`without-package-locks`); the
  nine were re-swept on SBCL (`results/aux/sbcl-pkgunlocked/`) and all nine digests now
  equal CCL's. `results/sbcl/` still holds the locked run for those nine.
- Raw macros (`mv-list`, `return-last`, `wormhole-eval`) called with quoted objects: one
  spurious mismatch in the first sweep; raw macros are no longer called.

### Functions the logical evaluator cannot evaluate (no comparison possible)

36 functions, 2147 tuples at `:none`: the actual side returns a value, the logical side
stops at a callee without an executable body.

- the apply$ family (`apply$`, `apply$-prim`, the 19 `*$`/`*$+`/`*$-ac` loop$ scions,
  `eviscerate-do$-alist`): body is non-exec or reaches a constrained function, and `aok` is nil;
- `char-upcase char-downcase upper-case-p lower-case-p alpha-char-p char-equal string-equal
  string-upcase string-downcase` on non-standard characters: partial-encapsulate
  (`ev-fncall-rec-logical-unknown-constraints`);
- `dfp to-dfp rize to-df?-fn to-df?-args`: constrained `df` functions.

For `apply$-prim`, `rize` and `to-df?-*` the logical side has no value on every tuple.

## Independence of the two sides

Traced on SBCL by wrapping all 3137 wrappable `:logic` functions and `*1*` functions
(`independence-probe.lisp`, `results/aux/probe-sbcl/independence.txt`) plus backtraces.
With `*ev-shortcut-okp*` nil the evaluator never runs the compiled code of a defined
function in place of its body. Compiled ACL2 code that does run during logical evaluation:

- the 31 primitives (host function, or `*1*` via `ec-call`), with their helpers
  (`make-character-list` from `*1*coerce`; `known-package-alist`, `assoc-equal` from raw
  `pkg-witness`);
- evaluator bookkeeping: `fgetprop`, `formals`, `pairlis$`, `stobjs-out`, guard tests
  `character-listp` / `bad-atom`;
- **`global-val`** (254 functions): called by `ev-fncall-rec-logical` itself for
  `(global-val 'attach-nil-lst w)`, because `ev-rec-return-last` evaluates the *second*
  argument of `return-last` with `aok` = t. That argument's value is discarded; the result
  comes from the third argument. It reads the world and does not replace any function body,
  so it does not weaken independence;
- error paths (`throw-raw-ev-fncall`, `hard-error`, `fmt`), which produce no value;
- `wormhole-eval`: `ev-rec` runs raw code (`put-assoc-equal` on the wormhole status);
  the value is `nil` either way (`clear-brr-data-lst`).

70 functions whose symbol is in `COMMON-LISP` could not be wrapped (package lock); for
those the claim rests on reading `ev-rec` / `ev-fncall-rec`, not on the trace.

Limits that follow: (a) primitives are shared, see above; (b) the `:exec` branch of `mbe`
is not interpreted, so the logical side is the `:logic` branch only, which is the intent;
(c) for a function without separate raw code, both sides come from the same source text,
so the sweep tests the host compiler and the `*1*` wrapper, not the definition.

## Rerun

    ./run.sh /path/to/saved_acl2 results/<name> [timeout-seconds] ['(fn1 fn2 ...)']
    ./run-probe.sh /path/to/sbcl/saved_acl2 results/aux/probe-sbcl
    python3 summarize.py results /path/to/acl2/sources

`run.sh` runs the image under `nice -n 15 timeout`, restarts after a function that kills
the image (recorded in `crashed.txt`), writes the image PID to `<out>/image.pid`, and stops
before the next function if `<out>/STOP` exists. A full run takes about 30 min (CCL) to
45 min (SBCL), most of it in `string-prefixp-1`.
