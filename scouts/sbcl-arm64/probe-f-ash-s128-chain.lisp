;; Probe F: (ash x m) with constant m consumed unboxed (high word / sign),
;; x fixnum. m sweeps 60..127. Consumer can't be folded.
(load (merge-pathnames "harness.lisp" *load-truename*))

(defparameter *xfix* '(0 1 -1 2 -2 3 -3 2305843009213693951
                       4611686018427387902 4611686018427387903
                       -4611686018427387903 -4611686018427387904))

(flet ((drive (m consumer-expr)
         (handler-case
             (let ((f (compile nil `(lambda (x)
                                      (declare (type fixnum x)
                                               (optimize (speed 3) (safety 0)))
                                      (let ((s (ash x ,m))) ,consumer-expr))))
                   (g (compile nil `(lambda (x)
                                      (declare (type fixnum x)
                                               (optimize (speed 3) (safety 0)))
                                      (locally (declare (notinline ash))
                                        (let ((s (ash x ,m))) ,consumer-expr))))))
               (dolist (v *xfix*)
                 (let ((r1 (multiple-value-list (ignore-errors (funcall f v))))
                       (r2 (multiple-value-list (ignore-errors (funcall g v)))))
                   (unless (equalp r1 r2)
                     (format t "DIVERGE m=~d consumer=~s x=~s inline=~s ref=~s~%"
                             m consumer-expr v r1 r2))))
               (format t "  m=~d ok~%" m))
           (error (e) (format t "  m=~d ERROR: ~a~%" m e)))))
  (dolist (m '(60 62 63 64 65 66 67 68 70 80 100 126 127))
    (drive m '(ash s -64))
    (drive m '(ash s -127))
    (drive m '(< s 0))))
(format t "probe F done~%")
