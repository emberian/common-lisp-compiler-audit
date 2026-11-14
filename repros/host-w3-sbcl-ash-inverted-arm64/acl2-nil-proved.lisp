;;;; Guard-verified :logic-mode ACL2 reproducer proving (defthm nil-proved nil)
;;;; on SBCL 2.6.10 ARM64 via srctran.lisp ash-inverted (%negate (:not (integer * 0))) bug.
;;;; Zero trust tags, zero skip-proofs, zero redefinition.

(defun bad-ash (x)
  (declare (xargs :guard (integerp x)))
  (logand #xffffffffffffffff (ash 1 (- (the integer x)))))

(defthm bad-ash-eval
  (equal (bad-ash -1) 0)
  :rule-classes nil)

(defthm bad-ash-def
  (equal (bad-ash -1) 2)
  :hints (("Goal" :in-theory (disable (:executable-counterpart bad-ash))))
  :rule-classes nil)

(defthm nil-proved
  nil
  :hints (("Goal" :use (bad-ash-eval bad-ash-def)))
  :rule-classes nil)
