# x86-64 SBCL cross-architecture audit — one confirmed SBCL soundness bug

This file records the x86-64 leg of the ACL2 host-compiler consistency audit.
All prior work ran on arm64 (Apple Silicon, SBCL 2.6.10 / CCL 1.14); SBCL's
x86-64 backend is a different VOP/codegen path and had not been exercised.

**Two headline results:**

1. **The ACL2 interface is clean on x86-64.** Every confirmed finding (S1-S7,
   R1-R7, H1) behaves on the x86-64 ACL2 image exactly as on arm64; the 8-route
   replay over 330 seeds and 111 single-host stale-artifact scenarios show no
   cross-arch divergence; no new proof of `nil`. The one disposition difference
   (R5) lives in ACL2's own host-independent evaluator and is attributable to
   the ACL2 *version* (release 8.7 vs the arm64 dev snapshot), not the host
   compiler.

2. **The non-integer fuzzer found a real SBCL x86-64 soundness bug** (the first
   confirmed SBCL defect in this audit — `SBCL.md` had been a clean negative).
   At `(speed 3)(safety 0)`, a variable-shift modular `ash` stored as one of
   several `(unsigned-byte 64)` array elements, with only that element read
   back, returns a **wrong value** on **SBCL 2.6.8 x86-64** (correct on 2.2.9
   x86-64 and on 2.6.10 arm64). Reproduced and minimized:
   `repros/sbcl-x86-modular-ash-u64-array/`. Classification: **soundness**.
   **Neither ACL2 image in use is affected** (hbox ACL2 embeds SBCL 2.2.9; the
   Mac ACL2 is SBCL 2.6.10 arm64), so it produces no proof of `nil` in the
   current setup — but it is a latent host-compiler hazard for an ACL2 built on
   the affected SBCL, and exactly the class of bug this audit exists to find.

## Environment (exact)

- **Host**: hbox, `Linux 6.11 x86-64`, i9-12900.
- **SBCL A**: `SBCL 2.2.9.debian` at `/usr/bin/sbcl` (old; used as a version
  differential and as the Lisp the ACL2 image embeds).
- **SBCL B**: `SBCL 2.6.8` at `/home/hbox/sbcl-2.6.8-x86-64-linux/run-sbcl.sh`
  (close to the Mac's 2.6.10; the "live" compiler).
- **ACL2 image**: `/home/hbox/acl2-8.7/saved_acl2` — **ACL2 Version 8.7**
  (release). Its wrapper execs `/usr/bin/sbcl ... --core saved_acl2.core`; the
  core banner is `This is SBCL 2.2.9.debian`. **So the ACL2 replay below
  exercises SBCL 2.2.9's x86-64 compiler, not 2.6.8.**
- **arm64 baseline**: SBCL 2.6.10 / CCL 1.14 on an ACL2 **development snapshot
  based on 8.7, commit `1d2b39a424`** (per `ACL2-BUG-REPORT.md`).

**Confound to keep in mind.** The x86 image is ACL2 *release 8.7*; the arm64
baseline was a *post-8.7 dev snapshot*. A disposition that differs can therefore
be an ACL2-version difference rather than an architecture/host-compiler one.
Findings carried by ACL2's own Lisp source (the robustness `R*` cases, the stale
machinery) are version-sensitive; the soundness findings that depend on the
host compiler's raw code (`S*`, `H1`) are the real cross-arch test. The latter
all matched.

## 1. Cross-architecture replay of the confirmed findings

Each reproducer in `repros/`, `derived-types/repros/`, `primitives/repros/` was
re-run on the x86-64 ACL2 image and its decisive lines compared to the arm64
disposition in `ACL2-BUG-REPORT.md`. Script: `replay-x86.sh` (committed).

| # | finding | arm64 disposition | x86-64 (SBCL 2.2.9) disposition | delta |
|---|---|---|---|---|
| S1 | stale compiled file loaded, no warning | NIL proved, 0 warnings | **NIL proved, 0 warnings** | same |
| S2 | cross-host reader conditional | NIL proved (SBCL↔CCL) | **N/A** — needs a CCL second host; hbox has only SBCL | — |
| S3 | stale `satisfies` type cache | CCL proves NIL; **SBCL rejects** `g-is-nil` | **SBCL rejects** (`contradiction` theorem = `:NONE`, not admitted) | same (SBCL correct) |
| S4 | empty `(and …)` array elt → string stobj | NIL proved, both hosts | **NIL proved** (`CONTRADICTION` admitted) | same |
| S5 | guard-verified `count` eql vs equal | gv=0, nogv=1 | **gv=0, nogv=1** | same |
| S6 | stale `double-float` ftype proclamation | CCL garbage `1.0E-323`; **SBCL correct** | **SBCL correct** — both paths = `2361183241434822606850` | same; **x86 SBCL does NOT retain the stale df ftype, and does not crash** |
| S7 | uncertified top + stale compiled file | NIL proved, `[Uncertified]` warning | **NIL proved**, `[Uncertified]` warning | same |
| R1 | `loop$`+`set-ignore-ok` after include-book | session `(f 1)=6`; include → Implementation error | **same** (session value; 1 impl error after include) | same |
| R2 | `lambda$` sibling aborts certification | `ld (g 7)=7`; certify → Implementation error | **same** (certify fails, not certified) | same |
| R3 | recertified portcullis sub-book | ABORTING from raw Lisp; forms discarded | **same** (1 raw abort; 0 later forms run; no book-hash detail) | same |
| R4 | ground self-call on a cons | HARD ACL2 ERROR in `ASSERT$` | **same** (1 HARD ASSERT$ error) | same |
| R5 | `ev-fncall-rec-logical` `binary-*` arg check | `(#\a 0)`→host TYPE-ERROR; `(0 #\a)`→`0` | **both** `(#\a 0)` **and** `(0 #\a)` → host TYPE-ERROR | **DIFFERS** (see note) |
| R6 | `flush-compress` guard t, raw error on non-symbol | thm proved; `(flush-compress 0)` raw error | **same** (thm proved; raw "not of type SYMBOL") | same |
| R7a | `df` tail `(floor …)` + declared return type | `@TAIL` → raw "not of the declared return type" | **same** (`@CLASS` compliant, `@RAT 2`, `@LET 2`, `@TAIL` → ABORTING from raw Lisp) | same |
| R7b | `loop$` var shadows a `df` formal | `@Y 2 @RAT 2 @LET 3`, then Translate error on `ZDF-LOOP-X` | **same** | same |
| H1 | `defstobj` `(satisfies p)` field | SBCL **admits**; CCL rejects | **SBCL admits** | same (SBCL admits) |

**Headline.** No finding changes its soundness verdict on x86-64. Critically,
the three findings where arm64 SBCL is the *correct* party — S3 (stale type
cache), S6 (stale df ftype), H1 (`satisfies`) — remain correct on the older
x86-64 SBCL 2.2.9. **No new x86-only proof of `NIL` was produced, and no
finding that is a wrong value on one arch is a crash on the other.** The
coordinator's specific question — does x86-64 SBCL retain the stale
double-float ftype (S6) and crash like CCL? — is answered **no**: both the
guard-verified and the logical path return the correct `2361183241434822606850`.

**The one difference — R5 — is not a host-compiler effect.** `binary-*` in
`ev-fncall-rec-logical` (ACL2's `translate.lisp`) is host-independent ACL2 Lisp.
On the x86 image (ACL2 8.7 release) the directly-invoked logical evaluator
raises a host `TYPE-ERROR` for the swapped `(0 #\a)` case too, where the arm64
dev snapshot returned `0`. The differing code is ACL2's version-specific
evaluator, reached only by calling it from raw Lisp (the finding itself notes
"whether a user-level event reaches this path is not established"); it is not an
SBCL x86 codegen divergence. Reported here as an observed version delta, not an
SBCL bug.

## 2. ACL2 routes and stale-artifact machinery on x86-64

### 2a. Route matrix (`routes/run-matrix.sh`, adapted → `routes/run-matrix-x86.sh`)

Each seed emits a book of typed REF/OPT twins and replays the same queries
through 8 routes (session, guard-checking T / :none, memo×2, redo, certified
book fasl, saved image). The REF twin runs under `(set-guard-checking :all)`;
the OPT twin is the guard-verified raw code; a planted `zctl` pair must report
`:DIFF`.

- **Seeds 1–330, N=8** (64 queries/route, ~21k query comparisons/seed-route):
  **every route agreed on every seed (0 `:DIFF`), every control fired `:DIFF`,
  every book certified and loaded its compiled file, every saved image carried
  the right marker.** 0 harness failures. Session-route residues (arch-
  independent `zhash` of the logical value) saved per seed for arm64 comparison.

### 2b. Stale / missing / foreign artifact scenarios (`routes/stale/run.sh head`)

122 scenarios (certify-book + include-book with tampered compiled files,
certificates, mtimes, sub-books, make-events, images). Compared against the
committed arm64 SBCL baseline `results-head.tsv` (saved as
`results-head-arm64.tsv`); x86 output committed as `results-head-x86.tsv`.

- **111 single-host scenarios: identical disposition on x86-64 and arm64**,
  including every mtime-tampering soundness scenario (F10 family:
  `fasl_oldver_*`, `src_body_samelen`, `sub_*`, `syn_*`). The mtime scenarios
  matching is itself a check that the Linux port of the macOS-only
  `touch -A`/relative-time logic in `routes/stale/lib.sh` is faithful.
  (To run on Linux, `routes/stale/lib.sh` was edited **locally, not committed**
  — `ROOT`/`ACL2` repointed to the hbox paths, and an OS-guarded wrapper
  translating macOS `touch -A [±]SS` to GNU `touch -d @<epoch±SS>` — so the
  committed file keeps its native-macOS behaviour untouched.)
- **8 scenarios differ, all cross-host** (require a CCL second host, which hbox
  lacks): `cert_otherhost_nofasl`, `fasl_otherhost`, `me_host`, `mec_host`,
  `rc_host`, `syn_cert_otherhost` → `SETUP-FAILED`; `cert_otherhost_oldfasl`,
  `rc_host_fasl` → degenerate (the cross-host stale condition cannot be built).
  These are harness-environment artifacts, **not** cross-arch deltas.

So ACL2's stale-artifact dispositions are architecture-/SBCL-version-invariant
for every scenario that a single SBCL host can express.

## 3. Non-integer differential SBCL codegen fuzz (secondary)

Per the mid-task steer, raw-integer arithmetic fuzzing was dropped (arm64 had
already cleared 360k Dietz forms + 4.4M primitive tuples with zero divergences).
A **non-integer** differential fuzzer (`fuzz-nonint.lisp`, committed) was built
and run instead. For each randomly generated, fully-typed CL function it
compiles the *same* source twice — `(speed 3)(safety 0)` vs
`(speed 0)(safety 3)(debug 3)` — and compares results on a batch of inputs.

- **Coverage of the grammar**: single/double floats, rationals, fixnum/bignum
  ints, `logand/ior/xor/not`, `ash`, `ldb/dpb/mask-field`, `logcount`,
  `integer-length`, `truncate/floor/ceiling/round/mod/rem` (constant and
  variable divisors), comparisons feeding `if`, `multiple-value-bind`,
  characters, strings, `simple-array`+`aref` (`(unsigned-byte 8/64)`,
  `double-float`, `character`), `coerce`, and safe (boundary-tight, correct by
  construction) `the` declarations.
- **Equality discipline (documented to avoid false float reports)**: floats
  compared **bit-exact** via `double-float-high/low-bits` / `single-float-bits`;
  all other numbers by `eql` (value *and* type); chars/strings/lists by `equal`.
  FP traps are **masked identically on both paths** (`with-float-traps-masked`),
  so NaN/inf *propagate* and are compared rather than one path trapping on an
  instruction-selection difference (`comisd` vs `ucomisd`). Two same-width NaNs
  compare equal (payload is IEEE-unspecified). Float `min`/`max` were removed
  from the grammar because min/max with a NaN operand is unspecified in CL and
  yields only implementation-defined divergence. A finding whose input contains
  a NaN/inf/-0.0 is auto-classified **soft** (implementation-defined); a
  **hard** finding has all-finite inputs and is the real alarm.
- **Oracle self-test**: the comparator was validated to flag planted
  miscompilations (int off-by-one, float off-by-one, ±0.0, char, string, int-vs-
  float type change) and to stay silent on true equalities (`x*2` vs `x+x`) and
  same-NaN. A trailing-`nil` bug that would have made the comparator report
  everything clean was caught and fixed by this self-test.

- **Volume and result on x86-64** (8 workers × 120 s each, 28 inputs/fn):
  - **SBCL 2.6.8**: 446,939 functions compiled-twice (~12.5M evaluations).
    **10 hard value-divergences — all one bug** (the modular-`ash` finding
    below). 0 soft, 0 asym.
  - **SBCL 2.2.9**: 370,536 functions (~10.4M evaluations). **0 hard**, 12 soft
    (NaN/±0.0, IEEE-unspecified), 1 asym.
- **arm64 control**: ~202k functions / 60 s / 6 cores, **0 hard findings**;
  the only soft findings were NaN-vs-±0.0 (IEEE-unspecified). This matches
  `SBCL.md`'s clean arm64 claim and validates the harness.

### FINDING X1 (soundness, SBCL 2.6.8 x86-64) — variable-shift modular `ash` in a multi-element `(unsigned-byte 64)` array

`repros/sbcl-x86-modular-ash-u64-array/` (`run.sh <sbcl>`). Minimal, reproduced
fresh in a clean process on all three Lisps:

```lisp
(defun buggy (v0 v1)
  (declare (optimize (speed 3) (safety 0)) (type integer v0 v1))
  (let ((a (make-array 3 :element-type '(unsigned-byte 64)
             :initial-contents
             (list (logand v1 #xFFFFFFFFFFFFFFFF)
                   (logand (ash v1 (- (logand v0 63) 20)) #xFFFFFFFFFFFFFFFF)
                   (logand v1 #xFFFFFFFFFFFFFFFF)))))
    (aref a 1)))
;; (buggy 64 9223372036854775807)
;;   (speed 3)(safety 0) => 0              on SBCL 2.6.8 x86-64   *** WRONG
;;   (speed 0)(safety 3) => 8796093022207  (= (logand (ash (1- 2^63) -20) 2^64-1))
```

| SBCL | arch | `(buggy 64 (1- 2^63))` |
|---|---|---|
| 2.6.8 | x86-64 | **0 (wrong)** |
| 2.2.9 | x86-64 | 8796093022207 (correct) |
| 2.6.10 | arm64 | 8796093022207 (correct) |

No contract is violated: `v0 v1` are plain integers, every element is masked into
`(unsigned-byte 64)`, the index is in bounds, and the two definitions differ only
in `optimize` policy. Essential conditions, each pinned by reduction: **≥3**
modular array elements (2, or siblings that are literal `0`, are correct); the
read element's `ash` shift must be **variable** (a constant shift is correct);
**only** that element is read (reading all three is correct → dead-store
elimination of the unread sibling stores is implicated); `(ldb (byte 64 0) …)`
triggers it identically to `(logand … 2^64-1)`. Likely area: the modular (mod
2^64) transform of `ASH` interacting with elimination of unread array stores.
**Open**: x86-64 SBCL 2.6.10/current was not on the test host — check whether the
bug persists there before reporting upstream (it may be post-2.6.8-fixed, or
x86-64-specific).

## 4. Coverage

Coverage-directed steering (`coverage/sbcl-cov.lisp`) was **not** re-measured on
x86-64: the mid-task steer refocused the effort from the fuzzing/coverage
direction onto the ACL2 interface, where every real bug in this project has
been. The arm64 reference tables are 1067 transforms / 1024 VOPs
(`coverage/`). The non-integer fuzzer's grammar (section 3) spans the float,
bit-op, division, multiple-value, array, string and coercion transform/VOP
families; the ACL2 replay (section 2) exercises the full `(safety 0)(speed 3)`
compilation path for every generated program. Recounting x86 transform/VOP
tables remains open (see below).

## Honest negatives / not reached

- **No soundness divergence in the ACL2 interface on x86-64.** No new proof of
  `NIL`; no confirmed finding that is sound on one arch and unsound on the
  other; no wrong-value-vs-crash swap. The SBCL-correct-party findings (S3, S6,
  H1) stay correct on SBCL 2.2.9. The one plain-SBCL soundness bug (finding X1)
  is in SBCL 2.6.8 x86-64 and does **not** affect either ACL2 image used here
  (SBCL 2.2.9 / SBCL 2.6.10-arm64), so it yields no proof of `NIL` in this setup.
- **S2 and the CCL-only findings (S3-CCL side, S6-CCL side, C1, C2, H1-CCL
  side)** cannot be exercised on hbox (no CCL). Only the SBCL side was tested.
- **ACL2-version confound** (release 8.7 vs the arm64 dev snapshot) is
  unresolved for the `R*` evaluator findings; R5 differs for this reason.
- **x86 transform/VOP coverage tables** were not recounted (section 4).
- **Cross-arch residue diff**: x86 session-route residues are saved per seed
  (`results-matrix/seed-*.residue`); a byte diff against arm64 residues for the
  same committed `synth.lisp` + seeds was not performed here (needs the arm64
  side regenerated).
