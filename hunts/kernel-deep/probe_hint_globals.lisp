(in-package "ACL2")

;; Check which state globals can be mutated from a computed hint inside THM
;; and persist after THM!
(defmacro try-hint-mut (g val)
  `(make-event
    (mv-let (erp v state)
      (thm (equal x x)
           :hints ((pprogn (f-put-global ',g ,val state)
                           (value nil))))
      (declare (ignore v))
      (value `(value-triple ',(list ',g :err erp :after (f-get-global ',g state)))))))

(try-hint-mut ld-skip-proofsp t)
(try-hint-mut guard-checking-on nil)
(try-hint-mut writes-okp t)
(try-hint-mut skip-proofs-seen t)
(try-hint-mut ttags-seen '(:evil))
(try-hint-mut axioms-seen t)
(try-hint-mut default-hints-table nil)
(try-hint-mut override-hints '((:no-thanks t)))
(try-hint-mut default-backtrack-hint '(:no-thanks t))
(try-hint-mut eval-g-rt nil)
(try-hint-mut certify-book-info nil)

;; Also test fmt-to-comment-window with unbound ~y1
(fmt-to-comment-window "~x0 ~y1" '((#\0 . 42)) 0 nil nil)

;; Also test spec-mv-let / plet / pargs / pand / por properly
(defun ptest2 (x y)
  (declare (xargs :guard (and (natp x) (natp y))))
  (spec-mv-let
   (a b) (mv (+ x 1) (+ y 1))
   (if (pand (integerp a) (por (equal b 1) (> b 1)))
       (plet ((u (+ a 2)) (v (+ b 3)))
         (pargs (mv (+ u v) (- u v))))
       (mv 0 0))))
