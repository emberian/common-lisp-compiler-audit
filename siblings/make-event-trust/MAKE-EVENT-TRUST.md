# make-event expansion trust: include-time divergence from re-execution

Soundness class under test: the expansion `certify-book` records for a
`make-event` (or the data a certified book carries for it) diverges from what a
faithful re-run in the *including* world would produce, with no check — so a
book installs an event that was never proved, ending in a proof of `NIL`.

Hosts: ACL2 8.7 at `6c0f3448f6`, SBCL 2.6.10 (`head-worktree/saved_acl2`) and
CCL 1.14 (`ccl-worktree/saved_acl2`), darwin arm64. Every finding and control
below was certified and then included in **fresh** sessions on **both** hosts
from the files in this directory (`<dir>/run.sh <image>`; `expected-sbcl.txt`,
`expected-ccl.txt` are the captured outputs).

This is the `make-event`/`:check-expansion` mechanism specifically; the stale /
foreign / reader-conditional artifact class (F10/F12, `routes/stale/`) and the
general certified-world = fresh-`ld` claim (P1/P5) are a different lane and are
not re-derived here.

## Method of enumeration

Read `make-event-fn`, `make-event-fn1`, `make-event-fn2`, `protected-eval`,
`ultimate-expansion`, `get-and-chk-last-make-event-expansion` and the
expansion-alist producer/consumer (`eval-event-lst`, `subst-by-position`,
`include-book-process-embedded-events`) in
`head-worktree/other-events.lisp`, plus `*initial-untouchable-vars*` and
`*protected-system-state-globals*` in `axioms.lisp` / `history-management.lisp`.
Classified every place where the include-time effect of a top-level
`make-event` is **taken from recorded data** instead of **re-derived**, and
whether the equality-of-expansion check is present, absent (by design), or
defeatable.

## Enumeration (count = 3 include-time trust paths + 1 adjacent mechanism)

Let `form` be the make-event body, `E?` its `:expansion?`, `ce` its
`:check-expansion`. During `certify-book`, `ld-skip-proofsp` is not
`'include-book`, so `form` is always evaluated (`protected-eval`, ~34804) and
its real expansion is computed; what is *recorded* for include time is one of:

- **I-A — recorded expansion-alist entry (default: `ce = nil`, no `E?`).**
  certify-book stores the real expansion at this position; `include-book`
  replaces the source `make-event` with it via `subst-by-position`
  (~14053) and re-admits it with proofs skipped. **No re-derivation, no check
  at include — by design.** Sound because the stored event was proved at cert
  time and is self-contained; the include-time environment is *ignored*
  (frozen). Documented behaviour of make-event.

- **I-B — `:expansion?` trusted (`E?` supplied, `ce ≠ t`).** At include,
  `make-event-fn` returns `(cons E? nil)` directly (~34765) — `form` is **never
  re-run and E? is never checked**. Guards: `ld-skip-proofsp = 'include-book`
  and `(not including-uncertified-p)`. Sound **only** because certify-book
  records a real replacement (→ I-A, which overrides E?) whenever the real
  expansion ≠ E?. That recording is gated at ~34937 on state global
  `boot-strap-flg`: when it is non-nil the replacement is **not** stored.
  **Defeatable → finding ME1.**

- **I-C — `:check-expansion t`.** certify-book stores
  `(make-event form :check-expansion <real-expansion>)`. At include the stored
  `:check-expansion` is a cons, so `form` **is re-run** (`protected-eval`) and
  the result is compared for equality against the recorded expansion (~34860,
  ~34866); any divergence is **refused**. Re-derivation + check both present —
  the safe mode. No defeat found.

- **I-D — cert-data (adjacent).** For `defun`/`defthm` inside an expansion,
  certify-book caches type-prescriptions, translated bodies etc. in the
  certificate's cert-data and trusts them at include without re-derivation. A
  distinct mechanism from expansion trust; covered generally by the prior
  lane's P1. Not pursued here.

`boot-strap-flg` is **not** in `*initial-untouchable-vars*` (axioms.lisp
~22930), but it **is** in `*protected-system-state-globals*`
(history-management.lisp ~4183), so a make-event's own `protected-eval` cannot
make a change to it persist to the recording decision. Setting it persistently
requires a top-level state mutation (`progn!` / raw mode), which requires a
**trust tag**. Hence I-B's defeat is trust-tag-gated.

## Results table

| Path | Check at include | Defeat | Result | SBCL | CCL | Warning at include |
|---|---|---|---|---|---|---|
| I-A default (`checkexp-fileread/bdef`) | none (by design) | — | frozen recorded expansion used; include-time env ignored | `*payload*`=CERT_VALUE | same | none for the divergence (`[Compiled file]` only) |
| I-B `:expansion?` + `boot-strap-flg` (`expansion-trust-bsf/book`) | none (E? trusted) | **set `boot-strap-flg` at cert (needs ttag)** | **unproved `(defthm nil-proved nil)` installed; NIL derived** | proves NIL | proves NIL | TTAG NOTE + `[Ttags]` |
| I-B control, ttag but no bsf set (`…/control`) | — | — | real expansion recorded, overrides E?; nil-proved undefined | `:UNDEFINED` | `:UNDEFINED` | TTAG NOTE |
| I-B control, no ttag (`…/control-nottag`) | — | — | same; cannot set boot-strap-flg at all | `:UNDEFINED` | `:UNDEFINED` | none |
| I-C `:check-expansion t` (`checkexp-fileread/bchk`) | re-run + equal check | not found | **refused**: "current MAKE-EVENT expansion differs" | refused | refused | `[Compiled file]`, then Failure |

## Finding ME1 (soundness; proves NIL; trust-tag gated) — `expansion-trust-bsf/`

`book.lisp`:

```lisp
(in-package "ACL2")
(defttag :me-trust)
(progn! (f-put-global 'boot-strap-flg t state))
(make-event (value '(value-triple :benign))
            :expansion? (defthm nil-proved nil :rule-classes nil))
(progn! (f-put-global 'boot-strap-flg nil state))
```

- certify-book succeeds. The make-event's `form` expands to the benign,
  provable `(value-triple :benign)`, so certification is honest. Because
  `boot-strap-flg` is non-nil at the store decision (~34937), the real
  expansion is **not recorded**: `book.cert` contains neither `VALUE-TRIPLE`
  nor `NIL-PROVED` (vs. `control.cert`, which records `VALUE-TRIPLE`).
- At include, the expansion-alist has no entry for this position, so the source
  `make-event` is re-processed, `ld-skip-proofsp = 'include-book`, and the
  `:expansion?` branch (~34765) installs `(defthm nil-proved nil)` **without
  running `form` and without proof**.
- Observed on **both hosts**: `nil-proved` theorem = `'NIL`; `derive-nil` (a
  fresh `(defthm derive-nil nil :hints (("Goal" :use nil-proved)))`) = `'NIL`;
  **`skip-proofs-seen` = NIL** (no record that proofs were skipped). A
  `TTAG NOTE (for included book): Adding ttag :ME-TRUST` and an `ACL2 Warning
  [Ttags]` are printed at include; nothing else flags the unproved event.

Controls (both hosts): removing only `(progn! (f-put-global 'boot-strap-flg t
state))` (`control.lisp`, keeping the ttag; `control-nottag.lisp`, no ttag)
makes certify-book record the real `(value-triple :benign)` expansion, which
overrides `:expansion?` at include, so `nil-proved` is **never defined**
(`:UNDEFINED`). This isolates the `boot-strap-flg` suppression as the sole cause.

Severity / disposition: this is the generalization of seed defect #1 and
confirms its mechanism on both hosts with a self-contained book. It is **gated
by a trust tag** (a `TTAG NOTE` is printed), which per `:DOC defttag` voids
ACL2's soundness guarantee. The sharp point worth a report is how *little* the
ttag is used for: no raw Lisp, no unsound primitive, just one
`(f-put-global 'boot-strap-flg t state)` — `boot-strap-flg` is a **touchable**
state global, and the make-event replacement-recording that makes `:expansion?`
trust sound is suppressed by it. Either making `boot-strap-flg` untouchable, or
not gating the `last-make-event-expansion` store on a user-reachable global,
closes I-B.

## Negative / documented — `checkexp-fileread/`

A make-event whose expansion reads `data.txt`; the file is `CERT_VALUE` at
certify time and `INCLUDE_VALUE` at include time.

- `bdef.lisp` (I-A, default): `include-book` silently installs the frozen
  recorded `(defconst *payload* 'CERT_VALUE)`; `*payload*` = `CERT_VALUE`, the
  include-time file ignored. Diverges from a faithful re-run but is sound (the
  recorded defconst is self-consistent); no divergence warning. Both hosts.
- `bchk.lisp` (I-C, `:check-expansion t`): `include-book` re-runs the form,
  gets `(defconst *payload* 'INCLUDE_VALUE)` ≠ recorded, and **refuses** with
  "The current MAKE-EVENT expansion differs from the expected … expansion".
  Both hosts.

## Paths examined and found clean / not independently defeatable

- **I-B without a ttag.** certify-book omits the make-event's expansion-alist
  entry only when the real expansion already equals `:expansion?` (~34884) *or*
  when `boot-strap-flg` is non-nil (~34937). The first case is sound by
  construction (E? *is* what was proved); the second needs a persistent
  top-level `boot-strap-flg` set, unreachable without `progn!`/raw mode (ttag).
  No third suppression path exists. So I-B is sound for any plain (ttag-free)
  book.
- **I-C comparison.** The include-time check is `equal` on the re-derived vs.
  recorded *event form*; equal forms re-admit to identical logical content, so
  a form that passes the check cannot diverge logically. Not defeated.
- **Nested / `encapsulate` / `progn` / sub-book make-events.** The inner
  expansion is baked into the recorded outer expansion (I-A) or the
  encapsulate's first-pass expansion-alist; they add no new include-time
  `:expansion?`-trust site and inherit I-A/I-B/I-C. Reasoned from source, not
  separately reproduced.

## Not tested

- `:do-proofs` expansions; make-event whose `form` calls `trans-eval`/`ld` with
  side effects; provisional certification (`.pcert`/`:convert-pcert`) paths.
- `set-ld-skip-proofsp 'include-book` during certification as an alternative to
  `boot-strap-flg` (also appears to require escaping skip-proofs tracking, which
  is gated by `:skip-proofs-okp` and recorded); not reproduced.
- I-D cert-data trust (covered generally by the prior lane's P1).
- Whether a non-ttag event macro exists that evaluates arbitrary
  state-mutating code at a book's top level outside `protect-system-state-globals`
  (would make ME1 ttag-free); none found in the macros read, not exhaustively
  searched.
