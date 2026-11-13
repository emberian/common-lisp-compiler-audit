;;; SBCL x86-64 soundness bug (found by the non-integer differential fuzzer).
;;;
;;; At (speed 3)(safety 0): a (simple-array (unsigned-byte 64)) is initialised
;;; with THREE modular (mod 2^64) expressions, one of them a variable-shift ASH;
;;; then ONLY that element is read back with AREF.  The dead-store elimination of
;;; the other two elements miscompiles the surviving variable-shift modular ASH
;;; and the read returns a WRONG value.
;;;
;;;   buggy  (speed 3)(safety 0)  => 0                      (wrong)
;;;   correct(speed 0)(safety 3)  => 8796093022207          (= (ash (1- 2^63) -20))
;;;
;;; Observed: WRONG on SBCL 2.6.8 x86-64.  Correct on SBCL 2.2.9 x86-64 and on
;;; SBCL 2.6.10 arm64.  No contract is violated: v0,v1 are plain integers, the
;;; array elements are masked into (unsigned-byte 64), the index is in bounds,
;;; and the two definitions differ only in their OPTIMIZE policy.
;;; Essential conditions (each verified by reduction): >= 3 array elements, each
;;; a modular expr; the read element's ASH shift must be VARIABLE (constant shift
;;; is correct); only the one element read (reading all three is correct).

(defun buggy (v0 v1)
  (declare (optimize (speed 3) (safety 0)) (type integer v0 v1))
  (let ((a (make-array 3 :element-type '(unsigned-byte 64)
             :initial-contents
             (list (logand v1 #xFFFFFFFFFFFFFFFF)
                   (logand (ash v1 (- (logand v0 63) 20)) #xFFFFFFFFFFFFFFFF)
                   (logand v1 #xFFFFFFFFFFFFFFFF)))))
    (aref a 1)))

(defun correct (v0 v1)
  (declare (optimize (speed 0) (safety 3)) (type integer v0 v1))
  (let ((a (make-array 3 :element-type '(unsigned-byte 64)
             :initial-contents
             (list (logand v1 #xFFFFFFFFFFFFFFFF)
                   (logand (ash v1 (- (logand v0 63) 20)) #xFFFFFFFFFFFFFFFF)
                   (logand v1 #xFFFFFFFFFFFFFFFF)))))
    (aref a 1)))

(let* ((v0 64) (v1 9223372036854775807)
       (b (buggy v0 v1)) (c (correct v0 v1)))
  (format t "~&SBCL ~a  ~a~%" (lisp-implementation-version) (machine-type))
  (format t "buggy   (speed 3 safety 0) = ~a~%" b)
  (format t "correct (speed 0 safety 3) = ~a~%" c)
  (format t "reference (logand (ash ~a -20) 2^64-1) = ~a~%" v1 (logand (ash v1 -20) #xFFFFFFFFFFFFFFFF))
  (format t "VERDICT: ~a~%" (if (eql b c) "OK (no divergence)" "SOUNDNESS DIVERGENCE")))
(sb-ext:exit)
