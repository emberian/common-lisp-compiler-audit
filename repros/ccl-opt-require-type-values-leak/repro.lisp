;;;; CCL compiler-macro bug: several arithmetic/comparison compiler-macros rewrite
;;;; a call to a BARE operand (directly, or via (REQUIRE-TYPE x T) / (THE T x)),
;;;; and that rewrite FORWARDS ALL VALUES of the operand at (speed 3)(safety 0).
;;;; The function is specified to return exactly ONE value, so extra values leak.
;;;;
;;;; This is the same defect as CCL-3 (identity + logand/logior/logxor identity
;;;; elimination), here shown on additional operators. All in
;;;; compiler/optimizers.lisp:
;;;;   +  unary  -> (require-type n0 'number)              ~line 1369
;;;;   *  unary  -> (require-type n0 'number)              ~line 1385
;;;;   =  unary  -> (require-type n0 'number)              ~line 1343
;;;;   /= unary  -> (require-type n0 'number)              ~line 1353
;;;;   < > <= >= unary -> (require-type n0 'real)          ~line 292 (transform-real-n-ary-comparision)
;;;;   max unary -> (require-type n0 'real)                ~line 1779
;;;;   min unary -> (require-type n0 'real)                ~line 1805
;;;;   nthcdr 0  -> (require-type list 'list)              ~line 968
;;;;   ash x 0   -> x (bare, when x is known integer)      ~line 323
;;;; REQUIRE-TYPE's own macro (optimizers.lisp ~line 999) returns ARG bare when the
;;;; type is already known, and (THE non-values-type form) forwards all values; that
;;;; is the mechanism.  (floor 23 10) is used as a known-integer two-value source so
;;;; no explicit THE is needed except where noted.
;;;;
;;;; Correct in SBCL. Shared source-level optimizer code => architecture-independent;
;;;; verified on arm64. Leak is (speed 3)(safety 0)-only: at (safety 3) CCL is correct.

(defun mvl (thunk) (multiple-value-list (funcall thunk)))

(defmacro probe (label form &rest notinline)
  `(let ((bad  (compile nil '(lambda () (declare (optimize (speed 3) (safety 0))) ,form)))
         (good (compile nil '(lambda () (declare (notinline ,@notinline))         ,form))))
     (format t "~&~22a opt(speed3,safety0)=~s   notinline=~s~%"
             ,label (mvl bad) (mvl good))))

;; (floor 23 10) => 2,3 : a known-integer operand carrying a second value.
(probe "(+ (floor 23 10))"       (+ (floor 23 10))        +)
(probe "(* (floor 23 10))"       (* (floor 23 10))        *)
(probe "(= (floor 23 10))"       (= (floor 23 10))        =)
(probe "(/= (floor 23 10))"      (/= (floor 23 10))       /=)
(probe "(< (floor 23 10))"       (< (floor 23 10))        <)
(probe "(> (floor 23 10))"       (> (floor 23 10))        >)
(probe "(<= (floor 23 10))"      (<= (floor 23 10))       <=)
(probe "(>= (floor 23 10))"      (>= (floor 23 10))       >=)
(probe "(max (floor 23 10))"     (max (floor 23 10))      max)
(probe "(min (floor 23 10))"     (min (floor 23 10))      min)
(probe "(logior 0 (floor 23 10))"  (logior 0 (floor 23 10))  logior)   ; CCL-3 class
(probe "(logand -1 (floor 23 10))" (logand -1 (floor 23 10)) logand)   ; CCL-3 class
(probe "(logxor 0 (floor 23 10))"  (logxor 0 (floor 23 10))  logxor)   ; CCL-3 class
(probe "(identity (floor 23 10))"  (identity (floor 23 10))  identity) ; CCL-3
;; nthcdr 0 and ash 0 need the operand's type made explicit to fire the bare path:
(probe "(nthcdr 0 (the list..))" (nthcdr 0 (the list (values (list 1 2) (list 3 4)))) nthcdr)
(probe "(ash (the integer..) 0)" (ash (the integer (values 5 6)) 0) ash)

(format t "~%Expected (correct, as SBCL and the notinline column): ONE value each.~%")
(finish-output)
#+ccl (ccl:quit)
#+sbcl (sb-ext:exit)
