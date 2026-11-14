(in-package "ACL2")
(ld "std/package.lsp" :dir :system)
(include-book "std/util/bstar" :dir :system :ttags nil)

;; 1. def-b*-decomp hardcodes un-gensymmed symbol b*-decomp-temp-var,
;;    causing lexical variable capture when the RHS is a non-symbol expression.
(def-b*-decomp mypair (a . car) (b . cdr))

(defun test-decomp-capture (b*-decomp-temp-var)
  (declare (xargs :guard t) (ignorable b*-decomp-temp-var))
  (b* (((mypair :a x) (cons 1 2)))
    (list x b*-decomp-temp-var)))

(cw "~%[BSTAR-DECOMP-CAPTURE: ~x0]~%" (test-decomp-capture 999))

;; 2. b* `access` binder duplicates non-symbol RHS across every bound field,
;;    evaluating side effects (and work) N times.
(defrec myrec (f1 . f2) nil)

(cw "~%[BSTAR-ACCESS-DUP: ~x0]~%"
    (b* (((access myrec f1 f2)
          (prog2$ (cw "[ACCESS-RHS-EVAL]~%")
                  (make myrec :f1 10 :f2 20))))
      (list f1 f2)))
(quit)
