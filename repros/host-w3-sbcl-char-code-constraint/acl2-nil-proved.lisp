;;;; Guard-verified :logic-mode ACL2 reproducer proving (defthm nil-proved nil)
;;;; on SBCL 2.6.10 (ARM64 and X86-64) via constraint-back.lisp char-code eq bug.
;;;; Zero trust tags, zero skip-proofs, zero redefinition.

(defun bad-cc (c y)
  (declare (xargs :guard (and (characterp c) (integerp y) (<= 10 y) (<= y 20))))
  (let ((y (the (integer 10 20) y)))
    (if (eql (char-code c) y)
        :eq
        (if (and (<= 10 (char-code c)) (<= (char-code c) 20))
            :in
            :out))))

(defthm bad-cc-eval
  (equal (bad-cc (code-char 10) 15) :out)
  :rule-classes nil)

(defthm bad-cc-def
  (equal (bad-cc (code-char 10) 15) :in)
  :hints (("Goal" :in-theory (disable (:executable-counterpart bad-cc))))
  :rule-classes nil)

(defthm nil-proved
  nil
  :hints (("Goal" :use (bad-cc-eval bad-cc-def)))
  :rule-classes nil)
