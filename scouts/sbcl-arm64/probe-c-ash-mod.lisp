;; Probe C: modular ash (ash-into-word-mod / ash-mod64) with s128-derived x
;; (fixed post-2.6.10 by 076335724 "Don't transform s128 to ash-into-word-mod")
(load (merge-pathnames "harness.lisp" *load-truename*))

(defparameter *mask* 18446744073709551615) ; 2^64-1

(defun try-c (name body ref-body xvars vals-list)
  (format t "--- ~a ---~%" name)
  (handler-case
      (let* ((vars xvars)
             (f (compile nil `(lambda ,vars
                                (declare (optimize (speed 3) (safety 0))
                                         ,@(mapcar (lambda (v ty) `(type ,ty ,v))
                                                   vars (mapcar #'car vals-list)))
                                ,body)))
             (g (compile nil `(lambda ,vars
                                (declare (optimize (speed 3) (safety 0))
                                         ,@(mapcar (lambda (v ty) `(type ,ty ,v))
                                                   vars (mapcar #'car vals-list)))
                                (locally (declare (notinline ash logand + - * lognot))
                                  ,ref-body)))))
        (dolist (args (mapcar #'cdr vals-list))
          (let ((r1 (multiple-value-list (ignore-errors (apply f args))))
                (r2 (multiple-value-list (ignore-errors (apply g args)))))
            (unless (equalp r1 r2)
              (format t "DIVERGE ~a args=~s inline=~s ref=~s~%" name args r1 r2))))
        (format t "  ran~%"))
    (error (e) (format t "  ERROR: ~a~%" e))))

(format t "=== direct driver ===~%")
(flet ((drive (name src src-ref decls args-list)
         (format t "--- ~a ---~%" name)
         (handler-case
             (let ((f (compile nil `(lambda ,(mapcar #'second decls)
                                      (declare (optimize (speed 3) (safety 0)))
                                      (declare ,@(mapcar (lambda (d) `(type ,(first d) ,(second d))) decls))
                                      ,src)))
                   (g (compile nil `(lambda ,(mapcar #'second decls)
                                      (declare (optimize (speed 3) (safety 0)))
                                      (declare ,@(mapcar (lambda (d) `(type ,(first d) ,(second d))) decls))
                                      (locally (declare (notinline ash logand + - * lognot logior)) ,src-ref)))))
               (dolist (args args-list)
                 (let ((r1 (multiple-value-list (ignore-errors (apply f args))))
                       (r2 (multiple-value-list (ignore-errors (apply g args)))))
                   (unless (equalp r1 r2)
                     (format t "DIVERGE ~a args=~s inline=~s ref=~s~%" name args r1 r2))))
               (format t "  ran~%"))
           (error (e) (format t "  ERROR: ~a~%" e)))))
  ;; C1: (+ a b) of two u64 -> s128, variable shift, mask 2^64-1
  (drive 'C1-u64-sum
         '(logand (ash (+ a b) n) 18446744073709551615)
         '(logand (ash (+ a b) n) 18446744073709551615)
         '(((unsigned-byte 64) a) ((unsigned-byte 64) b) (fixnum n))
         '((0 0 5) (1 2 -3) (18446744073709551615 1 -1) (9223372036854775807 9223372036854775807 3)
           (3 5 -65) (3 5 -64) (3 5 -63)))
  ;; C2: same but x declared s128 directly
  (drive 'C2-s128
         '(logand (ash x n) 18446744073709551615)
         '(logand (ash x n) 18446744073709551615)
         '(((signed-byte 128) x) (fixnum n))
         '((0 5) (-1 -3) (170141183460469231731687303715884105727 -1)
           (9223372036854775808 -64) (9223372036854775808 -65) (-9223372036854775809 -1) (5 70)))
  ;; C3: mask-signed-field-ish: logand with (signed) mask, x s128, fixnum tag context
  (drive 'C3-modfx
         '(logand (ash x n) -1)
         '(logand (ash x n) -1)
         '(((signed-byte 128) x) (fixnum n))
         '((0 5) (-1 -3) (170141183460469231731687303715884105727 -1) (5 -65)))
  ;; C4: signed word result: (the fixnum (logand (ash x n) small-mask))
  (drive 'C4-the-fixnum
         '(the fixnum (logand (ash x n) 4611686018427387903))
         '(the fixnum (logand (ash x n) 4611686018427387903))
         '(((signed-byte 128) x) (fixnum n))
         '((0 5) (-1 -3) (5 -65) (9223372036854775808 3)))
  ;; C5: x from (* a b) of two s64
  (drive 'C5-product
         '(logand (ash (* a b) n) 18446744073709551615)
         '(logand (ash (* a b) n) 18446744073709551615)
         '(((signed-byte 64) a) ((signed-byte 64) b) (fixnum n))
         '((3 5 2) (-3 5 -2) (9223372036854775807 9223372036854775807 -1) (3037000500 3037000500 10)))
  ;; C6: u64 array element as x (aref), shift variable
  (drive 'C6-aref
         '(logand (ash (aref v 0) n) 18446744073709551615)
         '(logand (ash (aref v 0) n) 18446744073709551615)
         '(((simple-array (unsigned-byte 64) (4)) v) (fixnum n))
         (list (list (make-array 4 :element-type '(unsigned-byte 64)
                                 :initial-contents '(0 18446744073709551615 9223372036854775808 1))
                     3)
               (list (make-array 4 :element-type '(unsigned-byte 64)
                                 :initial-contents '(0 18446744073709551615 9223372036854775808 1))
                     -3)))
  )
(format t "probe C done~%")
