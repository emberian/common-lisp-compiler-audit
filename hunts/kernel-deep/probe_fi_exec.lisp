(in-package "ACL2")

(encapsulate
  (((ef *) => *))
  (local (defun ef (x) x))
  (defthm ef-id (equal (ef x) (ef x)) :rule-classes nil))

;; 1. :program function with raw-Lisp type error (car 1)
(defun prog-crash (x)
  (declare (xargs :mode :program))
  (car (cons x (car 1))))

(make-event
 (mv-let (erp val state)
   (defthm test-prog-crash-preprocess
     (equal (car (cons x y)) x)
     :hints (("Goal" :use ((:instance (:functional-instance ef-id (ef prog-crash)) (x 0)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-1 :accepted-1)))))

(make-event
 (mv-let (erp val state)
   (defthm test-prog-crash-noprep
     (equal (car (cons x y)) x)
     :hints (("Goal"
              :do-not '(preprocess)
              :use ((:instance (:functional-instance ef-id (ef prog-crash)) (x 0)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-2 :accepted-2)))))

;; 2. :program function in a theorem whose conclusion has ONLY logic-mode,
;; wait: can a :program function evaluate in rewrite to prove NIL if it returns something inconsistent?
;; Wait: (equal (prog-crash 0) (prog-crash 0)) is a tautology. What about forcing it to evaluate (prog-crash 0) != (prog-crash 0) or just crashing?
(make-event
 (mv-let (erp val state)
   (defthm test-prog-crash-equal
     (equal (car (cons a b)) a)
     :hints (("Goal"
              :do-not '(preprocess)
              :use ((:functional-instance (:theorem (not (equal (ef 0) '999))) (ef prog-crash)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-3 :accepted-3)))))

;; 3. Stobj mutator in :functional-instance with :do-not '(preprocess)
(defstobj st0 (f0 :initially 0))
(defun st0-mut (st0)
  (declare (xargs :stobjs st0))
  (update-f0 7 st0))

(make-event
 (mv-let (erp val state)
   (defthm test-st0-noprep
     (equal (car (cons a b)) a)
     :hints (("Goal"
              :do-not '(preprocess)
              :use ((:instance (:functional-instance ef-id (ef st0-mut)) (x 0)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-4 :accepted-4)))))

;; 4. Check what happens with (ef state-fn) with :do-not '(preprocess)
(defun state-fn (state)
  (declare (xargs :stobjs state))
  (f-get-global 'last-make-event-expansion state))

(make-event
 (mv-let (erp val state)
   (defthm test-state-noprep
     (equal (car (cons a b)) a)
     :hints (("Goal"
              :do-not '(preprocess)
              :use ((:instance (:functional-instance ef-id (ef state-fn)) (x 0)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-5 :accepted-5)))))
