(in-package "ACL2")

(cw "~%=== H1 TAKE ORIGINAL ===~%")
(value-triple (take 1 nil))
(defthmd take-1-nil-logic-h1
  (equal (take 1 nil) '(nil))
  :hints (("Goal" :in-theory (disable (take))))
  :rule-classes nil)
(thm nil :hints (("Goal" :use take-1-nil-logic-h1)))

(cw "~%=== H2 MV FUNCTION IN OWN GUARD ORIGINAL ===~%")
(defun foo-h2 (x)
  (declare (xargs :guard (or (consp x)
                             (atom (foo-h2 '(a . b))))))
  (mv (car x)
      (mbe :logic (consp x)
           :exec t)))
(defthm bad-h2
  nil
  :hints (("Goal" :use ((:instance foo-h2 (x nil)))))
  :rule-classes nil)

(cw "~%=== H3 NONEXECUTABLE/MV ORIGINAL ===~%")
(defun f-h3 ()
  (declare (xargs :guard t :non-executable t))
  (mv-let (a b c)
          (mv 3 4)
          (declare (ignore a b))
          c))
(defun g-h3 ()
  (declare (xargs :guard t))
  (prog2$ (mv-let (x y z)
                  (mv 2 3 4)
                  (declare (ignore x y z))
                  nil)
          (f-h3)))
(defthm g-nil-h3
  (equal (g-h3) nil)
  :hints (("Goal" :in-theory (disable (f-h3))))
  :rule-classes nil)
(defthm contradiction-h3
  nil
  :hints (("Goal" :use g-nil-h3))
  :rule-classes nil)

(cw "~%=== H4 MBE IN DEFCONST/MACRO/VALUE-TRIPLE ===~%")
(defconst *mbe-direct-h4* (mbe :logic nil :exec t))
(defmacro mbe-mac-h4 () (mbe :logic ''nil :exec ''t))
(defconst *mbe-mac-value-h4* (mbe-mac-h4))
(value-triple (mbe :logic nil :exec t))

(cw "~%=== H5 CONGRUENCE NEW RHS VARIABLE ORIGINAL ===~%")
(defun e-h5 (x y)
  (or (equal x y)
      (and (booleanp x) (booleanp y))))
(defequiv e-h5)
(defun h-h5 (x y)
  (if (booleanp x)
      (booleanp y)
    (equal (car x) y)))
(defthm e-implies-equal-h-2-bad-h5
  (implies (e-h5 y1 y2)
           (equal (h-h5 y2 y1)
                  (h-h5 y2 y2)))
  :rule-classes :congruence)
(defun true-h5 () t)
(defun false-h5 () nil)
(defthm e-true-false-h5 (e-h5 (true-h5) (false-h5)))
(defthm fact-1-h5 (h-h5 (cons t x) (true-h5)) :rule-classes nil)
(defthm fact-2-h5 (not (h-h5 (cons t x) (false-h5))) :rule-classes nil)
(in-theory (disable true-h5 (true-h5) false-h5 (false-h5)))
(defthm contradiction-h5
  nil
  :hints (("Goal" :use (fact-1-h5 fact-2-h5)))
  :rule-classes nil)

(cw "~%=== H6 FORCED HYP/ELIM ORIGINAL ===~%")
(defun app-h6 (x y)
  (if (consp x)
      (cons (car x) (app-h6 (cdr x) y))
    y))
(defun rev-h6 (x)
  (if (consp x)
      (app-h6 (rev-h6 (cdr x)) (cons (car x) nil))
    x))
(defthm rev-type-h6
  (implies (force (true-listp x))
           (true-listp (rev-h6 x)))
  :rule-classes :type-prescription)
(defthm false-h6
  (equal (rev-h6 (rev-h6 x)) x)
  :rule-classes nil)
(defthm true-h6
  (equal (rev-h6 (rev-h6 '(a b . c))) '(a b))
  :rule-classes nil)
(defthm bug-h6
  nil
  :hints (("Goal" :use (true-h6 (:instance false-h6 (x '(a b . c))))))
  :rule-classes nil)

(cw "~%=== H7 STRING STOBJ ORIGINAL AND CHARACTER-ARRAY VARIANT ===~%")
(defstobj st-h7 fld-h7)
(value-triple (stp-h7 "abc"))
(defthm bad-h7 (stp-h7 "abc") :rule-classes nil)
(defthm contradiction-h7
  nil
  :hints (("Goal" :in-theory (disable (stp-h7)) :use bad-h7))
  :rule-classes nil)
(defstobj char-st-h7
  (chars-h7 :type (array character (3)) :initially #\b))
(value-triple (char-st-h7p "abc"))
(make-event (if (char-st-h7p char-st-h7)
                '(value-triple :live-char-stobj-recognized)
              (mv t nil state)))
(defthm bad-char-string-h7 (char-st-h7p "abc") :rule-classes nil)

(cw "~%=== H8 GETENV BUILD-STATE ORIGINAL ===~%")
(defthm getenv-bad-h8
  (stringp (cadr (getenv$ "PWD" (build-state))))
  :hints (("Goal" :in-theory (disable (getenv$))))
  :rule-classes nil)

(quit)
