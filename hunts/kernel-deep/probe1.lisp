; Quick probe 1: functional-instance with :program fn2, stobj/mv mismatch, defchoose
(in-package "ACL2")

; Case 1: :program mode fn2 in :functional-instance
(defun f1 (x) (declare (ignore x)) t)
(defthm f1-is-t (f1 x) :rule-classes nil)
(defun prog-g (x) (declare (xargs :mode :program)) (car x))

; Try using prog-g in :functional-instance
(make-event
 (mv-let (erp val state)
   (defthm test-prog-fi
     (equal (car (cons x y)) x)
     :hints (("Goal" :use ((:functional-instance f1-is-t (f1 prog-g)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-prog :accepted-prog)))))

; Case 2: stobjs-out mismatch (1 value vs mv)
(defun mv-g (x) (mv x x))
(make-event
 (mv-let (erp val state)
   (defthm test-mv-fi
     (equal (car (cons x y)) x)
     :hints (("Goal" :use ((:functional-instance f1-is-t (f1 mv-g)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-mv :accepted-mv)))))

; Case 3: stobjs-in mismatch (normal vs stobj)
(defstobj myst fld)
(defun st-g (myst) (declare (xargs :stobjs myst)) (fld myst))
(make-event
 (mv-let (erp val state)
   (defthm test-st-fi
     (equal (car (cons x y)) x)
     :hints (("Goal" :use ((:functional-instance f1-is-t (f1 st-g)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-st :accepted-st)))))

; Case 4: non-executable fn2
(defun-nx nx-g (x) (cons x x))
(make-event
 (mv-let (erp val state)
   (defthm test-nx-fi
     (equal (car (cons x y)) x)
     :hints (("Goal" :use ((:functional-instance f1-is-t (f1 nx-g)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-nx :accepted-nx)))))
