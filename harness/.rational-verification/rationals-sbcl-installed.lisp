(handler-case
    (format t "~a	~s~%" "arithmetic-0"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (+ x y))) 0 1 1 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-0")))

(handler-case
    (format t "~a	~s~%" "arithmetic-1"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (+ x y z))) 0 1 1 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-1")))

(handler-case
    (format t "~a	~s~%" "arithmetic-2"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- x))) 0 1 1 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-2")))

(handler-case
    (format t "~a	~s~%" "arithmetic-3"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- x y))) 0 1 1 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-3")))

(handler-case
    (format t "~a	~s~%" "arithmetic-4"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- x y z))) 0 1 1 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-4")))

(handler-case
    (format t "~a	~s~%" "arithmetic-5"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (* x y))) 0 1 1 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-5")))

(handler-case
    (format t "~a	~s~%" "arithmetic-6"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (* x y z))) 0 1 1 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-6")))

(handler-case
    (format t "~a	~s~%" "arithmetic-7"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/ (if (= x 0) 1 x)))) 0 1 1 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-7")))

(handler-case
    (format t "~a	~s~%" "arithmetic-8"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/ x (if (= y 0) 1 y)))) 0 1 1 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-8")))

(handler-case
    (format t "~a	~s~%" "arithmetic-9"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/ x (if (= y 0) 1 y) (if (= z 0) 1 z)))) 0 1 1 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-9")))

(handler-case
    (format t "~a	~s~%" "division-10"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (floor x))) 0 1 1 0)))
  (error ()
    (format t "~a	(:error)~%" "division-10")))

(handler-case
    (format t "~a	~s~%" "division-11"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (floor x (if (= y 0) 1 y)))) 0 1 1 0)))
  (error ()
    (format t "~a	(:error)~%" "division-11")))

(handler-case
    (format t "~a	~s~%" "division-12"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (ceiling x))) 0 1 1 0)))
  (error ()
    (format t "~a	(:error)~%" "division-12")))

(handler-case
    (format t "~a	~s~%" "division-13"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (ceiling x (if (= y 0) 1 y)))) 0 1 1 0)))
  (error ()
    (format t "~a	(:error)~%" "division-13")))

(handler-case
    (format t "~a	~s~%" "division-14"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (truncate x))) 0 1 1 0)))
  (error ()
    (format t "~a	(:error)~%" "division-14")))

(handler-case
    (format t "~a	~s~%" "division-15"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (truncate x (if (= y 0) 1 y)))) 0 1 1 0)))
  (error ()
    (format t "~a	(:error)~%" "division-15")))

(handler-case
    (format t "~a	~s~%" "division-16"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (round x))) 0 1 1 0)))
  (error ()
    (format t "~a	(:error)~%" "division-16")))

(handler-case
    (format t "~a	~s~%" "division-17"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (round x (if (= y 0) 1 y)))) 0 1 1 0)))
  (error ()
    (format t "~a	(:error)~%" "division-17")))

(handler-case
    (format t "~a	~s~%" "remainder-18"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (mod x (if (= y 0) 1 y)))) 0 1 1 0)))
  (error ()
    (format t "~a	(:error)~%" "remainder-18")))

(handler-case
    (format t "~a	~s~%" "remainder-19"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (rem x (if (= y 0) 1 y)))) 0 1 1 0)))
  (error ()
    (format t "~a	(:error)~%" "remainder-19")))

(handler-case
    (format t "~a	~s~%" "arithmetic-20"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (+ x y))) 1 2 3 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-20")))

(handler-case
    (format t "~a	~s~%" "arithmetic-21"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (+ x y z))) 1 2 3 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-21")))

(handler-case
    (format t "~a	~s~%" "arithmetic-22"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- x))) 1 2 3 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-22")))

(handler-case
    (format t "~a	~s~%" "arithmetic-23"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- x y))) 1 2 3 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-23")))

(handler-case
    (format t "~a	~s~%" "arithmetic-24"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- x y z))) 1 2 3 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-24")))

(handler-case
    (format t "~a	~s~%" "arithmetic-25"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (* x y))) 1 2 3 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-25")))

(handler-case
    (format t "~a	~s~%" "arithmetic-26"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (* x y z))) 1 2 3 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-26")))

(handler-case
    (format t "~a	~s~%" "arithmetic-27"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/ (if (= x 0) 1 x)))) 1 2 3 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-27")))

(handler-case
    (format t "~a	~s~%" "arithmetic-28"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/ x (if (= y 0) 1 y)))) 1 2 3 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-28")))

(handler-case
    (format t "~a	~s~%" "arithmetic-29"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/ x (if (= y 0) 1 y) (if (= z 0) 1 z)))) 1 2 3 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-29")))

(handler-case
    (format t "~a	~s~%" "division-30"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (floor x))) 1 2 3 0)))
  (error ()
    (format t "~a	(:error)~%" "division-30")))

(handler-case
    (format t "~a	~s~%" "division-31"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (floor x (if (= y 0) 1 y)))) 1 2 3 0)))
  (error ()
    (format t "~a	(:error)~%" "division-31")))

(handler-case
    (format t "~a	~s~%" "division-32"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (ceiling x))) 1 2 3 0)))
  (error ()
    (format t "~a	(:error)~%" "division-32")))

(handler-case
    (format t "~a	~s~%" "division-33"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (ceiling x (if (= y 0) 1 y)))) 1 2 3 0)))
  (error ()
    (format t "~a	(:error)~%" "division-33")))

(handler-case
    (format t "~a	~s~%" "division-34"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (truncate x))) 1 2 3 0)))
  (error ()
    (format t "~a	(:error)~%" "division-34")))

(handler-case
    (format t "~a	~s~%" "division-35"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (truncate x (if (= y 0) 1 y)))) 1 2 3 0)))
  (error ()
    (format t "~a	(:error)~%" "division-35")))

(handler-case
    (format t "~a	~s~%" "division-36"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (round x))) 1 2 3 0)))
  (error ()
    (format t "~a	(:error)~%" "division-36")))

(handler-case
    (format t "~a	~s~%" "division-37"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (round x (if (= y 0) 1 y)))) 1 2 3 0)))
  (error ()
    (format t "~a	(:error)~%" "division-37")))

(handler-case
    (format t "~a	~s~%" "remainder-38"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (mod x (if (= y 0) 1 y)))) 1 2 3 0)))
  (error ()
    (format t "~a	(:error)~%" "remainder-38")))

(handler-case
    (format t "~a	~s~%" "remainder-39"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (rem x (if (= y 0) 1 y)))) 1 2 3 0)))
  (error ()
    (format t "~a	(:error)~%" "remainder-39")))

(handler-case
    (format t "~a	~s~%" "arithmetic-40"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (+ x y))) -7/2 2 -3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-40")))

(handler-case
    (format t "~a	~s~%" "arithmetic-41"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (+ x y z))) -7/2 2 -3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-41")))

(handler-case
    (format t "~a	~s~%" "arithmetic-42"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- x))) -7/2 2 -3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-42")))

(handler-case
    (format t "~a	~s~%" "arithmetic-43"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- x y))) -7/2 2 -3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-43")))

(handler-case
    (format t "~a	~s~%" "arithmetic-44"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- x y z))) -7/2 2 -3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-44")))

(handler-case
    (format t "~a	~s~%" "arithmetic-45"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (* x y))) -7/2 2 -3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-45")))

(handler-case
    (format t "~a	~s~%" "arithmetic-46"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (* x y z))) -7/2 2 -3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-46")))

(handler-case
    (format t "~a	~s~%" "arithmetic-47"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/ (if (= x 0) 1 x)))) -7/2 2 -3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-47")))

(handler-case
    (format t "~a	~s~%" "arithmetic-48"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/ x (if (= y 0) 1 y)))) -7/2 2 -3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-48")))

(handler-case
    (format t "~a	~s~%" "arithmetic-49"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/ x (if (= y 0) 1 y) (if (= z 0) 1 z)))) -7/2 2 -3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-49")))

(handler-case
    (format t "~a	~s~%" "division-50"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (floor x))) -7/2 2 -3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "division-50")))

(handler-case
    (format t "~a	~s~%" "division-51"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (floor x (if (= y 0) 1 y)))) -7/2 2 -3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "division-51")))

(handler-case
    (format t "~a	~s~%" "division-52"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (ceiling x))) -7/2 2 -3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "division-52")))

(handler-case
    (format t "~a	~s~%" "division-53"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (ceiling x (if (= y 0) 1 y)))) -7/2 2 -3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "division-53")))

(handler-case
    (format t "~a	~s~%" "division-54"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (truncate x))) -7/2 2 -3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "division-54")))

(handler-case
    (format t "~a	~s~%" "division-55"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (truncate x (if (= y 0) 1 y)))) -7/2 2 -3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "division-55")))

(handler-case
    (format t "~a	~s~%" "division-56"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (round x))) -7/2 2 -3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "division-56")))

(handler-case
    (format t "~a	~s~%" "division-57"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (round x (if (= y 0) 1 y)))) -7/2 2 -3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "division-57")))

(handler-case
    (format t "~a	~s~%" "remainder-58"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (mod x (if (= y 0) 1 y)))) -7/2 2 -3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "remainder-58")))

(handler-case
    (format t "~a	~s~%" "remainder-59"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (rem x (if (= y 0) 1 y)))) -7/2 2 -3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "remainder-59")))

(handler-case
    (format t "~a	~s~%" "arithmetic-60"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (+ x y))) 7/2 -2 3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-60")))

(handler-case
    (format t "~a	~s~%" "arithmetic-61"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (+ x y z))) 7/2 -2 3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-61")))

(handler-case
    (format t "~a	~s~%" "arithmetic-62"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- x))) 7/2 -2 3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-62")))

(handler-case
    (format t "~a	~s~%" "arithmetic-63"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- x y))) 7/2 -2 3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-63")))

(handler-case
    (format t "~a	~s~%" "arithmetic-64"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- x y z))) 7/2 -2 3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-64")))

(handler-case
    (format t "~a	~s~%" "arithmetic-65"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (* x y))) 7/2 -2 3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-65")))

(handler-case
    (format t "~a	~s~%" "arithmetic-66"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (* x y z))) 7/2 -2 3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-66")))

(handler-case
    (format t "~a	~s~%" "arithmetic-67"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/ (if (= x 0) 1 x)))) 7/2 -2 3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-67")))

(handler-case
    (format t "~a	~s~%" "arithmetic-68"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/ x (if (= y 0) 1 y)))) 7/2 -2 3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-68")))

(handler-case
    (format t "~a	~s~%" "arithmetic-69"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/ x (if (= y 0) 1 y) (if (= z 0) 1 z)))) 7/2 -2 3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-69")))

(handler-case
    (format t "~a	~s~%" "division-70"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (floor x))) 7/2 -2 3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "division-70")))

(handler-case
    (format t "~a	~s~%" "division-71"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (floor x (if (= y 0) 1 y)))) 7/2 -2 3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "division-71")))

(handler-case
    (format t "~a	~s~%" "division-72"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (ceiling x))) 7/2 -2 3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "division-72")))

(handler-case
    (format t "~a	~s~%" "division-73"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (ceiling x (if (= y 0) 1 y)))) 7/2 -2 3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "division-73")))

(handler-case
    (format t "~a	~s~%" "division-74"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (truncate x))) 7/2 -2 3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "division-74")))

(handler-case
    (format t "~a	~s~%" "division-75"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (truncate x (if (= y 0) 1 y)))) 7/2 -2 3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "division-75")))

(handler-case
    (format t "~a	~s~%" "division-76"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (round x))) 7/2 -2 3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "division-76")))

(handler-case
    (format t "~a	~s~%" "division-77"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (round x (if (= y 0) 1 y)))) 7/2 -2 3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "division-77")))

(handler-case
    (format t "~a	~s~%" "remainder-78"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (mod x (if (= y 0) 1 y)))) 7/2 -2 3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "remainder-78")))

(handler-case
    (format t "~a	~s~%" "remainder-79"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (rem x (if (= y 0) 1 y)))) 7/2 -2 3/2 0)))
  (error ()
    (format t "~a	(:error)~%" "remainder-79")))

(handler-case
    (format t "~a	~s~%" "arithmetic-80"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (+ x y))) -22/7 1/3 -59/21 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-80")))

(handler-case
    (format t "~a	~s~%" "arithmetic-81"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (+ x y z))) -22/7 1/3 -59/21 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-81")))

(handler-case
    (format t "~a	~s~%" "arithmetic-82"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- x))) -22/7 1/3 -59/21 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-82")))

(handler-case
    (format t "~a	~s~%" "arithmetic-83"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- x y))) -22/7 1/3 -59/21 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-83")))

(handler-case
    (format t "~a	~s~%" "arithmetic-84"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- x y z))) -22/7 1/3 -59/21 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-84")))

(handler-case
    (format t "~a	~s~%" "arithmetic-85"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (* x y))) -22/7 1/3 -59/21 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-85")))

(handler-case
    (format t "~a	~s~%" "arithmetic-86"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (* x y z))) -22/7 1/3 -59/21 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-86")))

(handler-case
    (format t "~a	~s~%" "arithmetic-87"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/ (if (= x 0) 1 x)))) -22/7 1/3 -59/21 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-87")))

(handler-case
    (format t "~a	~s~%" "arithmetic-88"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/ x (if (= y 0) 1 y)))) -22/7 1/3 -59/21 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-88")))

(handler-case
    (format t "~a	~s~%" "arithmetic-89"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/ x (if (= y 0) 1 y) (if (= z 0) 1 z)))) -22/7 1/3 -59/21 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-89")))

(handler-case
    (format t "~a	~s~%" "division-90"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (floor x))) -22/7 1/3 -59/21 0)))
  (error ()
    (format t "~a	(:error)~%" "division-90")))

(handler-case
    (format t "~a	~s~%" "division-91"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (floor x (if (= y 0) 1 y)))) -22/7 1/3 -59/21 0)))
  (error ()
    (format t "~a	(:error)~%" "division-91")))

(handler-case
    (format t "~a	~s~%" "division-92"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (ceiling x))) -22/7 1/3 -59/21 0)))
  (error ()
    (format t "~a	(:error)~%" "division-92")))

(handler-case
    (format t "~a	~s~%" "division-93"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (ceiling x (if (= y 0) 1 y)))) -22/7 1/3 -59/21 0)))
  (error ()
    (format t "~a	(:error)~%" "division-93")))

(handler-case
    (format t "~a	~s~%" "division-94"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (truncate x))) -22/7 1/3 -59/21 0)))
  (error ()
    (format t "~a	(:error)~%" "division-94")))

(handler-case
    (format t "~a	~s~%" "division-95"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (truncate x (if (= y 0) 1 y)))) -22/7 1/3 -59/21 0)))
  (error ()
    (format t "~a	(:error)~%" "division-95")))

(handler-case
    (format t "~a	~s~%" "division-96"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (round x))) -22/7 1/3 -59/21 0)))
  (error ()
    (format t "~a	(:error)~%" "division-96")))

(handler-case
    (format t "~a	~s~%" "division-97"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (round x (if (= y 0) 1 y)))) -22/7 1/3 -59/21 0)))
  (error ()
    (format t "~a	(:error)~%" "division-97")))

(handler-case
    (format t "~a	~s~%" "remainder-98"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (mod x (if (= y 0) 1 y)))) -22/7 1/3 -59/21 0)))
  (error ()
    (format t "~a	(:error)~%" "remainder-98")))

(handler-case
    (format t "~a	~s~%" "remainder-99"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (rem x (if (= y 0) 1 y)))) -22/7 1/3 -59/21 0)))
  (error ()
    (format t "~a	(:error)~%" "remainder-99")))

(handler-case
    (format t "~a	~s~%" "arithmetic-100"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (+ x y))) 355/113 -113/355 113256/40115 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-100")))

(handler-case
    (format t "~a	~s~%" "arithmetic-101"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (+ x y z))) 355/113 -113/355 113256/40115 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-101")))

(handler-case
    (format t "~a	~s~%" "arithmetic-102"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- x))) 355/113 -113/355 113256/40115 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-102")))

(handler-case
    (format t "~a	~s~%" "arithmetic-103"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- x y))) 355/113 -113/355 113256/40115 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-103")))

(handler-case
    (format t "~a	~s~%" "arithmetic-104"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- x y z))) 355/113 -113/355 113256/40115 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-104")))

(handler-case
    (format t "~a	~s~%" "arithmetic-105"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (* x y))) 355/113 -113/355 113256/40115 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-105")))

(handler-case
    (format t "~a	~s~%" "arithmetic-106"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (* x y z))) 355/113 -113/355 113256/40115 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-106")))

(handler-case
    (format t "~a	~s~%" "arithmetic-107"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/ (if (= x 0) 1 x)))) 355/113 -113/355 113256/40115 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-107")))

(handler-case
    (format t "~a	~s~%" "arithmetic-108"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/ x (if (= y 0) 1 y)))) 355/113 -113/355 113256/40115 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-108")))

(handler-case
    (format t "~a	~s~%" "arithmetic-109"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/ x (if (= y 0) 1 y) (if (= z 0) 1 z)))) 355/113 -113/355 113256/40115 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-109")))

(handler-case
    (format t "~a	~s~%" "division-110"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (floor x))) 355/113 -113/355 113256/40115 0)))
  (error ()
    (format t "~a	(:error)~%" "division-110")))

(handler-case
    (format t "~a	~s~%" "division-111"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (floor x (if (= y 0) 1 y)))) 355/113 -113/355 113256/40115 0)))
  (error ()
    (format t "~a	(:error)~%" "division-111")))

(handler-case
    (format t "~a	~s~%" "division-112"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (ceiling x))) 355/113 -113/355 113256/40115 0)))
  (error ()
    (format t "~a	(:error)~%" "division-112")))

(handler-case
    (format t "~a	~s~%" "division-113"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (ceiling x (if (= y 0) 1 y)))) 355/113 -113/355 113256/40115 0)))
  (error ()
    (format t "~a	(:error)~%" "division-113")))

(handler-case
    (format t "~a	~s~%" "division-114"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (truncate x))) 355/113 -113/355 113256/40115 0)))
  (error ()
    (format t "~a	(:error)~%" "division-114")))

(handler-case
    (format t "~a	~s~%" "division-115"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (truncate x (if (= y 0) 1 y)))) 355/113 -113/355 113256/40115 0)))
  (error ()
    (format t "~a	(:error)~%" "division-115")))

(handler-case
    (format t "~a	~s~%" "division-116"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (round x))) 355/113 -113/355 113256/40115 0)))
  (error ()
    (format t "~a	(:error)~%" "division-116")))

(handler-case
    (format t "~a	~s~%" "division-117"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (round x (if (= y 0) 1 y)))) 355/113 -113/355 113256/40115 0)))
  (error ()
    (format t "~a	(:error)~%" "division-117")))

(handler-case
    (format t "~a	~s~%" "remainder-118"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (mod x (if (= y 0) 1 y)))) 355/113 -113/355 113256/40115 0)))
  (error ()
    (format t "~a	(:error)~%" "remainder-118")))

(handler-case
    (format t "~a	~s~%" "remainder-119"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (rem x (if (= y 0) 1 y)))) 355/113 -113/355 113256/40115 0)))
  (error ()
    (format t "~a	(:error)~%" "remainder-119")))

(handler-case
    (format t "~a	~s~%" "arithmetic-120"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (+ x y))) 10000000000000000000000000000000000000001 -3 9999999999999999999999999999999999999998 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-120")))

(handler-case
    (format t "~a	~s~%" "arithmetic-121"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (+ x y z))) 10000000000000000000000000000000000000001 -3 9999999999999999999999999999999999999998 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-121")))

(handler-case
    (format t "~a	~s~%" "arithmetic-122"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- x))) 10000000000000000000000000000000000000001 -3 9999999999999999999999999999999999999998 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-122")))

(handler-case
    (format t "~a	~s~%" "arithmetic-123"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- x y))) 10000000000000000000000000000000000000001 -3 9999999999999999999999999999999999999998 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-123")))

(handler-case
    (format t "~a	~s~%" "arithmetic-124"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- x y z))) 10000000000000000000000000000000000000001 -3 9999999999999999999999999999999999999998 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-124")))

(handler-case
    (format t "~a	~s~%" "arithmetic-125"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (* x y))) 10000000000000000000000000000000000000001 -3 9999999999999999999999999999999999999998 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-125")))

(handler-case
    (format t "~a	~s~%" "arithmetic-126"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (* x y z))) 10000000000000000000000000000000000000001 -3 9999999999999999999999999999999999999998 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-126")))

(handler-case
    (format t "~a	~s~%" "arithmetic-127"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/ (if (= x 0) 1 x)))) 10000000000000000000000000000000000000001 -3 9999999999999999999999999999999999999998 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-127")))

(handler-case
    (format t "~a	~s~%" "arithmetic-128"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/ x (if (= y 0) 1 y)))) 10000000000000000000000000000000000000001 -3 9999999999999999999999999999999999999998 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-128")))

(handler-case
    (format t "~a	~s~%" "arithmetic-129"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/ x (if (= y 0) 1 y) (if (= z 0) 1 z)))) 10000000000000000000000000000000000000001 -3 9999999999999999999999999999999999999998 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-129")))

(handler-case
    (format t "~a	~s~%" "division-130"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (floor x))) 10000000000000000000000000000000000000001 -3 9999999999999999999999999999999999999998 0)))
  (error ()
    (format t "~a	(:error)~%" "division-130")))

(handler-case
    (format t "~a	~s~%" "division-131"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (floor x (if (= y 0) 1 y)))) 10000000000000000000000000000000000000001 -3 9999999999999999999999999999999999999998 0)))
  (error ()
    (format t "~a	(:error)~%" "division-131")))

(handler-case
    (format t "~a	~s~%" "division-132"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (ceiling x))) 10000000000000000000000000000000000000001 -3 9999999999999999999999999999999999999998 0)))
  (error ()
    (format t "~a	(:error)~%" "division-132")))

(handler-case
    (format t "~a	~s~%" "division-133"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (ceiling x (if (= y 0) 1 y)))) 10000000000000000000000000000000000000001 -3 9999999999999999999999999999999999999998 0)))
  (error ()
    (format t "~a	(:error)~%" "division-133")))

(handler-case
    (format t "~a	~s~%" "division-134"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (truncate x))) 10000000000000000000000000000000000000001 -3 9999999999999999999999999999999999999998 0)))
  (error ()
    (format t "~a	(:error)~%" "division-134")))

(handler-case
    (format t "~a	~s~%" "division-135"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (truncate x (if (= y 0) 1 y)))) 10000000000000000000000000000000000000001 -3 9999999999999999999999999999999999999998 0)))
  (error ()
    (format t "~a	(:error)~%" "division-135")))

(handler-case
    (format t "~a	~s~%" "division-136"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (round x))) 10000000000000000000000000000000000000001 -3 9999999999999999999999999999999999999998 0)))
  (error ()
    (format t "~a	(:error)~%" "division-136")))

(handler-case
    (format t "~a	~s~%" "division-137"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (round x (if (= y 0) 1 y)))) 10000000000000000000000000000000000000001 -3 9999999999999999999999999999999999999998 0)))
  (error ()
    (format t "~a	(:error)~%" "division-137")))

(handler-case
    (format t "~a	~s~%" "remainder-138"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (mod x (if (= y 0) 1 y)))) 10000000000000000000000000000000000000001 -3 9999999999999999999999999999999999999998 0)))
  (error ()
    (format t "~a	(:error)~%" "remainder-138")))

(handler-case
    (format t "~a	~s~%" "remainder-139"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (rem x (if (= y 0) 1 y)))) 10000000000000000000000000000000000000001 -3 9999999999999999999999999999999999999998 0)))
  (error ()
    (format t "~a	(:error)~%" "remainder-139")))

(handler-case
    (format t "~a	~s~%" "arithmetic-140"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (+ x y))) 0 -5/7 -5/7 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-140")))

(handler-case
    (format t "~a	~s~%" "arithmetic-141"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (+ x y z))) 0 -5/7 -5/7 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-141")))

(handler-case
    (format t "~a	~s~%" "arithmetic-142"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- x))) 0 -5/7 -5/7 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-142")))

(handler-case
    (format t "~a	~s~%" "arithmetic-143"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- x y))) 0 -5/7 -5/7 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-143")))

(handler-case
    (format t "~a	~s~%" "arithmetic-144"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- x y z))) 0 -5/7 -5/7 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-144")))

(handler-case
    (format t "~a	~s~%" "arithmetic-145"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (* x y))) 0 -5/7 -5/7 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-145")))

(handler-case
    (format t "~a	~s~%" "arithmetic-146"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (* x y z))) 0 -5/7 -5/7 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-146")))

(handler-case
    (format t "~a	~s~%" "arithmetic-147"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/ (if (= x 0) 1 x)))) 0 -5/7 -5/7 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-147")))

(handler-case
    (format t "~a	~s~%" "arithmetic-148"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/ x (if (= y 0) 1 y)))) 0 -5/7 -5/7 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-148")))

(handler-case
    (format t "~a	~s~%" "arithmetic-149"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/ x (if (= y 0) 1 y) (if (= z 0) 1 z)))) 0 -5/7 -5/7 0)))
  (error ()
    (format t "~a	(:error)~%" "arithmetic-149")))

(handler-case
    (format t "~a	~s~%" "division-150"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (floor x))) 0 -5/7 -5/7 0)))
  (error ()
    (format t "~a	(:error)~%" "division-150")))

(handler-case
    (format t "~a	~s~%" "division-151"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (floor x (if (= y 0) 1 y)))) 0 -5/7 -5/7 0)))
  (error ()
    (format t "~a	(:error)~%" "division-151")))

(handler-case
    (format t "~a	~s~%" "division-152"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (ceiling x))) 0 -5/7 -5/7 0)))
  (error ()
    (format t "~a	(:error)~%" "division-152")))

(handler-case
    (format t "~a	~s~%" "division-153"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (ceiling x (if (= y 0) 1 y)))) 0 -5/7 -5/7 0)))
  (error ()
    (format t "~a	(:error)~%" "division-153")))

(handler-case
    (format t "~a	~s~%" "division-154"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (truncate x))) 0 -5/7 -5/7 0)))
  (error ()
    (format t "~a	(:error)~%" "division-154")))

(handler-case
    (format t "~a	~s~%" "division-155"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (truncate x (if (= y 0) 1 y)))) 0 -5/7 -5/7 0)))
  (error ()
    (format t "~a	(:error)~%" "division-155")))

(handler-case
    (format t "~a	~s~%" "division-156"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (round x))) 0 -5/7 -5/7 0)))
  (error ()
    (format t "~a	(:error)~%" "division-156")))

(handler-case
    (format t "~a	~s~%" "division-157"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (round x (if (= y 0) 1 y)))) 0 -5/7 -5/7 0)))
  (error ()
    (format t "~a	(:error)~%" "division-157")))

(handler-case
    (format t "~a	~s~%" "remainder-158"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (mod x (if (= y 0) 1 y)))) 0 -5/7 -5/7 0)))
  (error ()
    (format t "~a	(:error)~%" "remainder-158")))

(handler-case
    (format t "~a	~s~%" "remainder-159"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (rem x (if (= y 0) 1 y)))) 0 -5/7 -5/7 0)))
  (error ()
    (format t "~a	(:error)~%" "remainder-159")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-160"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (numerator x))) 0 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-160")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-161"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (denominator x))) 0 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-161")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-162"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (signum x))) 0 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-162")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-163"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (abs x))) 0 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-163")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-164"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (numerator x))) 1 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-164")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-165"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (denominator x))) 1 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-165")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-166"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (signum x))) 1 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-166")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-167"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (abs x))) 1 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-167")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-168"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (numerator x))) -1 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-168")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-169"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (denominator x))) -1 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-169")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-170"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (signum x))) -1 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-170")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-171"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (abs x))) -1 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-171")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-172"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (numerator x))) 2 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-172")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-173"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (denominator x))) 2 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-173")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-174"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (signum x))) 2 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-174")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-175"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (abs x))) 2 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-175")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-176"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (numerator x))) -2 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-176")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-177"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (denominator x))) -2 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-177")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-178"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (signum x))) -2 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-178")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-179"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (abs x))) -2 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-179")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-180"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (numerator x))) 1/2 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-180")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-181"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (denominator x))) 1/2 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-181")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-182"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (signum x))) 1/2 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-182")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-183"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (abs x))) 1/2 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-183")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-184"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (numerator x))) -1/2 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-184")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-185"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (denominator x))) -1/2 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-185")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-186"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (signum x))) -1/2 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-186")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-187"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (abs x))) -1/2 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-187")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-188"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (numerator x))) 7/2 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-188")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-189"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (denominator x))) 7/2 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-189")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-190"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (signum x))) 7/2 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-190")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-191"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (abs x))) 7/2 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-191")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-192"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (numerator x))) -7/2 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-192")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-193"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (denominator x))) -7/2 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-193")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-194"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (signum x))) -7/2 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-194")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-195"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (abs x))) -7/2 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-195")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-196"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (numerator x))) 22/7 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-196")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-197"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (denominator x))) 22/7 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-197")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-198"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (signum x))) 22/7 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-198")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-199"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (abs x))) 22/7 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-199")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-200"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (numerator x))) -22/7 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-200")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-201"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (denominator x))) -22/7 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-201")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-202"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (signum x))) -22/7 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-202")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-203"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (abs x))) -22/7 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-203")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-204"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (numerator x))) 355/113 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-204")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-205"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (denominator x))) 355/113 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-205")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-206"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (signum x))) 355/113 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-206")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-207"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (abs x))) 355/113 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-207")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-208"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (numerator x))) -355/113 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-208")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-209"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (denominator x))) -355/113 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-209")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-210"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (signum x))) -355/113 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-210")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-211"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (abs x))) -355/113 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-211")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-212"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (numerator x))) 10000000000000000000000000000000000000001 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-212")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-213"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (denominator x))) 10000000000000000000000000000000000000001 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-213")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-214"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (signum x))) 10000000000000000000000000000000000000001 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-214")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-215"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (abs x))) 10000000000000000000000000000000000000001 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-215")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-216"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (numerator x))) -10000000000000000000000000000000000000001 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-216")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-217"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (denominator x))) -10000000000000000000000000000000000000001 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-217")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-218"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (signum x))) -10000000000000000000000000000000000000001 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-218")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-219"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (abs x))) -10000000000000000000000000000000000000001 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-219")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-220"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (numerator x))) 10000000000000000000000000000000000000001/113 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-220")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-221"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (denominator x))) 10000000000000000000000000000000000000001/113 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-221")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-222"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (signum x))) 10000000000000000000000000000000000000001/113 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-222")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-223"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (abs x))) 10000000000000000000000000000000000000001/113 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-223")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-224"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (numerator x))) -10000000000000000000000000000000000000001/113 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-224")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-225"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (denominator x))) -10000000000000000000000000000000000000001/113 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-225")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-226"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (signum x))) -10000000000000000000000000000000000000001/113 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-226")))

(handler-case
    (format t "~a	~s~%" "parts-sign-abs-227"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (abs x))) -10000000000000000000000000000000000000001/113 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "parts-sign-abs-227")))

(handler-case
    (format t "~a	~s~%" "comparisons-228"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (= x y z))) 0 0 0 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-228")))

(handler-case
    (format t "~a	~s~%" "comparisons-229"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/= x y z))) 0 0 0 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-229")))

(handler-case
    (format t "~a	~s~%" "comparisons-230"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (< x y z))) 0 0 0 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-230")))

(handler-case
    (format t "~a	~s~%" "comparisons-231"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (> x y z))) 0 0 0 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-231")))

(handler-case
    (format t "~a	~s~%" "comparisons-232"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (<= x y z))) 0 0 0 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-232")))

(handler-case
    (format t "~a	~s~%" "comparisons-233"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (>= x y z))) 0 0 0 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-233")))

(handler-case
    (format t "~a	~s~%" "max-min-234"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (max x))) 0 0 0 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-234")))

(handler-case
    (format t "~a	~s~%" "max-min-235"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (max x y))) 0 0 0 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-235")))

(handler-case
    (format t "~a	~s~%" "max-min-236"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (max x y z))) 0 0 0 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-236")))

(handler-case
    (format t "~a	~s~%" "max-min-237"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (min x))) 0 0 0 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-237")))

(handler-case
    (format t "~a	~s~%" "max-min-238"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (min x y))) 0 0 0 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-238")))

(handler-case
    (format t "~a	~s~%" "max-min-239"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (min x y z))) 0 0 0 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-239")))

(handler-case
    (format t "~a	~s~%" "comparisons-240"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (= x y z))) -1/2 0 1/2 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-240")))

(handler-case
    (format t "~a	~s~%" "comparisons-241"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/= x y z))) -1/2 0 1/2 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-241")))

(handler-case
    (format t "~a	~s~%" "comparisons-242"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (< x y z))) -1/2 0 1/2 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-242")))

(handler-case
    (format t "~a	~s~%" "comparisons-243"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (> x y z))) -1/2 0 1/2 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-243")))

(handler-case
    (format t "~a	~s~%" "comparisons-244"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (<= x y z))) -1/2 0 1/2 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-244")))

(handler-case
    (format t "~a	~s~%" "comparisons-245"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (>= x y z))) -1/2 0 1/2 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-245")))

(handler-case
    (format t "~a	~s~%" "max-min-246"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (max x))) -1/2 0 1/2 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-246")))

(handler-case
    (format t "~a	~s~%" "max-min-247"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (max x y))) -1/2 0 1/2 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-247")))

(handler-case
    (format t "~a	~s~%" "max-min-248"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (max x y z))) -1/2 0 1/2 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-248")))

(handler-case
    (format t "~a	~s~%" "max-min-249"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (min x))) -1/2 0 1/2 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-249")))

(handler-case
    (format t "~a	~s~%" "max-min-250"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (min x y))) -1/2 0 1/2 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-250")))

(handler-case
    (format t "~a	~s~%" "max-min-251"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (min x y z))) -1/2 0 1/2 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-251")))

(handler-case
    (format t "~a	~s~%" "comparisons-252"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (= x y z))) 1/3 1/3 2/3 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-252")))

(handler-case
    (format t "~a	~s~%" "comparisons-253"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/= x y z))) 1/3 1/3 2/3 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-253")))

(handler-case
    (format t "~a	~s~%" "comparisons-254"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (< x y z))) 1/3 1/3 2/3 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-254")))

(handler-case
    (format t "~a	~s~%" "comparisons-255"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (> x y z))) 1/3 1/3 2/3 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-255")))

(handler-case
    (format t "~a	~s~%" "comparisons-256"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (<= x y z))) 1/3 1/3 2/3 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-256")))

(handler-case
    (format t "~a	~s~%" "comparisons-257"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (>= x y z))) 1/3 1/3 2/3 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-257")))

(handler-case
    (format t "~a	~s~%" "max-min-258"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (max x))) 1/3 1/3 2/3 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-258")))

(handler-case
    (format t "~a	~s~%" "max-min-259"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (max x y))) 1/3 1/3 2/3 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-259")))

(handler-case
    (format t "~a	~s~%" "max-min-260"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (max x y z))) 1/3 1/3 2/3 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-260")))

(handler-case
    (format t "~a	~s~%" "max-min-261"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (min x))) 1/3 1/3 2/3 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-261")))

(handler-case
    (format t "~a	~s~%" "max-min-262"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (min x y))) 1/3 1/3 2/3 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-262")))

(handler-case
    (format t "~a	~s~%" "max-min-263"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (min x y z))) 1/3 1/3 2/3 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-263")))

(handler-case
    (format t "~a	~s~%" "comparisons-264"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (= x y z))) 2/3 1/3 1/3 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-264")))

(handler-case
    (format t "~a	~s~%" "comparisons-265"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/= x y z))) 2/3 1/3 1/3 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-265")))

(handler-case
    (format t "~a	~s~%" "comparisons-266"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (< x y z))) 2/3 1/3 1/3 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-266")))

(handler-case
    (format t "~a	~s~%" "comparisons-267"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (> x y z))) 2/3 1/3 1/3 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-267")))

(handler-case
    (format t "~a	~s~%" "comparisons-268"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (<= x y z))) 2/3 1/3 1/3 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-268")))

(handler-case
    (format t "~a	~s~%" "comparisons-269"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (>= x y z))) 2/3 1/3 1/3 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-269")))

(handler-case
    (format t "~a	~s~%" "max-min-270"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (max x))) 2/3 1/3 1/3 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-270")))

(handler-case
    (format t "~a	~s~%" "max-min-271"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (max x y))) 2/3 1/3 1/3 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-271")))

(handler-case
    (format t "~a	~s~%" "max-min-272"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (max x y z))) 2/3 1/3 1/3 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-272")))

(handler-case
    (format t "~a	~s~%" "max-min-273"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (min x))) 2/3 1/3 1/3 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-273")))

(handler-case
    (format t "~a	~s~%" "max-min-274"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (min x y))) 2/3 1/3 1/3 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-274")))

(handler-case
    (format t "~a	~s~%" "max-min-275"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (min x y z))) 2/3 1/3 1/3 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-275")))

(handler-case
    (format t "~a	~s~%" "comparisons-276"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (= x y z))) -2 -1/2 -1/3 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-276")))

(handler-case
    (format t "~a	~s~%" "comparisons-277"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/= x y z))) -2 -1/2 -1/3 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-277")))

(handler-case
    (format t "~a	~s~%" "comparisons-278"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (< x y z))) -2 -1/2 -1/3 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-278")))

(handler-case
    (format t "~a	~s~%" "comparisons-279"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (> x y z))) -2 -1/2 -1/3 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-279")))

(handler-case
    (format t "~a	~s~%" "comparisons-280"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (<= x y z))) -2 -1/2 -1/3 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-280")))

(handler-case
    (format t "~a	~s~%" "comparisons-281"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (>= x y z))) -2 -1/2 -1/3 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-281")))

(handler-case
    (format t "~a	~s~%" "max-min-282"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (max x))) -2 -1/2 -1/3 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-282")))

(handler-case
    (format t "~a	~s~%" "max-min-283"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (max x y))) -2 -1/2 -1/3 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-283")))

(handler-case
    (format t "~a	~s~%" "max-min-284"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (max x y z))) -2 -1/2 -1/3 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-284")))

(handler-case
    (format t "~a	~s~%" "max-min-285"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (min x))) -2 -1/2 -1/3 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-285")))

(handler-case
    (format t "~a	~s~%" "max-min-286"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (min x y))) -2 -1/2 -1/3 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-286")))

(handler-case
    (format t "~a	~s~%" "max-min-287"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (min x y z))) -2 -1/2 -1/3 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-287")))

(handler-case
    (format t "~a	~s~%" "comparisons-288"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (= x y z))) 1 2 2 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-288")))

(handler-case
    (format t "~a	~s~%" "comparisons-289"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/= x y z))) 1 2 2 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-289")))

(handler-case
    (format t "~a	~s~%" "comparisons-290"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (< x y z))) 1 2 2 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-290")))

(handler-case
    (format t "~a	~s~%" "comparisons-291"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (> x y z))) 1 2 2 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-291")))

(handler-case
    (format t "~a	~s~%" "comparisons-292"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (<= x y z))) 1 2 2 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-292")))

(handler-case
    (format t "~a	~s~%" "comparisons-293"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (>= x y z))) 1 2 2 0)))
  (error ()
    (format t "~a	(:error)~%" "comparisons-293")))

(handler-case
    (format t "~a	~s~%" "max-min-294"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (max x))) 1 2 2 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-294")))

(handler-case
    (format t "~a	~s~%" "max-min-295"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (max x y))) 1 2 2 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-295")))

(handler-case
    (format t "~a	~s~%" "max-min-296"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (max x y z))) 1 2 2 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-296")))

(handler-case
    (format t "~a	~s~%" "max-min-297"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (min x))) 1 2 2 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-297")))

(handler-case
    (format t "~a	~s~%" "max-min-298"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (min x y))) 1 2 2 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-298")))

(handler-case
    (format t "~a	~s~%" "max-min-299"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (min x y z))) 1 2 2 0)))
  (error ()
    (format t "~a	(:error)~%" "max-min-299")))

(handler-case
    (format t "~a	~s~%" "expt-300"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt (if (= x 0) 1 x) n))) 0 1 -1 -4)))
  (error ()
    (format t "~a	(:error)~%" "expt-300")))

(handler-case
    (format t "~a	~s~%" "expt-301"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt (if (= x 0) 1 x) n))) 0 1 -1 -1)))
  (error ()
    (format t "~a	(:error)~%" "expt-301")))

(handler-case
    (format t "~a	~s~%" "expt-302"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) 0 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "expt-302")))

(handler-case
    (format t "~a	~s~%" "expt-303"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) 0 1 -1 1)))
  (error ()
    (format t "~a	(:error)~%" "expt-303")))

(handler-case
    (format t "~a	~s~%" "expt-304"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) 0 1 -1 2)))
  (error ()
    (format t "~a	(:error)~%" "expt-304")))

(handler-case
    (format t "~a	~s~%" "expt-305"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) 0 1 -1 5)))
  (error ()
    (format t "~a	(:error)~%" "expt-305")))

(handler-case
    (format t "~a	~s~%" "expt-306"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) 1 1 -1 -4)))
  (error ()
    (format t "~a	(:error)~%" "expt-306")))

(handler-case
    (format t "~a	~s~%" "expt-307"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) 1 1 -1 -1)))
  (error ()
    (format t "~a	(:error)~%" "expt-307")))

(handler-case
    (format t "~a	~s~%" "expt-308"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) 1 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "expt-308")))

(handler-case
    (format t "~a	~s~%" "expt-309"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) 1 1 -1 1)))
  (error ()
    (format t "~a	(:error)~%" "expt-309")))

(handler-case
    (format t "~a	~s~%" "expt-310"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) 1 1 -1 2)))
  (error ()
    (format t "~a	(:error)~%" "expt-310")))

(handler-case
    (format t "~a	~s~%" "expt-311"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) 1 1 -1 5)))
  (error ()
    (format t "~a	(:error)~%" "expt-311")))

(handler-case
    (format t "~a	~s~%" "expt-312"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) -1 1 -1 -4)))
  (error ()
    (format t "~a	(:error)~%" "expt-312")))

(handler-case
    (format t "~a	~s~%" "expt-313"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) -1 1 -1 -1)))
  (error ()
    (format t "~a	(:error)~%" "expt-313")))

(handler-case
    (format t "~a	~s~%" "expt-314"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) -1 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "expt-314")))

(handler-case
    (format t "~a	~s~%" "expt-315"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) -1 1 -1 1)))
  (error ()
    (format t "~a	(:error)~%" "expt-315")))

(handler-case
    (format t "~a	~s~%" "expt-316"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) -1 1 -1 2)))
  (error ()
    (format t "~a	(:error)~%" "expt-316")))

(handler-case
    (format t "~a	~s~%" "expt-317"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) -1 1 -1 5)))
  (error ()
    (format t "~a	(:error)~%" "expt-317")))

(handler-case
    (format t "~a	~s~%" "expt-318"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) 2 1 -1 -4)))
  (error ()
    (format t "~a	(:error)~%" "expt-318")))

(handler-case
    (format t "~a	~s~%" "expt-319"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) 2 1 -1 -1)))
  (error ()
    (format t "~a	(:error)~%" "expt-319")))

(handler-case
    (format t "~a	~s~%" "expt-320"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) 2 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "expt-320")))

(handler-case
    (format t "~a	~s~%" "expt-321"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) 2 1 -1 1)))
  (error ()
    (format t "~a	(:error)~%" "expt-321")))

(handler-case
    (format t "~a	~s~%" "expt-322"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) 2 1 -1 2)))
  (error ()
    (format t "~a	(:error)~%" "expt-322")))

(handler-case
    (format t "~a	~s~%" "expt-323"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) 2 1 -1 5)))
  (error ()
    (format t "~a	(:error)~%" "expt-323")))

(handler-case
    (format t "~a	~s~%" "expt-324"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) -2/3 1 -1 -4)))
  (error ()
    (format t "~a	(:error)~%" "expt-324")))

(handler-case
    (format t "~a	~s~%" "expt-325"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) -2/3 1 -1 -1)))
  (error ()
    (format t "~a	(:error)~%" "expt-325")))

(handler-case
    (format t "~a	~s~%" "expt-326"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) -2/3 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "expt-326")))

(handler-case
    (format t "~a	~s~%" "expt-327"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) -2/3 1 -1 1)))
  (error ()
    (format t "~a	(:error)~%" "expt-327")))

(handler-case
    (format t "~a	~s~%" "expt-328"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) -2/3 1 -1 2)))
  (error ()
    (format t "~a	(:error)~%" "expt-328")))

(handler-case
    (format t "~a	~s~%" "expt-329"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) -2/3 1 -1 5)))
  (error ()
    (format t "~a	(:error)~%" "expt-329")))

(handler-case
    (format t "~a	~s~%" "expt-330"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) 355/113 1 -1 -4)))
  (error ()
    (format t "~a	(:error)~%" "expt-330")))

(handler-case
    (format t "~a	~s~%" "expt-331"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) 355/113 1 -1 -1)))
  (error ()
    (format t "~a	(:error)~%" "expt-331")))

(handler-case
    (format t "~a	~s~%" "expt-332"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) 355/113 1 -1 0)))
  (error ()
    (format t "~a	(:error)~%" "expt-332")))

(handler-case
    (format t "~a	~s~%" "expt-333"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) 355/113 1 -1 1)))
  (error ()
    (format t "~a	(:error)~%" "expt-333")))

(handler-case
    (format t "~a	~s~%" "expt-334"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) 355/113 1 -1 2)))
  (error ()
    (format t "~a	(:error)~%" "expt-334")))

(handler-case
    (format t "~a	~s~%" "expt-335"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt x n))) 355/113 1 -1 5)))
  (error ()
    (format t "~a	(:error)~%" "expt-335")))

(handler-case
    (format t "~a	~s~%" "values-control-guards-336"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (values))) -7/2 0 5/3 1)))
  (error ()
    (format t "~a	(:error)~%" "values-control-guards-336")))

(handler-case
    (format t "~a	~s~%" "values-control-guards-337"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (values x))) -7/2 0 5/3 1)))
  (error ()
    (format t "~a	(:error)~%" "values-control-guards-337")))

(handler-case
    (format t "~a	~s~%" "values-control-guards-338"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (values x y z))) -7/2 0 5/3 1)))
  (error ()
    (format t "~a	(:error)~%" "values-control-guards-338")))

(handler-case
    (format t "~a	~s~%" "values-control-guards-339"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (multiple-value-list (values x z)))) -7/2 0 5/3 1)))
  (error ()
    (format t "~a	(:error)~%" "values-control-guards-339")))

(handler-case
    (format t "~a	~s~%" "values-control-guards-340"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (nth-value 0 (floor x z)))) -7/2 0 5/3 1)))
  (error ()
    (format t "~a	(:error)~%" "values-control-guards-340")))

(handler-case
    (format t "~a	~s~%" "values-control-guards-341"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (nth-value 1 (floor x z)))) -7/2 0 5/3 1)))
  (error ()
    (format t "~a	(:error)~%" "values-control-guards-341")))

(handler-case
    (format t "~a	~s~%" "values-control-guards-342"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (nth-value 3 (values x z)))) -7/2 0 5/3 1)))
  (error ()
    (format t "~a	(:error)~%" "values-control-guards-342")))

(handler-case
    (format t "~a	~s~%" "values-control-guards-343"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (let ((q (/ x (if (= z 0) 1 z)))) (values q (numerator q) (denominator q))))) -7/2 0 5/3 1)))
  (error ()
    (format t "~a	(:error)~%" "values-control-guards-343")))

(handler-case
    (format t "~a	~s~%" "values-control-guards-344"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/ x (if (= y 0) 1 y)))) -7/2 0 5/3 1)))
  (error ()
    (format t "~a	(:error)~%" "values-control-guards-344")))

(handler-case
    (format t "~a	~s~%" "values-control-guards-345"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt (if (= y 0) 1 y) -2))) -7/2 0 5/3 1)))
  (error ()
    (format t "~a	(:error)~%" "values-control-guards-345")))

(handler-case
    (format t "~a	~s~%" "generated-346"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (+ (round (denominator (expt (if (= z 0) 1 z) n))) (signum (ceiling x (if (= (signum z) 0) 1 (signum z))))))) -22/7 0 -1/2 -3)))
  (error ()
    (format t "~a	(:error)~%" "generated-346")))

(handler-case
    (format t "~a	~s~%" "generated-347"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             0)) -247 11 7/127 2)))
  (error ()
    (format t "~a	(:error)~%" "generated-347")))

(handler-case
    (format t "~a	~s~%" "generated-348"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/= (expt (if (= (- z) 0) 1 (- z)) n) (expt (if (= (- -100000000000000000001/2 -973/127) 0) 1 (- -100000000000000000001/2 -973/127)) n) (- -355/4 (* y y) (+ -1/8 x))))) 473/8 22/7 7/2 3)))
  (error ()
    (format t "~a	(:error)~%" "generated-348")))

(handler-case
    (format t "~a	~s~%" "generated-349"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt (if (= (expt (if (= (if (>= z (- 4/127 y) (/ (if (= z 0) 1 z))) (- y z y) (rem x (if (= x 0) 1 x))) 0) 1 (if (>= z (- 4/127 y) (/ (if (= z 0) 1 z))) (- y z y) (rem x (if (= x 0) 1 x)))) 5) 0) 1 (expt (if (= (if (>= z (- 4/127 y) (/ (if (= z 0) 1 z))) (- y z y) (rem x (if (= x 0) 1 x))) 0) 1 (if (>= z (- 4/127 y) (/ (if (= z 0) 1 z))) (- y z y) (rem x (if (= x 0) 1 x)))) 5)) -6))) -100000000000000000001/3 -725/2 -22/5 -3)))
  (error ()
    (format t "~a	(:error)~%" "generated-349")))

(handler-case
    (format t "~a	~s~%" "generated-350"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/= (- y x) (if (= 1/5 y x) z z) (numerator x)))) -355/113 -373/2 1/7 -6)))
  (error ()
    (format t "~a	(:error)~%" "generated-350")))

(handler-case
    (format t "~a	~s~%" "generated-351"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (values y y))) 22 7/4 100000000000000000001/16 5)))
  (error ()
    (format t "~a	(:error)~%" "generated-351")))

(handler-case
    (format t "~a	~s~%" "generated-352"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             z)) -22/5 22/3 355/8 4)))
  (error ()
    (format t "~a	(:error)~%" "generated-352")))

(handler-case
    (format t "~a	~s~%" "generated-353"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (max (if (< (if (<= (let ((q z)) -7/2)) (max z) (/ (if (= -100000000000000000001/127 0) 1 -100000000000000000001/127))) (+ (denominator x) (* 470/3 -22/127)) (+ (expt (if (= z 0) 1 z) n) 82)) (signum y) (+ (denominator z) (+ y x))) (let ((q x)) 1/4)))) -148 1/7 -2/3 6)))
  (error ()
    (format t "~a	(:error)~%" "generated-353")))

(handler-case
    (format t "~a	~s~%" "generated-354"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- (floor x)))) -2/3 10000000000000000000000000000000000000001/8 -219/8 -2)))
  (error ()
    (format t "~a	(:error)~%" "generated-354")))

(handler-case
    (format t "~a	~s~%" "generated-355"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (> (floor (* y z) (if (= (rem x (if (= z 0) 1 z)) 0) 1 (rem x (if (= z 0) 1 z)))) -916/5 (* (min z -1/5) (let ((q y)) x))))) -394/5 -355 355/16 -1)))
  (error ()
    (format t "~a	(:error)~%" "generated-355")))

(handler-case
    (format t "~a	~s~%" "generated-356"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- (- (expt (if (= -382/7 0) 1 -382/7) 4) (max x x) (/ y (if (= x 0) 1 x) (if (= 100 0) 1 100))) (expt (if (= (expt (if (= 355/4 0) 1 355/4) -1) 0) 1 (expt (if (= 355/4 0) 1 355/4) -1)) -2)))) -1/113 1 -1/2 1)))
  (error ()
    (format t "~a	(:error)~%" "generated-356")))

(handler-case
    (format t "~a	~s~%" "generated-357"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (multiple-value-list (expt (if (= (denominator y) 0) 1 (denominator y)) n)))) 100000000000000000001/3 -133 0 6)))
  (error ()
    (format t "~a	(:error)~%" "generated-357")))

(handler-case
    (format t "~a	~s~%" "generated-358"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (nth-value 2 (denominator (abs (if (< (expt (if (= y 0) 1 y) n) (min x)) (let ((q z)) z) (+ 158 -1/8))))))) 941/4 595/16 -22/3 3)))
  (error ()
    (format t "~a	(:error)~%" "generated-358")))

(handler-case
    (format t "~a	~s~%" "generated-359"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (rem (signum 389/113) (if (= (let ((q 407/113)) 355/127) 0) 1 (let ((q 407/113)) 355/127))))) 57 733 -277/8 -4)))
  (error ()
    (format t "~a	(:error)~%" "generated-359")))

(handler-case
    (format t "~a	~s~%" "generated-360"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             -665/3)) 345 22/127 -1/16 -2)))
  (error ()
    (format t "~a	(:error)~%" "generated-360")))

(handler-case
    (format t "~a	~s~%" "generated-361"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (numerator (max 0 y)))) 100000000000000000001/7 -15/8 10000000000000000000000000000000000000001/127 4)))
  (error ()
    (format t "~a	(:error)~%" "generated-361")))

(handler-case
    (format t "~a	~s~%" "generated-362"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (if (= (let ((q (max y (denominator x)))) (+ -7/4 (mod x (if (= x 0) 1 x)))) (expt (if (= (floor (signum y)) 0) 1 (floor (signum y))) n) 11/4) (- (denominator (- -797/8))) (let ((q (+ -355/8 (expt (if (= z 0) 1 z) n)))) (floor (mod x (if (= z 0) 1 z))))))) 225/127 -7/2 -215/16 -6)))
  (error ()
    (format t "~a	(:error)~%" "generated-362")))

(handler-case
    (format t "~a	~s~%" "generated-363"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (values (truncate x) y))) 7/3 677/7 -1/4 -3)))
  (error ()
    (format t "~a	(:error)~%" "generated-363")))

(handler-case
    (format t "~a	~s~%" "generated-364"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (truncate (* (min (- -1/8 y y)) (signum (/ (if (= z 0) 1 z)))) (if (= (numerator y) 0) 1 (numerator y))))) 71/2 100000000000000000001/5 -979/4 -1)))
  (error ()
    (format t "~a	(:error)~%" "generated-364")))

(handler-case
    (format t "~a	~s~%" "generated-365"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (if (< (/ (if (< (signum 0) (expt (if (= y 0) 1 y) n) (round x)) x (floor -100000000000000000001/3 (if (= y 0) 1 y))) (if (= 1/4 0) 1 1/4))) (mod (rem (if (>= 397) 0 x) (if (= z 0) 1 z)) (if (= (signum (denominator x)) 0) 1 (signum (denominator x)))) (if (> (abs (floor x (if (= x 0) 1 x)))) (+ (round -100000000000000000001/8) (let ((q z)) z)) (ceiling (max x) (if (= (truncate x) 0) 1 (truncate x))))))) 0 -1/3 -11/4 3)))
  (error ()
    (format t "~a	(:error)~%" "generated-365")))

(handler-case
    (format t "~a	~s~%" "generated-366"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt (if (= (mod (* x x) (if (= (denominator 1/113) 0) 1 (denominator 1/113))) 0) 1 (mod (* x x) (if (= (denominator 1/113) 0) 1 (denominator 1/113)))) n))) 861/8 -22/3 -1/8 5)))
  (error ()
    (format t "~a	(:error)~%" "generated-366")))

(handler-case
    (format t "~a	~s~%" "generated-367"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (+ (min x) (expt (if (= 733/113 0) 1 733/113) n)))) 11/4 -22/113 355 -2)))
  (error ()
    (format t "~a	(:error)~%" "generated-367")))

(handler-case
    (format t "~a	~s~%" "generated-368"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (= (expt (if (= (let ((q (rem y (if (= z 0) 1 z)))) (denominator y)) 0) 1 (let ((q (rem y (if (= z 0) 1 z)))) (denominator y))) n) (let ((q (* (abs y) (/ (if (= 100000000000000000001/8 0) 1 100000000000000000001/8))))) 100000000000000000001/4)))) 405/8 0 10000000000000000000000000000000000000001/5 -4)))
  (error ()
    (format t "~a	(:error)~%" "generated-368")))

(handler-case
    (format t "~a	~s~%" "generated-369"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (multiple-value-list (let ((q 100000000000000000001/7)) (expt (if (= (+ 355/113 -22/5) 0) 1 (+ 355/113 -22/5)) -1))))) 2/127 0 -256 -3)))
  (error ()
    (format t "~a	(:error)~%" "generated-369")))

(handler-case
    (format t "~a	~s~%" "generated-370"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (<= (signum (expt (if (= (/ (min -627/7) (if (= (rem x (if (= -611/7 0) 1 -611/7)) 0) 1 (rem x (if (= -611/7 0) 1 -611/7)))) 0) 1 (/ (min -627/7) (if (= (rem x (if (= -611/7 0) 1 -611/7)) 0) 1 (rem x (if (= -611/7 0) 1 -611/7))))) 2)) (mod y (if (= (truncate (round (round z)) (if (= (signum (+ 100000000000000000001/16 11/8)) 0) 1 (signum (+ 100000000000000000001/16 11/8)))) 0) 1 (truncate (round (round z)) (if (= (signum (+ 100000000000000000001/16 11/8)) 0) 1 (signum (+ 100000000000000000001/16 11/8))))))))) 0 284 0 6)))
  (error ()
    (format t "~a	(:error)~%" "generated-370")))

(handler-case
    (format t "~a	~s~%" "generated-371"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (> (* z (rem 28 (if (= z 0) 1 z)))))) -417/2 153/4 -1/8 -6)))
  (error ()
    (format t "~a	(:error)~%" "generated-371")))

(handler-case
    (format t "~a	~s~%" "generated-372"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/= (let ((q (if (= (abs x) (- (if (< -2/113) y y) (- z z y)) (rem (ceiling y) (if (= (abs z) 0) 1 (abs z)))) (min (+ y 998/3) (* y -100000000000000000001/4) (let ((q y)) y)) (mod (if (> -78/127) -2 1/16) (if (= (abs x) 0) 1 (abs x)))))) (ceiling (min (let ((q y)) z) z))) (/ (if (= (mod (rem (if (>= y z z) y z) (if (= (+ z 0) 0) 1 (+ z 0))) (if (= (+ (expt (if (= x 0) 1 x) -3) (+ x y)) 0) 1 (+ (expt (if (= x 0) 1 x) -3) (+ x y)))) 0) 1 (mod (rem (if (>= y z z) y z) (if (= (+ z 0) 0) 1 (+ z 0))) (if (= (+ (expt (if (= x 0) 1 x) -3) (+ x y)) 0) 1 (+ (expt (if (= x 0) 1 x) -3) (+ x y))))))))) 22/127 71 -967/2 -4)))
  (error ()
    (format t "~a	(:error)~%" "generated-372")))

(handler-case
    (format t "~a	~s~%" "generated-373"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (nth-value 2 (rem (numerator (denominator -100000000000000000001/16)) (if (= (max (denominator y)) 0) 1 (max (denominator y))))))) 7/2 -355/8 -81/8 -1)))
  (error ()
    (format t "~a	(:error)~%" "generated-373")))

(handler-case
    (format t "~a	~s~%" "generated-374"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (multiple-value-list (numerator (min -1/127 z z))))) -1/127 -325/4 937 5)))
  (error ()
    (format t "~a	(:error)~%" "generated-374")))

(handler-case
    (format t "~a	~s~%" "generated-375"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (round (numerator (truncate (abs x) (if (= (if (= -1/8 -958/5) z -100000000000000000001/5) 0) 1 (if (= -1/8 -958/5) z -100000000000000000001/5)))) (if (= (denominator (/ (if (= (max y -100000000000000000001/113) 0) 1 (max y -100000000000000000001/113)))) 0) 1 (denominator (/ (if (= (max y -100000000000000000001/113) 0) 1 (max y -100000000000000000001/113)))))))) -281 -267/5 -2/113 -4)))
  (error ()
    (format t "~a	(:error)~%" "generated-375")))

(handler-case
    (format t "~a	~s~%" "generated-376"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (* (+ y (max (expt (if (= y 0) 1 y) n))) (let ((q (expt (if (= (if (>= 857/113 z) y -871/3) 0) 1 (if (>= 857/113 z) y -871/3)) n))) (if (<= (denominator z) (truncate x (if (= z 0) 1 z)) (truncate z)) (let ((q 730)) 7/16) (abs -842)))))) -323 1/7 71 1)))
  (error ()
    (format t "~a	(:error)~%" "generated-376")))

(handler-case
    (format t "~a	~s~%" "generated-377"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- (expt (if (= y 0) 1 y) n) (let ((q -100000000000000000001/2)) y) (expt (if (= x 0) 1 x) n)))) 1/4 100000000000000000001/16 100000000000000000001/4 -2)))
  (error ()
    (format t "~a	(:error)~%" "generated-377")))

(handler-case
    (format t "~a	~s~%" "generated-378"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (> (denominator (let ((q x)) (max z -31))) (denominator (signum (+ x 7)))))) 7/5 100000000000000000001/7 372 -6)))
  (error ()
    (format t "~a	(:error)~%" "generated-378")))

(handler-case
    (format t "~a	~s~%" "generated-379"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (nth-value 1 z))) -469/2 356 1/5 4)))
  (error ()
    (format t "~a	(:error)~%" "generated-379")))

(handler-case
    (format t "~a	~s~%" "generated-380"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (nth-value 1 -835/113))) 0 54 10000000000000000000000000000000000000001/113 2)))
  (error ()
    (format t "~a	(:error)~%" "generated-380")))

(handler-case
    (format t "~a	~s~%" "generated-381"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (values (if (<= (if (<= z) x y)) (if (> y -1/7 0) 0 -7/127) (rem 10000000000000000000000000000000000000001/2 (if (= z 0) 1 z))) (+ (* y x) (mod x (if (= 0 0) 1 0)))))) -2/5 -100000000000000000001/5 -22/3 2)))
  (error ()
    (format t "~a	(:error)~%" "generated-381")))

(handler-case
    (format t "~a	~s~%" "generated-382"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (numerator (+ (expt (if (= z 0) 1 z) 0) (- x x))))) -229/3 164 -355/127 4)))
  (error ()
    (format t "~a	(:error)~%" "generated-382")))

(handler-case
    (format t "~a	~s~%" "generated-383"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (values (abs z) (+ -713/2 z)))) -282 -355 100000000000000000001/113 1)))
  (error ()
    (format t "~a	(:error)~%" "generated-383")))

(handler-case
    (format t "~a	~s~%" "generated-384"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (nth-value 0 y))) -35 -71 -229/7 2)))
  (error ()
    (format t "~a	(:error)~%" "generated-384")))

(handler-case
    (format t "~a	~s~%" "generated-385"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/ (if (= (denominator z) 0) 1 (denominator z))))) 355/4 -11/8 508/5 -4)))
  (error ()
    (format t "~a	(:error)~%" "generated-385")))

(handler-case
    (format t "~a	~s~%" "generated-386"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (signum x))) -1/8 905/127 -7/3 -6)))
  (error ()
    (format t "~a	(:error)~%" "generated-386")))

(handler-case
    (format t "~a	~s~%" "generated-387"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (nth-value 1 (signum (abs x))))) 591/2 379/8 7/127 5)))
  (error ()
    (format t "~a	(:error)~%" "generated-387")))

(handler-case
    (format t "~a	~s~%" "generated-388"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (min z))) 165/127 -117/8 7/4 -3)))
  (error ()
    (format t "~a	(:error)~%" "generated-388")))

(handler-case
    (format t "~a	~s~%" "generated-389"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (multiple-value-list (signum (* (let ((q (numerator -10000000000000000000000000000000000000001/8))) (- 22/3 z 1/127)) -911/7))))) 7/113 355/16 0 6)))
  (error ()
    (format t "~a	(:error)~%" "generated-389")))

(handler-case
    (format t "~a	~s~%" "generated-390"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (values (round (+ (if (> (numerator z) (* y x)) (min y x) (max -157 -22/3)) (/ (if (= (/ (if (= -677/16 0) 1 -677/16)) 0) 1 (/ (if (= -677/16 0) 1 -677/16))))) (if (= (let ((q z)) (if (= z (* z 22/3)) (let ((q -1/4)) 22/5) (numerator y))) 0) 1 (let ((q z)) (if (= z (* z 22/3)) (let ((q -1/4)) 22/5) (numerator y))))) (* (+ (min (if (>= x y 355/113) z -231/2) (+ x z) -1/16) (if (> (* 10000000000000000000000000000000000000001/2 x)) y (abs -1/8))) (floor (min (numerator 0)) (if (= (/ -18/127 (if (= (round 7/16) 0) 1 (round 7/16)) (if (= (/ z (if (= y 0) 1 y) (if (= z 0) 1 z)) 0) 1 (/ z (if (= y 0) 1 y) (if (= z 0) 1 z)))) 0) 1 (/ -18/127 (if (= (round 7/16) 0) 1 (round 7/16)) (if (= (/ z (if (= y 0) 1 y) (if (= z 0) 1 z)) 0) 1 (/ z (if (= y 0) 1 y) (if (= z 0) 1 z)))))))))) -41 -22 1/127 -2)))
  (error ()
    (format t "~a	(:error)~%" "generated-390")))

(handler-case
    (format t "~a	~s~%" "generated-391"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (= (* (mod (* (if (= y 2 -100000000000000000001/127) x 1) (if (= y) -1/2 -22/7)) (if (= (- (min y z) y) 0) 1 (- (min y z) y))) (/ (/ 100000000000000000001/7 (if (= (numerator x) 0) 1 (numerator x)) (if (= (denominator -2/7) 0) 1 (denominator -2/7))) (if (= (denominator (rem z (if (= x 0) 1 x))) 0) 1 (denominator (rem z (if (= x 0) 1 x)))))) (expt (if (= (floor (expt (if (= (* z y) 0) 1 (* z y)) n)) 0) 1 (floor (expt (if (= (* z y) 0) 1 (* z y)) n))) n)))) -10000000000000000000000000000000000000001/3 -971/2 355/8 -2)))
  (error ()
    (format t "~a	(:error)~%" "generated-391")))

(handler-case
    (format t "~a	~s~%" "generated-392"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt (if (= (/ (signum (- z 85)) (if (= (max (numerator z)) 0) 1 (max (numerator z)))) 0) 1 (/ (signum (- z 85)) (if (= (max (numerator z)) 0) 1 (max (numerator z))))) n))) -1 -22/113 10000000000000000000000000000000000000001/127 4)))
  (error ()
    (format t "~a	(:error)~%" "generated-392")))

(handler-case
    (format t "~a	~s~%" "generated-393"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (= (expt (if (= y 0) 1 y) 2) (min x 224) (denominator x)))) -1/2 7 -123 -4)))
  (error ()
    (format t "~a	(:error)~%" "generated-393")))

(handler-case
    (format t "~a	~s~%" "generated-394"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (multiple-value-list (floor (let ((q x)) z))))) 1/4 2 -1 4)))
  (error ()
    (format t "~a	(:error)~%" "generated-394")))

(handler-case
    (format t "~a	~s~%" "generated-395"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- 1/16 y 7/2))) -1/127 -2/127 -138/113 2)))
  (error ()
    (format t "~a	(:error)~%" "generated-395")))

(handler-case
    (format t "~a	~s~%" "generated-396"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (> (round (expt (if (= (* (/ z (if (= z 0) 1 z)) (if (> y -1/4 -355/2) y z)) 0) 1 (* (/ z (if (= z 0) 1 z)) (if (> y -1/4 -355/2) y z))) -1))))) 71/4 -100000000000000000001/8 -100000000000000000001 6)))
  (error ()
    (format t "~a	(:error)~%" "generated-396")))

(handler-case
    (format t "~a	~s~%" "generated-397"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (nth-value 2 (abs (* (if (>= -355/4 x y) 10000000000000000000000000000000000000001/7 x) (+ x y)))))) 7/4 -2/3 611/7 5)))
  (error ()
    (format t "~a	(:error)~%" "generated-397")))

(handler-case
    (format t "~a	~s~%" "generated-398"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (nth-value 1 (abs (let ((q -22/7)) x))))) -93/127 355/2 71 1)))
  (error ()
    (format t "~a	(:error)~%" "generated-398")))

(handler-case
    (format t "~a	~s~%" "generated-399"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (multiple-value-list 355/8))) -275 22/113 100000000000000000001 0)))
  (error ()
    (format t "~a	(:error)~%" "generated-399")))

(handler-case
    (format t "~a	~s~%" "generated-400"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (floor (let ((q (+ y (min -7/3)))) (- (expt (if (= z 0) 1 z) 0) (denominator y) 1)) (if (= (if (<= (expt (if (= (- 7/8 x -355/3) 0) 1 (- 7/8 x -355/3)) -5) (let ((q (numerator x))) (if (< 296/5 2/113) z 0)) x) (if (< (* z x) (max -485/127 763/127 -65/4)) (signum y) (let ((q y)) -123/8)) (* (truncate 279/8) (floor x (if (= z 0) 1 z)))) 0) 1 (if (<= (expt (if (= (- 7/8 x -355/3) 0) 1 (- 7/8 x -355/3)) -5) (let ((q (numerator x))) (if (< 296/5 2/113) z 0)) x) (if (< (* z x) (max -485/127 763/127 -65/4)) (signum y) (let ((q y)) -123/8)) (* (truncate 279/8) (floor x (if (= z 0) 1 z)))))))) 0 -7/113 119/8 -3)))
  (error ()
    (format t "~a	(:error)~%" "generated-400")))

(handler-case
    (format t "~a	~s~%" "generated-401"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- (abs (- -7/3)) (/ (denominator x) (if (= (+ x z) 0) 1 (+ x z)) (if (= (- z z -2) 0) 1 (- z z -2)))))) -100000000000000000001/7 -252 -132 2)))
  (error ()
    (format t "~a	(:error)~%" "generated-401")))

(handler-case
    (format t "~a	~s~%" "generated-402"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (let ((q (- (mod (signum y) (if (= (let ((q 0)) z) 0) 1 (let ((q 0)) z))) (- (* -829/7 x))))) (signum (expt (if (= (truncate 22 (if (= y 0) 1 y)) 0) 1 (truncate 22 (if (= y 0) 1 y))) -4))))) 22/3 0 -355/4 -1)))
  (error ()
    (format t "~a	(:error)~%" "generated-402")))

(handler-case
    (format t "~a	~s~%" "generated-403"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (nth-value 2 (/ z (if (= x 0) 1 x) (if (= (let ((q -873/8)) 7/4) 0) 1 (let ((q -873/8)) 7/4)))))) 636/5 129/5 -131/2 -3)))
  (error ()
    (format t "~a	(:error)~%" "generated-403")))

(handler-case
    (format t "~a	~s~%" "generated-404"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (rem (floor y) (if (= (let ((q (/ (if (= x 0) 1 x)))) (signum 26)) 0) 1 (let ((q (/ (if (= x 0) 1 x)))) (signum 26)))))) -11/8 376 979/4 1)))
  (error ()
    (format t "~a	(:error)~%" "generated-404")))

(handler-case
    (format t "~a	~s~%" "generated-405"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (<= (rem (round (* (expt (if (= z 0) 1 z) n) (rem 7/127 (if (= -355/127 0) 1 -355/127)))) (if (= (numerator (ceiling (signum 100000000000000000001/113) (if (= (round z (if (= -154 0) 1 -154)) 0) 1 (round z (if (= -154 0) 1 -154))))) 0) 1 (numerator (ceiling (signum 100000000000000000001/113) (if (= (round z (if (= -154 0) 1 -154)) 0) 1 (round z (if (= -154 0) 1 -154))))))) (expt (if (= (let ((q (- (/ x (if (= z 0) 1 z) (if (= x 0) 1 x))))) y) 0) 1 (let ((q (- (/ x (if (= z 0) 1 z) (if (= x 0) 1 x))))) y)) 3)))) -75 -1 -71 -6)))
  (error ()
    (format t "~a	(:error)~%" "generated-405")))

(handler-case
    (format t "~a	~s~%" "generated-406"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             z)) -857/7 381 -1/5 0)))
  (error ()
    (format t "~a	(:error)~%" "generated-406")))

(handler-case
    (format t "~a	~s~%" "generated-407"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/ (* y 1/127) (if (= (min y x x) 0) 1 (min y x x))))) 24 0 22/5 5)))
  (error ()
    (format t "~a	(:error)~%" "generated-407")))

(handler-case
    (format t "~a	~s~%" "generated-408"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt (if (= (max (floor -839/2 (if (= 7/3 0) 1 7/3)) y) 0) 1 (max (floor -839/2 (if (= 7/3 0) 1 7/3)) y)) n))) 0 -2/7 0 -1)))
  (error ()
    (format t "~a	(:error)~%" "generated-408")))

(handler-case
    (format t "~a	~s~%" "generated-409"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (values (+ 994/3 -100000000000000000001/16) (mod x (if (= 355/4 0) 1 355/4))))) -239 355/2 1 2)))
  (error ()
    (format t "~a	(:error)~%" "generated-409")))

(handler-case
    (format t "~a	~s~%" "generated-410"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (signum 319/4))) -156 -100000000000000000001/8 -100000000000000000001/5 0)))
  (error ()
    (format t "~a	(:error)~%" "generated-410")))

(handler-case
    (format t "~a	~s~%" "generated-411"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (nth-value 0 -921/2))) -45/4 1/2 0 -6)))
  (error ()
    (format t "~a	(:error)~%" "generated-411")))

(handler-case
    (format t "~a	~s~%" "generated-412"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (signum (- (expt (if (= (denominator -11/4) 0) 1 (denominator -11/4)) -4) (if (> (mod x (if (= y 0) 1 y)) (* x 355/2) (abs -7/16)) (min -22/7 -485/8) -489/127))))) 516/7 355/2 -2/5 -1)))
  (error ()
    (format t "~a	(:error)~%" "generated-412")))

(handler-case
    (format t "~a	~s~%" "generated-413"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (values (mod (rem (expt (if (= 0 0) 1 0) n) (if (= (let ((q z)) y) 0) 1 (let ((q z)) y))) (if (= (+ 355/3 (let ((q z)) -2)) 0) 1 (+ 355/3 (let ((q z)) -2)))) (min y (max (rem 100000000000000000001/3 (if (= 123/4 0) 1 123/4)) (/ (if (= z 0) 1 z))) (abs (expt (if (= y 0) 1 y) n)))))) -1/7 2/113 -11 3)))
  (error ()
    (format t "~a	(:error)~%" "generated-413")))

(handler-case
    (format t "~a	~s~%" "generated-414"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (>= (max (min (let ((q x)) (abs y))) (denominator (signum (rem z (if (= x 0) 1 x)))))))) 355/3 -706/5 100000000000000000001/127 1)))
  (error ()
    (format t "~a	(:error)~%" "generated-414")))

(handler-case
    (format t "~a	~s~%" "generated-415"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (values x (+ (mod z (if (= (max (abs z) (abs 1) x) 0) 1 (max (abs z) (abs 1) x))) 7/127)))) 959/4 -11 1/8 -1)))
  (error ()
    (format t "~a	(:error)~%" "generated-415")))

(handler-case
    (format t "~a	~s~%" "generated-416"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (ceiling (* -240 z) (if (= z 0) 1 z)))) 2 686/5 10000000000000000000000000000000000000001/8 6)))
  (error ()
    (format t "~a	(:error)~%" "generated-416")))

(handler-case
    (format t "~a	~s~%" "generated-417"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (nth-value 2 (floor (let ((q (let ((q (max z 2 y))) (numerator y)))) (expt (if (= (signum -2/3) 0) 1 (signum -2/3)) n)) (if (= (/ (if (>= (if (>= x) z -7/113) (/ -1/3 (if (= x 0) 1 x))) (max x 465/16 100000000000000000001/113) (let ((q x)) z)) (if (= (expt (if (= (rem 295/8 (if (= 581/113 0) 1 581/113)) 0) 1 (rem 295/8 (if (= 581/113 0) 1 581/113))) n) 0) 1 (expt (if (= (rem 295/8 (if (= 581/113 0) 1 581/113)) 0) 1 (rem 295/8 (if (= 581/113 0) 1 581/113))) n)) (if (= (+ (round 7/4) (numerator x)) 0) 1 (+ (round 7/4) (numerator x)))) 0) 1 (/ (if (>= (if (>= x) z -7/113) (/ -1/3 (if (= x 0) 1 x))) (max x 465/16 100000000000000000001/113) (let ((q x)) z)) (if (= (expt (if (= (rem 295/8 (if (= 581/113 0) 1 581/113)) 0) 1 (rem 295/8 (if (= 581/113 0) 1 581/113))) n) 0) 1 (expt (if (= (rem 295/8 (if (= 581/113 0) 1 581/113)) 0) 1 (rem 295/8 (if (= 581/113 0) 1 581/113))) n)) (if (= (+ (round 7/4) (numerator x)) 0) 1 (+ (round 7/4) (numerator x))))))))) -504/127 280 -593/127 -1)))
  (error ()
    (format t "~a	(:error)~%" "generated-417")))

(handler-case
    (format t "~a	~s~%" "generated-418"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- (/ (/ (if (= (expt (if (= x 0) 1 x) -5) 0) 1 (expt (if (= x 0) 1 x) -5))) (if (= (signum (min 22/127)) 0) 1 (signum (min 22/127))) (if (= z 0) 1 z)) (if (> (if (<= (rem y (if (= x 0) 1 x))) (/ y (if (= 2 0) 1 2)) (/ -237/5 (if (= 100000000000000000001/5 0) 1 100000000000000000001/5))) (max 355/127) y) (numerator x) (expt (if (= (ceiling 7/3 (if (= z 0) 1 z)) 0) 1 (ceiling 7/3 (if (= z 0) 1 z))) n)) (let ((q (- y (/ 7/8 (if (= x 0) 1 x))))) (* (expt (if (= x 0) 1 x) n) (if (>= -700/127) z y)))))) 7/2 -355/3 -523/4 3)))
  (error ()
    (format t "~a	(:error)~%" "generated-418")))

(handler-case
    (format t "~a	~s~%" "generated-419"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             1/7)) 1/127 100000000000000000001/4 715/16 -4)))
  (error ()
    (format t "~a	(:error)~%" "generated-419")))

(handler-case
    (format t "~a	~s~%" "generated-420"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (nth-value 0 (if (= -100000000000000000001/113 (expt (if (= (if (>= (+ y y)) (let ((q -100000000000000000001/3)) -1/2) (floor z (if (= 355/8 0) 1 355/8))) 0) 1 (if (>= (+ y y)) (let ((q -100000000000000000001/3)) -1/2) (floor z (if (= 355/8 0) 1 355/8)))) n) (- 290/7)) (if (> (+ (ceiling y) (min y y -73/7)) (numerator (let ((q z)) -11/4))) (floor (expt (if (= z 0) 1 z) 6) (if (= z 0) 1 z)) (- (* -209/16 z) (abs 10000000000000000000000000000000000000001/127))) (* x (floor 1/2 (if (= (round y (if (= z 0) 1 z)) 0) 1 (round y (if (= z 0) 1 z))))))))) 3 6 -10000000000000000000000000000000000000001/5 5)))
  (error ()
    (format t "~a	(:error)~%" "generated-420")))

(handler-case
    (format t "~a	~s~%" "generated-421"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (nth-value 2 (- (rem (expt (if (= (* z -1) 0) 1 (* z -1)) 2) (if (= 804 0) 1 804)))))) 421 -1 -2/7 -1)))
  (error ()
    (format t "~a	(:error)~%" "generated-421")))

(handler-case
    (format t "~a	~s~%" "generated-422"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (multiple-value-list (abs (+ (* x x) (rem 503/7 (if (= z 0) 1 z))))))) -11/2 -100000000000000000001/2 383/5 -2)))
  (error ()
    (format t "~a	(:error)~%" "generated-422")))

(handler-case
    (format t "~a	~s~%" "generated-423"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- -2))) 1/16 -789 -100000000000000000001/4 2)))
  (error ()
    (format t "~a	(:error)~%" "generated-423")))

(handler-case
    (format t "~a	~s~%" "generated-424"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (values (- (floor (if (> (round y (if (= -22/7 0) 1 -22/7))) (numerator -355/4) (rem -10000000000000000000000000000000000000001/16 (if (= z 0) 1 z))) (if (= y 0) 1 y))) (* (/ (mod (rem -1/2 (if (= x 0) 1 x)) (if (= (expt (if (= 149/2 0) 1 149/2) n) 0) 1 (expt (if (= 149/2 0) 1 149/2) n))) (if (= (* (+ -11/8 x) (/ y (if (= x 0) 1 x) (if (= -351/2 0) 1 -351/2))) 0) 1 (* (+ -11/8 x) (/ y (if (= x 0) 1 x) (if (= -351/2 0) 1 -351/2))))) (min (/ (if (= (numerator 100000000000000000001/7) 0) 1 (numerator 100000000000000000001/7))) (/ (round -22/5) (if (= (- -7/8 z) 0) 1 (- -7/8 z)) (if (= (expt (if (= 0 0) 1 0) n) 0) 1 (expt (if (= 0 0) 1 0) n)))))))) -400/3 661/16 -1/16 2)))
  (error ()
    (format t "~a	(:error)~%" "generated-424")))

(handler-case
    (format t "~a	~s~%" "generated-425"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (+ (denominator -1/4) (/ x (if (= 1/3 0) 1 1/3))))) 183/8 100000000000000000001/127 22/7 0)))
  (error ()
    (format t "~a	(:error)~%" "generated-425")))

(handler-case
    (format t "~a	~s~%" "generated-426"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (nth-value 1 (denominator (floor (* (expt (if (= y 0) 1 y) 4) (- z z)) (if (= (numerator (min z -878/5)) 0) 1 (numerator (min z -878/5)))))))) 294 0 -3 4)))
  (error ()
    (format t "~a	(:error)~%" "generated-426")))

(handler-case
    (format t "~a	~s~%" "generated-427"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (+ (+ (+ -681/127 1/127) (+ 629/2 x)) (max (- x) (expt (if (= 765/16 0) 1 765/16) n) (let ((q y)) 717/7))))) -2/113 1/8 -627/2 -6)))
  (error ()
    (format t "~a	(:error)~%" "generated-427")))

(handler-case
    (format t "~a	~s~%" "generated-428"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (ceiling (max (- -10000000000000000000000000000000000000001/7) (rem x (if (= x 0) 1 x)) (+ y z))))) 283/113 -11/2 100000000000000000001/8 2)))
  (error ()
    (format t "~a	(:error)~%" "generated-428")))

(handler-case
    (format t "~a	~s~%" "generated-429"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/ (- -294/5 (/ x (if (= -100000000000000000001/4 0) 1 -100000000000000000001/4) (if (= -192 0) 1 -192)) (abs x)) (if (= (if (< (numerator 2/3)) (+ z x) (rem x (if (= z 0) 1 z))) 0) 1 (if (< (numerator 2/3)) (+ z x) (rem x (if (= z 0) 1 z)))) (if (= (/ y (if (= (truncate -1/3) 0) 1 (truncate -1/3)) (if (= -355/2 0) 1 -355/2)) 0) 1 (/ y (if (= (truncate -1/3) 0) 1 (truncate -1/3)) (if (= -355/2 0) 1 -355/2)))))) 763/16 1/5 786 4)))
  (error ()
    (format t "~a	(:error)~%" "generated-429")))

(handler-case
    (format t "~a	~s~%" "generated-430"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (values (if (<= (expt (if (= -22/127 0) 1 -22/127) n)) (mod x (if (= -1/16 0) 1 -1/16)) (let ((q 0)) 1/3)) (denominator y)))) -10000000000000000000000000000000000000001 -939/127 -1/8 3)))
  (error ()
    (format t "~a	(:error)~%" "generated-430")))

(handler-case
    (format t "~a	~s~%" "generated-431"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (abs (expt (if (= (expt (if (= (- 2/5 22) 0) 1 (- 2/5 22)) n) 0) 1 (expt (if (= (- 2/5 22) 0) 1 (- 2/5 22)) n)) n)))) 1/3 100000000000000000001/3 488/3 -2)))
  (error ()
    (format t "~a	(:error)~%" "generated-431")))

(handler-case
    (format t "~a	~s~%" "generated-432"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (values (+ (expt (if (= (if (> z 11/8 651/127) -2/5 x) 0) 1 (if (> z 11/8 651/127) -2/5 x)) -5) (* 355/3 (rem y (if (= 22/7 0) 1 22/7)))) x))) -1/4 -355/8 -152/113 6)))
  (error ()
    (format t "~a	(:error)~%" "generated-432")))

(handler-case
    (format t "~a	~s~%" "generated-433"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/ (if (= x 0) 1 x)))) 22/5 -355/127 -1/113 -4)))
  (error ()
    (format t "~a	(:error)~%" "generated-433")))

(handler-case
    (format t "~a	~s~%" "generated-434"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (mod (mod x (if (= -1/5 0) 1 -1/5)) (if (= (min y x) 0) 1 (min y x))))) 11 287/16 1 -1)))
  (error ()
    (format t "~a	(:error)~%" "generated-434")))

(handler-case
    (format t "~a	~s~%" "generated-435"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (> y (floor y (if (= (rem (round (mod y (if (= 443/7 0) 1 443/7)) (if (= (* x -355/16) 0) 1 (* x -355/16))) (if (= (* (- z y z) (mod x (if (= 100000000000000000001/7 0) 1 100000000000000000001/7))) 0) 1 (* (- z y z) (mod x (if (= 100000000000000000001/7 0) 1 100000000000000000001/7))))) 0) 1 (rem (round (mod y (if (= 443/7 0) 1 443/7)) (if (= (* x -355/16) 0) 1 (* x -355/16))) (if (= (* (- z y z) (mod x (if (= 100000000000000000001/7 0) 1 100000000000000000001/7))) 0) 1 (* (- z y z) (mod x (if (= 100000000000000000001/7 0) 1 100000000000000000001/7))))))) (mod (/ (if (< (* y -27/4) (let ((q 100000000000000000001/2)) -1/8) (expt (if (= y 0) 1 y) n)) (* x x) (* x 1/5)) (if (= (max (- z) -87/16 z) 0) 1 (max (- z) -87/16 z)) (if (= (if (> (* y x) (/ -355/16 (if (= z 0) 1 z) (if (= 100000000000000000001/5 0) 1 100000000000000000001/5))) x (* z y)) 0) 1 (if (> (* y x) (/ -355/16 (if (= z 0) 1 z) (if (= 100000000000000000001/5 0) 1 100000000000000000001/5))) x (* z y)))) (if (= (expt (if (= (/ (if (= (- 1/7) 0) 1 (- 1/7))) 0) 1 (/ (if (= (- 1/7) 0) 1 (- 1/7)))) -1) 0) 1 (expt (if (= (/ (if (= (- 1/7) 0) 1 (- 1/7))) 0) 1 (/ (if (= (- 1/7) 0) 1 (- 1/7)))) -1)))))) -7/4 -10000000000000000000000000000000000000001/5 355/16 -4)))
  (error ()
    (format t "~a	(:error)~%" "generated-435")))

(handler-case
    (format t "~a	~s~%" "generated-436"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/ (signum z) (if (= (expt (if (= y 0) 1 y) -6) 0) 1 (expt (if (= y 0) 1 y) -6)) (if (= (expt (if (= 22/127 0) 1 22/127) n) 0) 1 (expt (if (= 22/127 0) 1 22/127) n))))) 148 -22/7 71 -6)))
  (error ()
    (format t "~a	(:error)~%" "generated-436")))

(handler-case
    (format t "~a	~s~%" "generated-437"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (nth-value 0 (+ z z)))) 355/7 22/3 22/3 -5)))
  (error ()
    (format t "~a	(:error)~%" "generated-437")))

(handler-case
    (format t "~a	~s~%" "generated-438"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (let ((q (+ 2/127 0))) y))) 1 -499/3 355/113 0)))
  (error ()
    (format t "~a	(:error)~%" "generated-438")))

(handler-case
    (format t "~a	~s~%" "generated-439"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (expt (if (= 1 0) 1 1) n))) -185/3 1/8 7/16 6)))
  (error ()
    (format t "~a	(:error)~%" "generated-439")))

(handler-case
    (format t "~a	~s~%" "generated-440"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (multiple-value-list z))) 0 -7/8 -23/4 3)))
  (error ()
    (format t "~a	(:error)~%" "generated-440")))

(handler-case
    (format t "~a	~s~%" "generated-441"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (values (signum x) x))) 10000000000000000000000000000000000000001/113 -10000000000000000000000000000000000000001/3 15/4 -4)))
  (error ()
    (format t "~a	(:error)~%" "generated-441")))

(handler-case
    (format t "~a	~s~%" "generated-442"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (<= (expt (if (= (min x y) 0) 1 (min x y)) 5) (/ (* y z) (if (= (truncate y (if (= z 0) 1 z)) 0) 1 (truncate y (if (= z 0) 1 z))) (if (= (signum x) 0) 1 (signum x))) (numerator (+ y z))))) -1/3 1 -229/16 -1)))
  (error ()
    (format t "~a	(:error)~%" "generated-442")))

(handler-case
    (format t "~a	~s~%" "generated-443"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (values (rem (* (- (round x) y (let ((q 7/16)) 22/5)) (numerator 731/5)) (if (= (ceiling (expt (if (= 247/7 0) 1 247/7) n)) 0) 1 (ceiling (expt (if (= 247/7 0) 1 247/7) n)))) (ceiling (min (- 10000000000000000000000000000000000000001/113 (denominator y))))))) -2/7 1/7 -355/16 -3)))
  (error ()
    (format t "~a	(:error)~%" "generated-443")))

(handler-case
    (format t "~a	~s~%" "generated-444"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (signum (round (numerator -68/127) (if (= (/ z (if (= z 0) 1 z) (if (= y 0) 1 y)) 0) 1 (/ z (if (= z 0) 1 z) (if (= y 0) 1 y))))))) -405/2 -21/4 -7/5 3)))
  (error ()
    (format t "~a	(:error)~%" "generated-444")))

(handler-case
    (format t "~a	~s~%" "generated-445"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (multiple-value-list y))) 487/5 -279/8 -100000000000000000001/5 0)))
  (error ()
    (format t "~a	(:error)~%" "generated-445")))

(handler-case
    (format t "~a	~s~%" "generated-446"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (nth-value 2 (min (+ 2/113 -966) (* -2/113 355/2) (mod -71 (if (= 0 0) 1 0)))))) -7/2 355/4 -337/16 6)))
  (error ()
    (format t "~a	(:error)~%" "generated-446")))

(handler-case
    (format t "~a	~s~%" "generated-447"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (> (expt (if (= (floor (* (let ((q -11)) x) x)) 0) 1 (floor (* (let ((q -11)) x) x))) n) (numerator (let ((q (/ (signum x) (if (= x 0) 1 x) (if (= (denominator z) 0) 1 (denominator z))))) (* -373/7 (signum 355/4)))) (denominator (signum y))))) 327/5 -385/127 0 -6)))
  (error ()
    (format t "~a	(:error)~%" "generated-447")))

(handler-case
    (format t "~a	~s~%" "generated-448"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (nth-value 0 (max (denominator (+ -549/127 y)) -161/8 (abs (min z x -1/2)))))) 22/3 -927/4 100000000000000000001/7 5)))
  (error ()
    (format t "~a	(:error)~%" "generated-448")))

(handler-case
    (format t "~a	~s~%" "generated-449"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (floor z))) 100000000000000000001/2 -267 -347/2 3)))
  (error ()
    (format t "~a	(:error)~%" "generated-449")))

(handler-case
    (format t "~a	~s~%" "generated-450"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (multiple-value-list (let ((q z)) (expt (if (= (rem x (if (= z 0) 1 z)) 0) 1 (rem x (if (= z 0) 1 z))) n))))) -27/2 -71 -269/2 -3)))
  (error ()
    (format t "~a	(:error)~%" "generated-450")))

(handler-case
    (format t "~a	~s~%" "generated-451"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (nth-value 1 (numerator (signum (abs x)))))) -53 1/2 201/4 2)))
  (error ()
    (format t "~a	(:error)~%" "generated-451")))

(handler-case
    (format t "~a	~s~%" "generated-452"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (let ((q z)) y))) 100000000000000000001/4 -1/2 -22/7 -4)))
  (error ()
    (format t "~a	(:error)~%" "generated-452")))

(handler-case
    (format t "~a	~s~%" "generated-453"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             z)) -1/2 11/2 -2/7 6)))
  (error ()
    (format t "~a	(:error)~%" "generated-453")))

(handler-case
    (format t "~a	~s~%" "generated-454"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (let ((q x)) -1/2))) 1/2 100000000000000000001/16 -1/8 -2)))
  (error ()
    (format t "~a	(:error)~%" "generated-454")))

(handler-case
    (format t "~a	~s~%" "generated-455"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/ (if (= (* (if (>= (- 394/7 -116/3 z)) (* x z) (* x 355/4)) (let ((q (let ((q -507/16)) z))) (mod y (if (= x 0) 1 x)))) 0) 1 (* (if (>= (- 394/7 -116/3 z)) (* x z) (* x 355/4)) (let ((q (let ((q -507/16)) z))) (mod y (if (= x 0) 1 x)))))))) 2/5 355/127 0 0)))
  (error ()
    (format t "~a	(:error)~%" "generated-455")))

(handler-case
    (format t "~a	~s~%" "generated-456"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (values (if (= (let ((q z)) z) (round x (if (= z 0) 1 z))) (if (/= z z) 965/8 0) (mod -811/3 (if (= 2/7 0) 1 2/7))) (min y)))) 7/5 -204/7 100000000000000000001/2 6)))
  (error ()
    (format t "~a	(:error)~%" "generated-456")))

(handler-case
    (format t "~a	~s~%" "generated-457"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (nth-value 2 (if (= z) x y)))) -71 57/5 -42 -4)))
  (error ()
    (format t "~a	(:error)~%" "generated-457")))

(handler-case
    (format t "~a	~s~%" "generated-458"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (/= (* (- -1/127) (expt (if (= 0 0) 1 0) n))))) -16/5 100000000000000000001/7 -100000000000000000001/16 -3)))
  (error ()
    (format t "~a	(:error)~%" "generated-458")))

(handler-case
    (format t "~a	~s~%" "generated-459"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (let ((q (- (min z 11/8 -7/2) (let ((q x)) x)))) z))) -2/3 -1/4 355/127 0)))
  (error ()
    (format t "~a	(:error)~%" "generated-459")))

(handler-case
    (format t "~a	~s~%" "generated-460"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (let ((q y)) z))) 1/113 -355 -365/16 2)))
  (error ()
    (format t "~a	(:error)~%" "generated-460")))

(handler-case
    (format t "~a	~s~%" "generated-461"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (multiple-value-list (mod (* (denominator z) z) (if (= (ceiling (let ((q y)) -22/5)) 0) 1 (ceiling (let ((q y)) -22/5))))))) -2/5 7/127 -2/7 6)))
  (error ()
    (format t "~a	(:error)~%" "generated-461")))

(handler-case
    (format t "~a	~s~%" "generated-462"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (values (abs (rem -7/2 (if (= x 0) 1 x))) 1/7))) 301 -1 -214/7 -2)))
  (error ()
    (format t "~a	(:error)~%" "generated-462")))

(handler-case
    (format t "~a	~s~%" "generated-463"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (values (mod (if (= (ceiling (let ((q y)) 53) (if (= (- x) 0) 1 (- x))) (+ (round 100000000000000000001/127) (rem -2/7 (if (= x 0) 1 x)))) (let ((q (signum -100000000000000000001))) (mod 465/2 (if (= x 0) 1 x))) 1/4) (if (= (abs (numerator (expt (if (= z 0) 1 z) -6))) 0) 1 (abs (numerator (expt (if (= z 0) 1 z) -6))))) (rem z (if (= (if (< (numerator (+ x y))) (max (max x) 937/127) (* (* -83/4 z) (truncate -515/127 (if (= z 0) 1 z)))) 0) 1 (if (< (numerator (+ x y))) (max (max x) 937/127) (* (* -83/4 z) (truncate -515/127 (if (= z 0) 1 z))))))))) -1/8 1/4 768 1)))
  (error ()
    (format t "~a	(:error)~%" "generated-463")))

(handler-case
    (format t "~a	~s~%" "generated-464"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (nth-value 2 x))) -1/127 1/8 71 -3)))
  (error ()
    (format t "~a	(:error)~%" "generated-464")))

(handler-case
    (format t "~a	~s~%" "generated-465"
            (multiple-value-list
             (funcall (compile nil '(lambda (x y z n)
             (declare (optimize (speed 3) (safety 1)) (type rational x y z) (type integer n))
             (- (* (ceiling (rem x (if (= z 0) 1 z)) (if (= (truncate y (if (= y 0) 1 y)) 0) 1 (truncate y (if (= y 0) 1 y)))) (/ (if (= (min -355/127 x) 0) 1 (min -355/127 x)))) (* (+ (expt (if (= -100000000000000000001/2 0) 1 -100000000000000000001/2) n) (ceiling 783/127 (if (= -10000000000000000000000000000000000000001/16 0) 1 -10000000000000000000000000000000000000001/16))) (denominator (+ z y)))))) 355/127 1/7 -1/8 0)))
  (error ()
    (format t "~a	(:error)~%" "generated-465")))
