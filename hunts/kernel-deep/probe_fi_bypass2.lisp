;; Test 1: prog-loop without irrelevant formal, both with and without :do-not '(preprocess)
(encapsulate
  (((ef *) => *))
  (local (defun ef (x) x))
  (defthm ef-id (equal (ef x) x)))

(defun prog-loop (x)
  (declare (xargs :mode :program))
  (and x (not (prog-loop x))))

;; Normal preprocess -> HARD ACL2 ERROR in EXPAND-ABBREVIATIONS?
(thm (equal x x)
     :hints (("Goal"
              :use ((:functional-instance ef-id (ef prog-loop))))))

;; With :do-not '(preprocess), what happens with ground term (prog-loop 1)?
(encapsulate
  (((ef2 *) => *))
  (local (defun ef2 (x) (not (not x))))
  (defthm ef2-ground (implies (equal x 1) (equal (ef2 1) t))))

(thm (equal x x)
     :hints (("Goal"
              :do-not '(preprocess)
              :use ((:functional-instance ef2-ground (ef2 prog-loop))))))

;; Test 2: :functional-instance substituting a stobj-taking function or stobj-returning function
;; into an encapsulate whose constraint assumes pure values!
(defstobj st (f :initially 0))

(encapsulate
  (((epure *) => *))
  (local (defun epure (x) x))
  (defthm epure-id (equal (epure x) x)))

(defun st-upd (st)
  (declare (xargs :stobjs st))
  (update-f 1 st))

;; Instantiate epure with st-upd inside a defun's :hints or verify-guards?
(defun use-st (st)
  (declare (xargs :stobjs st
                  :hints (("Goal" :use ((:functional-instance epure-id (epure st-upd)))))))
  (mv (f st) st))

;; Test 3: What if a :functional-instance introduces a :program function in a SUBGOAL
;; that reaches induction or another clause processor or rewrite?
(thm (equal (cons x y) (cons x y))
     :hints (("Goal"
              :do-not '(preprocess)
              :use ((:functional-instance ef-id (ef prog-loop))))))

;; Test 4: Can we prove something with (:functional-instance thm-with-no-constraints (ef prog-loop))?
(defthm ef-const (equal (car (cons x (ef y))) x))
(thm nil
     :rule-classes nil
     :hints (("Goal"
              :do-not '(preprocess)
              :use ((:functional-instance ef-const (ef prog-loop))))))
