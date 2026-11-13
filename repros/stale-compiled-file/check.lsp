(include-book "book")
:pe f
(cw "@R (f 1) evaluates to ~x0, *k* is ~x1~%" (f 1) *k*)
(cw "@R logical body of f: ~x0; world value of *k*: ~x1~%" (getpropc 'f 'unnormalized-body nil (w state)) (getpropc '*k* 'const nil (w state)))
(defthm contradiction nil :rule-classes nil :hints (("Goal" :use ((:instance f-is-new (x 1))))))
(cw "@R NIL proved: ~x0~%" (if (equal (getpropc 'contradiction 'theorem t (w state)) ''nil) :YES :no))
