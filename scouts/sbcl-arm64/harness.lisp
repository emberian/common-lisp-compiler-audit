;; Core differential harness. Loaded by probe scripts.
;; KEY RULE: only apply values consistent with the declared types
;; (otherwise it's a guard violation in safety-0 code, not a finding).

(defparameter *fixnums*
  '(0 1 -1 2 -2 3 -3 7 -7 61 62 63 64 65 -61 -62 -63 -64 -65
    4611686018427387902 4611686018427387903 -4611686018427387903 -4611686018427387904))
(defparameter *u64*
  '(0 1 2 3 62 63 64 65
    4611686018427387903 4611686018427387904
    9223372036854775807 9223372036854775808
    13835058055282163710 13835058055282163711
    18446744073709551614 18446744073709551615))
(defparameter *s64*
  '(0 1 -1 2 -2 62 -62 63 -63 64 -64
    4611686018427387903 -4611686018427387904
    9223372036854775807 -9223372036854775808
    9223372036854775806 -9223372036854775807))
(defparameter *s128*
  (append *s64*
          '(9223372036854775808 -9223372036854775809
            9223372036854775809 -9223372036854775810
            18446744073709551615 18446744073709551616 18446744073709551617
            -18446744073709551616 -18446744073709551617
            170141183460469231731687303715884105727
            -170141183460469231731687303715884105727
            -170141183460469231731687303715884105728)))
(defparameter *u32* '(0 1 2 3 62 63 64 65 2147483646 2147483647 4294967294 4294967295))
(defparameter *u8* '(0 1 2 127 128 255))

(defun vals-for (type)
  (cond ((subtypep type 'fixnum) *fixnums*)
        ((subtypep type '(unsigned-byte 8)) *u8*)
        ((subtypep type '(unsigned-byte 32)) *u32*)
        ((subtypep type '(unsigned-byte 64)) *u64*)
        ((subtypep type '(signed-byte 64)) *s64*)
        ((subtypep type '(signed-byte 128)) *s128*)
        (t *fixnums*)))

(defun vals-okp (v type)
  (typep v type))

(defparameter *fails* 0)

(defun norm-result (r)
  "Normalize an ignore-errors result list: replace condition objects by
(type message) so identical errors compare equal."
  (mapcar (lambda (x)
            (if (typep x 'condition)
                (list (type-of x)
                      (ignore-errors (format nil "~a" x)))
                x))
          r))

(defun cmp (name f g args-list)
  (dolist (args args-list)
    (let ((r1 (norm-result (multiple-value-list (ignore-errors (apply f args)))))
          (r2 (norm-result (multiple-value-list (ignore-errors (apply g args))))))
      (unless (equalp r1 r2)
        (incf *fails*)
        (format t "DIVERGE ~a args=~s inline=~s ref=~s~%" name args r1 r2)))))

(defun quiet-compile (&rest args)
  (let ((result nil))
    (with-output-to-string (*standard-output*)
      (with-output-to-string (*error-output*)
        (setf result (apply #'compile args))))
    result))

;; One-variable: type = declared type of x, body over x, ops notinline in ref.
(defun test1 (name type body ops &key quiet)
  (let* ((vals (remove-if-not (lambda (v) (vals-okp v type)) (vals-for type)))
         (f (quiet-compile nil `(lambda (x) (declare (optimize (speed 3) (safety 0))
                                          (type ,type x))
                                  ,body)))
         (g (quiet-compile nil `(lambda (x) (declare (optimize (speed 3) (safety 0))
                                          (type ,type x))
                                  (locally (declare (notinline ,@ops)) ,body)))))
    (unless quiet
      (cmp name f g (mapcar #'list vals)))
    (values f g)))

;; Two-variable
(defun test2 (name types body ops arg-pairs)
  (let ((f (quiet-compile nil `(lambda (x y) (declare (optimize (speed 3) (safety 0))
                                          (type ,(first types) x)
                                          (type ,(second types) y))
                                  ,body)))
        (g (quiet-compile nil `(lambda (x y) (declare (optimize (speed 3) (safety 0))
                                       (type ,(first types) x)
                                       (type ,(second types) y))
                                  (locally (declare (notinline ,@ops)) ,body)))))
    (cmp name f g arg-pairs)))
