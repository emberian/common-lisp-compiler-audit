# SBCL 2.6.10 (arm64) — Assembler `(SIGNED-BYTE 19)` PC-Relative Literal/Branch Overflow on Recursive Inline Function

- **Status:** **LIVE on SBCL 2.6.10 darwin-arm64** (crashes SBCL's ARM64 assembler back-patcher whenever a compiled code segment exceeds 1 MiB / `262,144` instructions).
- **Reproducer directory:** `repros/recursive-defun-inline-sbcl-arm64/`:
  - **Standalone pure Common Lisp (zero ACL2 dependency, ~2s):** `plain-sbcl.lisp`
  - **ACL2 reproducers:** `recursion-kept.lisp`, `reduced.lisp`, `original.lisp`, `run.sh`
- **Comparison:** Clozure CL 1.14 darwin-arm64 and SBCL 2.6.10 x86-64 compile the same forms cleanly.

## Standalone Plain-SBCL Reproducer (`plain-sbcl.lisp`, Zero ACL2 Dependency)

Run with `/opt/homebrew/bin/sbcl --noinform --non-interactive --load repros/recursive-defun-inline-sbcl-arm64/plain-sbcl.lisp`:

```lisp
(declaim (notinline sink)
         (inline rec-f18))

(defun sink (x) x)

(defun rec-f18 (l acc)
  (if (endp l)
      acc
      (rec-f18 (cdr l)
               (progn
                 (macrolet ((rep ()
                              `(progn ,@(loop repeat 450 collect '(sink acc)))))
                   (rep))
                 acc))))

(defun trigger-rec-f18 (l acc)
  (list (rec-f18 l acc)
        (rec-f18 l acc)))
```

### Plain-SBCL Failure & Backtrace (SBCL 2.6.10 arm64)

```text
Unhandled TYPE-ERROR in thread #<SB-THREAD:THREAD tid=259 "main thread" RUNNING>:
  The value
    -262149
  is not of type
    (SIGNED-BYTE 19)

Backtrace:
0: ((LABELS SB-ARM64-ASM::ONE-INSTRUCTION-EMITTER :IN SB-ARM64-ASM::LOAD-CONSTANT)
    #<SB-ASSEM:SEGMENT> 1048580)
1: (SB-ASSEM::PROCESS-BACK-PATCHES #<SB-ASSEM:SEGMENT>)
2: (SB-ASSEM:FINALIZE-SEGMENT #<SB-ASSEM:SEGMENT>)
3: (SB-ASSEM:ASSEMBLE-SECTIONS ... :CONSTANT-VECTOR #(((:FIXUP SB-VM::LIST-ALLOC-TRAMP :ASSEMBLY-ROUTINE) . #<SB-ASSEM:LABEL 4>)) ...)
4: (SB-C::GENERATE-CODE #<SB-C:COMPONENT :NAME (DEFUN TRIGGER-REC-F18)>)
```

## Minimal ACL2 Reproducer (`recursion-kept.lisp`)

```lisp
(in-package "ACL2")
(skip-proofs
 (defun-inline zf7-ref (l acc x0 x1)
   (declare (ignorable l acc x0 x1)
            (xargs :guard 0 :measure 0 :verify-guards nil))
   (if (endp l)
       acc
       (zf7-ref (cdr l)
                (loop$ for k1 from (from-df (df/ 0 (to-df (the (unsigned-byte 8) (the (signed-byte 8) acc)))))
                       to 0
                       sum nil)
                x0 x1))))
```

*(Note: `skip-proofs` only bypasses guard/measure proof obligations in the reduced artifact; the crash occurs inside SBCL's ARM64 assembler when compiling ACL2's generated executable-counterpart wrapper `(defun acl2_*1*_acl2::zf7-ref$inline ...)`, before any execution.)*

### Observed ACL2 Failure & Raw Backtrace on SBCL 2.6.10 arm64

Enabling `(set-debugger-enable :bt)` before admitting `recursion-kept.lisp` yields:

```text
Error:  The value
          -262148
        is not of type
          (SIGNED-BYTE 19)

0: ((LABELS SB-ARM64-ASM::ONE-INSTRUCTION-EMITTER :IN SB-ARM64-ASM::LOAD-FROM-LABEL)
    #<SB-ASSEM:SEGMENT> 1048600)
1: (SB-ASSEM::PROCESS-BACK-PATCHES #<SB-ASSEM:SEGMENT>)
2: (SB-ASSEM:FINALIZE-SEGMENT #<SB-ASSEM:SEGMENT>)
...
8: (SB-C::%COMPILE-COMPONENT #<SB-C:COMPONENT :NAME (DEFUN ACL2_*1*_ACL2::ZF7-REF$INLINE)>)
```

## Exact Source Root Cause (`src/compiler/arm64/insts.lisp`)

1. **How recursive `inline` crosses 1 MiB (`1,048,576` bytes = `262,144` ARM64 instructions):**
   - Defining `(defun rec-f18 ...)` (or ACL2's `(defun zf7-ref$inline ...)`) records its inline expansion; when a subsequent caller is compiled (`trigger-rec-f18`, or ACL2's auto-generated `*1*` executable-counterpart function `acl2_*1*_acl2::zf7-ref$inline`), SBCL recursively expands inline calls up to `sb-ext:*inline-expansion-limit*` (`50`), producing a single `SB-ASSEM:SEGMENT` slightly larger than `1,048,576` bytes (`position = 1,048,580` / `1,048,600`).

2. **Missing `lip` / long-displacement relaxation in `load-from-label` and `load-constant` (`src/compiler/arm64/insts.lisp:3399–3503`):**
   - Both `define-instruction-macro load-from-label` (`insts.lisp:3399–3455`) and `define-instruction-macro load-constant` (`insts.lisp:3457–3503`) accept an optional 3rd `lip` scratch register:
     - When `lip` is supplied, they call `emit-chooser` and relax displacements outside `(typep (ash delta -2) '(signed-byte 19))` into a 2-instruction `ADR lip, label` (`±1 MiB`? Actually `ADR` is `±1 MiB` in bytes = `(signed-byte 21)`, i.e. `±1 MiB`, Wait: `ADR` is `(signed-byte 21)` byte offset = ALSO `±1 MiB`!) — see point 3 below!
     - Worse, most callers **omit `lip` entirely**, including:
       - `src/compiler/arm64/float.lisp:83` / `simd-pack.lisp:75` (loading inline float/SIMD constants from segment start — the exact site hit by `df/ 0 ...` at `position = 1,048,600`, `delta/4 = -262148`!)
       - `src/compiler/arm64/macros.lisp:577` (`invoke-asm-routine` / out-of-line allocation trampolines `ALLOC-TRAMP`, `LIST-ALLOC-TRAMP`)
       - `src/compiler/arm64/move.lisp:260` (`define-move-fun (load-constant 5)`, hit by `plain-sbcl.lisp` at `position = 1,048,580`, `delta/4 = -262149`!)
       - `src/compiler/arm64/cell.lisp:424` and `type-vops.lisp:879,979`
     - When `lip` is `NIL`, `one-instruction-emitter` runs unconditionally via `emit-back-patch` and evaluates `(the (signed-byte 19) (ash (compute-delta position) -2))` (`insts.lisp:3440` and `insts.lisp:3495`), crashing with `TYPE-ERROR` as soon as the segment exceeds 1 MiB.

3. **Even WITH `lip`, `ADR` in `load-from-label` / `load-constant` only spans `±1 MiB` (`(signed-byte 21)` bytes = `±2^20` bytes = `±262,144` words!), AND conditional branches also lack relaxation:**
   - ARM64 `LDR (literal)` encodes a 19-bit signed **word** offset (`±2^18 * 4 = ±1 MiB`), and ARM64 `ADR` encodes a 21-bit signed **byte** offset (`±2^20 = ±1 MiB`) — the **exact same `±1 MiB` reach**! Thus `two-instruction-emitter` (`ADR` + `LDR`, `insts.lisp:3421–3434`) only helps unaligned byte offsets, NOT segments > 1 MiB (which require `ADRP` + `ADD`/`LDR` or periodic constant pools).
   - Furthermore, conditional `b` (`insts.lisp:2239–2258`, `emit-cond-branch`) and `cbz`/`cbnz` (`insts.lisp:2330–2351`, `emit-compare-branch-imm`) have **no `emit-chooser` relaxation at all** (unlike `tbz`/`tbnz` at `insts.lisp:2353–2392`, which properly invert and branch over an unconditional 26-bit `B`). Note also that `def-emitter` types 19-bit `imm` fields as `(integer -262144 524287)` (the union of `(signed-byte 19)` and `(unsigned-byte 19)`), so a forward `b :cond` or `cbz` displacement of `+262,144 .. +524,287` words (`+1 MiB .. +2 MiB`) would pass the emitter's type check and silently wrap bit 18 into a **negative backward branch**!
