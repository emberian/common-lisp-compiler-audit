; NOTE-3-5 original COMPRESS1 controls: logical and raw results must agree.
(defconst *c1*
  (compress1 'a '((:header :dimensions (4) :maximum-length 5
                           :default 1 :name a :order <)
                  (1 . 1))))
(cw "C1 ~x0~%" *c1*)
(defthm true-formula-1
  (equal *c1* '((:header :dimensions (4) :maximum-length 5
                         :default 1 :name a :order <)))
  :rule-classes nil)
(defconst *c2*
  (compress1 'a '((:header :dimensions (4) :maximum-length 5
                           :default nil :name a :order >)
                  (1 . 1) (2 . 2))))
(cw "C2 ~x0~%" *c2*)
(defthm true-formula-2
  (equal *c2* '((:header :dimensions (4) :maximum-length 5
                         :default nil :name a :order >)
                (2 . 2) (1 . 1)))
  :rule-classes nil)
(defconst *c3*
  (compress1 'a '((:header :dimensions (3) :maximum-length 4
                           :name a :order >)
                  (1 . b) (0 . a))))
(cw "C3 ~x0~%" *c3*)
(defthm true-formula-3
  (equal *c3* '((:header :dimensions (3) :maximum-length 4
                         :name a :order >)
                (1 . b) (0 . a)))
  :rule-classes nil)
(quit)
