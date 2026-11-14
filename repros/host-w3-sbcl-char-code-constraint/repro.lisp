;;;; Reproducer 1: src/compiler/constraint-back.lisp:505-516
;;;; (defoptimizer (char-code constraint-propagate-back) ...)
;;;; Under `eq` branch when `y` has a non-singleton integer range [low, high] (low < high),
;;;; SBCL emits `(conset-add-constraint-to-eql gen 'typep var type t alternative)`
;;;; asserting `(not (character-set ((low . high))))` on the NOT-EQ branch!
;;;; This falsely proves `(char-code c)` cannot lie in [low, high] whenever `(not (eql (char-code c) y))`.
;;;; Zero-UB: works even at default (speed 1) (safety 1) and at (speed 3) (safety 3).

(declaim (notinline black-box-char-eq-s3 black-box-char-eq-default))

(defun black-box-char-eq-s3 (c y)
  (declare (optimize (speed 3) (safety 3))
           (type character c)
           (type (integer 10 20) y))
  (let ((b (eql (char-code c) y)))
    (if b
        :eq
        (if (<= 10 (char-code c) 20)
            :in-range-not-eq
            :out-of-range))))

(defun black-box-char-eq-default (c y)
  (declare (type character c)
           (type (integer 10 20) y))
  (if (= (char-code c) y)
      :eq
      (list (<= 10 (char-code c) 20)
            (eql (char-code c) 10))))

(defun run-ref-char-eq (c y)
  (declare (optimize (speed 0) (safety 3)))
  ;; Note: constraint propagation still runs unless `(char-code c)` isn't constrained against `(integer 10 20)`
  ;; Compute truth directly via code-char/char-code without range declaration on y:
  (let ((cc (char-code c)))
    (if (eql cc y)
        :eq
        (if (<= 10 cc 20)
            :in-range-not-eq
            :out-of-range))))

(let ((c (code-char 10))
      (y 15))
  (format t "Arch: ~a ~a~%" (machine-type) (lisp-implementation-version))
  (format t "black-box-char-eq-s3      ((code-char 10), 15) => ~s (expected :IN-RANGE-NOT-EQ)~%"
          (black-box-char-eq-s3 c y))
  (format t "black-box-char-eq-default ((code-char 10), 15) => ~s (expected (T T))~%"
          (black-box-char-eq-default c y))
  (format t "reference                 ((code-char 10), 15) => ~s~%"
          (run-ref-char-eq c y)))
