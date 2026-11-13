;;; CCL arm64 (1.14 darwinarm64): (ash x K) with x truthfully declared
;;; (signed-byte (- 61 K)) compiles to %ilsl (a bare machine lsl of the
;;; tagged fixnum) at (speed 3)(safety 0), whose result wraps mod 2^64
;;; whenever x is in the top half of the declared range.  The acode
;;; rewrite gate is compiler/acode-rewrite.lisp:852-859 (upstream 2014,
;;; cbf2406b): `(signed-byte ,(- (1+ maxbits) camt))` with maxbits=60
;;; allows num up to 2^(61-camt)-1, but num<<camt then reaches
;;; 2^61-2^camt > most-positive-fixnum = 2^60-1.
(in-package :cl-user)

(defun ash16 (x)
  (declare (type (signed-byte 45) x))
  (declare (optimize (speed 3) (safety 0)))
  (ash x 16))

(format t "~&ash16 (2^45-1)  = ~s  expected ~s~%"
        (ash16 (1- (expt 2 45)))
        (ash (1- (expt 2 45)) 16))
(format t "~&ash16 (2^44)     = ~s  expected ~s~%"
        (ash16 (expt 2 44))
        (ash (expt 2 44) 16))
(format t "~&ash16 (2^44-1)   = ~s  expected ~s~%"
        (ash16 (1- (expt 2 44)))
        (ash (1- (expt 2 44)) 16))
(format t "~&ash16 (- (2^44)) = ~s  expected ~s~%"
        (ash16 (- (expt 2 44)))
        (ash (- (expt 2 44)) 16))

(defun ash1 (x)
  (declare (type (signed-byte 60) x))
  (declare (optimize (speed 3) (safety 0)))
  (ash x 1))

(format t "~&ash1 (2^59)      = ~s  expected ~s~%"
        (ash1 (expt 2 59))
        (ash (expt 2 59) 1))

;;; same through the mul2 -> ash rewrite: (* x 65536) with (signed-byte 45)
(defun mul65536 (x)
  (declare (type (signed-byte 45) x))
  (declare (optimize (speed 3) (safety 0)))
  (* x 65536))

(format t "~&mul65536 (2^45-1) = ~s  expected ~s~%"
        (mul65536 (1- (expt 2 45)))
        (* (1- (expt 2 45)) 65536))

;;; through an ACL2-shaped integer-range declaration instead of signed-byte
(defun ash16b (x)
  (declare (type (integer -35184372088832 35184372088831) x))
  (declare (optimize (speed 3) (safety 0)))
  (ash x 16))

(format t "~&ash16b (2^45-1) = ~s  expected ~s~%"
        (ash16b (1- (expt 2 45)))
        (ash (1- (expt 2 45)) 16))

;;; control: at safety 3 (no trust-declarations) it is correct
(defun ash16-safe (x)
  (declare (type (signed-byte 45) x))
  (declare (optimize (speed 3) (safety 3)))
  (ash x 16))

(format t "~&ash16-safe (2^45-1) = ~s  expected ~s~%"
        (ash16-safe (1- (expt 2 45)))
        (ash (1- (expt 2 45)) 16))

(quit)
