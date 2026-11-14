;;;; Reproducer 4: src/compiler/constraint.lisp:1232-1256
;;;; `type-after-comparison` inverts `<`/`>`/`<=`/`>=` when `not-p = t` on floats
;;;; to `>=`/`<=`/`>`/`<` without accounting for IEEE-754 NaN (unordered).
;;;; Under non-stop float traps (`:invalid` masked), `(< NaN 1.0d0)` is NIL,
;;;; taking the else branch where SBCL asserts `(double-float 1.0d0)` and folds `(>= x 1.0d0)` -> T.

(defun make-qnan ()
  (sb-int:with-float-traps-masked (:invalid)
    (- sb-ext:double-float-positive-infinity sb-ext:double-float-positive-infinity)))

(defun test-nan-lt-s3 (x)
  (declare (optimize (speed 3) (safety 3))
           (type double-float x))
  (sb-int:with-float-traps-masked (:invalid)
    (if (< x 1.0d0)
        :lt
        (list (typep x '(double-float 1.0d0))
              (< x 1.0d0)
              (>= x 1.0d0)))))

(defun test-nan-lt-ref (x)
  (let ((lt (locally (declare (notinline identity)) (identity #'<)))
        (tp (locally (declare (notinline identity)) (identity #'typep)))
        (ge (locally (declare (notinline identity)) (identity #'>=))))
    (sb-int:with-float-traps-masked (:invalid)
      (if (funcall lt x 1.0d0)
          :lt
          (list (funcall tp x '(double-float 1.0d0))
                (funcall lt x 1.0d0)
                (funcall ge x 1.0d0))))))

(let ((nan (make-qnan)))
  (format t "Arch: ~a ~a~%" (machine-type) (lisp-implementation-version))
  (format t "nan-lt s3        => ~s (expected (NIL NIL NIL))~%" (test-nan-lt-s3 nan))
  (format t "nan-lt ref       => ~s~%" (test-nan-lt-ref nan)))
