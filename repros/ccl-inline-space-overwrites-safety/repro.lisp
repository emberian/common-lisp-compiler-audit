;;;; CCL 1.14 cross-arch soundness bug:
;;;; `nx1-expand-inline-call` (compiler/nx0.lisp:2450-2455) constructs the
;;;; lexical environment for EVERY inlined user function (`declaim`/`declare`
;;;; `inline` on `defun`, `flet`, or `labels`) with a copy-paste bug:
;;;;
;;;;   (setf (lexenv.mdecls new-env)
;;;;         `((speed . ,(speed-optimize-quantity old-env))
;;;;           (space . ,(space-optimize-quantity old-env))
;;;;           (safety . ,(space-optimize-quantity old-env)) ; <-- BUG: space instead of safety!
;;;;           (compilation-speed . ,(compilation-speed-optimize-quantity old-env))
;;;;           (debug . ,(debug-optimize-quantity old-env))))
;;;;
;;;; Whenever `(space 0)` is active in the caller (including `(optimize (safety 3)
;;;; (speed 3) (space 0))`), the inlined body is silently compiled with
;;;; `(safety 0)` + `(speed 3)` => `nx-reckless-p = T`! All array bounds checks
;;;; and type checks inside inlined functions are silently elided, reading raw
;;;; out-of-bounds heap memory or fabricating bogus tagged pointers.

(declaim (inline inline-svref-helper inline-fixnum-add1))

(defun inline-svref-helper (v i)
  (svref v i))

(defun inline-fixnum-add1 (x)
  (declare (type fixnum x))
  (the fixnum (+ x 1)))

(let ((caller-space1
       (compile nil '(lambda (v i)
                       (declare (optimize (safety 3) (speed 3) (space 1)))
                       (inline-svref-helper v i))))
      (caller-space0
       (compile nil '(lambda (v i)
                       (declare (optimize (safety 3) (speed 3) (space 0)))
                       (inline-svref-helper v i))))
      (flet-space0
       (compile nil '(lambda (v i)
                       (declare (optimize (safety 3) (speed 3) (space 0)))
                       (flet ((local-get (a idx) (svref a idx)))
                         (declare (inline local-get))
                         (local-get v i)))))
      (bad-type-space0
       (compile nil '(lambda (x)
                       (declare (optimize (safety 3) (speed 3) (space 0)))
                       (inline-fixnum-add1 x)))))
  (format t "~&[1] Out-of-bounds (svref #(:a :b) 5) via DEFUN INLINE at (safety 3):~%")
  (format t "    (safety 3)(speed 3)(space 1) => ~S  (expected :ERR)~%"
          (handler-case (progn (funcall caller-space1 (vector :a :b) 5) :ok-no-error!)
            (error (c) (list :err (type-of c)))))
  (format t "    (safety 3)(speed 3)(space 0) => ~S  (BUG on CCL: no bounds check!)~%"
          (handler-case (progn (funcall caller-space0 (vector :a :b) 5) :ok-no-error!)
            (error (c) (list :err (type-of c)))))

  (format t "~%[2] Out-of-bounds (svref #(:a :b) 5) via FLET INLINE at (safety 3)(space 0):~%")
  (format t "    (safety 3)(speed 3)(space 0) => ~S  (BUG on CCL: no bounds check!)~%"
          (handler-case (progn (funcall flet-space0 (vector :a :b) 5) :ok-no-error!)
            (error (c) (list :err (type-of c)))))

  (format t "~%[3] Passing string \"not-a-fixnum\" to (declare (fixnum x)) DEFUN INLINE at (safety 3)(space 0):~%")
  (format t "    (safety 3)(speed 3)(space 0) => ~S  (BUG on CCL: skips type check, fabricates bogus tag!)~%"
          (handler-case
              (let ((res (funcall bad-type-space0 "not-a-fixnum")))
                (list :ok-no-error! :integerp (integerp res) :stringp (stringp res)))
            (error (c) (list :err (type-of c))))))

(finish-output)
#+ccl (ccl:quit)
#+sbcl (sb-ext:exit)
