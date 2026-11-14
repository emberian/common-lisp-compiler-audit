(in-package "ACL2")

;; End-to-end ACL2 + Z3 soundness bug:
;; books/projects/smtlink/verified/uninterpreted-fn-cp.lisp:105-142,388
;; wraps return-type proof obligations in a lambda/let whose formal/variable
;; shadows outer variables in the hypothesis, proving NIL (Q.E.D.) via Z3 5.4.1.
(encapsulate ()
  (local (defun w4-id-fn (z) (declare (xargs :guard t)) z))
  (local
   (defthm w4-let-shadow-lemma
     (implies (integerp y)
              (not (equal (let ((y 1/2)) (w4-id-fn y)) 1/2)))
     :hints (("Goal"
              :smtlink-custom (:functions ((w4-id-fn :formals ((z rationalp))
                                                     :returns ((r integerp))
                                                     :level 0)))))
     :rule-classes nil))
  (local
   (defthm w4-let-shadow-contradiction
     nil
     :hints (("Goal" :use ((:instance w4-let-shadow-lemma (y 0)))
              :in-theory (enable w4-id-fn)))
     :rule-classes nil))
  (defconst *w4-smt-let-shadow-nil* t))

(value-triple (list :SMT-LET-SHADOW-NIL (acl2::logical-namep '*w4-smt-let-shadow-nil* (w state))))
