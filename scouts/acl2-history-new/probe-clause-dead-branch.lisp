(in-package "ACL2")
; Put target calls in a dead IF branch, so correctness is independent of their
; evaluation. The output checker must nevertheless see them.
(defevaluator cpev cpev-lst ((not x) (if x y z)))

(defun cp-forbidden (clause)
  (list (cons '(if 't nil (sys-call "" nil)) clause)))
(defthm cp-forbidden-correct
  (implies (and (pseudo-term-listp clause)
                (alistp a)
                (cpev (conjoin-clauses (cp-forbidden clause)) a))
           (cpev (disjoin clause) a))
  :rule-classes :clause-processor)
(thm nil :hints (("Goal" :clause-processor (cp-forbidden clause))))

(defun cp-program (clause)
  (list (cons '(if 't nil (pprog nil)) clause)))
(defun pprog (x) (declare (xargs :mode :program) (ignore x)) nil)
(defthm cp-program-correct
  (implies (and (pseudo-term-listp clause)
                (alistp a)
                (cpev (conjoin-clauses (cp-program clause)) a))
           (cpev (disjoin clause) a))
  :rule-classes :clause-processor)
(thm nil :hints (("Goal" :clause-processor (cp-program clause))))

; Newer apply$/lambda$ route: program-mode call is nested in a quoted lambda
; object rather than appearing as the outermost call.
(defun cp-apply-lambda (clause)
  (list (cons '(if 't nil
                   (apply$ '(lambda (x) (pprog x)) '(nil)))
              clause)))
(defthm cp-apply-lambda-correct
  (implies (and (pseudo-term-listp clause)
                (alistp a)
                (cpev (conjoin-clauses (cp-apply-lambda clause)) a))
           (cpev (disjoin clause) a))
  :rule-classes :clause-processor)
(thm nil :hints (("Goal" :clause-processor (cp-apply-lambda clause))))
(quit)
