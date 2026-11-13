; Modern COMPRESS1 routes: honsed input and attempted memoization of the builtin.
(defconst *shared-alist*
  (hons '(:header :dimensions (4) :maximum-length 5
                  :default 1 :name a :order <)
        (hons (hons 1 1) nil)))
(defconst *compressed-hons*
  (compress1 'a *shared-alist*))
(cw "HONS-COMPRESSED ~x0~%" *compressed-hons*)
(defthm hons-compress-good
  (equal *compressed-hons*
         '((:header :dimensions (4) :maximum-length 5
                    :default 1 :name a :order <)))
  :rule-classes nil)
; The first attempt without options is rejected because COMPRESS1 has raw code.
; :RECURSIVE NIL is the documented escape for such builtins; exercise it too.
(memoize 'compress1 :recursive nil)
(cw "MEMOIZED-C1 ~x0~%"
    (compress1 'a '((:header :dimensions (4) :maximum-length 5
                             :default 1 :name a :order <)
                    (1 . 1))))
(cw "MEMOIZED-C2 ~x0~%"
    (compress1 'a '((:header :dimensions (4) :maximum-length 5
                             :default nil :name a :order >)
                    (1 . 1) (2 . 2))))
(defthm memoized-compress-good
  (equal (compress1 'a '((:header :dimensions (4) :maximum-length 5
                                  :default nil :name a :order >)
                         (1 . 1) (2 . 2)))
         '((:header :dimensions (4) :maximum-length 5
                    :default nil :name a :order >)
           (2 . 2) (1 . 1)))
  :rule-classes nil)
(quit)
