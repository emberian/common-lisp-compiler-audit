(in-package "ACL2")
; NOTE-7-1/7-3: try to make a correct meta rule emit forbidden/program terms.
(defevaluator mev mev-lst
  ((if x y z)
   (sys-call command-string args)))
(defun mf-forbidden (term)
  (if (equal term '(if nil nil nil))
      '(sys-call "" nil)
    term))
(defthm mf-forbidden-correct
  (equal (mev term a) (mev (mf-forbidden term) a))
  :rule-classes ((:meta :trigger-fns (if))))
(thm (if nil nil nil))

; Program-mode output through the same metafunction route.
(defun pprog (x) (declare (xargs :mode :program) (ignore x)) nil)
(defun mf-program (term)
  (if (equal term '(if nil nil nil))
      '(pprog nil)
    term))
(defthm mf-program-correct
  (equal (mev term a) (mev (mf-program term) a))
  :rule-classes ((:meta :trigger-fns (if))))
(thm (if nil nil nil))
(quit)
