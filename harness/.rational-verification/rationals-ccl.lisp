(handler-case
    (format t "~a	~s~%" "generated-458"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/= (* (- -1/127) (expt (if (= 0 0) 1 0) n))))) 0 0 0 0)))
  (error ()
    (format t "~a	(:error)~%" "generated-458")))
