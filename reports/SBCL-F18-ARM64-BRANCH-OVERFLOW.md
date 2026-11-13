# SBCL 2.6.10 (arm64) — Assembler `(SIGNED-BYTE 19)` Branch Overflow on Recursive Inline Function

- **Status:** **LIVE on SBCL 2.6.10 darwin-arm64** (crashes compiler/assembler during `defun-inline` admission).
- **Reproducer directory:** `repros/recursive-defun-inline-sbcl-arm64/` (`reduced.lisp`, `recursion-kept.lisp`, `original.lisp`, `run.sh`).
- **Comparison:** Clozure CL 1.14 darwin-arm64 compiles and admits all three files cleanly.

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

*(Note: `skip-proofs` is only used here to bypass guard/measure proofs in the reduced fuzz artifact; the crash occurs inside SBCL's native code emitter when compiling `ZF7-REF$INLINE`, before any execution.)*

## Observed Failure on SBCL 2.6.10 arm64

```text
************ ABORTING from raw Lisp ***********
Error:  The value
          -262148
        is not of type
          (SIGNED-BYTE 19)
***********************************************
; compilation unit aborted
;   caught 1 fatal ERROR condition
```

## Diagnosis

On ARM64, conditional branches (`B.cond`, `CBZ`, `CBNZ`, `TBZ`/`TBNZ`) encode a signed 19-bit
instruction-word offset (`(signed-byte 19)` = `-262144 .. 262143` words = `±1 MiB`). Here
`-262148` overflows `-2^18` by 4 instructions because SBCL unrolls/inlines the recursive
`defun-inline` body (containing `loop$` + `df/` expansions) until a backward conditional
branch spans slightly more than 1 MiB, and the ARM64 backend does not relax out-of-range
conditional branches into an inverted condition + unconditional 26-bit `B` (`±128 MiB`).
