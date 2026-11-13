;;; CCL x86-64 1.14 soundness bug: under optimization, a value-restricting wrapper
;;; that the compiler folds to its operand ( (logior 0 Y), (identity Y) ) forwards ALL
;;; of the operand's multiple values, when exactly ONE value is required.
;;;
;;;   (logior 0 (round x 10))  must return exactly one value (logior is single-valued).
;;;   CCL (speed 3)(safety 0): returns TWO values -- round's remainder leaks out.
;;;   CCL (speed 0)(safety 3): returns ONE value (correct).  SBCL: ONE value (correct).
;;;
;;; Run: lx86cl64 --batch --no-init --load repro-mv.lisp
;;;      run-sbcl.sh --noinform --non-interactive --load repro-mv.lisp   (reference)

(defun leak-fast (x) (declare (integer x) (optimize (speed 3) (safety 0)))
  (logior 0 (round x 10)))
(defun leak-safe (x) (declare (integer x) (optimize (speed 0) (safety 3)))
  (logior 0 (round x 10)))
(defun leak-id   (x) (declare (integer x) (optimize (speed 3) (safety 0)))
  (identity (truncate x 10)))

(defun nvals (fn x) (length (multiple-value-list (funcall fn x))))

(format t "~&== (logior 0 (round x 10)), x=37  [correct: 1 value, = (4)] ==~%")
(format t "  (speed 3)(safety 0): ~a value(s) -> ~s~%" (nvals #'leak-fast 37) (multiple-value-list (leak-fast 37)))
(format t "  (speed 0)(safety 3): ~a value(s) -> ~s~%" (nvals #'leak-safe 37) (multiple-value-list (leak-safe 37)))
(format t "~&== (identity (truncate x 10)), x=37  [correct: 1 value, = (3)] ==~%")
(format t "  (speed 3)(safety 0): ~a value(s) -> ~s~%" (nvals #'leak-id 37) (multiple-value-list (leak-id 37)))

;; Observable wrong behavior in a conforming consumer:
(format t "~&== observable consequence (multiple-value-call) ==~%")
(format t "  (multiple-value-call #'list (logior 0 (round 37 10)))~%")
(format t "    fast => ~s   [correct: (4)]~%"
        (locally (declare (optimize (speed 3)(safety 0)))
          (multiple-value-call #'list (logior 0 (round 37 10)))))
(format t "    safe => ~s~%"
        (locally (declare (optimize (speed 0)(safety 3)))
          (multiple-value-call #'list (logior 0 (round 37 10)))))

(let ((bug (or (/= (nvals #'leak-fast 37) 1) (/= (nvals #'leak-id 37) 1))))
  (format t "~&VERDICT: ~a~%" (if bug "BUG REPRODUCED (extra values leaked)" "no leak"))
  (finish-output)
  #+ccl (ccl:quit (if bug 1 0))
  #+sbcl (sb-ext:exit :code (if bug 1 0)))
