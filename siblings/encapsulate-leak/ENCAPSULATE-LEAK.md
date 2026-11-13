# Encapsulate local-information leak audit

Soundness class: information computed during an `encapsulate`'s first (local)
pass that must NOT survive into the exported second-pass world, but does, so an
obligation unprovable from the exported signature alone becomes provable, ending
in a proof of `NIL`.

Environment: ACL2 8.7+ development snapshot, Git `1d2b39a424`, hosts SBCL 2.6.10
and CCL 1.14 (darwin arm64), images `~/dev/acl2-fix/{head,ccl}-worktree/saved_acl2`.
Every result below was produced by `lisp-run.sh` in a fresh image on BOTH hosts.

## Enumeration method and count

The enabling fact: `encapsulate-pass-2` calls `process-embedded-events` with
`skip-proofsp = 'include-book` (`other-events.lisp:6275-6278`, arg 3 of
`process-embedded-events`, `:5606`). So in pass 2 **every proof obligation is
skipped** — the non-local events are only re-*asserted*, not re-*proved*. A fact
about an exported event therefore reaches the trusted world in one of three ways:

1. **re-derived** — recomputed from the pass-2 world (no pass-1 dependency); sound
   by construction.
2. **re-asserted as a logical formula** — a `defthm`/definitional axiom; soundness
   is handled by the constraint/conservativity machinery (`encapsulate-constraint`
   → [Front]/[Back] rules, `get-subversives`, the constraint-lst-etc).
3. **re-asserted as a meta/"trust" assertion** — "this function is guard-verified"
   or "this function terminates". These are NOT logical formulas, so the constraint
   machinery does not cover them; each needs its own explicit dependency check.

I enumerated the channels by reading, for a non-locally introduced `defun`/event,
every property ACL2 stores and classifying it into 1/2/3 (sources:
`defuns.lisp` store of `guard`, `split-types-term`, `justification`,
`type-prescriptions`, `symbol-class`; `other-events.lisp` `encapsulate-constraint`,
`bogus-exported-compliants`, `bogus-exported-measures`, `putprop-constraints`;
`history-management.lisp` `guard-clauses-for-fn1`; `defuns.lisp`
`subversive-cliquep`). The trust-assertion channels (class 3) are the only ones
that need a bespoke "bogus-exported"-style check, and there are exactly **two** of
them: guard verification and termination. **10 channels enumerated total.**

| # | Channel (stored exported fact) | Class | Dependency check | Result | Both-host outcome |
|---|---|---|---|---|---|
| 1 | Definitional axiom (`unnormalized-body`/`def-bodies`) | 2 logical | `encapsulate-constraint` [Front]/[Back] + `get-subversives` | sound (by design) | n/a |
| 2 | **Termination** (`:termination-theorem`/`justification`) | 3 trust | `subversive-cliquep` (tests + measured call args) **and** `bogus-exported-measures` (measure/mp/rel) | **both layers hold** — correctly rejected | SBCL+CCL agree |
| 3 | **Guard verification** (`:guard-theorem`, common-lisp-compliant) | 3 trust | `bogus-exported-compliants` (guard + body ancestors only) | **LEAK** — `split-types-term` not inspected | SBCL+CCL: proves NIL |
| 4 | Auto `type-prescription` of a `defun` | 1 recomputed | recomputed in pass-2 ens | sound (local rule does not leak) | SBCL+CCL agree |
| 5 | `defthm`-derived rules (rewrite/linear/fc/congruence/type-presc/elim/wfr) | 2 logical | constraint / conservativity | sound (by design) | n/a |
| 6 | The constraint-lst-etc / constraint alist | — machinery | this IS `encapsulate-constraint` | sound (by design) | n/a |
| 7 | Redundancy decision (exported redundant with a local event) | — | re-checked fresh in pass 2 | does NOT bypass the guard check | SBCL+CCL agree |
| 8 | `defattach` (attachment state) | 3 trust | defattach's own obligations | attach to same-encap sig fn is illegal — no leak | SBCL+CCL agree |
| 9 | `make-event` expansion recorded in pass 1 | conduit | reuses pass-1 expansion, but expanded events hit channels 1-8/10 | not an independent channel | n/a |
| 10 | `defstobj`/`defabsstobj` recognizers / field types | 3 trust | `chk-stobj-field-type-term` etc. | ALREADY REPORTED family (S3/S4/H1) — not re-audited | see ACL2-BUG-REPORT.md |

## Confirmed leak

### split-types guard-theorem leak — channel 3 (`split-types-guard/`)

`bogus-exported-compliants` (`other-events.lisp:6105-6154`) decides whether an
exported, guard-verified function's guard obligation may depend on a local
property by inspecting `(member-eq name exports-with-sig-ancestors)` (body has a
signature-function ancestor) OR `(all-fnnames (guard name nil wrld))` (guard
mentions one). But `guard-clauses-for-fn1` (`history-management.lisp:14266-14286`)
*also* conjoins the `'split-types-term` property into the guard obligation, and
that term is in **neither** of the two inspected places. So with `:split-types t`
a `(type (satisfies g) x)` declaration on a signature function `g` leaves
`(guard f) = 'T` and the body `= x` (both clean) while the exported
`:guard-theorem` of `f` is `(g x)` — a claim `g` has no exported constraint for.

Both hosts, from `split-types-guard/test.lsp`:

```
:F-SYMBOL-CLASS   :COMMON-LISP-COMPLIANT
:GUARD-OF-F       'T
:SPLIT-TYPES-TERM (G X)
:G-CONSTRAINT     (NIL)          ; g has no exported constraint
:GUARD-THEOREM    (G X)          ; <-- leaked
```

Because `g` is a pure signature function with no constraint, functionally
instantiating the leaked `(:guard-theorem f)` with `g := (lambda (x) nil)` has no
proof obligations and yields `((lambda (x) nil) x) = nil`:

```lisp
(defthm nil-proved nil :rule-classes nil
  :hints (("Goal" :use (:functional-instance (:guard-theorem f)
                                              (g (lambda (x) nil))))))
```

`NIL-PROVED` is installed as the theorem `'NIL` on SBCL and CCL, with
`skip-proofs-seen = NIL`, `redef-seen = NIL`, and no trust tag. Control
(`controls/`, probe B): the same shape with `:split-types nil` merges `(satisfies g)`
into the guard, so `(guard f)` mentions `g`, and the encapsulate is correctly
REJECTED ("guard verification may depend on local properties ... not exported").
Both hosts. (This is the already-reported seed defect; confirmed here as the
anchor of the family.)

## Channels found clean (valuable negatives)

- **Termination (channel 2)** is defended by two independent layers, both verified
  to fire:
  - *ruler / measured-call-arg dependence* → `subversive-cliquep`
    (`defuns.lisp:1561-1631`). `termination-ruler/test.lsp`: a recursive `f` whose
    only use of signature `g` is the governing test `(g x)` of a non-decreasing
    self-call is flagged **subversive**, its definitional equation is moved into
    the constraint, and its termination theorem is made local — so
    `(:termination-theorem f)` is unavailable and the NIL proof FAILS. Both hosts.
  - *measure/mp/rel dependence* → `bogus-exported-measures`
    (`other-events.lisp:6156-6184`). `misc-channels/test2.lsp` probe M: a
    non-subversive recursion whose measure mentions `g3` is correctly REJECTED.
    Both hosts.
  Note `bogus-exported-measures` alone does NOT inspect the body (unlike
  `bogus-exported-compliants`); the body/ruler case is covered only by
  subversive detection, so the two checks are complementary, not redundant.
- **Guard controls (channel 3), `controls/`:** `:split-types nil` (probe B),
  `(the (satisfies g) ...)` in the body (probe E, body is sig-ancestral), and a
  redundant local-then-exported `defun` (probe D) are all correctly REJECTED;
  redundancy does not bypass the guard check. Both hosts.
- **Auto type-prescription (channel 4), `misc-channels/test2.lsp` probe T2:** a
  local `:type-prescription` rule for `g2` does NOT strengthen the exported
  `fT`'s stored `type-prescriptions` (recomputed in the pass-2 ens); `(natp (fT x))`
  is not provable. Both hosts.
- **defattach (channel 8), `misc-channels/test.lsp` probe C:** `(defattach g hh)`
  for a signature function `g` of the same encapsulate is rejected as illegal, so
  no attachment can leak. Both hosts.

## Not tested (batch 1)

- make-event expansions whose recorded value depends on local *state* (channel 9)
  beyond confirming it only conduits to channels 1-8.
- nested/local stobjs beyond the already-reported `satisfies`-in-field family.

(The apply$/quoted-lambda gap, `defchoose`/`defun-sk`, and `defabsstobj` are
resolved in batch 2 below.)

---

# Batch 2: the apply$/quoted-lambda ancestry gap, and defchoose/defun-sk/defabsstobj

## 1. The ancestry walks DO have the gap — but it is unreachable for signature fns

Confirmed in source that all three export-surface checks compute
signature-function dependence with walks that **stop at `(fquotep x)`** and so do
NOT descend into quoted lambda objects:

- `all-fnnames1` (`translate.lisp:4274-4275`): `((variablep x) acc) ((fquotep x) acc)`
  — used by `bogus-exported-compliants` (`(all-fnnames (guard name))`) and by
  `bogus-exported-measures` (`all-fnnames` of measure/mp/rel), and by
  `subversivep`'s test walk (`all-fnnames-lst`) and `selected-all-fnnames-lst`.
- `instantiable-ffn-symbs` (`history-management.lisp:11531`): `((fquotep term) ans)`
  — the basis of `immediate-instantiable-ancestors` → `constrained-functions`,
  which computes `exports-with-sig-ancestors`.

The descending variant **`all-fnnames!`** (`translate.lisp:4933`, `where-flg`
`:both`/`:inside`, which unquotes `:FN` slots and recurs into well-formed quoted
lambda bodies) **exists but none of the three checks call it.** So a signature
function hidden inside a quoted lambda would be invisible to the export checks.

**But the gap is unreachable for the leak**, blocked upstream on BOTH hosts:

- A lambda object body (or guard) applied via `apply$`/`loop$`/`lambda$` must be
  *fully badged*. `lambda-ancestry/probe1.lsp` (probe A) and `probe4.lsp` (probe E):
  with signature `g`, `(apply$ '(lambda (y) (g y)) ...)` and the `:guard (g y)`
  variant are both rejected at translate time — *"the body of a LAMBDA object …
  should be fully badged but G is used in (G Y) and has no badge"* (both hosts).
- A constraint-free signature function can never acquire a badge: ACL2's own
  source forbids it by design — `apply.lisp:2563` *"Do not extend the functionality
  of defwarrant by making constrained functions warrantable!"* and `apply.lisp:2674`
  the same for `defbadge`. A signature in the encapsulate declaring `:badge` is
  also rejected as illegal (`probe2.lsp`, probe D2).

A quoted lambda is therefore either well-formed (then its functions are badged, so
no *constraint-free* signature function can be in it — nothing to leak) or not
well-formed (then it is dead data generating no obligation). Either way the walk
gap cannot carry a signature-function dependence. The gap is a latent
code-hygiene issue (the checks should use `all-fnnames!` for robustness), not a
reachable soundness hole, and the termination layer is NOT bypassed this way.

## 2. defchoose / defun-sk — sound (`lambda-ancestry/probe4.lsp`)

Both fold a signature-function dependence into the logical constraint, so nothing
leaks (both hosts):
- `defchoose fch w (x) (and (g x) (equal w x))` with local `g ≡ nil`: `(g x)` is
  NOT provable afterward — the choice axiom gives no usable fact about `g`.
- `defun-sk all-g2 () (forall x (g2 x))`: `g2`'s constraint is extended with
  `(implies (not (g2 x)) (not (all-g2)))` — the dependence is captured, not leaked.

## 3. defabsstobj — the coordinator's hypothesis, realized and ALREADY FIXED (ISSUE B18)

This is the quoted-lambda hypothesis realized through a different unchecked slot:
the **`:EXEC` function** of a `defabsstobj` export. `defabsstobj-fn1`
(`other-events.lisp:24984-25016`) does not prove the `{correspondence}`/`{preserved}`/
`{guard-thm}` lemmas; it only checks they already exist, and historically skipped
that check whenever `ld-skip-proofsp = include-book` — which is also encapsulate
pass 2. A signature function used as an export's `:EXEC`, with the supporting
lemmas made `local`, was thus installed in pass 2 without them; a later
`(defattach h …)` made raw execution of the export diverge from its `:LOGIC`
function, provable to `NIL` via a metafunction. `bogus-exported-compliants` only
inspects logical bodies/guards and the stobj-attachment restrictions cover only
ancestors of the recognizer and correspondence function — not the `:EXEC` slot.

The ACL2 developers found this (ISSUE B18; two reproducers in
`books/system/tests/defabsstobj-pass2-constrained-{exec,updater}.lisp`, produced by
Claude, passed along by Eric Smith) and **fixed it before ACL2 Version 8.8**. The
fix (`other-events.lisp:24194-24198`) uses `:skip-missing-chk` only for a genuine
`include-book` or when *not* inside a non-trivial encapsulate; inside encapsulate
pass 2 the missing-events check is enforced — *"we must check for missing events
inside a non-trivial encapsulate, even in pass 2."*

`defabsstobj-pass2/test.lsp` runs the B18-a encapsulate verbatim (minus the absent
`must-fail` book) in this tree: pass 2 correctly REJECTS it ("The following events
must be admitted before the given defabsstobj event"), `erp = T`, and none of
`stp`/`fld`/`h` are installed — on **both** SBCL and CCL. So this channel is a
real member of the family but is already closed here; it is **distinct from the
batch-1 split-types leak** (different slot: `:EXEC`/defabsstobj vs
`split-types-term`/guard-theorem, and already fixed).

## Still untested after batch 2

- Whether a *badged, defined* (non-constrained) function routed through a quoted
  lambda can still defeat a check via the `all-fnnames!` gap in some other export
  obligation — the gap is real; only the *constraint-free signature* exploit is
  ruled out.
- `defabsstobj` leaks through slots other than `:EXEC` after the B18 fix
  (e.g. nested abstract stobjs), and the attachment-restriction coverage.
- make-event whose expansion depends on local *state* (batch-1 channel 9).
