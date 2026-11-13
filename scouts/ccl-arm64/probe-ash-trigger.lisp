;;; Probe: which (ash x K) declaration shapes trigger the %ilsl overflow?
(in-package :cl-user)

(defun try (name decl k x)
  (let* ((form `(lambda (x)
                  (declare (type ,decl x))
                  (declare (optimize (speed 3) (safety 0)))
                  (ash x ,k)))
         (f (compile nil form))
         (got (ignore-errors (funcall f x)))
         (want (ignore-errors (ash x k))))
    (format t "~&~a decl=~s k=~d x=~d got=~s want=~s ~a~%"
            name decl k x got want
            (if (eql got want) "ok" "*** DIFF"))))

;; (signed-byte 45) - the known trigger
(try "sb45" '(signed-byte 45) 16 (1- (expt 2 45)))
;; integer-range identical to (signed-byte 45)
(try "intrange" '(integer -35184372088832 35184372088831) 16 (1- (expt 2 45)))
;; integer-range with * low
(try "intrange*" '(integer * 35184372088831) 16 (1- (expt 2 45)))
;; positive-only range
(try "intrangepos" '(integer 0 35184372088831) 16 (1- (expt 2 45)))
;; mod
(try "mod" '(mod 35184372088832) 16 (1- (expt 2 45)))
;; (signed-byte 46): too wide, should not fire
(try "sb46" '(signed-byte 46) 16 (1- (expt 2 45)))
;; fixnum alone
(try "fixnum" 'fixnum 16 (1- (expt 2 45)))
;; ash 1 with (signed-byte 60)
(try "sb60k1" '(signed-byte 60) 1 (expt 2 59))
(try "sb61k1" '(signed-byte 61) 1 (expt 2 59))
;; ash 2 with (signed-byte 59)
(try "sb59k2" '(signed-byte 59) 2 (expt 2 58))
;; ash 59 with (signed-byte 2)
(try "sb2k59" '(signed-byte 2) 59 1)
(try "sb2k59b" '(signed-byte 2) 59 3)
;; ash 60 with (signed-byte 1)
(try "sb1k60" '(signed-byte 1) 60 0)
(try "sb1k60b" '(signed-byte 1) 60 -1)
;; the-fixnum-asserted second disjunct: (the fixnum (ash x 16)), x declared fixnum
(let* ((form `(lambda (x)
                (declare (type fixnum x))
                (declare (optimize (speed 3) (safety 0)))
                (the fixnum (ash x 16))))
       (f (compile nil form))
       (x (1- (expt 2 45)))
       (got (ignore-errors (funcall f x))))
  (format t "~&the-fixnum-asserted x=2^45-1 got=~s want=~s ~a~%"
          got (ash x 16) (if (eql got (ash x 16)) "ok (lying the; not counted" "***")))

;; does (* x 65536) with (signed-byte 45) take a different path?
(let* ((form `(lambda (x)
                (declare (type (signed-byte 45) x))
                (declare (optimize (speed 3) (safety 0)))
                (* x 65536)))
       (f (compile nil form))
       (x (1- (expt 2 45)))
       (got (ignore-errors (funcall f x))))
  (format t "~&mul-sb45 x=2^45-1 got=~s want=~s ~a~%"
          got (* x 65536) (if (eql got (* x 65536)) "ok" "*** DIFF")))

(quit)
