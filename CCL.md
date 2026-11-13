# Clozure CL (CCL) findings — darwin arm64

Two bugs in Clozure CL 1.14, `darwinarm64` (Apple Silicon), found while using CCL as a
host for the ACL2 theorem prover. Neither is an ACL2 bug: both reproduce in plain CCL.

- CCL version: `Clozure Common Lisp Version 1.14 darwinarm64`
- Source checkout used for the root cause: Clozure/ccl at commit `23c9edcf`
- The matching ACL2-level symptoms are in `ACL2-BUG-REPORT.md` (C1, C2); this file is
  the plain-CCL report.

**How Clozure tracks bugs.** The active tracker is GitHub issues at
<https://github.com/Clozure/ccl/issues>. There is also the historical
`openmcl-devel` mailing list (<https://lists.clozure.com/mailman/listinfo/openmcl-devel>).
GitHub issues is the right place for both of these; each has a self-contained
reproducer below.

---

## CCL-1 — restarted `save-application` image livelocks on an inline store into a purified ivector

Reproducer: `repros/ccl-saved-image-write/` (`run.sh` runs plain CCL then ACL2;
`NOTES.md` has the full trigger matrix). Confirmed by re-running `run.sh` (≈40 s).

### Symptom
In an image produced by `save-application` (default `:purify t`) and then restarted, a
compiled **inline** store (`setf aref` / `(setf sbit)` / specialised-vector write)
into a vector that existed *before* the save **never returns** — the process spins at
100% CPU forever — when the storing instruction and the element being written fall in
the same 16 KB page.

### Minimal shape
1. Before saving: create a specialised vector (`(simple-array (unsigned-byte 8) (n))`,
   or `bit`, `u16/u32/u64`, `s8/…`, `single-float`, `double-float`) and compile a
   function that stores into it with the type declared (so the store is inlined).
2. `save-application` and restart.
3. Call the function. If the store instruction and the target element landed in the
   same read-only page (layout-dependent, but reliably reproducible — the repro forces
   it), the call hangs.

Element at index 1500 (same page as the code) hangs; index 1800 (next page) returns the
correct value, same function, same 100000-byte vector. A function compiled *after*
restart, or a vector made *after* restart, never hangs. `(array t)` arrays, conses,
structs and hash tables are never affected (they stay in the dynamic heap).

### Root cause (high confidence)
- `purify` copies every ivector except macptrs into the read-only area, next to code
  vectors (`lisp-kernel/arm64-gc.c`, the ivector-forwarding loop around lines
  1991–2020), and that area is mapped read + execute.
- Apple Silicon forbids simultaneously writable+executable pages, so the port's fault
  handler makes a page read+write on a write fault and read+execute on an instruction
  fetch fault (`lisp-kernel/arm64-darwin-mach.c` ~lines 60–98, wired at ~537;
  `arm64-exceptions.c` ~1222–1301; `memory.c` ~431–433).
- When the store instruction lives in the very page it writes, the two fix-ups undo
  each other on every retry — an infinite W^X protection flip at one PC.
- Verified directly: `CCL_DEBUG_WX=1` logs the alternating RW/RX fix-ups at a single
  `pc`, and `sample` shows the faulting thread in `mprotect`. The page-equality
  prediction matched every cell of a 90-cell test matrix.
- Inferred (not built): other ports avoid this because they restore RWX; the
  darwinarm64 port cannot, so the same-page case has no stable state.

### Scope / severity
- **Hang only. No silent wrong value was observed**: all returning cells read back
  correctly, before and after `(gc)`, and a full-vector sweep gave correct counts.
- Two things that *look* like a lost write but are not silent: a `read(2)` into a
  purified vector returns `EFAULT` and writes nothing (an error return, but code that
  ignores it sees stale data); and a `SIGTERM` to the spinning process can abort an
  in-progress update so a later read shows the old value.
- Side observation, not traced: with `:purify nil`, a function compiled before the save
  crashes the restarted image (SIGILL/SIGSEGV at a low address) — its code is in the
  JIT heap, which is unmapped after restart. ACL2 does not use `:purify nil`.

### Reproduce
```
repros/ccl-saved-image-write/run.sh        # plain CCL + ACL2, both shown; needs darm64cl + a CCL-hosted ACL2
```

---

## CCL-2 — `(ash 1 k)` for a huge fixnum `k` returns a malformed integer instead of signalling

Reproducer: `derived-types/repros/ccl-ash-near-fixnum-limit/` (`run.sh [ccl|sbcl]`).
Confirmed by re-running on both hosts.

### Symptom
For a shift count `k` within a few bits of `2^60`, `(ash 1 k)` returns a corrupt object
rather than signalling an error. The result reports a **negative** `integer-length`:
```
;; k = 1152921504606846975  (= 2^60 - 1)
(integer-length (ash 1 k))   ; CCL  => -1152921504606846976   (= -(2^60))   ** wrong **
(integer-length (ash 1 k))   ; SBCL =>  error "can't represent result of left shift"  (correct)
```
`integer-length` is always non-negative, so the CCL value is impossible. The true
result (`2^(2^60-1)`, a number with ~2^60 bits ≈ 144 PB) obviously cannot be
represented; the correct behaviour is to signal, as SBCL does. Slightly larger `k`
kills the process.

The wrong value is the same on both the interpreted and the compiled route, i.e. it is
in CCL's `ash` / bignum machinery, not in any optimization: the internal bit-count
arithmetic for the result size appears to overflow near `2^60` and wrap to a negative
fixnum instead of raising an allocation/size error.

### Why it matters beyond a crash
Because a host-level wrong value for a total CL function becomes a wrong value *inside
ACL2's logic* on CCL (ACL2 evaluates `ash`/`integer-length` with the host), an evident
truth such as `(<= 0 (integer-length x))` is refuted by evaluation on CCL. A prior
exploration left an ACL2 book that drives this to a proof of `NIL`; it is set aside
under `.../prior-agent/` pending a careful check that the `NIL` is genuine and not an
artifact of the near-crash state, so treat the plain-CCL wrong value above as the solid
claim.

### Reproduce
```
derived-types/repros/ccl-ash-near-fixnum-limit/run.sh ccl    # => -1152921504606846976
derived-types/repros/ccl-ash-near-fixnum-limit/run.sh sbcl   # => error (correct)
```
A pure-CL form with no ACL2 (for the Clozure issue):
```lisp
(integer-length (ash 1 (1- (expt 2 60))))   ; CCL 1.14 arm64: negative; should signal
```
