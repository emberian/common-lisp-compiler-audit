(include-book "rc")
(cw "@R host ~x0: (rc) evaluates to ~x1; logical body ~x2; theorem ~x3~%" (@ host-lisp) (rc) (getpropc 'rc 'unnormalized-body nil (w state)) (getpropc 'rc-value 'theorem nil (w state)))
(defthm contradiction nil :rule-classes nil :hints (("Goal" :use rc-value)))
(cw "@R NIL proved: ~x0~%" (if (equal (getpropc 'contradiction 'theorem t (w state)) ''nil) :YES :no))
