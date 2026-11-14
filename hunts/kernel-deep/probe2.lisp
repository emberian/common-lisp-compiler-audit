(in-package "ACL2")

; Probe 2: Test :functional-instance with :program mode, mv, stobjs, defchoose, apply$
(defun f1 (x) (declare (ignore x)) t)
(defthm f1-refl (equal (f1 x) (f1 x)) :rule-classes nil)

(defun mv-g (x) (mv x x))
(defstobj myst fld)
(defun st-g (myst) (declare (xargs :stobjs myst)) (fld myst))
(defun prog-g (x) (declare (xargs :mode :program)) (car x))

; 1. :use (:functional-instance f1-refl (f1 mv-g)) -> tautology constraint? No, f1-refl has NO constraints except f1's def!
; Wait: constraint on f1 is (equal (f1 x) x)? No, f1-refl defines f1: (equal (f1 x) t).
; What about encapsulated f with tautological constraint?
(encapsulate
  (((ef *) => *))
  (local (defun ef (x) x))
  (defthm ef-refl (equal (ef x) (ef x)) :rule-classes nil))

; Now instantiate ef with mv-g, st-g, prog-g!
(make-event
 (mv-let (erp val state)
   (defthm test-ef-mv
     (equal (car (cons x y)) x)
     :hints (("Goal" :use ((:functional-instance ef-refl (ef mv-g)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-ef-mv :accepted-ef-mv)))))

(make-event
 (mv-let (erp val state)
   (defthm test-ef-st
     (equal (car (cons x y)) x)
     :hints (("Goal" :use ((:functional-instance ef-refl (ef st-g)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-ef-st :accepted-ef-st)))))

(make-event
 (mv-let (erp val state)
   (defthm test-ef-prog
     (equal (car (cons x y)) x)
     :hints (("Goal" :use ((:functional-instance ef-refl (ef prog-g)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-ef-prog :accepted-ef-prog)))))

; 2. What if ef returns mv (e.g. defchoose with 2 bound vars)?
(defchoose ch2 (a b) (x) (and (equal a x) (equal b x)))
(defthm ch2-thm (implies (and (equal a x) (equal b x)) (true-listp (ch2 x))) :rule-classes nil)
(defun one-val (x) (declare (ignore x)) 0)
(make-event
 (mv-let (erp val state)
   (defthm test-ch2-one
     (equal (car (cons x y)) x)
     :hints (("Goal" :use ((:functional-instance ch2-thm (ch2 one-val)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-ch2-one :accepted-ch2-one)))))

; 3. What about ef -> (lambda (x) (mv x x)) or (lambda (x) (prog-g x))?
(make-event
 (mv-let (erp val state)
   (defthm test-ef-lam-mv
     (equal (car (cons x y)) x)
     :hints (("Goal" :use ((:functional-instance ef-refl (ef (lambda (x) (mv x x)))))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-lam-mv :accepted-lam-mv)))))

(make-event
 (mv-let (erp val state)
   (defthm test-ef-lam-prog
     (equal (car (cons x y)) x)
     :hints (("Goal" :use ((:functional-instance ef-refl (ef (lambda (x) (prog-g x)))))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-lam-prog :accepted-lam-prog)))))
