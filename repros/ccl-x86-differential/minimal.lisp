;;; Minimize: does a single-valued outer op wrapping an inner (round/truncate/floor ..)
;;; in argument position leak the inner's secondary value out of the function under
;;; (speed 3)(safety 0)?  A conforming function here returns exactly ONE value.
(defmacro deftest (name policy expr)
  `(progn
     (defun ,name (x) (declare (integer x) (optimize ,@policy)) ,expr)))

;; speed3/safety0 variants
(deftest f-logior-fast ((speed 3)(safety 0)) (logior 0 (round x 10)))
(deftest f-plus-fast   ((speed 3)(safety 0)) (+ 0 (truncate x 10)))
(deftest f-1plus-fast  ((speed 3)(safety 0)) (1+ (floor x 10)))
(deftest f-ash-fast    ((speed 3)(safety 0)) (logand 7 (ceiling x 10)))
(deftest f-identity-fast ((speed 3)(safety 0)) (identity (truncate x 10)))
(deftest f-bare-fast   ((speed 3)(safety 0)) (truncate x 10))   ; control: SHOULD be 2 values

;; speed0/safety3 variants (reference)
(deftest f-logior-safe ((speed 0)(safety 3)) (logior 0 (round x 10)))
(deftest f-plus-safe   ((speed 0)(safety 3)) (+ 0 (truncate x 10)))
(deftest f-1plus-safe  ((speed 0)(safety 3)) (1+ (floor x 10)))
(deftest f-bare-safe   ((speed 0)(safety 3)) (truncate x 10))   ; control

(defun nv (fn x) (length (multiple-value-list (funcall fn x))))
(defun vals (fn x) (multiple-value-list (funcall fn x)))

(dolist (spec (list (list "logior 0 (round x 10)   fast" #'f-logior-fast #'f-logior-safe)
                    (list "+ 0 (truncate x 10)     fast" #'f-plus-fast   #'f-plus-safe)
                    (list "1+ (floor x 10)         fast" #'f-1plus-fast  #'f-1plus-safe)
                    (list "logand 7 (ceiling x 10) fast" #'f-ash-fast    nil)
                    (list "identity (truncate x 10)fast" #'f-identity-fast nil)
                    (list "bare (truncate x 10)    CTRL" #'f-bare-fast   #'f-bare-safe)))
  (destructuring-bind (label fast safe) spec
    (format t "~a : fast nvalues=~a vals=~s~@[  safe nvalues=~a~]~%"
            label (nv fast 37) (vals fast 37)
            (and safe (nv safe 37)))))
(finish-output)
#+ccl (ccl:quit 0)
#+sbcl (sb-ext:exit :code 0)
