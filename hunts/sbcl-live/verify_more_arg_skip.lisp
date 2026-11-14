(declaim (muffle-conditions sb-ext:compiler-note style-warning))

(declaim (notinline sink))
(defun sink (x) x)

(format t "=== Testing PURE ANSI Common Lisp (zero declarations, default policy) ===~%")
(defun crash-default (p0 p1 p2 p3 p4 p5 p6 p7 p8 p9 &rest r)
  (multiple-value-prog1
      (values-list (cdr r))
    (sink (list p0 p1 p2 p3 p4 p5))))

(disassemble #'crash-default)

(handler-case
    (format t "Result: ~S~%"
            (multiple-value-list
             (crash-default 0 1 2 3 4 5 6 7 8 9 :skip-me :keep-1 :keep-2)))
  (error (e)
    (format t "CAUGHT CONDITION AT DEFAULT POLICY: ~A (~S)~%" e (type-of e))))

(format t "~%=== Search minimal pure ANSI reproducer (zero declarations!) ===~%")
(block search-min
  (dotimes (nprefix 12)
    (dotimes (nkeep (1+ nprefix))
      (let* ((pvars (loop for i below nprefix collect (intern (format nil "A~D" i))))
             (kvars (subseq pvars 0 nkeep))
             (fn (compile nil
                   `(lambda (,@pvars &rest r)
                      (multiple-value-prog1
                          (values-list (cdr r))
                        (sink (list ,@kvars))))))
             (dis (with-output-to-string (s) (disassemble fn :stream s))))
        (when (and (search "XOR ECX, ECX" dis)
                   (search "[RCX-8]" dis))
          (format t "MINIMAL ZERO-DECL HIT: nprefix=~D nkeep=~D~%~A~%" nprefix nkeep dis)
          (handler-case
              (let ((res (multiple-value-list
                          (apply fn (append (loop for i below nprefix collect i)
                                            (list :first :second :third))))))
                (format t "Returned: ~S~%" res))
            (error (e)
              (format t "CRASHED WITH: ~A (~S)~%" e (type-of e))))
          (return-from search-min t))))))
