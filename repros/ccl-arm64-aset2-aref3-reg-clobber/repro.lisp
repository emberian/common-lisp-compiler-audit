;;;; CCL 1.14 (ARM64) backend soundness bug:
;;;; `arm642-four-untargeted-reg-forms` (compiler/ARM64/arm642.lisp:3954, copied
;;;; from compiler/ARM/arm2.lisp:3814; contrast correct `cdest` in
;;;; compiler/X86/x862.lisp:4577) checks:
;;;;
;;;;   (unless bdest
;;;;     (when (same-arm64-reg-p ddest breg)   ; <-- BUG: `ddest` instead of `cdest`!
;;;;       (setq breg creg)))
;;;;
;;;; When `bform` (index `i`) is non-trivial/pushed, `cform` (index `j`) is a
;;;; stack-homed lexical variable loaded into `breg` while evaluating `dform`
;;;; (`newval` in 2D `setf aref`, or index `k` in 3D `aref`), `cdest` aliases
;;;; `breg`. Because line 3954 tests `ddest` instead of `cdest`, `breg` is not
;;;; renamed to `creg`, and popping `bform` (`i`) into `breg` overwrites `cdest`
;;;; (`j`) with `i`!
;;;;
;;;; Consequences EVEN AT `(optimize (safety 3) (speed 1))`:
;;;;   1. 2D `(setf (aref arr i j) newval)` silently writes to `arr[i, i]`
;;;;      instead of `arr[i, j]`.
;;;;   2. On a `(5 2)` array with valid in-bounds `(i=4, j=1)`, `(safety 3)`
;;;;      signals a bogus `ARRAY-BOUNDS` error (`4 >= 2`), while `(safety 0)`
;;;;      writes linear element `4*2 + 4 = 12` (out-of-bounds heap corruption!).
;;;;   3. 3D `(aref arr i j k)` silently reads `arr[i, i, k]` instead of
;;;;      `arr[i, j, k]`.

;; 1. 2D (setf (aref ...)) wrong-cell write at (safety 3) (speed 1)
(let ((arr2 (make-array '(2 2) :element-type 'fixnum :initial-element 0))
      (vec  (vector 0 0))
      (f-typed
       (compile nil '(lambda (arr2 vec fn cvar)
                       (declare (optimize (safety 3) (speed 1))
                                (type (simple-array fixnum (2 2)) arr2))
                       (setf (aref arr2 (funcall fn 0) cvar)
                             (setf (svref vec cvar) 99)))))
      (f-untyped
       (compile nil '(lambda (arr2 vec fn cvar)
                       (declare (optimize (safety 3) (speed 1))
                                (notinline aref))
                       (setf (aref arr2 (funcall fn 0) cvar)
                             (setf (svref vec cvar) 99))))))
  (funcall f-typed arr2 vec #'identity 1)
  (format t "~&[1] 2D setf aref at (safety 3)(speed 1), target (0,1)=99:~%")
  (format t "    typed   => arr[0,0]=~D arr[0,1]=~D  (WRONG on CCL arm64: wrote [0,0]!)~%"
          (aref arr2 0 0) (aref arr2 0 1))
  (setf (aref arr2 0 0) 0 (aref arr2 0 1) 0)
  (funcall f-untyped arr2 vec #'identity 1)
  (format t "    untyped => arr[0,0]=~D arr[0,1]=~D  (expected)~%"
          (aref arr2 0 0) (aref arr2 0 1)))

;; 2. Valid in-bounds (i=4, j=1) on a (5 2) array triggers bogus ARRAY-BOUNDS at (safety 3)
(let ((arr5x2 (make-array '(5 2) :element-type 'fixnum :initial-element 0))
      (vec    (vector 0 0))
      (f-safe
       (compile nil '(lambda (arr2 vec fn cvar)
                       (declare (optimize (safety 3) (speed 1))
                                (type (simple-array fixnum (5 2)) arr2))
                       (setf (aref arr2 (funcall fn 4) cvar)
                             (setf (svref vec cvar) 77))))))
  (format t "~%[2] 2D setf aref on (5 2) with valid in-bounds (i=4, j=1) at (safety 3):~%")
  (format t "    typed   => ~S  (expected (:OK 77))~%"
          (handler-case (list :ok (funcall f-safe arr5x2 vec #'identity 1))
            (error (c) (list :err (type-of c) (princ-to-string c))))))

;; 3. 3D (aref ...) wrong-cell read at (safety 3) (speed 1)
(let ((arr3  (make-array '(2 2 2)
                         :initial-contents '(((:a000 :a001) (:a010 :a011))
                                             ((:a100 :a101) (:a110 :a111)))))
      (u8arr (make-array '(2 2) :element-type '(unsigned-byte 8) :initial-element 9))
      (f-read3
       (compile nil '(lambda (arr u8 fn cvar)
                       (declare (optimize (safety 3) (speed 1))
                                (type (simple-array t (2 2 2)) arr)
                                (type (simple-array (unsigned-byte 8) (2 2)) u8))
                       (aref arr (funcall fn 0) cvar
                             (prog1 0
                               (funcall fn 0)
                               (setf (aref u8 0 cvar) 0)))))))
  (format t "~%[3] 3D aref at (safety 3)(speed 1), reading arr[0,1,0]:~%")
  (format t "    typed   => ~S  (expected :A010; CCL arm64 reads arr[0,0,0] = :A000!)~%"
          (funcall f-read3 arr3 u8arr #'identity 1)))

(finish-output)
#+ccl (ccl:quit)
#+sbcl (sb-ext:exit)
