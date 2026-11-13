(defun rd (p)
  (loop
    (handler-case
        (return (with-open-file (s p) (let ((*package* (find-package :cl))) (read s))))
      (sb-int:simple-reader-package-error (c)
        (make-package (package-error-package c) :use nil)))))
(let* ((d (rd "/Users/ember/dev/compiler-audit/coverage/data/dietz-20k.sexp"))
       (a (rd "/Users/ember/dev/compiler-audit/coverage/data/acl2tier-300.sexp"))
       (all (getf d :all-transforms))
       (hit (union (getf d :fired) (getf a :fired) :test #'equal))
       (arith '(+ - * / ash logand logior logxor lognot logeqv logandc1 logandc2 lognand lognor
                logorc1 logorc2 logtest logbitp logcount integer-length truncate floor ceiling round
                mod rem abs min max < > <= >= = /= eql equal expt gcd lcm isqrt signum
                1+ 1- zerop plusp minusp evenp oddp ldb dpb mask-field deposit-field
                numerator denominator char-code code-char car cdr cons length nth nthcdr
                eq not null consp atom integerp rationalp symbolp stringp characterp))
       (names (remove-duplicates (mapcar #'first all)))
       (cl-arith (remove-if-not (lambda (k) (member (first k) arith)) all)))
  (format t "transform table: ~D entries over ~D functions~%" (length all) (length names))
  (format t "hit by either corpus: ~D~%" (length hit))
  (format t "ACL2-expressible CL ops: ~D transforms, hit ~D, unhit ~D~%"
          (length cl-arith) (count-if (lambda (k) (member k hit :test #'equal)) cl-arith)
          (count-if-not (lambda (k) (member k hit :test #'equal)) cl-arith))
  (format t "~%UNHIT transforms on ACL2-expressible ops (function, arg-type signature):~%")
  (dolist (k (sort (remove-if (lambda (k) (member k hit :test #'equal)) (copy-list cl-arith))
                   #'string< :key (lambda (k) (symbol-name (first k)))))
    (format t "  ~12A ~A~%" (first k) (subseq (second k) 0 (min 110 (length (second k))))))
  (let ((dv (getf d :emitted)) (av (getf a :emitted)) (allv (getf d :all-vops)))
    (format t "~%VOPs: table ~D, hit by either ~D; arithmetic-looking unhit sample:~%" (length allv)
            (length (union dv av)))
    (let ((un (remove-if (lambda (v) (or (member v dv) (member v av))) allv)))
      (format t "  unhit with FIXNUM/SIGNED/UNSIGNED/BIGNUM in name: ~D~%"
              (count-if (lambda (v) (let ((n (symbol-name v))) (or (search "FIXNUM" n) (search "SIGNED" n) (search "BIGNUM" n)))) un))
      (format t "  unhit with FLOAT/COMPLEX/SIMD/ALIEN/SAP in name: ~D~%"
              (count-if (lambda (v) (let ((n (symbol-name v))) (or (search "FLOAT" n) (search "COMPLEX" n) (search "SIMD" n) (search "ALIEN" n) (search "SAP" n) (search "DOUBLE" n) (search "SINGLE" n)))) un)))))
