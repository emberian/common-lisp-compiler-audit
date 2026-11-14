;;;; Reproducer 2: src/compiler/seqtran.lisp:4470-4475
;;;; (defoptimizer (reduce derive-type) ...) for `logior`:
;;;; 1. When `initial-value` is omitted, derives `element-type` directly, ignoring empty sequences
;;;;    where `(reduce #'logior #())` calls `(logior)` => `0`, which may not be in `element-type`.
;;;; 2. When `initial-value` is supplied, derives `(%two-arg-derive-type element-type initial-value-type ...)`
;;;;    without unioning `initial-value-type`, ignoring empty sequences where `reduce` returns `initial-value`.
;;;; Zero-UB: works at default (speed 1)(safety 1) and (speed 3)(safety 3).

(defun reduce-logior-no-init-s3 (s)
  (declare (optimize (speed 3) (safety 3)))
  (let ((r (reduce #'logior s
                   :key (lambda (x)
                          (declare (ignore x))
                          (the (integer 1 10) 5)))))
    (list r (plusp r) (eql r 0) (typep r '(integer 1 10)))))

(defun reduce-logior-no-init-default (s)
  (let ((r (reduce #'logior s
                   :key (lambda (x)
                          (declare (ignore x))
                          (the (integer 1 10) 5)))))
    (list r (plusp r) (eql r 0) (typep r '(integer 1 10)))))

(defun reduce-logior-with-init-s3 (s)
  (declare (optimize (speed 3) (safety 3)))
  (let ((r (reduce #'logior s
                   :initial-value 5
                   :key (lambda (x)
                          (declare (ignore x))
                          (the (integer -5 -1) -2)))))
    (list r (minusp r) (eql r 5) (typep r '(integer -5 -1)))))

(defun reduce-logior-with-init-ref (s)
  (let ((red (locally (declare (notinline identity)) (identity #'reduce)))
        (min-fn (locally (declare (notinline identity)) (identity #'minusp)))
        (eql-fn (locally (declare (notinline identity)) (identity #'eql)))
        (tp-fn (locally (declare (notinline identity)) (identity #'typep))))
    (let ((r (funcall red #'logior s
                      :initial-value 5
                      :key (lambda (x)
                             (declare (ignore x))
                             (the (integer -5 -1) -2)))))
      (list r (funcall min-fn r) (funcall eql-fn r 5) (funcall tp-fn r '(integer -5 -1))))))

(format t "Arch: ~a ~a~%" (machine-type) (lisp-implementation-version))
(format t "no-init s3      #() => ~s (expected (0 NIL T NIL))~%" (reduce-logior-no-init-s3 #()))
(format t "no-init default #() => ~s (expected (0 NIL T NIL))~%" (reduce-logior-no-init-default #()))
(format t "with-init s3    #() => ~s (expected (5 NIL T NIL))~%" (reduce-logior-with-init-s3 #()))
(format t "with-init ref   #() => ~s~%" (reduce-logior-with-init-ref #()))
