; A proof of NIL in ACL2 built on CCL 1.14 (darwin arm64).  Not reproducible on SBCL.
;
; CCL's ASH, given a positive fixnum count within a few bits of most-positive-fixnum
; (2^60 - 1), neither computes the shift nor signals an error: %ASH-LEFT
; (ccl/level-0/l0-numbers.lisp) adds (integer-length int) to the count in fixnum
; arithmetic, the sum wraps negative, the "result needs a bignum" test fails, and the
; inline fixnum shift %IASH is applied with an out-of-range count.  What comes back is
; not a valid integer; INTEGER-LENGTH of it is -1152921504606846976.
;
; Logically (integer-length (ash 1 k)) is k+1 for every natural k.

(in-package "ACL2")

(defund il-ash (k)
  (declare (xargs :guard (natp k)))
  (integer-length (ash 1 k)))

(in-theory (disable (:e il-ash)))

; Proved symbolically: INTEGER-LENGTH has a built-in non-negative-integer type
; prescription.  No executable counterpart of ours is available here.
(defthmd il-ash-nonnegative
  (<= 0 (il-ash k))
  :hints (("Goal" :in-theory (enable (:d il-ash)))))

; But (il-ash 1152921504606846975) evaluates to -1152921504606846976 in CCL.
(defthm contradiction
  nil
  :hints (("Goal" :use ((:instance il-ash-nonnegative (k 1152921504606846975)))
                  :in-theory (enable (:e il-ash))))
  :rule-classes nil)
