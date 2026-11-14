(in-package "ACL2")

; Follow-up probe on :functional-instance edge cases:
; 1. :program mode fn2 bypassing EXPAND-ABBREVIATIONS (or inside :by, :or, :do-not, etc.)
(encapsulate
  (((ef *) => *))
  (local (defun ef (x) x))
  (defthm ef-id (equal (ef x) (ef x)) :rule-classes nil))

(defun prog-id (x)
  (declare (xargs :mode :program))
  x)

(make-event
 (mv-let (erp val state)
   (defthm test-prog-by
     (equal (prog-id x) (prog-id x))
     :hints (("Goal" :by (:functional-instance ef-id (ef prog-id))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-prog-by :accepted-prog-by)))))

; 2. Disabled stobj mutator evaluated on '0 via :executable-counterpart
(defstobj myst (fld :type integer :initially 0))
(defun st-upd (myst)
  (declare (xargs :stobjs myst))
  (update-fld 42 myst))
(in-theory (disable st-upd))

(make-event
 (mv-let (erp val state)
   (defthm test-st-exec
     (equal (car (cons x y)) x)
     :hints (("Goal" :use ((:instance (:functional-instance ef-id (ef st-upd)) (x 0)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-st-exec :accepted-st-exec)))))

; 3. Function taking STATE (verify-guards nil) in :functional-instance
(defun state-fn (state)
  (declare (xargs :stobjs state :verify-guards nil))
  (f-get-global 'last-make-event-expansion state))
(in-theory (disable state-fn))

(make-event
 (mv-let (erp val state)
   (defthm test-state-exec
     (equal (car (cons x y)) x)
     :hints (("Goal" :use ((:instance (:functional-instance ef-id (ef state-fn)) (x 0)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-state-exec :accepted-state-exec)))))

; 4. Functional instance with st-upd where goal has NO expand-abbreviations?
(defun st-read (myst)
  (declare (xargs :stobjs myst))
  (fld myst))
(in-theory (disable st-read))

(make-event
 (mv-let (erp val state)
   (defthm test-st-read-const
     (equal (car (cons x y)) x)
     :hints (("Goal" :use ((:instance (:functional-instance ef-id (ef st-read)) (x 0)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-st-read :accepted-st-read)))))

; 5. Functional instance with :do-not '(preprocess) and prog-id
(make-event
 (mv-let (erp val state)
   (defthm test-prog-nopp
     (equal (car (cons x y)) x)
     :hints (("Goal" :do-not '(preprocess)
              :use ((:instance (:functional-instance ef-id (ef prog-id)) (x 0)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-prog-nopp :accepted-prog-nopp)))))
