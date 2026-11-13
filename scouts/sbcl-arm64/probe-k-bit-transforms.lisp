;;; K: source-transform and variable-shift boundaries not covered by value-only tests.
(setq *compile-print* nil *compile-verbose* nil)
(defparameter *k-fails* 0)
(defparameter *k-count* 0)
(defparameter *k-vals*
  '(0 1 -1 2 -2 3 -3 7 -7 15 -16 31 -32 32 -33 63 -64 64 -65
    127 -128 128 -129 255 -256 256 -257
    4611686018427387902 4611686018427387903
    -4611686018427387903 -4611686018427387904
    4611686018427387904 -4611686018427387905
    9223372036854775806 9223372036854775807
    -9223372036854775807 -9223372036854775808
    9223372036854775808 -9223372036854775809
    18446744073709551614 18446744073709551615 18446744073709551616
    -18446744073709551616 -18446744073709551617
    170141183460469231731687303715884105727
    -170141183460469231731687303715884105728
    170141183460469231731687303715884105728
    -170141183460469231731687303715884105729))
(defparameter *k-ops*
  '(< <= = > >= eql integer-length logcount abs logbitp logtest lognot ash
    logand logior logxor + - * evenp oddp min max))
(defun k-result (thunk)
  (handler-case (multiple-value-list (funcall thunk))
    (error (e) (list :error (type-of e) (princ-to-string e)))))
(defun k-compile (form)
  (let ((result nil))
    (with-output-to-string (*standard-output*)
      (with-output-to-string (*error-output*)
        (setf result (compile nil form))))
    result))
(defun k-drive1 (name type body &optional (vals *k-vals*))
  (incf *k-count*)
  (handler-case
      (let ((f (k-compile `(lambda (x)
                             (declare (type ,type x) (optimize (speed 3) (safety 0)))
                             ,body)))
            (g (k-compile `(lambda (x)
                             (declare (type ,type x) (optimize (speed 3) (safety 0)))
                             (locally (declare (notinline ,@*k-ops*)) ,body)))))
        (dolist (x (remove-if-not (lambda (v) (typep v type)) vals))
          (let ((a (k-result (lambda () (funcall f x))))
                (b (k-result (lambda () (funcall g x)))))
            (unless (equal a b)
              (incf *k-fails*)
              (format t "KDIVERGE ~s type=~s x=~s inline=~s ref=~s~%" name type x a b)))))
    (error (e) (format t "KERROR ~s type=~s: ~a~%" name type e))))

;;; K1: INTEGER-LENGTH result compared to constants (srctran.lisp:3405).
(dolist (type '(fixnum (signed-byte 64) (unsigned-byte 64) (signed-byte 128) integer))
  (dolist (c '(0 1 2 3 62 63 64 65 126 127 128 129))
    (dolist (op '(= < > <= >=))
      (k-drive1 (list 'integer-length op c) type `(,op (integer-length x) ,c)))))

;;; K2: LOGCOUNT contexts and rewrites (srctran.lisp:3521).
(dolist (type '(fixnum (signed-byte 64) (unsigned-byte 64) (signed-byte 128) integer))
  (dolist (body '((= (logcount x) 0)
                  (< (logcount x) (integer-length x))
                  (> (logcount x) (integer-length x))
                  (= (logcount (lognot x)) (logcount x))
                  (logcount (lognot x))
                  (= (logcount (ash x 1)) (logcount x))
                  (= (logcount (* x 2)) (logcount x))
                  (= (logcount (* x -2)) (logcount (- x)))))
    (k-drive1 (list 'logcount-context body) type body)))

;;; K3: ABS in equality and ordering transforms.
(dolist (type '(fixnum (signed-byte 64) (signed-byte 128) integer))
  (dolist (c '(-9223372036854775808 -65 -2 -1 0 1 2 63 64 9223372036854775807))
    (dolist (op '(= eql < >))
      (k-drive1 (list 'abs op c) type `(,op (abs x) ,c)))))

;;; K4: nested LOGBITP/LOGTEST rewrites.
(dolist (type '(fixnum (signed-byte 64) (unsigned-byte 64) (signed-byte 128) integer))
  (dolist (k '(0 1 2 61 62 63 64 65 126 127 128))
    (dolist (body `((logbitp ,k (lognot x))
                    (logbitp ,k (ash x 1))
                    (logbitp ,k (logand x -3))
                    (logbitp ,k (logior x 1))))
      (k-drive1 (list 'logbitp-nested body) type body)))
  (dolist (c '(0 1 -1 2 -2 3 -3 4611686018427387903 -4611686018427387904
               9223372036854775807 -9223372036854775808 18446744073709551615))
    (dolist (body `((logtest x ,c)
                    (logtest (lognot x) ,c)
                    (logtest (logand x ,c) ,c)
                    (= (logand x ,c) 0)))
      (k-drive1 (list 'logtest-nested body) type body))))

;;; K5: variable-count ASH, direct and narrowed to unsigned/fixnum masks.
(defparameter *k-shifts*
  '(-130 -129 -128 -127 -126 -66 -65 -64 -63 -62 -2 -1 0 1 2 61 62 63 64 65 66 126 127 128 129 130))
(dolist (type '(fixnum (signed-byte 64) (unsigned-byte 64) (signed-byte 128)))
  (dolist (body '((ash x n)
                  (logand (ash x n) 18446744073709551615)
                  (logand (ash x n) 4611686018427387903)))
    (incf *k-count*)
    (handler-case
        (let ((f (k-compile `(lambda (x n)
                               (declare (type ,type x) (type fixnum n)
                                        (optimize (speed 3) (safety 0)))
                               ,body)))
              (g (k-compile `(lambda (x n)
                               (declare (type ,type x) (type fixnum n)
                                        (optimize (speed 3) (safety 0)))
                               (locally (declare (notinline ,@*k-ops*)) ,body)))))
          (dolist (x (remove-if-not (lambda (v) (typep v type)) *k-vals*))
            (dolist (n *k-shifts*)
              (let ((a (k-result (lambda () (funcall f x n))))
                    (b (k-result (lambda () (funcall g x n)))))
                (unless (equal a b)
                  (incf *k-fails*)
                  (format t "KDIVERGE variable-ash type=~s body=~s x=~s n=~s inline=~s ref=~s~%"
                          type body x n a b))))))
      (error (e) (format t "KERROR variable-ash type=~s body=~s: ~a~%" type body e)))))
(format t "probe K done, cases=~d fails=~d~%" *k-count* *k-fails*)
