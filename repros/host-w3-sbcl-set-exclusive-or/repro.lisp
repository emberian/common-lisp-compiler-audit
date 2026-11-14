;;;; Reproducer 3: src/compiler/seqtran.lisp:4350-4364
;;;; (deftransforms (set-exclusive-or nset-exclusive-or) ...)
;;;; Copy-pasted `union`/`nunion`'s `(same-leaf-ref-p list1 list2)` branch and returns `'list1`
;;;; instead of `nil` (x `XOR` x = empty set, NOT `x`!).
;;;; Zero-UB: triggers at default (speed 1)(safety 1) and (speed 3)(safety 3) with zero declarations.

(defun f-set-xor-default (x)
  (set-exclusive-or x x))

(defun f-nset-xor-default (x)
  (nset-exclusive-or x x))

(defun f-set-xor-s3 (x)
  (declare (optimize (speed 3) (safety 3)))
  (set-exclusive-or x x :test #'equal))

(defun f-set-xor-notinline (x)
  (declare (notinline set-exclusive-or nset-exclusive-or))
  (list (set-exclusive-or x x)
        (nset-exclusive-or (copy-list x) (copy-list x))))

(format t "Arch: ~a ~a~%" (machine-type) (lisp-implementation-version))
(format t "set-exclusive-or default  '(1 2 3) => ~s (expected NIL)~%"
        (f-set-xor-default (list 1 2 3)))
(format t "nset-exclusive-or default '(1 2 3) => ~s (expected NIL)~%"
        (f-nset-xor-default (list 1 2 3)))
(format t "set-exclusive-or s3       '(1 2 3) => ~s (expected NIL)~%"
        (f-set-xor-s3 (list 1 2 3)))
(format t "notinline                 '(1 2 3) => ~s~%"
        (f-set-xor-notinline (list 1 2 3)))
