(handler-case
  (let ((value (eval '(= '1 '1))))
    (format t "HOST-RESULT|=-0045|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|=-0045|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (= '1 '1))))))
    (format t "HOST-RESULT|=-0045|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|=-0045|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(= '1/2 '1/2))))
    (format t "HOST-RESULT|=-0046|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|=-0046|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (= '1/2 '1/2))))))
    (format t "HOST-RESULT|=-0046|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|=-0046|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(= '-2 '2))))
    (format t "HOST-RESULT|=-0047|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|=-0047|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (= '-2 '2))))))
    (format t "HOST-RESULT|=-0047|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|=-0047|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(= '#C(1 2) '#C(1 2)))))
    (format t "HOST-RESULT|=-0048|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|=-0048|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (= '#C(1 2) '#C(1 2)))))))
    (format t "HOST-RESULT|=-0048|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|=-0048|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(= '#C(1 2) '#C(1 3)))))
    (format t "HOST-RESULT|=-0049|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|=-0049|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (= '#C(1 2) '#C(1 3)))))))
    (format t "HOST-RESULT|=-0049|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|=-0049|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(= '#C(1 2) '1))))
    (format t "HOST-RESULT|=-0050|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|=-0050|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (= '#C(1 2) '1))))))
    (format t "HOST-RESULT|=-0050|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|=-0050|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(= 'A 'A))))
    (format t "HOST-RESULT|=-0051|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|=-0051|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (= 'A 'A))))))
    (format t "HOST-RESULT|=-0051|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|=-0051|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(= 'A '0))))
    (format t "HOST-RESULT|=-0052|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|=-0052|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (= 'A '0))))))
    (format t "HOST-RESULT|=-0052|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|=-0052|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(= NIL '1))))
    (format t "HOST-RESULT|=-0053|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|=-0053|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (= NIL '1))))))
    (format t "HOST-RESULT|=-0053|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|=-0053|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(= '"x" '0))))
    (format t "HOST-RESULT|=-0054|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|=-0054|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (= '"x" '0))))))
    (format t "HOST-RESULT|=-0054|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|=-0054|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(/= '1 '1))))
    (format t "HOST-RESULT|/=-0055|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|/=-0055|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (/= '1 '1))))))
    (format t "HOST-RESULT|/=-0055|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|/=-0055|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(/= '1/2 '1/2))))
    (format t "HOST-RESULT|/=-0056|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|/=-0056|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (/= '1/2 '1/2))))))
    (format t "HOST-RESULT|/=-0056|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|/=-0056|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(/= '-2 '2))))
    (format t "HOST-RESULT|/=-0057|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|/=-0057|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (/= '-2 '2))))))
    (format t "HOST-RESULT|/=-0057|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|/=-0057|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(/= '#C(1 2) '#C(1 2)))))
    (format t "HOST-RESULT|/=-0058|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|/=-0058|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (/= '#C(1 2) '#C(1 2)))))))
    (format t "HOST-RESULT|/=-0058|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|/=-0058|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(/= '#C(1 2) '#C(1 3)))))
    (format t "HOST-RESULT|/=-0059|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|/=-0059|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (/= '#C(1 2) '#C(1 3)))))))
    (format t "HOST-RESULT|/=-0059|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|/=-0059|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(/= '#C(1 2) '1))))
    (format t "HOST-RESULT|/=-0060|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|/=-0060|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (/= '#C(1 2) '1))))))
    (format t "HOST-RESULT|/=-0060|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|/=-0060|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(car NIL))))
    (format t "HOST-RESULT|car-0065|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|car-0065|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (car NIL))))))
    (format t "HOST-RESULT|car-0065|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|car-0065|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(car '(1 2 3)))))
    (format t "HOST-RESULT|car-0066|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|car-0066|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (car '(1 2 3)))))))
    (format t "HOST-RESULT|car-0066|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|car-0066|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(car '(1 2 . 3)))))
    (format t "HOST-RESULT|car-0067|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|car-0067|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (car '(1 2 . 3)))))))
    (format t "HOST-RESULT|car-0067|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|car-0067|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(car '7))))
    (format t "HOST-RESULT|car-0068|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|car-0068|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (car '7))))))
    (format t "HOST-RESULT|car-0068|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|car-0068|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(car 'A))))
    (format t "HOST-RESULT|car-0069|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|car-0069|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (car 'A))))))
    (format t "HOST-RESULT|car-0069|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|car-0069|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(car '"atom"))))
    (format t "HOST-RESULT|car-0070|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|car-0070|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (car '"atom"))))))
    (format t "HOST-RESULT|car-0070|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|car-0070|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(cdr NIL))))
    (format t "HOST-RESULT|cdr-0071|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|cdr-0071|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (cdr NIL))))))
    (format t "HOST-RESULT|cdr-0071|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|cdr-0071|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(cdr '(1 2 3)))))
    (format t "HOST-RESULT|cdr-0072|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|cdr-0072|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (cdr '(1 2 3)))))))
    (format t "HOST-RESULT|cdr-0072|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|cdr-0072|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(cdr '(1 2 . 3)))))
    (format t "HOST-RESULT|cdr-0073|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|cdr-0073|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (cdr '(1 2 . 3)))))))
    (format t "HOST-RESULT|cdr-0073|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|cdr-0073|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(cdr '7))))
    (format t "HOST-RESULT|cdr-0074|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|cdr-0074|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (cdr '7))))))
    (format t "HOST-RESULT|cdr-0074|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|cdr-0074|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(cdr 'A))))
    (format t "HOST-RESULT|cdr-0075|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|cdr-0075|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (cdr 'A))))))
    (format t "HOST-RESULT|cdr-0075|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|cdr-0075|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(cdr '"atom"))))
    (format t "HOST-RESULT|cdr-0076|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|cdr-0076|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (cdr '"atom"))))))
    (format t "HOST-RESULT|cdr-0076|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|cdr-0076|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(length NIL))))
    (format t "HOST-RESULT|len-0077|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|len-0077|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (length NIL))))))
    (format t "HOST-RESULT|len-0077|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|len-0077|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(length '(1)))))
    (format t "HOST-RESULT|len-0078|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|len-0078|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (length '(1)))))))
    (format t "HOST-RESULT|len-0078|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|len-0078|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(length '(1 2 3)))))
    (format t "HOST-RESULT|len-0079|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|len-0079|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (length '(1 2 3)))))))
    (format t "HOST-RESULT|len-0079|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|len-0079|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(length '(1 . 2)))))
    (format t "HOST-RESULT|len-0080|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|len-0080|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (length '(1 . 2)))))))
    (format t "HOST-RESULT|len-0080|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|len-0080|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(length '(1 2 . 3)))))
    (format t "HOST-RESULT|len-0081|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|len-0081|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (length '(1 2 . 3)))))))
    (format t "HOST-RESULT|len-0081|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|len-0081|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(length '9))))
    (format t "HOST-RESULT|len-0082|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|len-0082|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (length '9))))))
    (format t "HOST-RESULT|len-0082|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|len-0082|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(length 'A))))
    (format t "HOST-RESULT|len-0083|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|len-0083|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (length 'A))))))
    (format t "HOST-RESULT|len-0083|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|len-0083|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(length '""))))
    (format t "HOST-RESULT|len-0084|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|len-0084|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (length '""))))))
    (format t "HOST-RESULT|len-0084|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|len-0084|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(length '"abc"))))
    (format t "HOST-RESULT|len-0085|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|len-0085|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (length '"abc"))))))
    (format t "HOST-RESULT|len-0085|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|len-0085|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(length '"a\"b\\c"))))
    (format t "HOST-RESULT|len-0086|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|len-0086|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (length '"a\"b\\c"))))))
    (format t "HOST-RESULT|len-0086|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|len-0086|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-7 '-3))))
    (format t "HOST-RESULT|mod-0087|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0087|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-7 '-3))))))
    (format t "HOST-RESULT|mod-0087|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0087|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-7 '-2/3))))
    (format t "HOST-RESULT|mod-0088|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0088|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-7 '-2/3))))))
    (format t "HOST-RESULT|mod-0088|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0088|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-7 '2/3))))
    (format t "HOST-RESULT|mod-0089|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0089|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-7 '2/3))))))
    (format t "HOST-RESULT|mod-0089|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0089|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-7 '3))))
    (format t "HOST-RESULT|mod-0090|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0090|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-7 '3))))))
    (format t "HOST-RESULT|mod-0090|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0090|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-7 '0))))
    (format t "HOST-RESULT|mod-0091|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0091|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-7 '0))))))
    (format t "HOST-RESULT|mod-0091|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0091|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-5/2 '-3))))
    (format t "HOST-RESULT|mod-0092|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0092|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-5/2 '-3))))))
    (format t "HOST-RESULT|mod-0092|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0092|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-5/2 '-2/3))))
    (format t "HOST-RESULT|mod-0093|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0093|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-5/2 '-2/3))))))
    (format t "HOST-RESULT|mod-0093|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0093|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-5/2 '2/3))))
    (format t "HOST-RESULT|mod-0094|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0094|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-5/2 '2/3))))))
    (format t "HOST-RESULT|mod-0094|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0094|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-5/2 '3))))
    (format t "HOST-RESULT|mod-0095|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0095|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-5/2 '3))))))
    (format t "HOST-RESULT|mod-0095|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0095|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-5/2 '0))))
    (format t "HOST-RESULT|mod-0096|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0096|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-5/2 '0))))))
    (format t "HOST-RESULT|mod-0096|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0096|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '0 '-3))))
    (format t "HOST-RESULT|mod-0097|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0097|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '0 '-3))))))
    (format t "HOST-RESULT|mod-0097|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0097|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '0 '-2/3))))
    (format t "HOST-RESULT|mod-0098|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0098|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '0 '-2/3))))))
    (format t "HOST-RESULT|mod-0098|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0098|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '0 '2/3))))
    (format t "HOST-RESULT|mod-0099|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0099|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '0 '2/3))))))
    (format t "HOST-RESULT|mod-0099|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0099|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '0 '3))))
    (format t "HOST-RESULT|mod-0100|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0100|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '0 '3))))))
    (format t "HOST-RESULT|mod-0100|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0100|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '0 '0))))
    (format t "HOST-RESULT|mod-0101|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0101|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '0 '0))))))
    (format t "HOST-RESULT|mod-0101|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0101|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '5/2 '-3))))
    (format t "HOST-RESULT|mod-0102|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0102|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '5/2 '-3))))))
    (format t "HOST-RESULT|mod-0102|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0102|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '5/2 '-2/3))))
    (format t "HOST-RESULT|mod-0103|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0103|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '5/2 '-2/3))))))
    (format t "HOST-RESULT|mod-0103|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0103|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '5/2 '2/3))))
    (format t "HOST-RESULT|mod-0104|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0104|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '5/2 '2/3))))))
    (format t "HOST-RESULT|mod-0104|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0104|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '5/2 '3))))
    (format t "HOST-RESULT|mod-0105|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0105|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '5/2 '3))))))
    (format t "HOST-RESULT|mod-0105|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0105|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '5/2 '0))))
    (format t "HOST-RESULT|mod-0106|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0106|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '5/2 '0))))))
    (format t "HOST-RESULT|mod-0106|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0106|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '7 '-3))))
    (format t "HOST-RESULT|mod-0107|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0107|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '7 '-3))))))
    (format t "HOST-RESULT|mod-0107|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0107|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '7 '-2/3))))
    (format t "HOST-RESULT|mod-0108|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0108|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '7 '-2/3))))))
    (format t "HOST-RESULT|mod-0108|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0108|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '7 '2/3))))
    (format t "HOST-RESULT|mod-0109|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0109|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '7 '2/3))))))
    (format t "HOST-RESULT|mod-0109|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0109|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '7 '3))))
    (format t "HOST-RESULT|mod-0110|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0110|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '7 '3))))))
    (format t "HOST-RESULT|mod-0110|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0110|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '7 '0))))
    (format t "HOST-RESULT|mod-0111|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0111|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '7 '0))))))
    (format t "HOST-RESULT|mod-0111|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|mod-0111|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(rem '-7 '-3))))
    (format t "HOST-RESULT|rem-0112|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0112|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (rem '-7 '-3))))))
    (format t "HOST-RESULT|rem-0112|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0112|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(rem '-7 '-2/3))))
    (format t "HOST-RESULT|rem-0113|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0113|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (rem '-7 '-2/3))))))
    (format t "HOST-RESULT|rem-0113|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0113|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(rem '-7 '2/3))))
    (format t "HOST-RESULT|rem-0114|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0114|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (rem '-7 '2/3))))))
    (format t "HOST-RESULT|rem-0114|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0114|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(rem '-7 '3))))
    (format t "HOST-RESULT|rem-0115|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0115|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (rem '-7 '3))))))
    (format t "HOST-RESULT|rem-0115|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0115|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(rem '-7 '0))))
    (format t "HOST-RESULT|rem-0116|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0116|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (rem '-7 '0))))))
    (format t "HOST-RESULT|rem-0116|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0116|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(rem '-5/2 '-3))))
    (format t "HOST-RESULT|rem-0117|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0117|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (rem '-5/2 '-3))))))
    (format t "HOST-RESULT|rem-0117|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0117|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(rem '-5/2 '-2/3))))
    (format t "HOST-RESULT|rem-0118|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0118|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (rem '-5/2 '-2/3))))))
    (format t "HOST-RESULT|rem-0118|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0118|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(rem '-5/2 '2/3))))
    (format t "HOST-RESULT|rem-0119|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0119|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (rem '-5/2 '2/3))))))
    (format t "HOST-RESULT|rem-0119|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0119|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(rem '-5/2 '3))))
    (format t "HOST-RESULT|rem-0120|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0120|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (rem '-5/2 '3))))))
    (format t "HOST-RESULT|rem-0120|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0120|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(rem '-5/2 '0))))
    (format t "HOST-RESULT|rem-0121|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0121|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (rem '-5/2 '0))))))
    (format t "HOST-RESULT|rem-0121|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0121|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(rem '0 '-3))))
    (format t "HOST-RESULT|rem-0122|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0122|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (rem '0 '-3))))))
    (format t "HOST-RESULT|rem-0122|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0122|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(rem '0 '-2/3))))
    (format t "HOST-RESULT|rem-0123|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0123|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (rem '0 '-2/3))))))
    (format t "HOST-RESULT|rem-0123|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0123|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(rem '0 '2/3))))
    (format t "HOST-RESULT|rem-0124|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0124|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (rem '0 '2/3))))))
    (format t "HOST-RESULT|rem-0124|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0124|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(rem '0 '3))))
    (format t "HOST-RESULT|rem-0125|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0125|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (rem '0 '3))))))
    (format t "HOST-RESULT|rem-0125|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0125|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(rem '0 '0))))
    (format t "HOST-RESULT|rem-0126|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0126|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (rem '0 '0))))))
    (format t "HOST-RESULT|rem-0126|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0126|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(rem '5/2 '-3))))
    (format t "HOST-RESULT|rem-0127|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0127|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (rem '5/2 '-3))))))
    (format t "HOST-RESULT|rem-0127|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0127|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(rem '5/2 '-2/3))))
    (format t "HOST-RESULT|rem-0128|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0128|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (rem '5/2 '-2/3))))))
    (format t "HOST-RESULT|rem-0128|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0128|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(rem '5/2 '2/3))))
    (format t "HOST-RESULT|rem-0129|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0129|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (rem '5/2 '2/3))))))
    (format t "HOST-RESULT|rem-0129|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0129|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(rem '5/2 '3))))
    (format t "HOST-RESULT|rem-0130|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0130|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (rem '5/2 '3))))))
    (format t "HOST-RESULT|rem-0130|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0130|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(rem '5/2 '0))))
    (format t "HOST-RESULT|rem-0131|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0131|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (rem '5/2 '0))))))
    (format t "HOST-RESULT|rem-0131|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0131|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(rem '7 '-3))))
    (format t "HOST-RESULT|rem-0132|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0132|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (rem '7 '-3))))))
    (format t "HOST-RESULT|rem-0132|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0132|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(rem '7 '-2/3))))
    (format t "HOST-RESULT|rem-0133|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0133|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (rem '7 '-2/3))))))
    (format t "HOST-RESULT|rem-0133|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0133|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(rem '7 '2/3))))
    (format t "HOST-RESULT|rem-0134|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0134|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (rem '7 '2/3))))))
    (format t "HOST-RESULT|rem-0134|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0134|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(rem '7 '3))))
    (format t "HOST-RESULT|rem-0135|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0135|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (rem '7 '3))))))
    (format t "HOST-RESULT|rem-0135|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0135|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(rem '7 '0))))
    (format t "HOST-RESULT|rem-0136|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0136|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (rem '7 '0))))))
    (format t "HOST-RESULT|rem-0136|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|rem-0136|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(expt '-2 '-3))))
    (format t "HOST-RESULT|expt-0146|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0146|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (expt '-2 '-3))))))
    (format t "HOST-RESULT|expt-0146|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0146|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(expt '-2 '3))))
    (format t "HOST-RESULT|expt-0147|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0147|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (expt '-2 '3))))))
    (format t "HOST-RESULT|expt-0147|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0147|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(expt '-1 '-4))))
    (format t "HOST-RESULT|expt-0148|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0148|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (expt '-1 '-4))))))
    (format t "HOST-RESULT|expt-0148|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0148|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(expt '-1 '5))))
    (format t "HOST-RESULT|expt-0149|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0149|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (expt '-1 '5))))))
    (format t "HOST-RESULT|expt-0149|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0149|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(expt '-1/2 '-2))))
    (format t "HOST-RESULT|expt-0150|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0150|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (expt '-1/2 '-2))))))
    (format t "HOST-RESULT|expt-0150|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0150|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(expt '-1/2 '3))))
    (format t "HOST-RESULT|expt-0151|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0151|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (expt '-1/2 '3))))))
    (format t "HOST-RESULT|expt-0151|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0151|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(expt '0 '0))))
    (format t "HOST-RESULT|expt-0152|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0152|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (expt '0 '0))))))
    (format t "HOST-RESULT|expt-0152|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0152|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(expt '0 '3))))
    (format t "HOST-RESULT|expt-0153|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0153|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (expt '0 '3))))))
    (format t "HOST-RESULT|expt-0153|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0153|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(expt '0 '-1))))
    (format t "HOST-RESULT|expt-0154|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0154|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (expt '0 '-1))))))
    (format t "HOST-RESULT|expt-0154|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0154|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(expt '1/2 '-3))))
    (format t "HOST-RESULT|expt-0155|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0155|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (expt '1/2 '-3))))))
    (format t "HOST-RESULT|expt-0155|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0155|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(expt '2 '0))))
    (format t "HOST-RESULT|expt-0156|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0156|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (expt '2 '0))))))
    (format t "HOST-RESULT|expt-0156|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0156|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(expt '2 '10))))
    (format t "HOST-RESULT|expt-0157|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0157|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (expt '2 '10))))))
    (format t "HOST-RESULT|expt-0157|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0157|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(expt '#C(1 1) '2))))
    (format t "HOST-RESULT|expt-0158|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0158|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (expt '#C(1 1) '2))))))
    (format t "HOST-RESULT|expt-0158|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0158|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(expt '#C(1 1) '-2))))
    (format t "HOST-RESULT|expt-0159|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0159|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (expt '#C(1 1) '-2))))))
    (format t "HOST-RESULT|expt-0159|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0159|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(expt '#C(1/2 -1/3) '3))))
    (format t "HOST-RESULT|expt-0160|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0160|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (expt '#C(1/2 -1/3) '3))))))
    (format t "HOST-RESULT|expt-0160|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0160|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(expt '#C(2 -1) '-1))))
    (format t "HOST-RESULT|expt-0161|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0161|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (expt '#C(2 -1) '-1))))))
    (format t "HOST-RESULT|expt-0161|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|expt-0161|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-65 (expt '2 '0)))))
    (format t "HOST-RESULT|loghead-0162|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0162|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-65 (expt '2 '0)))))))
    (format t "HOST-RESULT|loghead-0162|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0162|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-64 (expt '2 '0)))))
    (format t "HOST-RESULT|loghead-0163|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0163|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-64 (expt '2 '0)))))))
    (format t "HOST-RESULT|loghead-0163|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0163|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-17 (expt '2 '0)))))
    (format t "HOST-RESULT|loghead-0164|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0164|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-17 (expt '2 '0)))))))
    (format t "HOST-RESULT|loghead-0164|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0164|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-1 (expt '2 '0)))))
    (format t "HOST-RESULT|loghead-0165|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0165|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-1 (expt '2 '0)))))))
    (format t "HOST-RESULT|loghead-0165|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0165|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '0 (expt '2 '0)))))
    (format t "HOST-RESULT|loghead-0166|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0166|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '0 (expt '2 '0)))))))
    (format t "HOST-RESULT|loghead-0166|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0166|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '1 (expt '2 '0)))))
    (format t "HOST-RESULT|loghead-0167|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0167|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '1 (expt '2 '0)))))))
    (format t "HOST-RESULT|loghead-0167|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0167|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '17 (expt '2 '0)))))
    (format t "HOST-RESULT|loghead-0168|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0168|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '17 (expt '2 '0)))))))
    (format t "HOST-RESULT|loghead-0168|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0168|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '63 (expt '2 '0)))))
    (format t "HOST-RESULT|loghead-0169|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0169|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '63 (expt '2 '0)))))))
    (format t "HOST-RESULT|loghead-0169|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0169|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '64 (expt '2 '0)))))
    (format t "HOST-RESULT|loghead-0170|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0170|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '64 (expt '2 '0)))))))
    (format t "HOST-RESULT|loghead-0170|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0170|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-65 (expt '2 '1)))))
    (format t "HOST-RESULT|loghead-0171|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0171|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-65 (expt '2 '1)))))))
    (format t "HOST-RESULT|loghead-0171|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0171|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-64 (expt '2 '1)))))
    (format t "HOST-RESULT|loghead-0172|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0172|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-64 (expt '2 '1)))))))
    (format t "HOST-RESULT|loghead-0172|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0172|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-17 (expt '2 '1)))))
    (format t "HOST-RESULT|loghead-0173|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0173|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-17 (expt '2 '1)))))))
    (format t "HOST-RESULT|loghead-0173|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0173|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-1 (expt '2 '1)))))
    (format t "HOST-RESULT|loghead-0174|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0174|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-1 (expt '2 '1)))))))
    (format t "HOST-RESULT|loghead-0174|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0174|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '0 (expt '2 '1)))))
    (format t "HOST-RESULT|loghead-0175|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0175|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '0 (expt '2 '1)))))))
    (format t "HOST-RESULT|loghead-0175|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0175|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '1 (expt '2 '1)))))
    (format t "HOST-RESULT|loghead-0176|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0176|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '1 (expt '2 '1)))))))
    (format t "HOST-RESULT|loghead-0176|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0176|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '17 (expt '2 '1)))))
    (format t "HOST-RESULT|loghead-0177|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0177|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '17 (expt '2 '1)))))))
    (format t "HOST-RESULT|loghead-0177|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0177|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '63 (expt '2 '1)))))
    (format t "HOST-RESULT|loghead-0178|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0178|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '63 (expt '2 '1)))))))
    (format t "HOST-RESULT|loghead-0178|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0178|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '64 (expt '2 '1)))))
    (format t "HOST-RESULT|loghead-0179|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0179|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '64 (expt '2 '1)))))))
    (format t "HOST-RESULT|loghead-0179|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0179|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-65 (expt '2 '3)))))
    (format t "HOST-RESULT|loghead-0180|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0180|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-65 (expt '2 '3)))))))
    (format t "HOST-RESULT|loghead-0180|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0180|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-64 (expt '2 '3)))))
    (format t "HOST-RESULT|loghead-0181|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0181|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-64 (expt '2 '3)))))))
    (format t "HOST-RESULT|loghead-0181|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0181|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-17 (expt '2 '3)))))
    (format t "HOST-RESULT|loghead-0182|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0182|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-17 (expt '2 '3)))))))
    (format t "HOST-RESULT|loghead-0182|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0182|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-1 (expt '2 '3)))))
    (format t "HOST-RESULT|loghead-0183|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0183|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-1 (expt '2 '3)))))))
    (format t "HOST-RESULT|loghead-0183|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0183|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '0 (expt '2 '3)))))
    (format t "HOST-RESULT|loghead-0184|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0184|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '0 (expt '2 '3)))))))
    (format t "HOST-RESULT|loghead-0184|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0184|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '1 (expt '2 '3)))))
    (format t "HOST-RESULT|loghead-0185|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0185|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '1 (expt '2 '3)))))))
    (format t "HOST-RESULT|loghead-0185|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0185|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '17 (expt '2 '3)))))
    (format t "HOST-RESULT|loghead-0186|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0186|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '17 (expt '2 '3)))))))
    (format t "HOST-RESULT|loghead-0186|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0186|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '63 (expt '2 '3)))))
    (format t "HOST-RESULT|loghead-0187|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0187|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '63 (expt '2 '3)))))))
    (format t "HOST-RESULT|loghead-0187|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0187|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '64 (expt '2 '3)))))
    (format t "HOST-RESULT|loghead-0188|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0188|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '64 (expt '2 '3)))))))
    (format t "HOST-RESULT|loghead-0188|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0188|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-65 (expt '2 '6)))))
    (format t "HOST-RESULT|loghead-0189|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0189|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-65 (expt '2 '6)))))))
    (format t "HOST-RESULT|loghead-0189|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0189|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-64 (expt '2 '6)))))
    (format t "HOST-RESULT|loghead-0190|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0190|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-64 (expt '2 '6)))))))
    (format t "HOST-RESULT|loghead-0190|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0190|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-17 (expt '2 '6)))))
    (format t "HOST-RESULT|loghead-0191|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0191|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-17 (expt '2 '6)))))))
    (format t "HOST-RESULT|loghead-0191|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0191|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-1 (expt '2 '6)))))
    (format t "HOST-RESULT|loghead-0192|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0192|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-1 (expt '2 '6)))))))
    (format t "HOST-RESULT|loghead-0192|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0192|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '0 (expt '2 '6)))))
    (format t "HOST-RESULT|loghead-0193|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0193|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '0 (expt '2 '6)))))))
    (format t "HOST-RESULT|loghead-0193|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0193|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '1 (expt '2 '6)))))
    (format t "HOST-RESULT|loghead-0194|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0194|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '1 (expt '2 '6)))))))
    (format t "HOST-RESULT|loghead-0194|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0194|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '17 (expt '2 '6)))))
    (format t "HOST-RESULT|loghead-0195|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0195|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '17 (expt '2 '6)))))))
    (format t "HOST-RESULT|loghead-0195|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0195|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '63 (expt '2 '6)))))
    (format t "HOST-RESULT|loghead-0196|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0196|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '63 (expt '2 '6)))))))
    (format t "HOST-RESULT|loghead-0196|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0196|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '64 (expt '2 '6)))))
    (format t "HOST-RESULT|loghead-0197|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0197|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '64 (expt '2 '6)))))))
    (format t "HOST-RESULT|loghead-0197|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0197|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-65 (expt '2 '7)))))
    (format t "HOST-RESULT|loghead-0198|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0198|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-65 (expt '2 '7)))))))
    (format t "HOST-RESULT|loghead-0198|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0198|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-64 (expt '2 '7)))))
    (format t "HOST-RESULT|loghead-0199|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0199|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-64 (expt '2 '7)))))))
    (format t "HOST-RESULT|loghead-0199|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0199|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-17 (expt '2 '7)))))
    (format t "HOST-RESULT|loghead-0200|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0200|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-17 (expt '2 '7)))))))
    (format t "HOST-RESULT|loghead-0200|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0200|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-1 (expt '2 '7)))))
    (format t "HOST-RESULT|loghead-0201|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0201|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-1 (expt '2 '7)))))))
    (format t "HOST-RESULT|loghead-0201|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0201|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '0 (expt '2 '7)))))
    (format t "HOST-RESULT|loghead-0202|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0202|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '0 (expt '2 '7)))))))
    (format t "HOST-RESULT|loghead-0202|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0202|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '1 (expt '2 '7)))))
    (format t "HOST-RESULT|loghead-0203|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0203|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '1 (expt '2 '7)))))))
    (format t "HOST-RESULT|loghead-0203|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0203|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '17 (expt '2 '7)))))
    (format t "HOST-RESULT|loghead-0204|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0204|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '17 (expt '2 '7)))))))
    (format t "HOST-RESULT|loghead-0204|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0204|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '63 (expt '2 '7)))))
    (format t "HOST-RESULT|loghead-0205|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0205|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '63 (expt '2 '7)))))))
    (format t "HOST-RESULT|loghead-0205|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0205|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '64 (expt '2 '7)))))
    (format t "HOST-RESULT|loghead-0206|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0206|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '64 (expt '2 '7)))))))
    (format t "HOST-RESULT|loghead-0206|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0206|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-65 (expt '2 '64)))))
    (format t "HOST-RESULT|loghead-0207|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0207|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-65 (expt '2 '64)))))))
    (format t "HOST-RESULT|loghead-0207|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0207|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-64 (expt '2 '64)))))
    (format t "HOST-RESULT|loghead-0208|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0208|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-64 (expt '2 '64)))))))
    (format t "HOST-RESULT|loghead-0208|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0208|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-17 (expt '2 '64)))))
    (format t "HOST-RESULT|loghead-0209|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0209|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-17 (expt '2 '64)))))))
    (format t "HOST-RESULT|loghead-0209|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0209|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '-1 (expt '2 '64)))))
    (format t "HOST-RESULT|loghead-0210|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0210|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '-1 (expt '2 '64)))))))
    (format t "HOST-RESULT|loghead-0210|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0210|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '0 (expt '2 '64)))))
    (format t "HOST-RESULT|loghead-0211|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0211|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '0 (expt '2 '64)))))))
    (format t "HOST-RESULT|loghead-0211|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0211|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '1 (expt '2 '64)))))
    (format t "HOST-RESULT|loghead-0212|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0212|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '1 (expt '2 '64)))))))
    (format t "HOST-RESULT|loghead-0212|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0212|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '17 (expt '2 '64)))))
    (format t "HOST-RESULT|loghead-0213|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0213|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '17 (expt '2 '64)))))))
    (format t "HOST-RESULT|loghead-0213|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0213|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '63 (expt '2 '64)))))
    (format t "HOST-RESULT|loghead-0214|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0214|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '63 (expt '2 '64)))))))
    (format t "HOST-RESULT|loghead-0214|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0214|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(mod '64 (expt '2 '64)))))
    (format t "HOST-RESULT|loghead-0215|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0215|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (mod '64 (expt '2 '64)))))))
    (format t "HOST-RESULT|loghead-0215|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|loghead-0215|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '-65 (expt '2 '0)))))
    (format t "HOST-RESULT|logtail-0219|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0219|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '-65 (expt '2 '0)))))))
    (format t "HOST-RESULT|logtail-0219|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0219|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '-64 (expt '2 '0)))))
    (format t "HOST-RESULT|logtail-0220|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0220|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '-64 (expt '2 '0)))))))
    (format t "HOST-RESULT|logtail-0220|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0220|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '-17 (expt '2 '0)))))
    (format t "HOST-RESULT|logtail-0221|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0221|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '-17 (expt '2 '0)))))))
    (format t "HOST-RESULT|logtail-0221|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0221|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '-1 (expt '2 '0)))))
    (format t "HOST-RESULT|logtail-0222|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0222|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '-1 (expt '2 '0)))))))
    (format t "HOST-RESULT|logtail-0222|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0222|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '0 (expt '2 '0)))))
    (format t "HOST-RESULT|logtail-0223|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0223|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '0 (expt '2 '0)))))))
    (format t "HOST-RESULT|logtail-0223|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0223|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '1 (expt '2 '0)))))
    (format t "HOST-RESULT|logtail-0224|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0224|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '1 (expt '2 '0)))))))
    (format t "HOST-RESULT|logtail-0224|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0224|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '17 (expt '2 '0)))))
    (format t "HOST-RESULT|logtail-0225|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0225|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '17 (expt '2 '0)))))))
    (format t "HOST-RESULT|logtail-0225|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0225|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '63 (expt '2 '0)))))
    (format t "HOST-RESULT|logtail-0226|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0226|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '63 (expt '2 '0)))))))
    (format t "HOST-RESULT|logtail-0226|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0226|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '64 (expt '2 '0)))))
    (format t "HOST-RESULT|logtail-0227|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0227|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '64 (expt '2 '0)))))))
    (format t "HOST-RESULT|logtail-0227|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0227|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '-65 (expt '2 '1)))))
    (format t "HOST-RESULT|logtail-0228|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0228|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '-65 (expt '2 '1)))))))
    (format t "HOST-RESULT|logtail-0228|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0228|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '-64 (expt '2 '1)))))
    (format t "HOST-RESULT|logtail-0229|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0229|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '-64 (expt '2 '1)))))))
    (format t "HOST-RESULT|logtail-0229|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0229|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '-17 (expt '2 '1)))))
    (format t "HOST-RESULT|logtail-0230|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0230|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '-17 (expt '2 '1)))))))
    (format t "HOST-RESULT|logtail-0230|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0230|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '-1 (expt '2 '1)))))
    (format t "HOST-RESULT|logtail-0231|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0231|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '-1 (expt '2 '1)))))))
    (format t "HOST-RESULT|logtail-0231|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0231|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '0 (expt '2 '1)))))
    (format t "HOST-RESULT|logtail-0232|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0232|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '0 (expt '2 '1)))))))
    (format t "HOST-RESULT|logtail-0232|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0232|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '1 (expt '2 '1)))))
    (format t "HOST-RESULT|logtail-0233|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0233|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '1 (expt '2 '1)))))))
    (format t "HOST-RESULT|logtail-0233|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0233|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '17 (expt '2 '1)))))
    (format t "HOST-RESULT|logtail-0234|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0234|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '17 (expt '2 '1)))))))
    (format t "HOST-RESULT|logtail-0234|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0234|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '63 (expt '2 '1)))))
    (format t "HOST-RESULT|logtail-0235|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0235|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '63 (expt '2 '1)))))))
    (format t "HOST-RESULT|logtail-0235|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0235|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '64 (expt '2 '1)))))
    (format t "HOST-RESULT|logtail-0236|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0236|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '64 (expt '2 '1)))))))
    (format t "HOST-RESULT|logtail-0236|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0236|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '-65 (expt '2 '3)))))
    (format t "HOST-RESULT|logtail-0237|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0237|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '-65 (expt '2 '3)))))))
    (format t "HOST-RESULT|logtail-0237|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0237|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '-64 (expt '2 '3)))))
    (format t "HOST-RESULT|logtail-0238|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0238|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '-64 (expt '2 '3)))))))
    (format t "HOST-RESULT|logtail-0238|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0238|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '-17 (expt '2 '3)))))
    (format t "HOST-RESULT|logtail-0239|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0239|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '-17 (expt '2 '3)))))))
    (format t "HOST-RESULT|logtail-0239|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0239|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '-1 (expt '2 '3)))))
    (format t "HOST-RESULT|logtail-0240|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0240|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '-1 (expt '2 '3)))))))
    (format t "HOST-RESULT|logtail-0240|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0240|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '0 (expt '2 '3)))))
    (format t "HOST-RESULT|logtail-0241|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0241|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '0 (expt '2 '3)))))))
    (format t "HOST-RESULT|logtail-0241|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0241|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '1 (expt '2 '3)))))
    (format t "HOST-RESULT|logtail-0242|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0242|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '1 (expt '2 '3)))))))
    (format t "HOST-RESULT|logtail-0242|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0242|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '17 (expt '2 '3)))))
    (format t "HOST-RESULT|logtail-0243|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0243|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '17 (expt '2 '3)))))))
    (format t "HOST-RESULT|logtail-0243|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0243|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '63 (expt '2 '3)))))
    (format t "HOST-RESULT|logtail-0244|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0244|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '63 (expt '2 '3)))))))
    (format t "HOST-RESULT|logtail-0244|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0244|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '64 (expt '2 '3)))))
    (format t "HOST-RESULT|logtail-0245|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0245|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '64 (expt '2 '3)))))))
    (format t "HOST-RESULT|logtail-0245|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0245|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '-65 (expt '2 '6)))))
    (format t "HOST-RESULT|logtail-0246|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0246|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '-65 (expt '2 '6)))))))
    (format t "HOST-RESULT|logtail-0246|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0246|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '-64 (expt '2 '6)))))
    (format t "HOST-RESULT|logtail-0247|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0247|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '-64 (expt '2 '6)))))))
    (format t "HOST-RESULT|logtail-0247|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0247|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '-17 (expt '2 '6)))))
    (format t "HOST-RESULT|logtail-0248|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0248|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '-17 (expt '2 '6)))))))
    (format t "HOST-RESULT|logtail-0248|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0248|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '-1 (expt '2 '6)))))
    (format t "HOST-RESULT|logtail-0249|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0249|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '-1 (expt '2 '6)))))))
    (format t "HOST-RESULT|logtail-0249|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0249|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '0 (expt '2 '6)))))
    (format t "HOST-RESULT|logtail-0250|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0250|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '0 (expt '2 '6)))))))
    (format t "HOST-RESULT|logtail-0250|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0250|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '1 (expt '2 '6)))))
    (format t "HOST-RESULT|logtail-0251|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0251|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '1 (expt '2 '6)))))))
    (format t "HOST-RESULT|logtail-0251|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0251|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '17 (expt '2 '6)))))
    (format t "HOST-RESULT|logtail-0252|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0252|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '17 (expt '2 '6)))))))
    (format t "HOST-RESULT|logtail-0252|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0252|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '63 (expt '2 '6)))))
    (format t "HOST-RESULT|logtail-0253|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0253|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '63 (expt '2 '6)))))))
    (format t "HOST-RESULT|logtail-0253|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0253|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '64 (expt '2 '6)))))
    (format t "HOST-RESULT|logtail-0254|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0254|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '64 (expt '2 '6)))))))
    (format t "HOST-RESULT|logtail-0254|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0254|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '-65 (expt '2 '7)))))
    (format t "HOST-RESULT|logtail-0255|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0255|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '-65 (expt '2 '7)))))))
    (format t "HOST-RESULT|logtail-0255|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0255|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '-64 (expt '2 '7)))))
    (format t "HOST-RESULT|logtail-0256|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0256|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '-64 (expt '2 '7)))))))
    (format t "HOST-RESULT|logtail-0256|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0256|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '-17 (expt '2 '7)))))
    (format t "HOST-RESULT|logtail-0257|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0257|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '-17 (expt '2 '7)))))))
    (format t "HOST-RESULT|logtail-0257|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0257|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '-1 (expt '2 '7)))))
    (format t "HOST-RESULT|logtail-0258|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0258|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '-1 (expt '2 '7)))))))
    (format t "HOST-RESULT|logtail-0258|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0258|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '0 (expt '2 '7)))))
    (format t "HOST-RESULT|logtail-0259|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0259|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '0 (expt '2 '7)))))))
    (format t "HOST-RESULT|logtail-0259|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0259|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '1 (expt '2 '7)))))
    (format t "HOST-RESULT|logtail-0260|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0260|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '1 (expt '2 '7)))))))
    (format t "HOST-RESULT|logtail-0260|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0260|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '17 (expt '2 '7)))))
    (format t "HOST-RESULT|logtail-0261|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0261|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '17 (expt '2 '7)))))))
    (format t "HOST-RESULT|logtail-0261|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0261|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '63 (expt '2 '7)))))
    (format t "HOST-RESULT|logtail-0262|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0262|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '63 (expt '2 '7)))))))
    (format t "HOST-RESULT|logtail-0262|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0262|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '64 (expt '2 '7)))))
    (format t "HOST-RESULT|logtail-0263|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0263|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '64 (expt '2 '7)))))))
    (format t "HOST-RESULT|logtail-0263|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0263|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '-65 (expt '2 '64)))))
    (format t "HOST-RESULT|logtail-0264|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0264|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '-65 (expt '2 '64)))))))
    (format t "HOST-RESULT|logtail-0264|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0264|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '-64 (expt '2 '64)))))
    (format t "HOST-RESULT|logtail-0265|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0265|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '-64 (expt '2 '64)))))))
    (format t "HOST-RESULT|logtail-0265|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0265|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '-17 (expt '2 '64)))))
    (format t "HOST-RESULT|logtail-0266|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0266|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '-17 (expt '2 '64)))))))
    (format t "HOST-RESULT|logtail-0266|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0266|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '-1 (expt '2 '64)))))
    (format t "HOST-RESULT|logtail-0267|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0267|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '-1 (expt '2 '64)))))))
    (format t "HOST-RESULT|logtail-0267|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0267|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '0 (expt '2 '64)))))
    (format t "HOST-RESULT|logtail-0268|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0268|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '0 (expt '2 '64)))))))
    (format t "HOST-RESULT|logtail-0268|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0268|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '1 (expt '2 '64)))))
    (format t "HOST-RESULT|logtail-0269|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0269|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '1 (expt '2 '64)))))))
    (format t "HOST-RESULT|logtail-0269|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0269|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '17 (expt '2 '64)))))
    (format t "HOST-RESULT|logtail-0270|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0270|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '17 (expt '2 '64)))))))
    (format t "HOST-RESULT|logtail-0270|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0270|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '63 (expt '2 '64)))))
    (format t "HOST-RESULT|logtail-0271|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0271|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '63 (expt '2 '64)))))))
    (format t "HOST-RESULT|logtail-0271|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0271|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(floor '64 (expt '2 '64)))))
    (format t "HOST-RESULT|logtail-0272|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0272|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (floor '64 (expt '2 '64)))))))
    (format t "HOST-RESULT|logtail-0272|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|logtail-0272|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(< '-1 '0))))
    (format t "HOST-RESULT|lexicographic-<-0276|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0276|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (< '-1 '0))))))
    (format t "HOST-RESULT|lexicographic-<-0276|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0276|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(< '0 '1/2))))
    (format t "HOST-RESULT|lexicographic-<-0277|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0277|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (< '0 '1/2))))))
    (format t "HOST-RESULT|lexicographic-<-0277|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0277|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(< '1/2 '2))))
    (format t "HOST-RESULT|lexicographic-<-0278|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0278|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (< '1/2 '2))))))
    (format t "HOST-RESULT|lexicographic-<-0278|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0278|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(< '2 '#C(-1 1)))))
    (format t "HOST-RESULT|lexicographic-<-0279|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0279|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (< '2 '#C(-1 1)))))))
    (format t "HOST-RESULT|lexicographic-<-0279|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0279|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(< '#C(-1 1) '#C(0 -1)))))
    (format t "HOST-RESULT|lexicographic-<-0280|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0280|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (< '#C(-1 1) '#C(0 -1)))))))
    (format t "HOST-RESULT|lexicographic-<-0280|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0280|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(< '#C(0 -1) '#C(0 1)))))
    (format t "HOST-RESULT|lexicographic-<-0281|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0281|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (< '#C(0 -1) '#C(0 1)))))))
    (format t "HOST-RESULT|lexicographic-<-0281|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0281|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(< '#C(0 1) '#C(1/2 -2)))))
    (format t "HOST-RESULT|lexicographic-<-0282|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0282|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (< '#C(0 1) '#C(1/2 -2)))))))
    (format t "HOST-RESULT|lexicographic-<-0282|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0282|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(< '#C(1/2 -2) '#C(1/2 -1)))))
    (format t "HOST-RESULT|lexicographic-<-0283|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0283|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (< '#C(1/2 -2) '#C(1/2 -1)))))))
    (format t "HOST-RESULT|lexicographic-<-0283|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0283|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(< '#C(1/2 -1) '#C(1/2 0)))))
    (format t "HOST-RESULT|lexicographic-<-0284|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0284|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (< '#C(1/2 -1) '#C(1/2 0)))))))
    (format t "HOST-RESULT|lexicographic-<-0284|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0284|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(< '#C(1/2 0) '#C(1/2 1)))))
    (format t "HOST-RESULT|lexicographic-<-0285|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0285|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (< '#C(1/2 0) '#C(1/2 1)))))))
    (format t "HOST-RESULT|lexicographic-<-0285|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0285|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(< '#C(1/2 1) '#C(2 -100)))))
    (format t "HOST-RESULT|lexicographic-<-0286|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0286|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (< '#C(1/2 1) '#C(2 -100)))))))
    (format t "HOST-RESULT|lexicographic-<-0286|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0286|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(< '#C(2 -100) '-1))))
    (format t "HOST-RESULT|lexicographic-<-0287|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0287|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (< '#C(2 -100) '-1))))))
    (format t "HOST-RESULT|lexicographic-<-0287|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0287|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(< '#C(1 2) '#C(1 3)))))
    (format t "HOST-RESULT|lexicographic-<-0288|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0288|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (< '#C(1 2) '#C(1 3)))))))
    (format t "HOST-RESULT|lexicographic-<-0288|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0288|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(< '#C(1 3) '#C(1 2)))))
    (format t "HOST-RESULT|lexicographic-<-0289|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0289|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (< '#C(1 3) '#C(1 2)))))))
    (format t "HOST-RESULT|lexicographic-<-0289|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0289|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(< '#C(1 2) '2))))
    (format t "HOST-RESULT|lexicographic-<-0290|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0290|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (< '#C(1 2) '2))))))
    (format t "HOST-RESULT|lexicographic-<-0290|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0290|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(< '1 '2))))
    (format t "HOST-RESULT|lexicographic-<-0291|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0291|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (< '1 '2))))))
    (format t "HOST-RESULT|lexicographic-<-0291|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0291|compiled|:ERROR~%")))

(handler-case
  (let ((value (eval '(< '2 '2))))
    (format t "HOST-RESULT|lexicographic-<-0292|eval|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0292|eval|:ERROR~%")))

(handler-case
  (let ((value (funcall (compile nil '(lambda () (< '2 '2))))))
    (format t "HOST-RESULT|lexicographic-<-0292|compiled|~s~%" value))
  (error ()
    (format t "HOST-RESULT|lexicographic-<-0292|compiled|:ERROR~%")))

(quit)
