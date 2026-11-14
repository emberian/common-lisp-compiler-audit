;; Test :functional-instance with :program-mode function + :do-not '(preprocess),
;; non-terminating :program function, and constraint with mv-let / stobj.

(encapsulate
  (((ef *) => *))
  (local (defun ef (x) x))
  (defthm ef-id (equal (ef x) x)))

(defun prog-id (x)
  (declare (xargs :mode :program))
  x)

;; Test 1: :do-not '(preprocess) skips expand-abbreviations?
(thm (equal x x)
     :hints (("Goal"
              :do-not '(preprocess)
              :use ((:functional-instance ef-id (ef prog-id))))))

;; Test 2: non-terminating :program function used in :functional-instance!
(defun prog-loop (x)
  (declare (xargs :mode :program))
  (not (prog-loop x)))

;; What happens on Goal with normal preprocess vs :do-not '(preprocess)?
(thm (equal (cons x y) (cons x y))
     :hints (("Goal"
              :use ((:functional-instance ef-id (ef prog-loop))))))

(thm (equal (cons x y) (cons x y))
     :hints (("Goal"
              :do-not '(preprocess)
              :use ((:functional-instance ef-id (ef prog-loop))))))

;; Test 3: Can a :program function with inconsistent def prove NIL if preprocess is skipped?!
(thm nil
     :rule-classes nil
     :hints (("Goal"
              :do-not '(preprocess)
              :use ((:functional-instance ef-id (ef prog-loop))))))

;; Test 4: Can :functional-instance substitute a :program function in a :rewrite rule proof?
(defthm bad-rule
  (equal (car (cons a b)) a)
  :hints (("Goal"
           :do-not '(preprocess)
           :use ((:functional-instance ef-id (ef prog-loop))))))

;; Test 5: Functional instantiation inside a lambda!
(thm (equal x x)
     :hints (("Goal"
              :do-not '(preprocess)
              :use ((:functional-instance ef-id (ef (lambda (z) (prog-loop z))))))))

;; Test 6: :functional-instance with a :non-executable function
(defun-nx nx-id (x) x)
(thm (equal x x)
     :hints (("Goal"
              :use ((:functional-instance ef-id (ef nx-id))))))

;; Test 7: :functional-instance with defchoose and mv-let
(defchoose ch1 (a b) (x)
  (equal a (car b)))

(encapsulate
  (((ep *) => (mv * *)))
  (local (defun ep (x) (mv x x)))
  (defthm ep-prop
    (mv-let (u v) (ep x) (equal u v))))

(defun sv1 (x) x)
(thm (equal (car x) (car x))
     :hints (("Goal"
              :use ((:functional-instance ep-prop (ep sv1))))))
