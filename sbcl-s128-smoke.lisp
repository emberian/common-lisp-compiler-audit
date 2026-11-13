(sb-ext:unlock-package "SB-VM")

(defpackage "COMPILER-AUDIT"
  (:use "CL"))
(in-package "COMPILER-AUDIT")

(defun modular-ash (x count)
  (declare (type (signed-byte 128) x)
           (type fixnum count)
           (optimize (speed 3) (safety 0)))
  (sb-c::mask-signed-field 62 (ash x count)))

(defun modular-ash-into (x count)
  (declare (type (signed-byte 128) x)
           (type fixnum count)
           (optimize (speed 3) (safety 0)))
  (sb-vm::ash-modfx x count))

(compile 'modular-ash)
(compile 'modular-ash-into)

(let ((failures 0))
  (dolist (x (list (ash 1 65) (- (ash 1 65))
                   (1- (ash 1 64)) (- (1- (ash 1 64)))
                   (ash 1 63) (- (ash 1 63))
                   (ash 3 62) (- (ash 3 62))))
    (dolist (count '(-64 -63 -3 -2 -1 1 2 3 63 64))
      (let ((expected (sb-c::mask-signed-field sb-vm:n-fixnum-bits (ash x count)))
            (actual (modular-ash-into x count)))
        (unless (eql expected actual)
          (incf failures)
          (format t "~s x=~s count=~s expected=~s actual=~s~%"
                  'mismatch x count expected actual)))))
  (format t "~s~%" (list :failures failures)))
