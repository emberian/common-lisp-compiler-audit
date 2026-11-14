(in-package "ACL2")

(encapsulate
  (((ef *) => *))
  (local (defun ef (x) x))
  (defthm ef-id (equal (ef x) (ef x)) :rule-classes nil))

; Test 1: stobj mutator in :functional-instance on constant '0
(defstobj myst (fld :type integer :initially 0))
(defun st-upd (myst)
  (declare (xargs :stobjs myst))
  (update-fld 42 myst))

(make-event
 (mv-let (erp val state)
   (defthm test-st-const
     (equal (ef '0) (ef '0))
     :hints (("Goal" :by (:functional-instance ef-id (ef st-upd))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-st-const :accepted-st-const)))))

; Wait: what if goal mentions car/cons and :use runs st-upd on '0?
(make-event
 (mv-let (erp val state)
   (defthm test-st-use-const
     (equal (car (cons x y)) x)
     :hints (("Goal" :use ((:instance (:functional-instance ef-id (ef st-upd)) (x 0)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-st-use :accepted-st-use)))))

; Test 2: function taking STATE in :functional-instance!
(defun state-fn (state)
  (declare (xargs :stobjs state))
  (f-get-global 'last-make-event-expansion state))

(make-event
 (mv-let (erp val state)
   (defthm test-state-use
     (equal (car (cons x y)) x)
     :hints (("Goal" :use ((:instance (:functional-instance ef-id (ef state-fn)) (x 0)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-state-use :accepted-state-use)))))

; Test 3: :program mode non-terminating function in :functional-instance!
(defun loop-prog (x)
  (declare (xargs :mode :program))
  (if (equal x 0) 0 (loop-prog x)))

(make-event
 (mv-let (erp val state)
   (defthm test-prog-eval
     (equal (car (cons x y)) x)
     :hints (("Goal" :use ((:instance (:functional-instance ef-id (ef loop-prog)) (x 1)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-prog-eval :accepted-prog-eval)))))

; Test 4: :program mode function with non-terminating / contradictory body?
(defun prog-id (x)
  (declare (xargs :mode :program))
  (declare (ignore x))
  t)

(make-event
 (mv-let (erp val state)
   (defthm test-prog-eq
     (equal (car (cons x y)) x)
     :hints (("Goal" :use ((:instance (:functional-instance ef-id (ef prog-id)) (x 1)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-prog-eq :accepted-prog-eq)))))

; Test 5: what if ef has constraint (equal (ef 0) 0) or we instantiate with a :program fn or defun-sk?
; Wait: can we prove (equal (prog-id 1) t)? No, prog-id has no axioms.
; Wait: what if prog-id has an executable-counterpart?! Let's check!
(make-event
 (mv-let (erp val state)
   (defthm test-prog-exec
     (equal (car (cons x y)) x)
     :hints (("Goal" :use ((:functional-instance (:theorem (equal (ef 0) (ef 0))) (ef prog-id)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-prog-exec :accepted-prog-exec)))))
