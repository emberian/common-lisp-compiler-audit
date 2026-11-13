; Exact NOTE-3-5 COMPRESS1 proof shapes, including attempted contradictions.
(defthm true-formula-1
  (equal (compress1 'a '((:header :dimensions (4) :maximum-length 5
                                  :default 1 :name a :order <)
                         (1 . 1)))
         '((:header :dimensions (4) :maximum-length 5
                    :default 1 :name a :order <)))
  :hints (("Goal" :in-theory (disable (compress1))))
  :rule-classes nil)
(defthm ouch-1 nil :hints (("Goal" :use true-formula-1)) :rule-classes nil)
(defthm true-formula-2
  (equal (compress1 'a '((:header :dimensions (4) :maximum-length 5
                                  :default nil :name a :order >)
                         (1 . 1) (2 . 2)))
         '((:header :dimensions (4) :maximum-length 5
                    :default nil :name a :order >)
           (2 . 2) (1 . 1)))
  :hints (("Goal" :in-theory (disable (compress1))))
  :rule-classes nil)
(defthm ouch-2 nil :hints (("Goal" :use true-formula-2)) :rule-classes nil)
(defthm true-formula-3
  (equal (compress1 'a '((:header :dimensions (3) :maximum-length 4
                                  :name a :order >)
                         (1 . b) (0 . a)))
         '((:header :dimensions (3) :maximum-length 4
                    :name a :order >)
           (1 . b) (0 . a)))
  :hints (("Goal" :in-theory (disable (compress1))))
  :rule-classes nil)
(defthm ouch-3 nil :hints (("Goal" :use true-formula-3)) :rule-classes nil)
(quit)
