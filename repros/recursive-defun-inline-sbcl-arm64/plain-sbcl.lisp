;;;; Standalone Pure Common Lisp Reproducer for SBCL 2.6.10 (arm64)
;;;; Assembler `(SIGNED-BYTE 19)` PC-Relative Literal-Load Overflow (SB2 / F18)
;;;;
;;;; Zero ACL2 dependencies. Reproduces in ~2 seconds on SBCL 2.6.10 darwin-arm64:
;;;;   /opt/homebrew/bin/sbcl --noinform --non-interactive \
;;;;     --load repros/recursive-defun-inline-sbcl-arm64/plain-sbcl.lisp
;;;;
;;;; Expected crash during compilation of TRIGGER-REC-F18:
;;;;   Unhandled TYPE-ERROR ...:
;;;;     The value -262149 is not of type (SIGNED-BYTE 19)
;;;;   0: ((LABELS SB-ARM64-ASM::ONE-INSTRUCTION-EMITTER :IN SB-ARM64-ASM::LOAD-CONSTANT) ...)
;;;;
;;;; Root cause (`src/compiler/arm64/insts.lisp:3399-3503`):
;;;;   1. Compiling a caller (`trigger-rec-f18`, or ACL2's `*1*` executable-counterpart
;;;;      wrapper for `zf7-ref$inline`) of an `inline` recursive function expands inline
;;;;      calls up to `sb-ext:*inline-expansion-limit*` (50), pushing the code segment
;;;;      past 1 MiB (262,144 32-bit instruction words = 1,048,576 bytes).
;;;;   2. Out-of-line trampolines / inline constants at the tail of the segment invoke
;;;;      `load-constant` (`move.lisp:260` / assembly-routine fixup `SB-VM::LIST-ALLOC-TRAMP`)
;;;;      or `load-from-label` (`float.lisp:83` / `macros.lisp:577` in ACL2's `df/ 0 ...`)
;;;;      WITHOUT passing the optional `lip` scratch register.
;;;;   3. When `lip` is NIL, both `load-constant` (`insts.lisp:3495`) and `load-from-label`
;;;;      (`insts.lisp:3440`) skip `emit-chooser` ADR+LDR relaxation and unconditionally
;;;;      emit a single PC-relative `LDR (literal)` (`emit-ldr-literal`) back-patch targeting
;;;;      the segment header/constant pool, failing `(the (signed-byte 19) ...)` once
;;;;      `(ash delta -2) < -262144`.

(declaim (muffle-conditions sb-ext:compiler-note style-warning))

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
